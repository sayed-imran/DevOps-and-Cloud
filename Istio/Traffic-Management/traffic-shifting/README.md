# Istio Traffic Shifting Demo

This demo showcases Istio's traffic shifting capabilities using weighted routing between two versions of a movie backend application.

## Overview

Traffic shifting (also known as traffic splitting) is a technique used to gradually route traffic between different versions of a service. This is particularly useful for:

- **Canary Deployments**: Gradually rolling out new versions
- **A/B Testing**: Comparing different versions with real traffic
- **Blue-Green Deployments**: Switching traffic between environments
- **Risk Mitigation**: Reducing blast radius of new deployments

## Architecture

All resources run in the `traffic-shifting-demo` namespace. The ingress gateway sends `/` to the frontend and `/api/` to the backend. The `movie-backend` VirtualService splits backend requests between the v1 and v2 subsets defined in the DestinationRule.

```
                    Browser / curl  (http://localhost)
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
│    (React UI)     │             │  + DestinationRule subsets    │
└───────────────────┘             └───────────────┬───────────────┘
                                                  │
                                     ┌────────────┴────────────┐
                                     ▼                         ▼
                             ┌───────────────┐         ┌───────────────┐
                             │  backend v1   │         │  backend v2   │
                             │  (Bollywood)  │         │  (Hollywood)  │
                             └───────────────┘         └───────────────┘
```

## Components

### 1. Applications
- **Frontend**: React-based movie catalog UI
- **Backend V1**: Serves Bollywood movies from TMDB API
- **Backend V2**: Serves Hollywood movies from TMDB API (includes DATA_DIR=hollywood-data)
- Both backends use the same Docker image but with different configurations

### 2. Kubernetes Resources
- **Namespace**: `traffic-shifting-demo`, with Istio sidecar injection enabled
- **Deployments**:
  - movie-frontend (React UI)
  - movie-backend-v1 (Bollywood movies)
  - movie-backend-v2 (Hollywood movies)
- **Services**:
  - movie-frontend (port 80)
  - movie-backend (port 8000)
- **Secret**: tmdb-api-key for TMDB API access

### 3. Istio Resources
- **Gateway** `istio-gateway`: Exposes the application on port 80 for any host
- **VirtualService** `movie-frontend`: Routes `/` to the frontend
- **DestinationRule** `movie-backend`: Defines the `v1` and `v2` subsets from the pods' `version` label
- **VirtualService** `movie-backend`: Routes `/api/` to the backend and sets the v1/v2 weights. There is one file per split in `manifests/istio/virtual-services/`.

## Files Structure

```
traffic-shifting/
├── manifests/                        # All Kubernetes & Istio YAML resources
│   ├── base/                         # Core Kubernetes workloads & services
│   │   ├── namespace.yaml            # Target namespace definition
│   │   ├── configmap.yaml            # ConfigMaps for observability / test scripts
│   │   ├── frontend.yaml             # Frontend UI deployment & service
│   │   ├── deployment-v1.yaml        # Backend V1 deployment (Bollywood)
│   │   ├── deployment-v2.yaml        # Backend V2 deployment (Hollywood)
│   │   └── service.yaml              # Backend Kubernetes service
│   └── istio/                        # Istio Traffic Management resources
│       ├── gateway.yaml              # Istio Gateway definition
│       ├── destination-rule.yaml     # DestinationRule defining v1 & v2 subsets
│       └── virtual-services/         # Traffic weight configurations
│           ├── virtual-service-100-0.yaml  # 100% V1, 0% V2
│           ├── virtual-service-80-20.yaml  # 80% V1, 20% V2
│           ├── virtual-service-50-50.yaml  # 50% V1, 50% V2
│           └── virtual-service-0-100.yaml  # 0% V1, 100% V2
├── infrastructure/                   # Cluster & Mesh setup configurations
│   ├── kind/
│   │   └── kind-config.yaml          # Kind cluster topology config
│   └── istio/
│       └── istio.yaml                # IstioOperator installation profile
├── scripts/                          # Operational & testing scripts
│   ├── deploy.sh                     # Interactive deployment script
│   ├── cleanup.sh                    # Resource cleanup script
│   └── test-traffic.sh               # Traffic distribution testing script
├── docs/                             # Detailed documentation
│   ├── SETUP.md                      # Detailed setup guide
│   └── DEPLOYMENTS.md                # Detailed deployment guide
└── README.md                         # Main entry point & project overview
```

## Prerequisites

1. **Docker** and **[Kind](https://kind.sigs.k8s.io/)**: The deploy script creates a single-node Kind cluster named `cluster1` from `infrastructure/kind/kind-config.yaml`. The cluster maps host port 80 to the ingress gateway, so port 80 must be free on your machine.
2. **istioctl**: The script installs Istio with `infrastructure/istio/istio.yaml`, which runs the ingress gateway as NodePort `30000`.
   ```bash
   curl -L https://istio.io/downloadIstio | sh -
   cd istio-*
   export PATH=$PWD/bin:$PATH
   ```
3. **kubectl**
4. **TMDB API Key**: (Optional) For real movie data
   - Sign up at https://www.themoviedb.org/
   - Get API key from your account settings

> **Note:** The Multi-Cluster demo (`../../MultiCluster-Kind`) also creates a Kind cluster named `cluster1`. Run only one of the two at a time.

## Quick Start

Run all commands from this directory (`Istio/Traffic-Management/traffic-shifting`), because the scripts use relative paths.

### Option 1: Interactive Script (Recommended)
```bash
./scripts/deploy.sh
```

| Option | Action |
|--------|--------|
| 1 | Deploy everything: Kind cluster, Istio, namespace, TMDB secret (prompts for the key), app, and 100% of traffic to v1 |
| 2–5 | Set the v1/v2 split to 100/0, 80/20, 50/50, or 0/100 |
| 6 | Show pods, services, VirtualServices, and DestinationRules |
| 7 | Print the frontend and API URLs |
| 8 | Send 20 requests to the API |
| 9 | Start a `traffic-test` pod that calls the backend from inside the cluster |
| 10 | Remove all demo resources, including the namespace |

The script also runs without the menu: `./scripts/deploy.sh deploy|status|url|test|cleanup`.

### Option 2: Manual Deployment

1. **Create the cluster and install Istio:**
   ```bash
   kind create cluster --config infrastructure/kind/kind-config.yaml
   istioctl install -f infrastructure/istio/istio.yaml -y
   ```

2. **Create the namespace and the TMDB API secret:**
   ```bash
   kubectl apply -f manifests/base/namespace.yaml
   kubectl create secret generic tmdb-api-key \
     --from-literal=TMDB_API_KEY="your_api_key_here" \
     -n traffic-shifting-demo
   ```

3. **Deploy the resources:**
   ```bash
   kubectl apply -f manifests/base/frontend.yaml
   kubectl apply -f manifests/base/deployment-v1.yaml
   kubectl apply -f manifests/base/deployment-v2.yaml
   kubectl apply -f manifests/base/service.yaml
   kubectl apply -f manifests/istio/gateway.yaml
   kubectl apply -f manifests/istio/destination-rule.yaml
   kubectl apply -f manifests/base/configmap.yaml
   ```

4. **Apply initial traffic configuration (100% to V1):**
   ```bash
   kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
   ```

5. **Verify deployment:**
   ```bash
   kubectl get pods -n traffic-shifting-demo -l app=movie-backend
   kubectl get pods -n traffic-shifting-demo -l app=movie-frontend
   kubectl get svc -n traffic-shifting-demo movie-backend movie-frontend
   ```

## Traffic Shifting Scenarios

### Scenario 1: All Traffic to V1 (100% - 0%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
```
All API requests go to the V1 backend (Bollywood movies).

### Scenario 2: Canary Testing (80% - 20%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-80-20.yaml
```
80% of requests go to V1, 20% to V2 (Hollywood movies).

### Scenario 3: A/B Testing (50% - 50%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-50-50.yaml
```
Equal distribution between both versions.

### Scenario 4: Full Migration (0% - 100%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-0-100.yaml
```

## Accessing the Application

On Kind, host port 80 is mapped to the ingress gateway, and the Gateway accepts any host:

```bash
export GATEWAY_URL=localhost

# Frontend UI (or open http://localhost in a browser)
curl http://$GATEWAY_URL/

# Backend API, split between V1 and V2
curl http://$GATEWAY_URL/api/
```

`./scripts/deploy.sh url` also prints the URLs. If the gateway isn't reachable, port-forward it and use `GATEWAY_URL=localhost:8080`:

```bash
kubectl -n istio-system port-forward service/istio-ingressgateway 8080:80
```

## Testing Traffic Distribution

Use the provided test script to analyze traffic distribution:

```bash
# Send 100 requests and count V1 vs V2 responses
./scripts/test-traffic.sh test 100

# Monitor real-time traffic (Ctrl+C to stop)
./scripts/test-traffic.sh monitor
```

The script finds the gateway through its LoadBalancer IP or, on Kind, through the node IP and NodePort `30000`. It tells V1 and V2 apart by looking for `bollywood` or `hollywood` in each response.

You can also manually test:
```bash
# Send 20 requests and observe the distribution
for i in {1..20}; do
  response=$(curl -s http://$GATEWAY_URL/api/)
  if echo "$response" | grep -q "bollywood"; then
    echo "Request $i: V1 (Bollywood)"
  elif echo "$response" | grep -q "hollywood"; then
    echo "Request $i: V2 (Hollywood)"
  else
    echo "Request $i: Unknown"
  fi
done
```

## Monitoring

### View Current Traffic Configuration
```bash
kubectl get virtualservice movie-backend -n traffic-shifting-demo -o yaml
kubectl get destinationrule movie-backend -n traffic-shifting-demo -o yaml
```

### Monitor Application Status
```bash
# Watch pods
kubectl get pods -n traffic-shifting-demo -l app=movie-backend -w

# Check backend logs
kubectl logs -f deployment/movie-backend-v1 -n traffic-shifting-demo
kubectl logs -f deployment/movie-backend-v2 -n traffic-shifting-demo

# Check frontend logs
kubectl logs -f deployment/movie-frontend -n traffic-shifting-demo
```

### Istio Observability (if addons installed)
```bash
# Access Kiali dashboard
istioctl dashboard kiali

# Access Grafana dashboard
istioctl dashboard grafana

# Access Jaeger tracing
istioctl dashboard jaeger
```

## Advanced Scenarios

### Header-Based Routing
You can extend the VirtualService to route based on headers. The header and the path are in the same `match` entry, so a request must match both. Separate entries in a `match` list are ORed together.

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: movie-backend
  namespace: traffic-shifting-demo
spec:
  hosts:
  - "*"
  gateways:
  - istio-gateway
  http:
  - match:
    - headers:
        x-user-type:
          exact: premium
      uri:
        prefix: /api/
    rewrite:
      uri: /
    route:
    - destination:
        host: movie-backend
        subset: v2
  - match:
    - uri:
        prefix: /api/
    rewrite:
      uri: /
    route:
    - destination:
        host: movie-backend
        subset: v1
```

### Fault Injection for Testing
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: movie-backend
  namespace: traffic-shifting-demo
spec:
  hosts:
  - "*"
  gateways:
  - istio-gateway
  http:
  - fault:
      delay:
        percentage:
          value: 20.0
        fixedDelay: 3s
    match:
    - uri:
        prefix: /api/
    rewrite:
      uri: /
    route:
    - destination:
        host: movie-backend
        subset: v1
      weight: 80
    - destination:
        host: movie-backend
        subset: v2
      weight: 20
```

## Cleanup

Remove all demo resources, including the TMDB secret and the namespace:
```bash
./scripts/deploy.sh cleanup      # same as option 10 in the menu
```

Remove the resources and delete the Kind cluster:
```bash
./scripts/cleanup.sh all
```

Manual cleanup:
```bash
kubectl delete namespace traffic-shifting-demo
kubectl delete configmap traffic-policies test-scenarios -n default   # configmap.yaml creates these two in "default"
kind delete cluster --name cluster1                                  # optional: remove the cluster too
```

## Troubleshooting

### Common Issues

1. **Pods not starting**: Check that Istio injection is enabled and the TMDB secret exists
   ```bash
   kubectl get namespace traffic-shifting-demo --show-labels
   kubectl get secret tmdb-api-key -n traffic-shifting-demo
   kubectl describe pod <pod-name> -n traffic-shifting-demo
   ```

2. **Service not accessible**: Verify the ingress gateway
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway
   kubectl get gateway istio-gateway -n traffic-shifting-demo
   ```

3. **Traffic not splitting**: Check VirtualService configuration
   ```bash
   kubectl describe virtualservice movie-backend -n traffic-shifting-demo
   kubectl get destinationrule movie-backend -n traffic-shifting-demo -o yaml
   ```

4. **API requests failing**: Check backend pod logs
   ```bash
   kubectl logs -f deployment/movie-backend-v1 -n traffic-shifting-demo
   kubectl logs -f deployment/movie-backend-v2 -n traffic-shifting-demo
   ```

### Debug Commands
```bash
# Check Istio proxy configuration
istioctl proxy-config routes <pod-name>.traffic-shifting-demo
istioctl proxy-config clusters <pod-name>.traffic-shifting-demo

# Verify Envoy configuration
kubectl exec deployment/movie-backend-v1 -n traffic-shifting-demo -c istio-proxy -- pilot-agent request GET /config_dump

# Analyze Istio configuration
istioctl analyze -n traffic-shifting-demo
```

## Real-World Deployment Patterns

### 1. Blue-Green Deployment
```bash
# Start with all traffic on blue (v1)
kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml

# Switch all traffic to green (v2) after validation
kubectl apply -f manifests/istio/virtual-services/virtual-service-0-100.yaml
```

### 2. Canary Deployment
```bash
# Start with 95% blue, 5% canary
# (Create custom virtual service with these weights)

# Gradually increase canary traffic
kubectl apply -f manifests/istio/virtual-services/virtual-service-80-20.yaml
kubectl apply -f manifests/istio/virtual-services/virtual-service-50-50.yaml
kubectl apply -f manifests/istio/virtual-services/virtual-service-0-100.yaml
```

### 3. A/B Testing
```bash
# Split traffic evenly for testing
kubectl apply -f manifests/istio/virtual-services/virtual-service-50-50.yaml

# Monitor metrics and user behavior
# Route based on user characteristics if needed
```

## Best Practices

1. **Gradual Traffic Shifting**: Start with small percentages (e.g., 5%, 10%)
2. **Monitor Key Metrics**: Watch error rates, latency, and business metrics
3. **Automated Rollback**: Implement automatic rollback based on SLI violations
4. **Load Testing**: Test with realistic traffic patterns before production
5. **Version Labeling**: Use consistent version labels across all resources
6. **Feature Flags**: Combine with feature flags for additional control
7. **Documentation**: Document rollback procedures and emergency contacts

## Integration with CI/CD

Example GitLab CI pipeline step:
```yaml
deploy_canary:
  script:
    - kubectl apply -f manifests/base/deployment-v2.yaml
    - kubectl apply -f manifests/istio/virtual-services/virtual-service-80-20.yaml
    - ./scripts/test-traffic.sh test 100
    - # Add health checks and validation
```

## Additional Resources

- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Istio VirtualService Reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/)
- [Canary Deployments with Istio](https://istio.io/latest/blog/2017/0.1-canary/)
- [Traffic Shifting Tutorial](https://istio.io/latest/docs/tasks/traffic-management/traffic-shifting/)
- [Production Best Practices](https://istio.io/latest/docs/ops/best-practices/)

---

This demo provides a comprehensive foundation for understanding and implementing traffic shifting with Istio in your Kubernetes environment using a real-world movie application scenario.
