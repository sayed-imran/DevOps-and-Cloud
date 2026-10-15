# Flagger Canary Release Demo

This demo showcases automated canary deployments using Flagger with Istio service mesh. Flagger automates the promotion of canary deployments using Istio traffic shifting and Prometheus metrics for canary analysis.

## Overview

Flagger is a progressive delivery tool that automates the release process for applications running on Kubernetes. It reduces the risk of introducing a new software version in production by gradually shifting traffic to the canary while measuring metrics and running conformance tests.

This demo features:
- **Automated Canary Analysis**: Progressive traffic shifting based on success metrics
- **Automated Rollback**: Automatic rollback on failure detection
- **Load Testing**: Automated load testing during canary analysis
- **Prometheus Metrics**: Real-time monitoring of success rates and latency
- **Istio Integration**: Seamless integration with Istio service mesh

## Architecture

The canary target is the `movie-backend` Deployment. Flagger copies it to `movie-backend-primary`, which serves live traffic, and takes over the `movie-backend` VirtualService to shift `/api/` traffic between primary and canary. All routes use the host `devops.imran`.

```
                        Browser / curl  (Host: devops.imran)
                                  │
                                  ▼
                     ┌─────────────────────────┐
                     │  Istio Ingress Gateway  │   Gateway: istio-gateway
                     └────────────┬────────────┘
                     path /       │       path /api/  (rewritten to /)
              ┌───────────────────┴───────────────────┐
              ▼                                       ▼
    ┌───────────────────┐             ┌───────────────────────────────┐
    │  movie-frontend   │             │ VirtualService movie-backend  │
    │    (React UI)     │             │   (managed by Flagger)        │
    └───────────────────┘             └───────────────┬───────────────┘
                                                      │
                                         ┌────────────┴────────────┐
                                         ▼                         ▼
                                 ┌───────────────┐         ┌───────────────┐
                                 │    primary    │         │    canary     │
                                 │   (stable)    │         │ (new version) │
                                 └───────────────┘         └───────────────┘
```

## Components

### 1. Applications
- **Movie Backend** (`backend.yaml`): Deployment `movie-backend` (`sayedimran/istio-sample-app-backend:v1.0.1`, `DATA_DIR=bollywood-data`), plus its Service and VirtualService. This is the canary target.
- **Movie Frontend** (`frontend.yaml`): React UI (`sayedimran/istio-sample-app-frontend:v1.0.0`), plus its Service and VirtualService
- **Gateway** (`gateway.yaml`): `istio-gateway` on port 80 for the host `devops.imran`

### 2. Flagger Resources
- **Canary** (`canary.yaml`): `canary-release`, which targets `deployment/movie-backend` and defines the analysis
- **Load Tester**: `flagger-loadtester` in `istio-system`, which runs the canary webhooks
- **Prometheus**: Supplies the success-rate and latency metrics

### 3. Resources Flagger Creates
Once the canary is initialized, Flagger manages:
- **Deployment** `movie-backend-primary`: Serves live traffic. Flagger scales the original `movie-backend` to zero until the next release.
- **Services** `movie-backend`, `movie-backend-primary`, and `movie-backend-canary`
- **DestinationRules** `movie-backend-primary` and `movie-backend-canary`
- **VirtualService** `movie-backend`: Holds the primary/canary weights during a release

## Prerequisites

1. **Kubernetes cluster** with `kubectl` access. For a local Kind cluster, see [SETUP.md](SETUP.md#kind).
2. **Istio**, with sidecar injection enabled in the `default` namespace:
   ```bash
   istioctl install -y
   kubectl label namespace default istio-injection=enabled
   ```
3. **Prometheus** (for metrics collection):
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
   ```
4. **Flagger**, installed with Helm:
   ```bash
   # Add Flagger Helm repository
   helm repo add flagger https://flagger.app

   # Install Flagger CRDs
   kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml

   # Install Flagger for Istio
   helm upgrade -i flagger flagger/flagger \
     --namespace=istio-system \
     --set crd.create=false \
     --set meshProvider=istio \
     --set metricsServer=http://prometheus:9090
   ```
5. **Flagger Load Tester** in `istio-system`, where the webhooks in `canary.yaml` call it (`http://flagger-loadtester.istio-system/`):
   ```bash
   helm upgrade -i flagger-loadtester flagger/loadtester \
     --namespace=istio-system \
     --set cmd.timeout=1h \
     --set cmd.namespaceRegexp=''
   ```

The deploy script can install items 2–5 for you (menu option 3). See [SETUP.md](SETUP.md) for details and verification steps.

> **Note:** The manifests and the webhook URLs in `canary.yaml` (`movie-backend-canary.default`) assume the `default` namespace.

## Quick Start

Run the commands from this directory (`Istio/Traffic-Management/flagger-canary-release`).

### Option 1: Automated Script (Recommended)
```bash
./deploy.sh
```

| Option | Action |
|--------|--------|
| 1 | Check prerequisites (istioctl, Istio, Flagger, Prometheus, load tester) |
| 2 | Install Istio |
| 3 | Install whatever is missing: Istio, Prometheus, Flagger, and the load tester |
| 4 | Deploy into `default`: prompts for the TMDB key, applies `backend.yaml`, `frontend.yaml`, `gateway.yaml`, and `canary.yaml`, then prints the URL |
| 8 | Print the application URL |
| 9 | Delete the canary, the app resources, and the TMDB secret |

Then trigger and watch a release with the commands in [Triggering a Canary Release](#triggering-a-canary-release) and [Monitoring Canary Progress](#monitoring-canary-progress).

### Option 2: Manual Deployment

1. **Create the TMDB API secret:**
   ```bash
   kubectl create secret generic tmdb-api-key \
     --from-literal=TMDB_API_KEY="your_api_key_here"
   ```

2. **Deploy the application:**
   ```bash
   kubectl apply -f backend.yaml
   kubectl apply -f frontend.yaml
   kubectl apply -f gateway.yaml
   ```

3. **Wait for deployment to be ready:**
   ```bash
   kubectl wait --for=condition=available --timeout=300s deployment/movie-backend
   kubectl wait --for=condition=available --timeout=300s deployment/movie-frontend
   ```

4. **Initialize Flagger canary:**
   ```bash
   kubectl apply -f canary.yaml
   ```

5. **Wait for Flagger to initialize:**
   ```bash
   kubectl wait --for=condition=promoted --timeout=300s canary/canary-release
   ```

## Triggering a Canary Release

Any change to the `movie-backend` pod template starts a new analysis.

### Scenario 1: Update Configuration
```bash
# Switch the backend from Bollywood to Hollywood data
kubectl set env deployment/movie-backend DATA_DIR=hollywood-data
```

### Scenario 2: Update Application Version
```bash
# Update the deployment with a new image version
kubectl set image deployment/movie-backend \
  movie-backend=sayedimran/istio-sample-app-backend:v1.0.2
```

## Monitoring Canary Progress

### Watch Canary Status
```bash
# Watch canary analysis progress
kubectl get canary canary-release -w

# Get detailed canary status
kubectl describe canary canary-release

# Check Flagger events
kubectl get events --field-selector involvedObject.name=canary-release
```

### View Traffic Distribution
```bash
# Check the current primary/canary weights
kubectl get virtualservice movie-backend -o yaml

# Check the primary and canary deployments
kubectl get deployment movie-backend movie-backend-primary

# Check primary and canary services
kubectl get svc movie-backend movie-backend-primary movie-backend-canary
```

### Access Application

The Gateway and VirtualServices only accept the host `devops.imran`, so send that `Host` header:

```bash
# Get ingress gateway URL
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

# Frontend
curl -H "Host: devops.imran" http://$GATEWAY_URL/

# Backend API (served by the primary or the canary)
curl -H "Host: devops.imran" http://$GATEWAY_URL/api/
```

To use a browser, add `<INGRESS_HOST> devops.imran` to `/etc/hosts` and open `http://devops.imran`. If the gateway has no external IP, run `kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80` and set `GATEWAY_URL=localhost:8080`.

## Canary Analysis Configuration

`canary.yaml` configures the analysis with these parameters:

- **Interval**: 1 minute between analysis checks
- **Threshold**: 10 failed checks before rollback
- **Max Weight**: 50% maximum traffic to canary
- **Step Weight**: 10% traffic increment per successful check
- **Success Rate**: At least 99% of requests must succeed (measured over 1 minute)
- **Request Duration**: P99 latency must stay at or below 500 ms (measured over 30 seconds)
- **Progress Deadline**: 60 seconds for the canary deployment to make progress before Flagger rolls it back
- **Retries**: Up to 3 attempts, 1 second per try, on gateway errors, connect failures, and refused streams

### Metrics Monitored
1. **Request Success Rate**: Percentage of requests that don't return a 5xx response
2. **Request Duration**: 99th percentile response time in milliseconds

### Webhooks
Both webhooks run from the load tester against `http://movie-backend-canary.default:8000/`:
1. **Pre-rollout Test** (`acceptance-test`): Runs `curl` against the canary before any traffic shifts
2. **Load Test** (`load-test`): Runs `hey` for 2 minutes with 2 workers at 10 requests per second each, so the canary has traffic to measure

## Canary Lifecycle

1. **Initialization**: Flagger creates `movie-backend-primary`, the services, and the routing, then scales `movie-backend` to zero
2. **Trigger**: Flagger detects a change to the `movie-backend` pod template
3. **Canary Creation**: Flagger scales `movie-backend` back up with the new version as the canary
4. **Pre-rollout**: Acceptance tests run against canary
5. **Traffic Shifting**: Gradual traffic increase (10% → 20% → 30% → 40% → 50%)
6. **Analysis**: Metrics checked at each step (1-minute intervals)
7. **Promotion**: If successful, Flagger copies the canary spec to the primary, routes all traffic back to the primary, and scales the canary to zero
8. **Rollback**: If 10 checks fail, traffic returns to the primary and the canary is scaled to zero

## Observability

### Grafana Dashboards
```bash
# If Grafana is installed
istioctl dashboard grafana
```

Istio's Grafana add-on includes the Istio dashboards. Flagger's own canary dashboards come from the separate `flagger/grafana` Helm chart.

### Application Logs
```bash
# Check primary workload logs
kubectl logs -f deployment/movie-backend-primary

# Check canary workload logs (during analysis)
kubectl logs -f deployment/movie-backend

# Check Flagger operator logs
kubectl logs -f deployment/flagger -n istio-system

# Check load tester logs
kubectl logs -f deployment/flagger-loadtester -n istio-system
```

### Istio Observability
```bash
# Access Kiali dashboard
istioctl dashboard kiali

# Access Jaeger tracing
istioctl dashboard jaeger
```

## Troubleshooting

### Common Issues

1. **Canary stuck in initialization**:
   ```bash
   # Check Flagger logs
   kubectl logs -f deployment/flagger -n istio-system

   # Verify Prometheus connectivity
   kubectl exec -it deployment/flagger -n istio-system -- \
     wget -q -O- http://prometheus.istio-system:9090/api/v1/query?query=up
   ```

2. **Canary analysis failing**:
   ```bash
   # Check metrics manually
   kubectl port-forward -n istio-system svc/prometheus 9090:9090
   # Visit http://localhost:9090 and query istio metrics

   # Check load tester
   kubectl logs -f deployment/flagger-loadtester -n istio-system
   ```

3. **Traffic not shifting**:
   ```bash
   # Verify VirtualService updates
   kubectl get virtualservice movie-backend -o yaml

   # Check the routes on the ingress gateway
   istioctl proxy-config routes deployment/istio-ingressgateway -n istio-system
   ```

4. **Backend pods stuck in `CreateContainerConfigError`**: The `tmdb-api-key` secret is missing.
   ```bash
   kubectl get secret tmdb-api-key
   ```

### Cleanup

```bash
# Delete canary (this will also clean up generated resources)
kubectl delete canary canary-release

# Delete application
kubectl delete -f backend.yaml
kubectl delete -f frontend.yaml
kubectl delete -f gateway.yaml

# Delete the TMDB secret
kubectl delete secret tmdb-api-key
```

`./cleanup.sh` runs most of this interactively. `./cleanup.sh -d` also uninstalls Flagger and Prometheus.

## Advanced Configuration

### Custom Metrics
You can extend the canary analysis with custom Prometheus queries under `analysis.metrics`. Flagger also supports defining them as reusable `MetricTemplate` resources.

```yaml
metrics:
- name: "404-errors"
  thresholdRange:
    max: 5
  query: |
    sum(rate(
      istio_requests_total{
        destination_workload="movie-backend",
        response_code="404"
      }[1m]
    ))
```

### Header-Based Testing
To send only requests with a specific header to the canary (A/B testing), Flagger uses `iterations` instead of `stepWeight` and `maxWeight`:

```yaml
analysis:
  # ... other configuration
  iterations: 10
  match:
    - headers:
        x-canary:
          exact: "true"
```

### Blue-Green Deployment
Switch to blue-green deployment mode:

```yaml
analysis:
  # Skip traffic shifting, promote directly after validation
  stepWeight: 100
  maxWeight: 100
```

## Resources

- [Flagger Documentation](https://flagger.app/)
- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Progressive Delivery](https://argoproj.github.io/rollouts/)
- [Canary Deployments Best Practices](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/#canary-deployments)
