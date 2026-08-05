# Woow_k3s_emqx — EMQX Helm Chart for K3s/Kubernetes

[繁體中文](README_zh-TW.md)

Helm chart deploying the [EMQX](https://www.emqx.io/) MQTT broker on
K3s / Kubernetes as a **StatefulSet**, with a headless service for stable pod
DNS (required by EMQX node naming) and a NodePort service that exposes MQTT
(TCP / SSL / WebSocket / Secure WebSocket) and the EMQX dashboard.

> **Looking for another platform?**
> Docker / Podman Compose → [Woow_podman_emqx](https://github.com/WOOWTECH/Woow_podman_emqx) ·
> Home Assistant add-on → [Woow_ha_emqx](https://github.com/WOOWTECH/Woow_ha_emqx)

## Architecture

| Component | Image | Kind | Service | NodePort |
|---|---|---|---|---|
| EMQX MQTT broker | `emqx/emqx:latest` | StatefulSet (1 replica) | `emqx` (NodePort) + `emqx-headless` (ClusterIP, headless) | `31883` (MQTT TCP) · `31808` (dashboard) |

- Storage: two `local-path` PVCs — `emqx-data` (5 Gi, runtime state) and
  `emqx-log` (2 Gi, logs).
- The StatefulSet uses `emqx-headless` as its `serviceName` so pods get
  a stable DNS name (`emqx-0.emqx-headless.<ns>.svc.cluster.local`), which is
  hard-wired into `EMQX_NODE_NAME` for stable cluster identity.
- Only `mqtt-tcp` (1883) and `dashboard` (18083) have pinned NodePorts by
  default; the other MQTT ports (`mqtt-ssl` 8883, `mqtt-ws` 8083,
  `mqtt-wss` 8084) are exposed as NodePorts too but Kubernetes assigns them a
  random node port unless you set `emqx.service.nodePort_mqttSsl` etc.

## Quick start

```bash
# Install straight from the repo tarball (no clone needed)
helm install emqx https://github.com/WOOWTECH/Woow_k3s_emqx/archive/refs/heads/main.tar.gz

# Or from a local clone
git clone https://github.com/WOOWTECH/Woow_k3s_emqx.git
cd Woow_k3s_emqx
helm install emqx .
```

> **Change the dashboard password before any non-test deployment:**
>
> ```bash
> helm install emqx . \
>   --set secrets.dashboardPassword="$(openssl rand -base64 24)"
> ```

Then open `http://<node-ip>:31808` for the EMQX dashboard (default login
`admin` / the password you set) and point MQTT clients at
`tcp://<node-ip>:31883`.

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `emqx` | Target namespace |
| `emqx.image.tag` | `latest` | EMQX version |
| `emqx.image.pullPolicy` | `Always` | Explicit (matches `:latest` default) |
| `emqx.replicas` | `1` | Broker replicas (scale up requires cluster config) |
| `emqx.service.type` | `NodePort` | How the broker is exposed |
| `emqx.service.nodePort.mqttTcp` | `31883` | MQTT TCP node port |
| `emqx.service.nodePort.dashboard` | `31808` | Dashboard HTTP node port |
| `emqx.persistence.data.size` | `5Gi` | Runtime data PVC (`local-path`) |
| `emqx.persistence.log.size` | `2Gi` | Logs PVC (`local-path`) |
| `emqx.config.EMQX_NODE_NAME` | `emqx@emqx-0.emqx-headless.emqx.svc.cluster.local` | Node identity (must match pod DNS) |
| `emqx.config.EMQX_ALLOW_ANONYMOUS` | `"true"` | Anonymous MQTT clients (**set `"false"` for production**) |
| `secrets.dashboardUsername` | `admin` | Dashboard admin username |
| `secrets.dashboardPassword` | `changeme_emqx_2024` | Dashboard admin password (**change this**) |

Full list: [`values.yaml`](values.yaml)

## Verify

```bash
kubectl get pods -n emqx                                # emqx-0 Running/Ready
kubectl -n emqx exec emqx-0 -- emqx ctl status          # Node 'emqx@…' is started
curl -s -o /dev/null -w "%{http_code}\n" \
     http://<node-ip>:31808                             # 200
```

Quick MQTT round-trip (needs `mosquitto-clients` on the host):

```bash
mosquitto_sub -h <node-ip> -p 31883 -t 'test/topic' -v &
mosquitto_pub -h <node-ip> -p 31883 -t 'test/topic' -m 'hello emqx'
```

## Uninstall

```bash
helm uninstall emqx
# PVCs are kept by Helm; remove them (and your data!) with:
kubectl delete pvc -n emqx emqx-data emqx-log
# and remove the namespace if you no longer need it:
kubectl delete ns emqx
```

## Migrating from the old Kustomize deployment

This repository replaces the `k3s` branch of the archived
[Woow_eqmx_docker_compose_all](https://github.com/WOOWTECH/Woow_eqmx_docker_compose_all)
repo (note the typo `eqmx` in the old name; the new repos use the correct
spelling `emqx`). The chart's default rendering is resource-equivalent to
those manifests (same names, namespace, labels, ports, StatefulSet kind,
PVCs), with only two deliberate differences:

1. `emqx.image.pullPolicy: Always` is set explicitly — this matches
   Kubernetes' implicit behaviour for the `:latest` tag.
2. The `Namespace` resource carries an extra `managed-by: helm` label so
   `helm list -n emqx` / `helm uninstall` can track it.

An existing Kustomize-deployed cluster can be adopted by Helm or left as-is;
the original manifests remain available in this repo's git history.

## License

MIT
