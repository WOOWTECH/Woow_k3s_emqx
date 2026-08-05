# Woow_k3s_emqx — EMQX 在 K3s/Kubernetes 上的 Helm Chart

[English](README.md)

在 K3s / Kubernetes 上部署 [EMQX](https://www.emqx.io/) MQTT Broker 的 Helm
chart,採 **StatefulSet** 佈署搭配 headless service 提供穩定 Pod DNS
(EMQX 節點命名所必需),並以 NodePort service 對外提供 MQTT
(TCP / SSL / WebSocket / Secure WebSocket) 與 EMQX Dashboard。

> **需要其他部署平台?**
> Docker / Podman Compose → [Woow_podman_emqx](https://github.com/WOOWTECH/Woow_podman_emqx) ·
> Home Assistant add-on → [Woow_ha_emqx](https://github.com/WOOWTECH/Woow_ha_emqx)

## 架構

| 元件 | 映像 | Kind | Service | NodePort |
|---|---|---|---|---|
| EMQX MQTT broker | `emqx/emqx:latest` | StatefulSet (1 replica) | `emqx` (NodePort) + `emqx-headless` (ClusterIP, headless) | `31883` (MQTT TCP)、`31808` (Dashboard) |

- 儲存:兩顆 `local-path` PVC — `emqx-data` (5 Gi,執行期資料) 與
  `emqx-log` (2 Gi,日誌)。
- StatefulSet 以 `emqx-headless` 作為 `serviceName`,讓 Pod 取得穩定 DNS
  (`emqx-0.emqx-headless.<ns>.svc.cluster.local`),此 DNS 名稱直接寫死在
  `EMQX_NODE_NAME`,確保節點身份穩定。
- 預設僅 `mqtt-tcp` (1883) 與 `dashboard` (18083) 固定 NodePort;其餘 MQTT
  ports (`mqtt-ssl` 8883、`mqtt-ws` 8083、`mqtt-wss` 8084) 亦透過 NodePort
  service 對外,但由 Kubernetes 隨機分配 nodePort,如需固定請設定
  `emqx.service.nodePort_mqttSsl` 等 values。

## 快速開始

```bash
# 直接從倉庫 tarball 安裝 (不用 clone)
helm install emqx https://github.com/WOOWTECH/Woow_k3s_emqx/archive/refs/heads/main.tar.gz

# 或先 clone 到本機
git clone https://github.com/WOOWTECH/Woow_k3s_emqx.git
cd Woow_k3s_emqx
helm install emqx .
```

> **非測試環境部署前務必更換 Dashboard 密碼:**
>
> ```bash
> helm install emqx . \
>   --set secrets.dashboardPassword="$(openssl rand -base64 24)"
> ```

然後開啟 `http://<node-ip>:31808` 進入 EMQX Dashboard (預設帳號 `admin`,
密碼為上述設定值),MQTT 客戶端連線 `tcp://<node-ip>:31883`。

## 主要 values

| Value | 預設 | 說明 |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `emqx` | 目標 namespace |
| `emqx.image.tag` | `latest` | EMQX 版本 |
| `emqx.image.pullPolicy` | `Always` | 明寫 (與 `:latest` 隱性行為相同) |
| `emqx.replicas` | `1` | Broker replicas (擴充需先配置叢集) |
| `emqx.service.type` | `NodePort` | 對外方式 |
| `emqx.service.nodePort.mqttTcp` | `31883` | MQTT TCP node port |
| `emqx.service.nodePort.dashboard` | `31808` | Dashboard HTTP node port |
| `emqx.persistence.data.size` | `5Gi` | 資料 PVC (`local-path`) |
| `emqx.persistence.log.size` | `2Gi` | 日誌 PVC (`local-path`) |
| `emqx.config.EMQX_NODE_NAME` | `emqx@emqx-0.emqx-headless.emqx.svc.cluster.local` | 節點識別 (需與 Pod DNS 相符) |
| `emqx.config.EMQX_ALLOW_ANONYMOUS` | `"true"` | 匿名 MQTT 客戶端 (**生產環境請設 `"false"`**) |
| `secrets.dashboardUsername` | `admin` | Dashboard 管理員帳號 |
| `secrets.dashboardPassword` | `changeme_emqx_2024` | Dashboard 管理員密碼 (**請修改**) |

完整清單: [`values.yaml`](values.yaml)

## 驗證

```bash
kubectl get pods -n emqx                                # emqx-0 Running/Ready
kubectl -n emqx exec emqx-0 -- emqx ctl status          # Node 'emqx@…' is started
curl -s -o /dev/null -w "%{http_code}\n" \
     http://<node-ip>:31808                             # 200
```

快速 MQTT 通訊測試 (需在主機安裝 `mosquitto-clients`):

```bash
mosquitto_sub -h <node-ip> -p 31883 -t 'test/topic' -v &
mosquitto_pub -h <node-ip> -p 31883 -t 'test/topic' -m 'hello emqx'
```

## 移除

```bash
helm uninstall emqx
# PVC 不會被 Helm 自動刪除,若要一併清除資料:
kubectl delete pvc -n emqx emqx-data emqx-log
# 若不再使用整個 namespace:
kubectl delete ns emqx
```

## 從舊 Kustomize 版本遷移

本倉庫取代已封存的
[Woow_eqmx_docker_compose_all](https://github.com/WOOWTECH/Woow_eqmx_docker_compose_all)
的 `k3s` 分支 (舊名有拼字 `eqmx`,新倉庫改為正確拼法 `emqx`)。本 chart
以預設值渲染出來的結果,與原本 Kustomize manifests 「資源等價」 (同名、同
namespace、同標籤、同埠、StatefulSet kind 一致、PVC 一致),僅有兩處
刻意差異:

1. `emqx.image.pullPolicy: Always` 明寫 — 與 Kubernetes 對 `:latest` 的
   隱性行為一致。
2. `Namespace` 資源多一個 `managed-by: helm` 標籤,方便
   `helm list -n emqx` 追蹤與 `helm uninstall` 清除。

現行以 Kustomize 部署的叢集可透過 Helm adopt 或原樣保留;原 manifests 仍
可從本倉庫的 git 歷史取得。

## 授權

MIT
