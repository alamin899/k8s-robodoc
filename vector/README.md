# Vector দিয়ে Kubernetes Log Collection (বাংলা গাইড)

> এই ফোল্ডারের সব YAML ফাইল মিলে একটা **log shipping pipeline** তৈরি করে।
> কাজটা হলো — Kubernetes এর ভেতরে চলা `robodoc-backend` অ্যাপের log গুলো ধরে,
> পরিষ্কার করে, দরকারি অংশ বের করে **Elasticsearch** এ পাঠানো।
> এটা আগের **Filebeat** সেটআপের মতোই কাজ করে, শুধু টুল হিসেবে **Vector** ব্যবহার করা হয়েছে।

---

## ১. Vector আসলে কী? (একদম সহজ ভাষায়)

ধরো তোমার সার্ভারে অনেকগুলো অ্যাপ চলছে, আর প্রত্যেকটা অ্যাপ log (মানে কী কী ঘটছে তার রেকর্ড) লিখছে।
এই log গুলো এক জায়গায় জমা করা, খোঁজা আর দেখা সহজ করতে দরকার একটা "log collector"।

**Vector** হলো সেই log collector। এর কাজ তিন ধাপে:

1. **Source (উৎস):** log কোথা থেকে আসবে সেটা ঠিক করা (এখানে Kubernetes এর container log)।
2. **Transform (রূপান্তর):** log গুলো ফিল্টার করা, অপ্রয়োজনীয় লাইন ফেলে দেওয়া, দরকারি তথ্য বের করা।
3. **Sink (গন্তব্য):** পরিষ্কার log কোথায় পাঠাবে সেটা ঠিক করা (এখানে Elasticsearch)।

```
[অ্যাপের Log]  ─▶  Source  ─▶  Transform  ─▶  Sink  ─▶  [Elasticsearch]
                  (ধরা)        (পরিষ্কার)      (পাঠানো)
```

---

## ২. এই ফোল্ডারে কী কী ফাইল আছে?

log collector পুরো ঠিকঠাক চলার জন্য Kubernetes এ কয়েকটা জিনিস দরকার হয়। প্রত্যেকটার জন্য আলাদা ফাইল:

| ফাইল | Kubernetes অবজেক্ট | সহজ ভাষায় কাজ |
|------|--------------------|-----------------|
| `00-elasticsearch.example.yaml` | Secret | Elasticsearch এর host/port/user/password (`logging` রুমে) |
| `01-namespace.yaml` | Namespace | একটা আলাদা "রুম" (`logging`) যেখানে Vector থাকবে |
| `02-serviceaccount.yaml` | ServiceAccount | Vector এর নিজস্ব "পরিচয়পত্র" / ID card |
| `03-clusterrole.yaml` | ClusterRole | সেই ID card দিয়ে কী কী দেখার অনুমতি আছে তার তালিকা |
| `04-clusterrolebinding.yaml` | ClusterRoleBinding | ID card আর অনুমতির তালিকাকে জোড়া লাগানো |
| `05-configmap.yaml` | ConfigMap | Vector এর মূল **সেটিং/নিয়ম** (এটাই সবচেয়ে গুরুত্বপূর্ণ) |
| `06-daemonset.yaml` | DaemonSet | Vector কে **প্রতিটা node/server এ চালু** রাখা |
| `07-kustomization.yaml` | Kustomization | সব ফাইল একসাথে apply করার তালিকা |

> **মনে রাখার সহজ উপায়:** ৫ নম্বর ফাইল বলে দেয় Vector *"কী করবে"*, আর ৬ নম্বর ফাইল বলে দেয় Vector *"কোথায় চলবে"*।

---

## ৩. কিছু দরকারি Kubernetes শব্দ (Beginner রা এখানে আটকায়)

- **Pod:** এক বা একাধিক container এর ছোট প্যাকেট। তোমার অ্যাপ একটা Pod এর ভেতরে চলে।
- **Node:** একটা আসল সার্ভার/মেশিন, যার ওপর অনেকগুলো Pod চলে।
- **Namespace:** Pod গুলোকে ভাগ করে রাখার "ফোল্ডার" বা "রুম"। **Vector নিজে `logging` রুমে চলে**, আর যে অ্যাপের log নেয় (`robodoc-backend`) সেটা `robodoc` রুমে থাকে।
- **DaemonSet:** এমন একটা নিয়ম যেটা বলে — "প্রতিটা Node এ এই Pod টার **একটা করে কপি** চালু রাখো"।
  log সব Node এ ছড়িয়ে থাকে, তাই log collector কেও সব Node এ থাকতে হয় → এজন্য DaemonSet.
- **ConfigMap:** সেটিং/কনফিগ রাখার জায়গা। কোড না বদলে শুধু সেটিং বদলানো যায়।
- **hostPath:** Node এর আসল ডিস্কের একটা ফোল্ডার Pod এর ভেতরে ঢুকিয়ে দেওয়া (mount)।

---

## ৪. ConfigMap (`05-configmap.yaml`) — লাইন ধরে ব্যাখ্যা

এটাই Vector এর "মগজ"। এখানে তিনটা অংশ: **sources → transforms → sinks**।

### ৪.১ `data_dir`

```yaml
data_dir: /var/lib/vector
```
Vector কোন লাইন পর্যন্ত পড়েছে (offset) সেই হিসাব এখানে জমা রাখে। Pod restart হলেও যাতে
আগের জায়গা থেকে আবার শুরু করতে পারে, ডুপ্লিকেট না পাঠায়।

### ৪.২ Sources — log কোথা থেকে আসবে

```yaml
sources:
  kubernetes_logs:
    type: kubernetes_logs
    extra_field_selector: metadata.namespace=robodoc

  internal_metrics:
    type: internal_metrics
```

- **`kubernetes_logs`**: এটা Kubernetes এর সব container log স্বয়ংক্রিয়ভাবে পড়ে।
  container log এর সামনে একটা টেকনিক্যাল অংশ থাকে (যেমন `2026-06-17T10:00:00Z stdout F ...`) —
  Vector সেটা নিজে থেকেই সরিয়ে আসল মেসেজটা `.message` এ রেখে দেয়।
  (Filebeat এ এই কাজটা `parsers: - container: ~` করত)।
- **`extra_field_selector: metadata.namespace=robodoc`**: শুধু `robodoc` রুমের log টানবে, বাকিগুলো না।
- **`internal_metrics`**: Vector নিজে কেমন চলছে (কত log পাঠালো, error হলো কিনা) — নিজের health তথ্য।

### ৪.৩ Transforms — log পরিষ্কার আর দরকারি অংশ বের করা

এটা VRL (Vector Remap Language) নামের ছোট স্ক্রিপ্ট দিয়ে লেখা। ধাপগুলো:

```yaml
# ১) শুধু robodoc-backend-production Pod এর log রাখো, বাকি বাদ
pod = to_string(.kubernetes.pod_name) ?? ""
if !starts_with(pod, "robodoc-backend-production") { abort }
```
`abort` মানে — এই log টা ফেলে দাও, সামনে আর নিয়ে যেও না।

```yaml
msg = to_string(.message) ?? ""

if msg == "" { abort }                                  # ২) ফাঁকা লাইন বাদ
if match(msg, r'^\d+\.\d+\.\d+\.\d+ -\s') { abort }     # ৩) Nginx access log বাদ
if contains(msg, "\"OPTIONS ") { abort }                # ৪) OPTIONS রিকোয়েস্ট বাদ
if !contains(msg, "k8s|") { abort }                     # ৫) "k8s|" না থাকলে বাদ
```
মানে আমরা শুধু সেই log রাখছি যেগুলোতে `k8s|` লেখা আছে (আসল দরকারি API log)।

```yaml
# ৬) কোন Node থেকে এসেছে + log এর ধরন ট্যাগ করা
.node_name = get_env_var("VECTOR_SELF_NODE_NAME") ?? ""
.log_type  = "robodoc-backend"
```

```yaml
# ৭) "k8s|" এর পরের অংশ থেকে URL আর JSON আলাদা করা
# ফরম্যাট:  k8s|{url} {json}
after   = split(msg, "k8s|", limit: 2)[1] ?? ""
parts   = split(after, " ", limit: 2)
.api_url = parts[0] ?? ""      # URL
payload  = parts[1] ?? ""      # JSON টেক্সট

parsed, err = parse_json(payload)   # JSON টেক্সট কে আসল অবজেক্টে রূপান্তর
if err == null { .api = parsed }     # সফল হলে .api ফিল্ডে রাখো
```

```yaml
# ৮) অপ্রয়োজনীয় ফিল্ড মুছে ফেলা (জায়গা বাঁচে, পরিষ্কার থাকে)
del(.message)
del(.source_type)
del(.stream)
del(.file)
```

### ৪.৪ Sinks — পরিষ্কার log কোথায় যাবে

```yaml
sinks:
  elasticsearch:
    type: elasticsearch
    inputs: [robodoc_backend]
    endpoints:
      - "http://${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}"
    auth:
      strategy: basic
      user: "${ELASTICSEARCH_USER}"
      password: "${ELASTICSEARCH_PASSWORD}"
    healthcheck: false
    compression: gzip
    bulk:
      index: "kubernetes-{{ log_type }}-logs-%Y.%m"
```

- **`inputs: [robodoc_backend]`**: উপরের transform এর আউটপুট এখানে ঢুকছে।
- **`endpoints`**: Elasticsearch এর ঠিকানা। `${...}` মানগুলো environment variable থেকে আসে
  (DaemonSet এ ঠিক করা আছে, নিচে দেখো)।
- **`auth`**: Elasticsearch এ ঢোকার username/password।
- **`index`**: log কোন index এ জমা হবে। উদাহরণ → `kubernetes-robodoc-backend-logs-2026.07`
  (`%Y.%m` মানে বছর.মাস, তাই প্রতি মাসে নতুন index)।

```yaml
  prometheus:
    type: prometheus_exporter
    inputs: [internal_metrics]
    address: 0.0.0.0:9090
```
Vector এর নিজের metrics `9090` পোর্টে দেখা যাবে (Prometheus দিয়ে monitor করা যায়)।
Filebeat এ এটা `5066` পোর্টে ছিল।

---

## ৫. DaemonSet (`06-daemonset.yaml`) — লাইন ধরে ব্যাখ্যা

ConfigMap বলল "কী করবে", আর DaemonSet বলে **"কোথায় আর কীভাবে চলবে"**।

```yaml
kind: DaemonSet          # প্রতিটা Node এ ১টা করে Vector Pod চলবে
metadata:
  name: vector
  namespace: logging
```

### ৫.১ Container আর Image

```yaml
containers:
- name: vector
  image: timberio/vector:0.46.1-alpine   # Vector এর তৈরি সফটওয়্যার
  args:
    - --config
    - /etc/vector/vector.yaml             # কোন কনফিগ ফাইল পড়বে
```

### ৫.২ Environment Variables (গোপন তথ্য এখানে আসে)

```yaml
env:
- name: VECTOR_SELF_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName            # Pod টা কোন Node এ আছে সেই নাম
```
এই নামটাই ConfigMap এ `.node_name` ফিল্ডে বসে।

```yaml
- name: ELASTICSEARCH_HOST
  valueFrom:
    secretKeyRef:                          # ES এর সব মান একটা Secret থেকে
      name: vector-elasticsearch
      key: ELASTICSEARCH_HOST
- name: ELASTICSEARCH_PASSWORD
  valueFrom:
    secretKeyRef:                          # পাসওয়ার্ড Secret থেকে (নিরাপদ)
      name: vector-elasticsearch
      key: ELASTICSEARCH_PASSWORD
```

> ⚠️ **গুরুত্বপূর্ণ:** `configMapKeyRef`/`secretKeyRef` শুধু **একই namespace** থেকে মান নিতে পারে।
> Vector এখন `logging` namespace এ চলে, কিন্তু `robodoc-backend-production` ConfigMap/Secret টা
> `robodoc` namespace এ — তাই সেটা পড়া যেত না। এজন্য `logging` namespace এ Vector এর নিজের একটা
> `vector-elasticsearch` Secret বানানো হয়েছে (`00-elasticsearch.example.yaml` দেখো), যেখানে ES এর
> host/port/user/password থাকে। **Vector চালানোর আগে এই Secret অবশ্যই তৈরি করতে হবে।**

### ৫.৩ Volumes (Node এর ফোল্ডার Pod এ ঢোকানো)

log ফাইলগুলো Node এর ডিস্কে থাকে, তাই সেই ফোল্ডারগুলো Vector Pod এর ভেতরে দিতে হয়:

```yaml
volumeMounts:
  - name: config          # ConfigMap → /etc/vector (কনফিগ ফাইল)
    mountPath: /etc/vector
    readOnly: true
  - name: varlogcontainers  # /var/log/containers (log এর symlink)
    mountPath: /var/log/containers
    readOnly: true
  - name: varlogpods        # /var/log/pods (আসল log ফাইল)
    mountPath: /var/log/pods
    readOnly: true
  - name: data              # offset হিসাব রাখার জায়গা
    mountPath: /var/lib/vector
```

```yaml
volumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods       # Node এর আসল ফোল্ডার
      type: DirectoryOrCreate
```
`hostPath` = Node এর আসল ডিস্কের ফোল্ডার। `readOnly: true` মানে Vector শুধু পড়বে, লিখবে না।

---

## ৬. পুরো ফ্লো এক নজরে

```
                (প্রতি Node এ ১টা Vector Pod — DaemonSet)
                              │
robodoc-backend Pod ──log──▶ /var/log/pods (Node এর ডিস্ক)
                              │
                              ▼
                     ┌─────────────────┐
                     │  Vector (Pod)   │
                     │                 │
   kubernetes_logs ─▶│  Source: log ধরা│
                     │       ↓         │
                     │  Transform:     │
                     │   • ফিল্টার      │
                     │   • k8s| খোঁজা   │
                     │   • JSON parse   │
                     │       ↓         │
                     │  Sink: পাঠানো   │
                     └────────┬────────┘
                              │
                              ▼
                       Elasticsearch
              index: kubernetes-robodoc-backend-logs-2026.07
```

---

## ৭. কীভাবে চালু (deploy) করবে

`07-kustomization.yaml` এ সব ফাইলের তালিকা আছে। দুইভাবে apply করা যায়:

**উপায় ১ — এক এক করে (সবচেয়ে সহজ, সবসময় কাজ করে):**

```bash
kubectl apply -f vector/01-namespace.yaml
# ES creds Secret বানাও (example কপি করে আসল মান বসিয়ে):
cp vector/00-elasticsearch.example.yaml vector/00-elasticsearch.yaml
# ...00-elasticsearch.yaml এডিট করে host/user/password বসাও, তারপর:
kubectl apply -f vector/00-elasticsearch.yaml
kubectl apply -f vector/02-serviceaccount.yaml
kubectl apply -f vector/03-clusterrole.yaml
kubectl apply -f vector/04-clusterrolebinding.yaml
kubectl apply -f vector/05-configmap.yaml
kubectl apply -f vector/06-daemonset.yaml
```

**উপায় ২ — পুরো ফোল্ডার একসাথে:**

```bash
kubectl apply -f vector/
```

> নোট: `kubectl -k` (kustomize) ব্যবহার করতে হলে ফাইলের নাম হুবহু `kustomization.yaml`
> হতে হয়। এখন এটার নাম `07-kustomization.yaml`, তাই `-k` কাজ করবে না — উপরের উপায়
> ১ বা ২ ব্যবহার করো।

---

## ৮. ঠিকঠাক চলছে কিনা যেভাবে দেখবে

```bash
# প্রতিটা Node এ Pod চালু হয়েছে কিনা
kubectl get pods -n logging -l app=vector -o wide

# Vector এর log দেখা (কোনো error আছে কিনা)
kubectl logs -n logging -l app=vector -f

# Vector এর নিজের metrics দেখা
kubectl port-forward -n logging <pod-name> 9090:9090
# তারপর ব্রাউজারে: http://localhost:9090/metrics
```

Elasticsearch এ index এসেছে কিনা:

```bash
curl -u "$ELASTICSEARCH_USER:$ELASTICSEARCH_PASSWORD" \
  "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/_cat/indices/kubernetes-robodoc-backend-logs-*?v"
```

---

## ৯. সমস্যা হলে (Troubleshooting)

| সমস্যা | সম্ভাব্য কারণ | সমাধান |
|--------|---------------|--------|
| Pod `CrashLoopBackOff` | কনফিগে ভুল / ES creds ভুল | `kubectl logs` দেখো, ConfigMap ঠিক করো |
| Elasticsearch এ log আসছে না | filter খুব কড়া (`k8s|` না থাকলে সব বাদ) | transform এর নিয়ম মিলিয়ে দেখো |
| Pod `CreateContainerConfigError` | `vector-elasticsearch` Secret নেই | `logging` namespace এ Secret টা apply করেছ কিনা দেখো |
| `secret not found` error | ES Secret ভুল namespace এ | `vector-elasticsearch` Secret `logging` এ আছে কিনা দেখো |
| একই log বারবার | offset হারিয়েছে | `data` volume (`/var/lib/vector-data`) ঠিক আছে কিনা দেখো |

---

## ১০. Filebeat আর Vector এর তুলনা (এক নজরে)

| কাজ | Filebeat | Vector (এখানে) |
|-----|----------|----------------|
| log পড়া | `filestream` input | `kubernetes_logs` source |
| CRI prefix সরানো | `parsers: container` | স্বয়ংক্রিয় |
| ফিল্টার/পরিষ্কার | `processors` | `transforms` (VRL) |
| Elasticsearch এ পাঠানো | `output.elasticsearch` | `elasticsearch` sink |
| Metrics পোর্ট | `5066` | `9090` (Prometheus) |
| কোথায় চলে | DaemonSet | DaemonSet |

দুইটাই একই কাজ করে — শুধু Vector এর কনফিগ বেশি নমনীয় (flexible) আর VRL দিয়ে
জটিল রূপান্তরও সহজে করা যায়।
