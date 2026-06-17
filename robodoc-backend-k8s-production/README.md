# Robodoc Backend — Kubernetes Production

Laravel backend deployed on Kubernetes with Filebeat log shipping to Elasticsearch.

---

## Project Structure

```
robodoc-backend-k8s-production/
│
├── deployment.yaml              # Laravel app Deployment (1 replica)
├── service.yaml                 # ClusterIP Service (port 80)
├── configmap.yaml               # App environment variables  ← gitignored
├── secret.yaml                  # App secrets & passwords    ← gitignored
├── redis.yaml                   # Redis Deployment + Service
├── regcred.sh                   # Registry pull secret setup ← gitignored
│
├── filebeat-configmap.yaml      # Filebeat configuration
├── filebeat-daemonset.yaml      # Filebeat DaemonSet (1 pod per node)
│
├── envoy-gateway/
│   └── envoy.yaml               # Envoy Gateway config
│
├── deploy.sh                    # One-command deploy script
│
├── configmap.example.yaml       # ← copy to configmap.yaml, fill values
├── secret.example.yaml          # ← copy to secret.yaml, fill values
├── regcred.example.sh           # ← copy to regcred.sh, fill values
└── .gitignore
```

---

## First-Time Setup

### 1. Create real config files from examples

```bash
cp configmap.example.yaml configmap.yaml
cp secret.example.yaml secret.yaml
cp regcred.example.sh regcred.sh
chmod +x regcred.sh
```

Fill in all empty `""` values in `configmap.yaml` and `secret.yaml`.

---

### 2. Create Kubernetes namespace

```bash
kubectl create namespace robodoc
```

---

### 3. Create Docker registry pull secret

```bash
./regcred.sh
```

This creates a `regcred` secret in the `robodoc` namespace so Kubernetes can pull images from DigitalOcean Container Registry.

---

### 4. Deploy everything

```bash
./deploy.sh
```

This runs in order:
1. `kubectl apply -f secret.yaml` — app secrets
2. `kubectl apply -f configmap.yaml` — app environment variables
3. `kubectl apply -f deployment.yaml` — Laravel app pod
4. `kubectl apply -f service.yaml` — ClusterIP service
5. `kubectl apply -f filebeat-configmap.yaml` — Filebeat config
6. `kubectl apply -f filebeat-daemonset.yaml` — Filebeat on all nodes
7. Rollout restart + status wait for both Deployment and DaemonSet

---

## Filebeat Log Shipping

Filebeat runs as a **DaemonSet** — one pod per Kubernetes node. It reads logs from the `robodoc` namespace only and ships to Elasticsearch.

### How it works

```
Pod logs (containerd)
  /var/log/containers/robodoc-backend-production-*_robodoc_*.log
          │  (symlinks)
          ▼
  /var/log/pods/robodoc_robodoc-backend-production-*/*/*
          │
          ▼  parsers: container  (strips CRI prefix)
  message = "[2026-06-18 01:05:10] production.INFO: k8s|http://... {...}"
          │
          ▼  drop_event  (nginx, OPTIONS, empty lines filtered)
          │
          ▼  drop_event  (only keep lines containing "k8s|")
          │
          ▼  dissect + decode_json_fields
          │
          ▼
  Elasticsearch index: kubernetes-robodoc-backend-logs-2026.06
```

### Log path pattern

| Path type | Pattern |
|---|---|
| `/var/log/containers/` (symlinks) | `robodoc-backend-production-*_robodoc_*.log` |
| `/var/log/pods/` (actual files) | `robodoc_robodoc-backend-production-*/*/*` |

### Elasticsearch index

```
kubernetes-robodoc-backend-logs-{yyyy.MM}

Example: kubernetes-robodoc-backend-logs-2026.06
```

### Elasticsearch credentials

Filebeat reads credentials from the existing `robodoc-backend-production` ConfigMap and Secret — no separate secret needed:

| Env var | Source |
|---|---|
| `ELASTICSEARCH_HOST` | ConfigMap → `robodoc-backend-production` |
| `ELASTICSEARCH_PORT` | ConfigMap → `robodoc-backend-production` |
| `ELASTICSEARCH_USER` | ConfigMap → `robodoc-backend-production` |
| `ELASTICSEARCH_PASSWORD` | Secret → `robodoc-backend-production` |

---

## Day-to-day Deploy

```bash
./deploy.sh
```

---

## Useful Debug Commands

### Check pod status
```bash
kubectl get pods -n robodoc -o wide
```

### Check app logs
```bash
kubectl logs -n robodoc deployment/robodoc-backend-production --follow
```

### Check Filebeat logs
```bash
kubectl logs -n robodoc -l app=filebeat --follow
```

### Check Filebeat metrics (events acked/filtered)
```bash
kubectl exec -n robodoc <filebeat-pod-name> -- curl -s http://localhost:5066/stats | python3 -c "
import sys, json
d = json.load(sys.stdin)
h = d['filebeat']['harvester']
e = d['libbeat']['output']['events']
p = d['libbeat']['pipeline']['events']
print('open_files :', h['open_files'])
print('acked      :', e.get('acked', 0))
print('filtered   :', p.get('filtered', 0))
print('failed     :', e.get('failed', 0))
"
```

### Check Elasticsearch indices
```bash
kubectl exec -n robodoc <filebeat-pod-name> -- curl -s \
  -u "elastic:YOUR_PASSWORD" \
  "http://ELASTICSEARCH_HOST:9200/_cat/indices/kubernetes-*?v"
```

### Check log file exists on node
```bash
kubectl exec -n robodoc <filebeat-pod-name> -- \
  ls /var/log/containers/ | grep robodoc-backend-production
```

---

## Node Selector

The app is pinned to `worker-1-elasticsearch` node:

```yaml
# deployment.yaml
nodeSelector:
  kubernetes.io/hostname: worker-1-elasticsearch
```

To change the node:
```bash
# Add label to new node
kubectl label node <node-name> robodoc-backend-production=true

# Remove from old node
kubectl label node worker-1-elasticsearch robodoc-backend-production-
```

---

## Security Notes

- `secret.yaml`, `configmap.yaml`, `regcred.sh` are **gitignored** — never commit these
- Use `*.example.yaml` files as templates
- Rotate credentials by updating `secret.yaml` and running `./deploy.sh`
