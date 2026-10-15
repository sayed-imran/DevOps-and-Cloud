# Flagger Canary Release Setup Guide

This guide provides step-by-step instructions for setting up the Flagger Canary Release demo environment.

## Prerequisites Installation

### 1. Kubernetes Cluster
Ensure you have a running Kubernetes cluster with at least:
- 2 worker nodes (recommended)
- 4GB RAM per node
- kubectl configured

### 2. Istio Service Mesh
Install Istio if not already installed:

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Install Istio
istioctl install --set values.defaultRevision=default -y

# Verify installation
kubectl get pods -n istio-system
```

### 3. Enable Istio Injection
```bash
kubectl label namespace default istio-injection=enabled
```

The demo's manifests and the webhook URLs in `canary.yaml` assume the `default` namespace.

### 4. Install Helm (if not already installed)
```bash
# On Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# On macOS
brew install helm

# Verify installation
helm version
```

### 5. Install Flagger

#### Option A: Using the deploy script (Recommended)
```bash
./deploy.sh
# Choose option 3: "Install Missing Dependencies" (Istio, Prometheus, Flagger, and the load tester)
```

#### Option B: Manual installation
```bash
# Add Flagger Helm repository
helm repo add flagger https://flagger.app
helm repo update

# Install Flagger CRDs
kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml

# Install Flagger for Istio
helm upgrade -i flagger flagger/flagger \
  --namespace=istio-system \
  --set crd.create=false \
  --set meshProvider=istio \
  --set metricsServer=http://prometheus:9090

# Verify installation
kubectl get pods -n istio-system -l app.kubernetes.io/name=flagger
```

### 6. Install Prometheus
```bash
# Install Prometheus from Istio samples
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml

# Wait for Prometheus to be ready
kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n istio-system

# Verify installation
kubectl get svc prometheus -n istio-system
```

### 7. Install Flagger Load Tester
The webhooks in `canary.yaml` call `http://flagger-loadtester.istio-system/`, so install the load tester in `istio-system`:
```bash
helm upgrade -i flagger-loadtester flagger/loadtester \
  --namespace=istio-system \
  --set cmd.timeout=1h \
  --set cmd.namespaceRegexp=''

# Verify installation
kubectl get deployment flagger-loadtester -n istio-system
```

## Verification

### Check All Components
```bash
# Check Istio
kubectl get pods -n istio-system

# Check Flagger
kubectl get pods -n istio-system -l app.kubernetes.io/name=flagger

# Check Prometheus
kubectl get svc prometheus -n istio-system

# Check Load Tester
kubectl get deployment flagger-loadtester -n istio-system

# Check CRDs
kubectl get crd canaries.flagger.app
```

### Test Basic Connectivity
```bash
# Test Prometheus metrics endpoint
kubectl port-forward -n istio-system svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/query?query=up | jq .
pkill -f "port-forward.*prometheus"

# Test load tester
kubectl port-forward -n istio-system svc/flagger-loadtester 8080:80 &
curl -s http://localhost:8080/ | grep -i flagger
pkill -f "port-forward.*loadtester"
```

## Optional: Install Observability Tools

### Grafana (for advanced monitoring)
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml

# Access Grafana
istioctl dashboard grafana
```

### Kiali (for service mesh visualization)
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Access Kiali
istioctl dashboard kiali
```

### Jaeger (for distributed tracing)
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Access Jaeger
istioctl dashboard jaeger
```

## Network Configuration

### For Cloud Providers

#### AWS EKS
```bash
# Ensure LoadBalancer service type is supported
kubectl get svc istio-ingressgateway -n istio-system

# If using ALB, you might need AWS Load Balancer Controller
# Follow: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
```

#### Google GKE
Install Istio with `istioctl` as in step 2. The old "Istio on GKE" add-on has been removed, so `--update-addons=Istio=ENABLED` no longer works.

#### Azure AKS
```bash
# Enable Istio addon (alternative to manual installation)
az aks mesh enable --resource-group myResourceGroup --name myAKSCluster
```

The AKS add-on uses revision labels (`istio.io/rev`) for sidecar injection and has its own ingress gateway names. This demo's `istio-injection=enabled` label and the `istio: ingressgateway` selector in `gateway.yaml` would need changing to work with it. Installing Istio with `istioctl` (step 2) avoids that.

### For Local Development

#### Minikube
```bash
# Enable LoadBalancer support
minikube tunnel

# Alternative: Use NodePort
kubectl patch svc istio-ingressgateway -n istio-system -p '{"spec":{"type":"NodePort"}}'
```

#### Kind
Reuse the Kind and Istio configs from the traffic-shifting demo. They map host port 80 to the ingress gateway's NodePort 30000:
```bash
kind create cluster --config ../traffic-shifting/infrastructure/kind/kind-config.yaml
istioctl install -f ../traffic-shifting/infrastructure/istio/istio.yaml -y

# Once the app is deployed, it answers on localhost
curl -H "Host: devops.imran" http://localhost/
```

This creates a cluster named `cluster1`, the same name the traffic-shifting and multi-cluster demos use, so run only one of them at a time.

## Troubleshooting Setup

### Common Issues

1. **Flagger not starting**:
   ```bash
   kubectl logs -f deployment/flagger -n istio-system
   # Check for Prometheus connectivity errors
   ```

2. **Prometheus not accessible**:
   ```bash
   kubectl get endpoints prometheus -n istio-system
   # Ensure service is properly exposed
   ```

3. **Load tester not working**:
   ```bash
   kubectl logs -f deployment/flagger-loadtester -n istio-system
   # Check for network policies blocking traffic
   ```

4. **Istio injection not working**:
   ```bash
   kubectl get namespace -L istio-injection
   # Verify injection label is set
   
   kubectl describe pod POD_NAME
   # Check for istio-proxy container
   ```

### Cleanup for Fresh Install
```bash
# Remove Flagger
helm uninstall flagger -n istio-system
kubectl delete crd canaries.flagger.app

# Remove Prometheus
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml

# Remove Load Tester
helm uninstall flagger-loadtester -n istio-system

# Remove Istio (if needed)
istioctl uninstall --purge -y
kubectl delete namespace istio-system
```

## Next Steps

Once setup is complete:

1. Run the deployment script: `./deploy.sh`
2. Follow the README.md for demo scenarios
3. Explore the canary configuration in `canary.yaml`
4. Monitor with observability tools

## Resources

- [Flagger Installation Guide](https://docs.flagger.app/install/flagger-install-on-kubernetes)
- [Istio Installation Guide](https://istio.io/latest/docs/setup/getting-started/)
- [Prometheus Configuration](https://istio.io/latest/docs/ops/integrations/prometheus/)
- [Flagger Tutorials](https://docs.flagger.app/tutorials/)
