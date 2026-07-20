# OpenTelemetry (OTel) Metrics & Tracing Pipeline

এই ডিরেক্টরিতে Kubernetes ক্লাস্টারের জন্য একটি **উৎপাদন-মানের (production-grade) OpenTelemetry (OTel) metrics & tracing pipeline** কনফিগারেশন ম্যানিফেস্ট রয়েছে। এটি আপনার অ্যাপ্লিকেশনের পারফরম্যান্স মেট্রিক্স সংগ্রহ করে প্রমিথিউস (Prometheus) বাইনারি স্ট্যাকে এবং রিকোয়েস্ট ট্রেসিং/স্প্যান ডেটা আপনার বাইরের সার্ভারে চলমান **Grafana Tempo (বাইনারি)** সার্ভিসে সরবরাহ করে।

---

## ১. প্রসেস লাইফসাইকেল এবং আর্কিটেকচার (Process Lifecycle & Architecture)

OpenTelemetry মেট্রিক্স এবং ট্রেসিং লাইফসাইকেলের চিত্র নিচে দেওয়া হলো:

```
[robodoc-backend] -------- OTLP (HTTP/protobuf) -------> [ OTel Collector ]
[robodoc-frontend]                                      /                \
                                             (Metrics) /                  \ (Traces: OTLP/gRPC)
                                                      v                    v
                                            [ Prometheus NodePort ]   [ External Tempo (Binary) ]
                                                (Port 30889)            (Port 4317 / 3200)
                                                      |                    |
                                                      v                    v
                                                [ Prometheus ] -------> [ Grafana ]
```

### কাজের ধাপসমূহ (How it works):
1. **Push Telemetry (মেট্রিক্স ও ট্রেস পাঠানো):** ফ্রন্টএন্ড (`robodoc-customer-frontend`) এবং ব্যাকএন্ড (`robodoc-backend`) অ্যাপ্লিকেশন পডগুলো থেকে OTLP প্রোটোকলের মাধ্যমে মেট্রিক্স ও স্প্যান (Traces) OTel Collector পডে পাঠানো হয়।
2. **OTel Collector (প্রসেসিং):** OTel Collector পডটি এই ডেটা গ্রহণ করে এবং মেমরি লিমিট নিয়ন্ত্রণ ও ব্যাচিং (batching)-এর মাধ্যমে মেট্রিক্স এবং ট্রেস আলাদা লাইনে প্রসেস করে।
3. **Exporters (ডেটা পাঠানো):** 
   - **Metrics:** Collector মেট্রিক্সগুলোকে একটি প্রমিথিউস স্ক্র্যাপ এন্ডপয়েন্টে (Port `8889`) রূপান্তর করে যা NodePort `30889` এর মাধ্যমে ক্লাস্টারের বাইরে প্রমিথিউসে স্ক্র্যাপের জন্য এক্সপোজ করা থাকে।
   - **Traces:** Collector স্প্যানগুলোকে OTLP/gRPC এর মাধ্যমে বাইরের সার্ভারে চলমান **Grafana Tempo** সার্ভিসে (Port `4317`) পাঠিয়ে দেয়।
4. **Grafana Visualization (ইউজার ইন্টারফেস):** গ্রাফানা (Grafana) প্রমিথিউস থেকে মেট্রিক্স এবং টেম্পো থেকে স্প্যান কুয়েরি করে একই ড্যাশবোর্ডে প্রদর্শন করে।

---

## ২. ফাইলসমূহের বিবরণ (File Descriptions)

এই ফোল্ডারে নিম্নলিখিত কনফিগারেশন ফাইলগুলো রয়েছে:

| ফাইলের নাম | Kubernetes অবজেক্ট | কাজের বিবরণ |
| :--- | :--- | :--- |
| `00-namespace.yaml` | Namespace | OTel Collector চালানোর জন্য একটি পৃথক নেমস্পেস `opentelemetry` তৈরি করে। |
| `01-otel-collector-configmap.yaml` | ConfigMap | কালেক্টরের রিসিভার, প্রসেসর, এক্সপোর্টার এবং পাইপলাইন কনফিগারেশন ধারণ করে। |
| `02-otel-collector-deployment.yaml` | Deployment | কালেক্টর পডের রেপ্লিক্যাসেট, ইমেজ ভার্সন, রিসোর্স লিমিট এবং প্রোবসমূহ পরিচালনা করে। |
| `03-otel-collector-service.yaml` | Service (ClusterIP) | ওটিএলপি gRPC/HTTP এবং মেট্রিক্স পোর্টগুলোর ক্লাস্টার-অভ্যন্তরীণ যোগাযোগের জন্য সার্ভিস। |
| `04-otel-collector-service-nodeport.yaml` | Service (NodePort) | ক্লাস্টারের বাইরে প্রমিথিউসে মেট্রিক্স এক্সপোজ করার জন্য NodePort সার্ভিস। |
| `kustomization.yaml` | Kustomization | এই ফোল্ডারের সমস্ত ম্যানিফেস্টকে একসাথে যুক্ত করে যাতে একটি একক কম্যান্ড দিয়ে ওটেল মেট্রিক্স ও ট্রেস পাইপলাইন ডেপ্লয় করা যায়। |

---

## ৩. ডেপ্লয়মেন্ট নির্দেশিকা (Deployment Guide)

টার্মিনাল থেকে পুরো স্ট্যাকটি ডেপ্লয় করতে নিচের ধাপগুলো অনুসরণ করুন:

### ধাপ ১: Tempo সার্ভার আইপি কনফিগার করা
আপনার ওটেল কালেক্টর যাতে বাইরের টেম্পো বাইনারিতে ট্রেস পাঠাতে পারে, সেজন্য [02-otel-collector-deployment.yaml](file:///Users/test/Documents/practice/kubernetes/k8s-robodoc/opentelemetry/02-otel-collector-deployment.yaml) ফাইলের Deployment সেকশনে `TEMPO_ENDPOINT` এর মান হিসেবে আপনার টেম্পো সার্ভারের IP এবং gRPC পোর্ট (ডিফল্ট `4317`) সেট করুন:

```yaml
          env:
            - name: TEMPO_ENDPOINT
              value: "143.198.138.192:4317" # আপনার বাইরের টেম্পো আইপি ও পোর্ট বসান
```

### ধাপ ২: OpenTelemetry স্ট্যাক ডেপ্লয় করা
আপনার ক্লাস্টার টার্মিনালে এই কমান্ডটি চালান:
```bash
kubectl apply -k opentelemetry/
```
এটি নেমস্পেস, ওটেল কালেক্টর এবং সংশ্লিষ্ট সার্ভিসসমূহ ডেপ্লয় করে দেবে।

### ধাপ ৩: অ্যাপ্লিকেশন কনফিগারেশন আপডেট করা
আপনার ব্যাকএন্ড ও ফ্রন্টএন্ড অ্যাপ্লিকেশনগুলো যাতে ওটেল কালেক্টরে মেট্রিক্স এবং স্প্যান পাঠাতে পারে, সেজন্য তাদের ConfigMap-এ ওটেল ইন্টিগ্রেশন সচল করতে হবে।

**ব্যাকএন্ডের জন্য (`robodoc-backend-k8s-production/configmap.yaml`):**
```yaml
data:
  OTEL_SERVICE_NAME: "robodoc-backend"
  OTEL_TRACES_EXPORTER: "otlp"    # ওটিএলপি ট্রেসিং সচল করা হয়েছে
  OTEL_METRICS_EXPORTER: "otlp"   # মেট্রিক্স ওটিএলপিতে পাঠানো হবে
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.opentelemetry.svc.cluster.local:4318"
  OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf"
```

অ্যাপ্লিকেশনগুলো নতুন সেটিংস গ্রহণ করার জন্য ডেপ্লয়মেন্টগুলো রিস্টার্ট করুন:
```bash
kubectl apply -f robodoc-backend-k8s-production/configmap.yaml
kubectl rollout restart deployment/robodoc-backend-production -n robodoc
```

---

## ৪. গ্রাফানা টেম্পো ইন্টিগ্রেশন (Grafana Tempo Integration)

আপনার গ্রাফানায় টেম্পো থেকে স্প্যান দেখাতে নিচের ধাপগুলো অনুসরণ করুন:

### ৪.১. Grafana-তে Tempo Data Source যোগ করা
1. আপনার গ্রাফানা পোর্টালে লগইন করুন।
2. বাঁদিকের মেনু থেকে **Connections** -> **Data Sources**-এ যান।
3. **Add data source** বাটনে ক্লিক করে **Tempo** সিলেক্ট করুন।
4. কনফিগারেশনে নিচের প্রোপার্টিগুলো সেট করুন:
   - **Name:** `Tempo`
   - **URL:** `http://<YOUR_TEMPO_SERVER_IP>:3200` (টেম্পো বাইনারির HTTP লিসেন পোর্ট)
5. নিচে স্ক্রোল করে **Save & test** বাটনে ক্লিক করুন। আপনি `Data source is working` সাকসেস মেসেজ দেখতে পাবেন।

### ৪.২. ট্রেস খোঁজা ও যাচাইকরণ (Explore Traces)
1. গ্রাফানার বাঁদিকের মেনু থেকে **Explore** ট্যাবে যান।
2. ওপরে ডাটা সোর্স ড্রপডাউন থেকে **Tempo** নির্বাচন করুন।
3. **Search** ট্যাবে গিয়ে `Service Name` এ `robodoc-backend` সিলেক্ট করে **Run query** বাটনে ক্লিক করুন।
4. রিকোয়েস্টগুলোর টাইমলাইন ও স্প্যান ডিটেইলস সুন্দরভাবে দেখতে পাবেন!
