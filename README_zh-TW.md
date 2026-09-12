# Woow_k3s_emqx — EMQX 在 K3s/Kubernetes 上的 Helm Chart

[English](README.md)

在 K3s / Kubernetes 上部署 [EMQX](https://www.emqx.io/) MQTT Broker 的 Helm
chart,採 **StatefulSet** 佈署搭配 headless service 提供穩定 Pod DNS
(EMQX 節點命名所必需),並以 NodePort service 對外提供 MQTT
(TCP / SSL / WebSocket / Secure WebSocket) 與 EMQX Dashboard。

> **需要其他部署平台?**
> Docker / Podman Compose → [Woow_podman_emqx](https://github.com/WOOWTECH/Woow_podman_emqx) ·
> Home Assistant add-on → [Woow_ha_emqx](https://github.com/WOOWTECH/Woow_ha_emqx)

> **EMQX MCP 管理主控台** (`emqx-mcp-admin`) 是獨立的應用程式,部署自
> [Woow_emqx_mcp_server](https://github.com/WOOWTECH/Woow_emqx_mcp_server)
> (原生 manifest,不屬於本 chart,不受本 chart 的 `helm install`/`helm uninstall` 影響)。

## 架構

| 元件 | 映像 | Kind | Service | NodePort |
|---|---|---|---|---|
| EMQX MQTT broker | `emqx/emqx:latest` | StatefulSet (1 replica) | `emqx` (NodePort) + `emqx-headless` (ClusterIP, headless) | `31883` (MQTT TCP)、`31808` (Dashboard) |

- 儲存:兩顆 PVC(預設 StorageClass 為 `local-path`)— `emqx-data`
  (5 Gi,執行期資料) 與 `emqx-log` (2 Gi,日誌)。兩者都帶
  `helm.sh/resource-policy: keep`,`helm uninstall` 不會刪除它們。
- StatefulSet 以 `emqx-headless` 作為 `serviceName`,讓 Pod 取得穩定 DNS
  (`emqx-0.emqx-headless.<ns>.svc.cluster.local`),此 DNS 名稱直接寫死在
  `EMQX_NODE_NAME`,確保節點身份穩定。
- 預設僅 `mqtt-tcp` (1883) 與 `dashboard` (18083) 固定 NodePort;其餘 MQTT
  ports (`mqtt-ssl` 8883、`mqtt-ws` 8083、`mqtt-wss` 8084) 亦透過 NodePort
  service 對外,但由 Kubernetes 隨機分配 nodePort,如需固定請設定
  `emqx.service.nodePort_mqttSsl` 等 values。
- Dashboard 管理員密碼存放在 Secret `emqx-secret`。預設
  (`secrets.create=false`) chart 只會「引用」它 — 必須事先存在(見
  [`examples/secrets.example.yaml`](examples/secrets.example.yaml))— 這樣
  `helm upgrade` 就永遠不會把真的密碼覆寫成空值。

| Template | 產生的物件 | 開關 |
|---|---|---|
| `templates/emqx-statefulset.yaml` | StatefulSet(單一 container) | 一律渲染 |
| `templates/emqx-service.yaml` | Service `emqx`(對外)、Service `emqx-headless` | 一律渲染 |
| `templates/configmap.yaml` | ConfigMap `emqx-config` | 一律渲染 |
| `templates/pvc.yaml` | PVC `emqx-data`、PVC `emqx-log` | 一律渲染 |
| `templates/secret.yaml` | Secret `emqx-secret` | `secrets.create` |
| `templates/namespace.yaml` | Namespace `namespace.name`,僅在與 release namespace 不同時渲染 | `namespace.create` |
| `templates/tests/smoke.yaml` | `helm test` pod | `tests.enabled` |

## 快速開始

請一律明確指定 context(helm 用 `--kube-context`,kubectl 用 `--context`)。

### A. Secret 由 Helm 之外管理(建議做法)

預設 `secrets.create=false` 時,chart 完全不會渲染或碰觸這個 Secret,所以
`helm upgrade` 永遠不會把真的密碼蓋成空值。

```bash
kubectl --context woow-k3s create namespace emqx
cp examples/secrets.example.yaml ~/secure/emqx-secret.yaml   # 填入真正的密碼
kubectl --context woow-k3s apply -f ~/secure/emqx-secret.yaml

# 直接從倉庫 tarball 安裝(不用 clone)
helm --kube-context woow-k3s install emqx \
  https://github.com/WOOWTECH/Woow_k3s_emqx/archive/refs/heads/main.tar.gz \
  -n emqx

# 或先 clone 到本機
git clone https://github.com/WOOWTECH/Woow_k3s_emqx.git && cd Woow_k3s_emqx
helm --kube-context woow-k3s install emqx . -n emqx
```

### B. 讓 chart 建立 Secret

```bash
helm --kube-context woow-k3s install emqx . -n emqx --create-namespace \
  --set secrets.create=true \
  --set secrets.dashboardPassword="$(openssl rand -base64 24)"
```

之後每次 `helm upgrade` 都要帶上同樣的 `--set`(或含此設定的 values
檔),否則 `required()` 檢查會擋下 upgrade,而不是把密碼清空。

### C. 測試安裝(專用 namespace、可拋棄的儲存)

```bash
NS=ht-emqx
helm --kube-context woow-k3s install emqx . -n $NS --create-namespace \
  --set namespace.name=$NS,storageClassName=longhorn-delete \
  --set emqx.config.EMQX_NODE_NAME="emqx@emqx-0.emqx-headless.$NS.svc.cluster.local" \
  --set secrets.create=true,secrets.dashboardPassword="$(openssl rand -base64 24)"
```

除了 `emqx` 之外的任何 namespace 都必須覆寫 `EMQX_NODE_NAME`,見
[已知限制](#已知限制)。

### 接著

開啟 `http://<node-ip>:31808` 進入 EMQX Dashboard(預設帳號 `admin`,
密碼為上述設定值),MQTT 客戶端連線 `tcp://<node-ip>:31883`。

## 主要 values

| Value | 預設 | 說明 |
|---|---|---|
| `namespace.name` | `emqx` | 所有物件所在的 namespace |
| `namespace.create` | `true` | 當它與 release namespace 不同時才渲染 |
| `keepOnUninstall` | `true` | 在 Namespace、PVC 與 chart 建立的 Secret 上加 `helm.sh/resource-policy: keep` |
| `storageClassName` | `local-path` | 兩顆 PVC 的預設 StorageClass |
| `secrets.create` | `false` | 由 `secrets.*` 渲染 `emqx-secret`,而非使用既有的 |
| `secrets.dashboardUsername` | `admin` | Dashboard 管理員帳號 |
| `secrets.dashboardPassword` | *(空字串,`secrets.create=true` 時必填)* | Dashboard 管理員密碼 |
| `emqx.image.tag` | `latest` | EMQX 版本 |
| `emqx.replicas` | `1` | Broker replicas(擴充前請見[已知限制](#已知限制)) |
| `emqx.service.type` | `NodePort` | 對外方式 |
| `emqx.service.nodePort.mqttTcp` | `31883` | MQTT TCP node port |
| `emqx.service.nodePort.dashboard` | `31808` | Dashboard HTTP node port |
| `emqx.persistence.data.size` | `5Gi` | 資料 PVC |
| `emqx.persistence.log.size` | `2Gi` | 日誌 PVC |
| `emqx.config.EMQX_NODE_NAME` | `emqx@emqx-0.emqx-headless.emqx.svc.cluster.local` | 節點識別(需與 Pod DNS 相符) |
| `emqx.config.EMQX_ALLOW_ANONYMOUS` | `"true"` | 匿名 MQTT 客戶端 — 見[已知限制](#已知限制) |
| `tests.enabled` | `true` | `helm test` smoke pod |

完整清單: [`values.yaml`](values.yaml)。

## 驗證

```bash
kubectl -n emqx rollout status statefulset/emqx --timeout=5m
helm --kube-context woow-k3s test emqx -n emqx --logs   # dashboard /status + MQTT 收發往返(唯讀)
curl -s http://<node-ip>:31808/status                    # "... is running"
```

手動 MQTT 通訊測試(需在主機安裝 `mosquitto-clients`):

```bash
mosquitto_sub -h <node-ip> -p 31883 -t 'test/topic' -v &
mosquitto_pub -h <node-ip> -p 31883 -t 'test/topic' -m 'hello emqx'
```

## 移除

```bash
helm --kube-context woow-k3s uninstall emqx -n emqx
```

這會移除 StatefulSet、Service 與 ConfigMap。資料會保留:

- PVC `emqx-data`、`emqx-log`,以及 Secret(`secrets.create=true` 時)都帶
  keep policy,`helm uninstall` 不會刪除。
- `emqx` namespace 是 release namespace,本 chart 從不渲染它,所以無論如何
  都不會被刪除。若本 chart 有渲染出 Namespace(`namespace.name` 與 `-n`
  不同時),它也帶 keep policy。

若要真的清掉所有東西,包含資料:

```bash
kubectl --context woow-k3s delete namespace emqx
```

## 已知限制

以下是原始 manifests 就有的既有行為,**本次 chart 修訂不處理**(phase 1
只處理 uninstall / secrets / CI / 文件四項);後續處理請見 issue tracker
或遷移說明。

- **預設允許匿名 MQTT** (`EMQX_ALLOW_ANONYMOUS=true`)。這是 EMQX 4.x 時代的
  環境變數;EMQX 5.x/6.x(即 `:latest`)已改用 authentication chain,單獨
  設成 `"false"` 很可能**不會**真的關閉匿名連線。請勿把預設安裝直接暴露在
  不受信任的網路。
- **`emqx.config.EMQX_NODE_NAME` 不會跟著 `namespace.name` 變。** 它是固定
  字串預設值(`...emqx-headless.emqx.svc.cluster.local`),裝到 `emqx` 以外
  的 namespace(例如測試安裝)必須加上
  `--set emqx.config.EMQX_NODE_NAME=emqx@emqx-0.emqx-headless.<ns>.svc.cluster.local`,
  否則 startup probe 會一直失敗(`Node '...' not responding to pings`),
  pod 永遠不會 Ready。見「快速開始」路徑 C。
- **`emqx.replicas` 實際上無法調整。** 兩顆 PVC 是一般的 PVC(RWO,不是
  `volumeClaimTemplates`),`EMQX_NODE_NAME` 又寫死成 `emqx-0`,第二個 pod
  無法掛載自己的 volume,也拿不到自己的節點身份。請維持 `replicas: 1`。
- **`:latest` 版本沒有釘住。** `imagePullPolicy: Always` 加上
  `emqx/emqx:latest`,代表每次 pod 重啟都可能拉到新的 EMQX 大版本、套用在
  既有資料上。長期使用請把 `emqx.image.tag` 釘死。
- 改 `ConfigMap`/`Secret` 不會觸發 rollout,而且 EMQX 只在節點第一次啟動時
  讀取 `EMQX_DASHBOARD__DEFAULT_PASSWORD`——所以安裝後才改
  `secrets.dashboardPassword` 不會改到正在跑的管理員密碼。

## 從舊 Kustomize 版本遷移

本倉庫取代已封存的
[Woow_eqmx_docker_compose_all](https://github.com/WOOWTECH/Woow_eqmx_docker_compose_all)
的 `k3s` 分支(舊名有拼字 `eqmx`,新倉庫改為正確拼法 `emqx`)。本 chart
以預設值渲染出來的結果,與原本 Kustomize manifests 資源等價(同名、同
namespace、同標籤、同埠、StatefulSet kind 一致、PVC 大小一致),差異僅有:

1. `emqx.image.pullPolicy: Always` 明寫 — 與 Kubernetes 對 `:latest` 的
   隱性行為一致。
2. Namespace、PVC,以及 Secret(`secrets.create=true` 時)都多了
   `helm.sh/resource-policy: keep`。
3. 預設(`secrets.create=false`)完全不會渲染 Secret — 請先自行建立
   `emqx-secret`(見「快速開始」路徑 A)。
4. 新增 `helm test` smoke pod。
5. Pod template 多了 `securityContext.fsGroup: 1000`。`emqx/emqx` 映像以
   uid/gid 1000 執行;過去因為 `local-path` 建立的 hostPath 目錄是任何人
   可寫,這個問題被蓋住了,但只要 PVC 由會以 root 擁有掛載目錄的
   provisioner(例如測試安裝所要求的 Longhorn)建立,沒有這個設定就會在
   `emqx-data`/`emqx-log` 上出現 `Permission denied`。woow-k3s 目前沒有任何
   東西用這個 chart 在跑,所以這個改動不影響任何 live pod。

與 release namespace(`-n`)相同的 Namespace 永遠不會被渲染 — 上面的
Kustomize 等價渲染沒有帶 `-n`,所以不受影響;但這代表
`helm install emqx . -n emqx --create-namespace` 不會跟本 chart 自己想建立
的 namespace 衝突。

既有的 Kustomize 部署**不會**被 `helm install`/`helm upgrade --take-ownership`
自動 adopt:那些物件缺少 Helm 認定所有權所需的
`meta.helm.sh/release-name` / `release-namespace` annotation 與
`app.kubernetes.io/managed-by=Helm` 標籤,直接對該 namespace 執行
`helm install` 會因所有權檢查失敗。要 adopt 必須先手動補上這些
annotation/標籤(本 chart 未涵蓋)— 若想原樣保留既有部署,原始 manifests
仍留在本倉庫的 git 歷史中。

## 授權

MIT
