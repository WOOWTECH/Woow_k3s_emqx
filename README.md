# Woow_k3s_emqx — EMQX Helm Chart for K3s/Kubernetes

[繁體中文](README_zh-TW.md)

Helm chart deploying the [EMQX](https://www.emqx.io/) MQTT broker on
K3s / Kubernetes as a **StatefulSet**, with a headless service for stable pod
DNS (required by EMQX node naming) and a NodePort service that exposes MQTT
(TCP / SSL / WebSocket / Secure WebSocket) and the EMQX dashboard.

> **Looking for another platform?**
> Docker / Podman Compose → [Woow_podman_emqx](https://github.com/WOOWTECH/Woow_podman_emqx) ·
> Home Assistant add-on → [Woow_ha_emqx](https://github.com/WOOWTECH/Woow_ha_emqx)

> The **EMQX MCP admin console** (`emqx-mcp-admin`) is a separate application
> deployed from [Woow_emqx_mcp_server](https://github.com/WOOWTECH/Woow_emqx_mcp_server)
> (native manifests, not part of this chart, not touched by `helm install`/`helm uninstall` here).

## Architecture

| Component | Image | Kind | Service | NodePort |
|---|---|---|---|---|
| EMQX MQTT broker | `emqx/emqx:latest` | StatefulSet (1 replica) | `emqx` (NodePort) + `emqx-headless` (ClusterIP, headless) | `31883` (MQTT TCP) · `31808` (dashboard) |

- Storage: two PVCs (default StorageClass `local-path`) — `emqx-data` (5 Gi,
  runtime state) and `emqx-log` (2 Gi, logs). Both carry
  `helm.sh/resource-policy: keep`, so `helm uninstall` never deletes them.
- The StatefulSet uses `emqx-headless` as its `serviceName` so pods get
  a stable DNS name (`emqx-0.emqx-headless.<ns>.svc.cluster.local`), which is
  hard-wired into `EMQX_NODE_NAME` for stable cluster identity.
- Only `mqtt-tcp` (1883) and `dashboard` (18083) have pinned NodePorts by
  default; the other MQTT ports (`mqtt-ssl` 8883, `mqtt-ws` 8083,
  `mqtt-wss` 8084) are exposed as NodePorts too but Kubernetes assigns them a
  random node port unless you set `emqx.service.nodePort_mqttSsl` etc.
- The dashboard admin credential lives in Secret `emqx-secret`. By default
  (`secrets.create=false`) the chart only *references* it — it must already
  exist (see [`examples/secrets.example.yaml`](examples/secrets.example.yaml))
  — so a `helm upgrade` can never overwrite a real password with an empty one.

| Template | Objects | Toggle |
|---|---|---|
| `templates/emqx-statefulset.yaml` | StatefulSet (1 container) | always |
| `templates/emqx-service.yaml` | Service `emqx` (client-facing), Service `emqx-headless` | always |
| `templates/configmap.yaml` | ConfigMap `emqx-config` | always |
| `templates/pvc.yaml` | PVC `emqx-data`, PVC `emqx-log` | always |
| `templates/secret.yaml` | Secret `emqx-secret` | `secrets.create` |
| `templates/namespace.yaml` | Namespace `namespace.name`, only when it differs from the release namespace | `namespace.create` |
| `templates/tests/smoke.yaml` | `helm test` pod | `tests.enabled` |

## Quick start

Always pass the context explicitly (`--kube-context` for helm, `--context` for kubectl).

### A. Manage the Secret outside Helm (recommended)

With the default `secrets.create=false`, the chart never renders or touches
the Secret, so no upgrade can ever overwrite a real password.

```bash
kubectl --context woow-k3s create namespace emqx
cp examples/secrets.example.yaml ~/secure/emqx-secret.yaml   # fill in the real password
kubectl --context woow-k3s apply -f ~/secure/emqx-secret.yaml

# Install straight from the repo tarball (no clone needed)
helm --kube-context woow-k3s install emqx \
  https://github.com/WOOWTECH/Woow_k3s_emqx/archive/refs/heads/main.tar.gz \
  -n emqx

# Or from a local clone
git clone https://github.com/WOOWTECH/Woow_k3s_emqx.git && cd Woow_k3s_emqx
helm --kube-context woow-k3s install emqx . -n emqx
```

### B. Let the chart create the Secret

```bash
helm --kube-context woow-k3s install emqx . -n emqx --create-namespace \
  --set secrets.create=true \
  --set secrets.dashboardPassword="$(openssl rand -base64 24)"
```

Every later `helm upgrade` needs the same `--set` (or a values file with it),
otherwise the `required()` check stops the upgrade before it can blank the
password.

### C. Test install (own namespace, disposable storage)

```bash
NS=ht-emqx
helm --kube-context woow-k3s install emqx . -n $NS --create-namespace \
  --set namespace.name=$NS,storageClassName=longhorn-delete \
  --set emqx.config.EMQX_NODE_NAME="emqx@emqx-0.emqx-headless.$NS.svc.cluster.local" \
  --set secrets.create=true,secrets.dashboardPassword="$(openssl rand -base64 24)"
```

`EMQX_NODE_NAME` must be overridden for any namespace other than `emqx` — see
[Known limitations](#known-limitations).

### Then

Open `http://<node-ip>:31808` for the EMQX dashboard (default login
`admin` / the password you set) and point MQTT clients at
`tcp://<node-ip>:31883`.

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace.name` | `emqx` | Namespace of every object |
| `namespace.create` | `true` | Render that Namespace when it differs from the release namespace |
| `keepOnUninstall` | `true` | `helm.sh/resource-policy: keep` on the Namespace, PVCs and the chart-created Secret |
| `storageClassName` | `local-path` | Default StorageClass for both PVCs |
| `secrets.create` | `false` | Render `emqx-secret` from `secrets.*` instead of using an existing one |
| `secrets.dashboardUsername` | `admin` | Dashboard admin username |
| `secrets.dashboardPassword` | *(empty, required when `secrets.create=true`)* | Dashboard admin password |
| `emqx.image.tag` | `latest` | EMQX version |
| `emqx.replicas` | `1` | Broker replicas (scale up requires cluster config — see [Known limitations](#known-limitations)) |
| `emqx.service.type` | `NodePort` | How the broker is exposed |
| `emqx.service.nodePort.mqttTcp` | `31883` | MQTT TCP node port |
| `emqx.service.nodePort.dashboard` | `31808` | Dashboard HTTP node port |
| `emqx.persistence.data.size` | `5Gi` | Runtime data PVC |
| `emqx.persistence.log.size` | `2Gi` | Logs PVC |
| `emqx.config.EMQX_NODE_NAME` | `emqx@emqx-0.emqx-headless.emqx.svc.cluster.local` | Node identity (must match pod DNS) |
| `emqx.config.EMQX_ALLOW_ANONYMOUS` | `"true"` | Anonymous MQTT clients — see [Known limitations](#known-limitations) |
| `tests.enabled` | `true` | `helm test` smoke pod |

Full list: [`values.yaml`](values.yaml).

## Verify

```bash
kubectl -n emqx rollout status statefulset/emqx --timeout=5m
helm --kube-context woow-k3s test emqx -n emqx --logs   # dashboard /status + MQTT pub/sub round-trip (read-only)
curl -s http://<node-ip>:31808/status                    # "... is running"
```

Manual MQTT round-trip (needs `mosquitto-clients` on the host):

```bash
mosquitto_sub -h <node-ip> -p 31883 -t 'test/topic' -v &
mosquitto_pub -h <node-ip> -p 31883 -t 'test/topic' -m 'hello emqx'
```

## Uninstall

```bash
helm --kube-context woow-k3s uninstall emqx -n emqx
```

This removes the StatefulSet, Services and ConfigMap. Data stays:

- PVCs `emqx-data` and `emqx-log`, and the Secret (when `secrets.create=true`),
  carry the keep policy and are never deleted by `helm uninstall`.
- The `emqx` namespace is the release namespace and is never rendered by this
  chart, so it is never deleted either way. A Namespace this chart *does*
  render (`namespace.name` different from `-n`) also carries the keep policy.

To really delete everything, including the data:

```bash
kubectl --context woow-k3s delete namespace emqx
```

## Known limitations

These are pre-existing behaviours of the original manifests. They are **not**
changed in this chart revision (phase 1 is uninstall/secrets/CI/docs only);
see the repo's issue tracker / migration notes for follow-up work.

- **Anonymous MQTT is allowed by default** (`EMQX_ALLOW_ANONYMOUS=true`).
  This is a 4.x-era environment variable; EMQX 5.x/6.x (the `:latest` tag) use
  an authentication chain instead, so setting it to `"false"` alone likely
  does **not** disable anonymous access. Do not expose the default install
  to an untrusted network.
- **`emqx.config.EMQX_NODE_NAME` does not follow `namespace.name`.** It is a
  plain string default (`...emqx-headless.emqx.svc.cluster.local`), so
  installing into any namespace other than `emqx` (e.g. a test install)
  needs `--set emqx.config.EMQX_NODE_NAME=emqx@emqx-0.emqx-headless.<ns>.svc.cluster.local`
  or the startup probe fails with `Node '...' not responding to pings` and
  the pod never becomes ready. See Quick start path C.
- **`emqx.replicas` is not really adjustable.** The two PVCs are plain
  (`ReadWriteOnce`, not `volumeClaimTemplates`) and `EMQX_NODE_NAME` is fixed
  to `emqx-0`, so a second pod cannot mount its own volume or get its own
  node identity. Keep `replicas: 1`.
- **`:latest` is not pinned.** `imagePullPolicy: Always` plus `emqx/emqx:latest`
  means every pod restart can pull a new EMQX major version onto existing
  data. Pin `emqx.image.tag` for anything long-lived.
- Changing a `ConfigMap`/`Secret` value does not trigger a rollout, and EMQX
  only reads `EMQX_DASHBOARD__DEFAULT_PASSWORD` on a node's first boot — so
  changing `secrets.dashboardPassword` after the first install does not
  change the running admin password.

## Migrating from the old Kustomize deployment

This repository replaces the `k3s` branch of the archived
[Woow_eqmx_docker_compose_all](https://github.com/WOOWTECH/Woow_eqmx_docker_compose_all)
repo (note the typo `eqmx` in the old name; the new repos use the correct
spelling `emqx`). Rendered with default values, this chart is
resource-equivalent to those manifests (same names, namespace, labels, ports,
StatefulSet kind, PVC sizes), except:

1. `emqx.image.pullPolicy: Always` is set explicitly — this matches
   Kubernetes' implicit behaviour for the `:latest` tag.
2. The Namespace, PVCs and the Secret (when `secrets.create=true`) carry
   `helm.sh/resource-policy: keep`.
3. By default (`secrets.create=false`) no Secret is rendered at all — create
   `emqx-secret` yourself first (see Quick start, path A).
4. A `helm test` smoke pod is added.
5. The pod template gains `securityContext.fsGroup: 1000`. The `emqx/emqx`
   image runs as uid/gid 1000; this was previously masked because
   `local-path` creates world-writable hostPath directories, but any
   provisioner that mounts PVCs root-owned (e.g. Longhorn, required for test
   installs) fails with `Permission denied` on `emqx-data`/`emqx-log`
   without it. Nothing on woow-k3s runs this chart today, so this change
   affects no live pod.

A Namespace equal to the release namespace (`-n`) is never rendered — this
does not change the Kustomize-equivalent render above, since that render used
no `-n`, but it does mean `helm install emqx . -n emqx --create-namespace`
will not conflict with a namespace this chart also tries to create.

An existing Kustomize-deployed cluster is **not** automatically adopted by
`helm install`/`helm upgrade --take-ownership`: those objects lack the
`meta.helm.sh/release-name` / `release-namespace` annotations and the
`app.kubernetes.io/managed-by=Helm` label Helm requires for ownership, so a
plain `helm install` against that namespace fails with an ownership error.
Adopting it needs those annotations/labels added first (not covered by this
chart) — the original manifests remain available in this repo's git history
if you'd rather leave an existing deployment as-is.

## License

MIT
