# Envoy Gateway গাইড (বাংলা)

## ১. পরিচিতি

Envoy Gateway হচ্ছে Kubernetes-এর জন্য একটি API Gateway যা Envoy Proxy ব্যবহার করে। এটি Gateway API স্ট্যান্ডার্ড অনুসরণ করে এবং Kubernetes ক্লাস্টারের উপরে HTTP/HTTPS ট্র্যাফিক রাউটিং সহজ করে।

এই ফোল্ডারে নীচের ম্যানিফেস্টগুলো আছে:

- `00-envoy-proxy.yaml` - Envoy Proxy কনফিগারেশন
- `01-gateway-class.yaml` - GatewayClass ডেফিনিশন
- `02-gateway.yaml` - Gateway ইনস্ট্যান্স
- `10-route-admin.yaml` - অ্যাডমিন সাইটের HTTPRoute
- `11-route-customer.yaml` - কাস্টমার সাইটের HTTPRoute
- `kustomization.yaml` - কাস্টমাইজেশন ফাইল

---

## ২. Envoy Gateway কীভাবে কাজ করে

### প্রধান ধারণা

1. **GatewayClass**: এটি পরিবেশের কন্ট্রোলার ও ইমপ্লিমেন্টেশন নির্ধারণ করে। এখানে `gateway.envoyproxy.io/gatewayclass-controller` ব্যবহার করা হয়েছে।
2. **Gateway**: ক্লাস্টারে একটি ইনস্ট্যান্স তৈরি করে যা ইনকামিং ট্র্যাফিক গ্রহণ করে।
3. **HTTPRoute**: কোন হোস্ট/পাথ কোন সার্ভিসে যাবে তা নির্ধারণ করে।
4. **EnvoyProxy**: Envoy-এর নির্দিষ্ট কনফিগারেশন যা GatewayClass দিয়ে রেফারেন্স করা হয়।

### আগের থেকে পরবর্তী প্রবাহ

- ব্যবহারকারী ক্লাস্টারের বাইরে URL এ রিকোয়েস্ট করে।
- Kubernetes এ Envoy Gateway লিসেন করে `Gateway` এর মাধ্যমে।
- `HTTPRoute` নির্ধারিত হোস্ট ও পাথ অনুযায়ী সার্ভিসে রিকোয়েস্ট ফরোয়ার্ড করে।
- ব্যাকএন্ড সার্ভিস রেসপন্স পাঠায়।
- Envoy আবার রেসপন্স ক্লায়েন্টকে ফেরত দেয়।

---

## ৩. ম্যানিফেস্ট ফাইলের বিস্তারিত

### 00-envoy-proxy.yaml

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: robodoc-prod
  namespace: robodoc
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
```

- এটি Envoy Proxy নির্ধারণ করে।
- `namespace: robodoc` ব্যবহার করা হয়েছে, মানে এই রিসোর্স ও Gateway একই নেমস্পেসে থাকতে হবে।
- `envoyService.type: NodePort` মানে Kubernetes ক্লাস্টারে Envoy Service NodePort হিসেবে তৈরি হবে।

### 01-gateway-class.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: robodoc-prod
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: robodoc-prod
    namespace: robodoc
```

- `GatewayClass` বলে দেয় কোন কন্ট্রোলার এই গেটওয়েট হ্যান্ডেল করবে।
- `parametersRef` এর মাধ্যমে `EnvoyProxy` রিসোর্সে কনফিগারেশন দেখানো হয়েছে।

### 02-gateway.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: robodoc-prod
  namespace: robodoc
spec:
  gatewayClassName: robodoc-prod
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

- এটি একটি `Gateway` ইনস্ট্যান্স তৈরি করে।
- `gatewayClassName` `GatewayClass` কে রেফার করে।
- `listeners` এ HTTP 80 পোর্ট লিসেন করা হবে।

### 10-route-admin.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: robodoc-admin-route
  namespace: robodoc
spec:
  parentRefs:
    - name: robodoc-prod
      namespace: robodoc
  hostnames:
    - admin.robodocbd.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      timeouts:
        request: 60s
        backendRequest: 55s
      backendRefs:
        - name: robodoc-backend-production
          port: 80
```

- `HTTPRoute` বলে দেয় `admin.robodocbd.com` হোস্টে আসা রিকোয়েস্ট কোথায় যাবে।
- `backendRefs` এ ব্যাকএন্ড সার্ভিস `robodoc-backend-production` দেখানো হয়েছে।
- `PathPrefix /` মানে সব পাথ এই রুটে কাজ করবে।

### 11-route-customer.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: robodoc-customer-route
  namespace: robodoc
spec:
  parentRefs:
    - name: robodoc-prod
      namespace: robodoc
  hostnames:
    - robodocbd.com
    - www.robodocbd.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      timeouts:
        request: 60s
        backendRequest: 55s
      backendRefs:
        - name: robodoc-customer-production
          port: 80
```

- এখানে কাস্টমার ডোমেইনগুলো `robodocbd.com` ও `www.robodocbd.com`।
- ব্যাকএন্ড সার্ভিস `robodoc-customer-production`।

### kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 00-envoy-proxy.yaml
  - 01-gateway-class.yaml
  - 02-gateway.yaml
  - 10-route-admin.yaml
  - 11-route-customer.yaml
```

- এটি একসাথে সব কনফিগ ফাইল একসাথে প্রয়োগ করার জন্য।
- `kubectl apply -k .` করলে সব ফাইল একবারেই প্রয়োগ হবে।

---

## ৪. Envoy Gateway এর স্টেপ-বাই-স্টেপ রান

### ৪.১ প্রাথমিক চেক

1. Kubernetes ক্লাস্টার চালু আছে কিনা চেক করুন:

```bash
kubectl cluster-info
```

2. `robodoc` নেমস্পেস আছে কিনা দেখুন:

```bash
kubectl get ns
```

3. যদি নেমস্পেস না থাকে:

```bash
kubectl create namespace robodoc
```

> লক্ষ করুন: এই ফোল্ডারে নেমস্পেস ডেফিনিশন নেই, তাই `robodoc` নেমস্পেস আগে তৈরি করতে হবে।

### ৪.২ Envoy Gateway ইনস্টলেশন

`envoy-gateway` সাধারণত Helm বা কুবectl দিয়ে ইনস্টল করা হয়। এই ফোল্ডারে কেবল Gateway API রিসোর্স আছে, কন্ট্রোলার ইনস্টল নেই।

Envoy Gateway কন্ট্রোলার যদি আগে ইনস্টল করা না থাকে, তবে অফিসিয়াল ডকুমেন্টেশন অনুযায়ী ইনস্টল করতে হবে:

```bash
kubectl create namespace envoy-gateway-system
kubectl apply -f https://raw.githubusercontent.com/envoyproxy/gateway/main/config/release/standard/envoy-gateway.yaml
```

> এই কমান্ডটি বর্তমান রিলিজ বা কনফিগ অনুযায়ী পরিবর্তিত হতে পারে। অফিসিয়াল রিপোজিটরি দেখে নিন।

### ৪.৩ রিসোর্স প্রয়োগ

`envoy-gateway` ডিরেক্টরিতে গিয়ে সব রিসোর্স প্রয়োগ করুন:

```bash
cd /Users/test/Documents/practice/kubernetes/k8s-robodoc/envoy-gateway
kubectl apply -k .
```

### ৪.৪ রিসোর্স পরীক্ষা

প্রয়োগের পর চেক করুন:

```bash
kubectl get gatewayclasses
kubectl get gateways -n robodoc
kubectl get httproutes -n robodoc
kubectl get envoyproxy -n robodoc
```

### ৪.৫ সার্ভিস ও পোর্ট চেক

Envoy Proxy `NodePort` সার্ভিস তৈরি হলে দেখতে পারেন:

```bash
kubectl get svc -n robodoc
```

NodePort পোর্ট পেয়ে গেলে বাইরের থেকে অ্যাক্সেস করবার জন্য সেই নোডের IP/পোর্ট ব্যবহার করুন।

### ৪.৬ DNS বা হোস্ট ফাইল কনফিগারেশন

`HTTPRoute` এ ডোমেইন `admin.robodocbd.com`, `robodocbd.com`, `www.robodocbd.com` ব্যবহৃত হয়েছে।
- যদি ডোমেইন ভিন্ন হয়, `hostnames` পরিবর্তন করুন।
- ডেভ-এ পরীক্ষার জন্য `/etc/hosts` এ নোড IP ও ডোমেইন ম্যাপ করতে পারেন।

উদাহরণ:

```text
<node-ip> admin.robodocbd.com robodocbd.com www.robodocbd.com
```

---

## ৫. উন্নত বিষয়বস্তু (Advanced)

### ৫.১ `GatewayClass` ও `Gateway` সম্পর্ক

- `GatewayClass` মূলত কন্ট্রোলার টাইপ এবং প্যারামিটার নির্ধারণ করে।
- `Gateway` ব্যবহারকারীর লিসেনার, পোর্ট, প্রোটোকল সেট করে।
- একাধিক `Gateway` একই `GatewayClass` শেয়ার করতে পারে।

### ৫.২ `HTTPRoute` কাস্টমাইজেশন

`HTTPRoute`-এ আপনি নিম্নলিখিত উন্নত ফিচার ব্যবহার করতে পারেন:
- `matches` এ প্রিসাইস পাথ রুল
- `filters` যোগ করে রেট লিমিট, JWT, রিডাইরেক্ট ইত্যাদি
- `backendRefs`-এ একাধিক সার্ভিস রেফারেন্স
- `timeouts` ও `retries`

### ৫.৩ EnvoyProxy কাস্টমাইজেশন

`EnvoyProxy` ব্যবহার করলে আপনি নিম্নলিখিত কনফিগারেশন অ্যাড করতে পারেন:
- `envoyService` টাইপ `LoadBalancer`, `ClusterIP`, `NodePort`
- `gatewayProvider` কনফিগারেশন
- লগিং এবং মনিটরিং সেটিংস

### ৫.৪ `NodePort` vs `LoadBalancer`

- `NodePort`: সাধারণত লোকাল ডেভ বা প্রাইভেট ক্লাস্টারে ব্যবহার হয়।
- `LoadBalancer`: ক্লাউড পরিবেশে এক্সটার্নাল LB প্রোভাইডার ব্যবহার করলে।

### ৫.৫ ডিবাগিং

- `kubectl describe gateway -n robodoc robodoc-prod`
- `kubectl describe httproute -n robodoc robodoc-customer-route`
- `kubectl get events -n robodoc`
- `kubectl logs -n envoy-gateway-system -l app=envoy-gateway`

---

## ৬. অতিরিক্ত টিপস

- প্রথমে `namespace` তৈরি করুন।
- `GatewayClass` ও `Gateway` একই `namespace`-এ থাকতে হবে না, কিন্তু `parametersRef` যেখানে আছে সেই `namespace` ঠিক রাখতে হবে।
- ডোমেইন পরিবর্তন করলে `hostnames` আপডেট করুন।
- যদি HTTP-র পরিবর্তে HTTPS চালাতে চান, `Gateway` এ TLS লিসেনার ও `TLSRoute` ব্যবহার করতে হবে।

---

## ৭. সিম্পল ওয়ার্কফ্লো

1. `robodoc` নেমস্পেস তৈরি করুন
2. Envoy Gateway কন্ট্রোলার ইনস্টল করুন
3. `kubectl apply -k .` চালান
4. `kubectl get gateway,httproute,envoyproxy -n robodoc` চেক করুন
5. সার্ভিস ও পোর্ট চেক করুন
6. DNS/হোস্ট ফাইল কনফিগার করে ট্র্যাফিক পাঠান

---

## ৮. উপসংহার

এই ফোল্ডারের সেটআপ `Envoy Gateway`-এর সাথে HTTP ট্র্যাফিক রাউট করা সহজ করে।
- `GatewayClass` ও `EnvoyProxy` Envoy কনফিগার করে।
- `Gateway` ইনকামিং ট্রাফিক গ্রহণ করে।
- `HTTPRoute` নির্দিষ্ট হোস্ট ও ব্যাকএন্ড সার্ভিসকে ম্যাপ করে।

নতুনদের জন্য, প্রথমে ম্যানিফেস্টগুলো ধাপে ধাপে বুঝুন, তারপর `kubectl apply -k .` দিয়ে প্রয়োগ করুন।

এখন আপনি এই ফাইলটিকে `envoy-gateway/README.md` হিসেবে ব্যবহার করতে পারেন।
