# Argo CD GitOps Configuration for Robodoc

This directory contains Declarative GitOps configuration manifests for managing the **Robodoc Backend** and **Robodoc Customer (Frontend)** microservices on Kubernetes using [Argo CD](https://argoproj.github.io/cd/).

---

## Files

| File | Type | Description |
|---|---|---|
| [`run.sh`](run.sh) / [`start.sh`](start.sh) | Script | Starts or resumes Argo CD, waits for components to be ready, applies manifests, and retrieves admin credentials. |
| [`stop.sh`](stop.sh) | Script | Safely pauses Argo CD (scales pods to 0), stops applications, or completely uninstalls Argo CD. |
| [`robodoc-backend-application.yaml`](robodoc-backend-application.yaml) | `Application` | Configures Argo CD to sync `robodoc-backend-k8s-production/` from GitHub into the `robodoc` namespace. |
| [`robodoc-customer-application.yaml`](robodoc-customer-application.yaml) | `Application` | Configures Argo CD to sync `robodoc-frontend-k8s-production/` from GitHub into the `robodoc` namespace. |
| [`robodoc-project.yaml`](robodoc-project.yaml) | `AppProject` | Dedicated Argo CD Project (`robodoc`) defining repository, namespace, and resource whitelists. |

---

## 1. Running Argo CD

We provide automated scripts to start Argo CD and apply all Robodoc applications in a single command.

### Start / Resume Argo CD
```bash copy
cd argocd
./run.sh
# or
./start.sh
```

### Start with Automatic Web UI Port-Forwarding
```bash copy
./run.sh --port-forward
# or
./run.sh -p
```

### What `./run.sh` Does:
1. **Checks Prerequisites**: Verifies `kubectl` and Kubernetes cluster connection.
2. **Auto-Installs or Resumes**:
   - If Argo CD is not installed, creates the `argocd` namespace and applies official stable manifests.
   - If Argo CD was previously paused (`./stop.sh`), wakes it up by scaling deployments & statefulset back to 1 replica.
3. **Health Verification**: Waits for all Argo CD deployments and statefulsets to become healthy/available.
4. **Applies GitOps Manifests**: Applies `robodoc-project.yaml`, `robodoc-backend-application.yaml`, and `robodoc-customer-application.yaml`.
5. **Prints Credentials & Access Info**: Displays admin credentials, application statuses, and Web UI access instructions.

---

## 2. Stopping Argo CD

We provide flexible stopping modes via [`./stop.sh`](stop.sh):

### Option A: Safe Stop / Pause (Default - Recommended)
Scales all Argo CD deployments and statefulsets down to `0` replicas and terminates active port-forwarding:
```bash copy
./stop.sh
```
- **Zero Resource Consumption**: All Argo CD pods terminate, releasing cluster CPU and memory.
- **Sync Paused**: GitOps self-healing and auto-sync are paused.
- **No Data Loss**: All configuration, secrets, and application definitions remain preserved.
- **Workloads Kept Alive**: Production services in the `robodoc` namespace remain untouched and running.
- **Resume Anytime**: Run `./run.sh` to resume right where you left off.

### Option B: Stop / Remove Applications Only
Removes the `robodoc` applications and project from Argo CD without stopping the Argo CD server:
```bash copy
./stop.sh --apps-only
```
*(Workloads in the `robodoc` namespace continue running safely).*

### Option C: Complete Teardown / Purge
Completely uninstalls Argo CD manifests and deletes the `argocd` namespace:
```bash copy
./stop.sh --purge
# or
./stop.sh --uninstall
```

---

## 3. Manual Deployment (via `kubectl`)

If you prefer deploying or managing manually without scripts:

### Install Argo CD
```bash copy
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
```

### Apply Project & Applications
```bash copy
kubectl apply -f argocd/robodoc-project.yaml -f argocd/robodoc-backend-application.yaml -f argocd/robodoc-customer-application.yaml
```

> [!TIP]
> If you prefer using the `default` Argo CD project instead of the custom `robodoc` project, change `project: robodoc` to `project: default` in the application YAMLs and apply only the application files:
> ```bash copy
> kubectl apply -f argocd/robodoc-backend-application.yaml -f argocd/robodoc-customer-application.yaml
> ```

Once applied, Argo CD will register both applications under the `robodoc` project and begin syncing the backend and customer resources from GitHub (`https://github.com/alamin899/k8s-robodoc.git`, directories `robodoc-backend-k8s-production/` and `robodoc-frontend-k8s-production/`) into the `robodoc` namespace.

---

## Key Configuration Details

### 1. Excluding Template / Example Files
Within [`robodoc-backend-k8s-production`](file:///Users/test/Documents/practice/kubernetes/k8s-robodoc/robodoc-backend-k8s-production) and [`robodoc-frontend-k8s-production`](file:///Users/test/Documents/practice/kubernetes/k8s-robodoc/robodoc-frontend-k8s-production), template files (`configmap.example.yaml` and `secret.example.yaml`) are tracked in Git, whereas production secrets are gitignored.

To prevent Argo CD from applying `configmap.example.yaml` and `secret.example.yaml` (which contain empty values) over real production configurations, the Application manifests explicitly exclude them:

```yaml copy
source:
  repoURL: https://github.com/alamin899/k8s-robodoc.git
  targetRevision: HEAD
  path: robodoc-backend-k8s-production # (or robodoc-frontend-k8s-production)
  directory:
    recurse: false
    exclude: '*.example.yaml'
```

### 2. Secrets and Untracked ConfigMap Management
Because `configmap.yaml`, `secret.yaml`, and registry credentials (`regcred`) are gitignored for security, they must be created in the `robodoc` namespace either:
- **Manually**: Running `./deploy.sh` or applying `kubectl apply -f secret.yaml -f configmap.yaml` once during initial setup.
- **GitOps Secrets Manager**: Using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or [External Secrets Operator](https://external-secrets.io/) to generate Kubernetes secrets automatically.

To guarantee that Argo CD never overwrites, prunes, or flags your manually applied production Secrets and ConfigMaps (`robodoc-backend-production` and `robodoc-customer-production`) as out-of-sync, both Application manifests explicitly configure `ignoreDifferences` for them.

### 3. Automated Sync & Self-Healing
The Application is configured with automated synchronization:
- `prune: true`: Automatically removes resources from Kubernetes if they are deleted from Git.
- `selfHeal: true`: Automatically reverts any manual drift made directly in the cluster back to the state in Git.
- `CreateNamespace=true`: Automatically creates the `robodoc` namespace if it does not already exist.

---

## Useful Commands

### Get Argo CD Initial Admin Password
```bash copy
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### Port-Forward Argo CD Web UI
```bash copy
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Check Application Statuses
```bash copy
kubectl get applications -n argocd
```

### View Application Details & Sync Conditions
```bash copy
kubectl describe application robodoc-backend -n argocd
kubectl describe application robodoc-customer -n argocd
```

### Manually Trigger a Refresh / Sync via CLI (if `argocd` CLI is installed)
```bash copy
argocd app sync robodoc-backend robodoc-customer
argocd app get robodoc-backend
argocd app get robodoc-customer
```

---

## Removing / Uninstalling from Kubernetes

### 1. Remove the Argo CD Applications (`robodoc-backend` and `robodoc-customer`)

#### Option A: Cascading Delete (Delete Application + All Deployed Resources)
Because the application manifests can include the `resources-finalizer.argocd.argoproj.io` finalizer, deleting the Applications will automatically delete all managed resources in the `robodoc` namespace:

```bash copy
kubectl delete -f argocd/robodoc-backend-application.yaml -f argocd/robodoc-customer-application.yaml
# OR
kubectl delete applications robodoc-backend robodoc-customer -n argocd
```

#### Option B: Non-Cascading Delete (Remove Application from Argo CD, Keep Resources Running)
If you want to remove the applications from Argo CD but **keep** your pods and services running in Kubernetes, strip any finalizers before deleting:

```bash copy
kubectl patch application robodoc-backend -n argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
kubectl patch application robodoc-customer -n argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
kubectl delete applications robodoc-backend robodoc-customer -n argocd
```

---

### 2. Completely Uninstall Argo CD from Kubernetes

If you want to completely uninstall Argo CD from your Kubernetes cluster:

1. **Delete all Argo CD Application resources first** (to allow finalizers to clean up or prevent hanging):
   ```bash copy
   kubectl delete applications --all -n argocd
   ```
2. **Uninstall Argo CD manifests** (matching the installation method you used):
   ```bash copy
   kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
3. **Delete the `argocd` namespace**:
   ```bash copy
   kubectl delete namespace argocd
   ```
4. **(Optional) Delete Argo CD Custom Resource Definitions (CRDs)** if any remain:
   ```bash copy
   kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
   ```
