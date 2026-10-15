# Istio Traffic Shifting Demo

This demo showcases Istio's traffic shifting capabilities using weighted routing between two versions of a movie backend application.

## Overview

Traffic shifting (also known as traffic splitting) is a technique used to gradually route traffic between different versions of a service. This is particularly useful for:

- **Canary Deployments**: Gradually rolling out new versions
- **A/B Testing**: Comparing different versions with real traffic
- **Blue-Green Deployments**: Switching traffic between environments
- **Risk Mitigation**: Reducing blast radius of new deployments

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│                 │    │                  │    │                 │
│   Istio Gateway │────┤  VirtualService  │────┤ DestinationRule │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
            ┌───────────────┐       ┌───────────────┐
            │  Backend V1   │       │  Backend V2   │
            │ (Bollywood)   │       │ (Hollywood)   │
            │               │       │               │
            └───────────────┘       └───────────────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                        ┌───────────────┐
                        │   Frontend    │
                        │  (React UI)   │
                        │               │
                        └───────────────┘
```

## Components

### 1. Applications
- **Frontend**: React-based movie catalog UI
- **Backend V1**: Serves Bollywood movies from TMDB API
- **Backend V2**: Serves Hollywood movies from TMDB API (includes DATA_DIR=hollywood-data)
- Both backends use the same Docker image but with different configurations

### 2. Kubernetes Resources
- **Deployments**: 
  - movie-frontend (React UI)
  - movie-backend-v1 (Bollywood movies)
  - movie-backend-v2 (Hollywood movies)
- **Services**: 
  - movie-frontend (port 80)
  - movie-backend (port 8000)
- **Secret**: tmdb-api-key for TMDB API access

### 3. Istio Resources
- **Gateway**: Exposes the application externally
- **DestinationRule**: Defines subsets for V1 and V2
- **VirtualService**: Controls traffic distribution between backend versions

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

1. **Kubernetes Cluster**: A running Kubernetes cluster
2. **Istio**: Installed and configured
   ```bash
   # Install Istio (if not already installed)
   curl -L https://istio.io/downloadIstio | sh -
   cd istio-*
   export PATH=$PWD/bin:$PATH
   istioctl install --set values.defaultRevision=default
   
   # Enable automatic sidecar injection for default namespace
   kubectl label namespace default istio-injection=enabled
   ```
3. **kubectl**: Configured to access your cluster
4. **TMDB API Key**: (Optional) For real movie data
   - Sign up at https://www.themoviedb.org/
   - Get API key from your account settings

## Quick Start

### Option 1: Interactive Script (Recommended)
```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

The script provides an interactive menu to:
- Deploy all resources
- Switch between different traffic configurations
- Monitor status and generate test traffic
- Clean up resources

### Option 2: Manual Deployment

1. **Create TMDB API secret:**
   ```bash
   kubectl create secret generic tmdb-api-key \
     --from-literal=TMDB_API_KEY="your_api_key_here"
   ```

2. **Deploy the resources:**
   ```bash
   kubectl apply -f manifests/base/frontend.yaml
   kubectl apply -f manifests/base/deployment-v1.yaml
   kubectl apply -f manifests/base/deployment-v2.yaml
   kubectl apply -f manifests/base/service.yaml
   kubectl apply -f manifests/istio/gateway.yaml
   kubectl apply -f manifests/istio/destination-rule.yaml
   kubectl apply -f manifests/base/configmap.yaml
   ```

3. **Apply initial traffic configuration (100% to V1):**
   ```bash
   kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
   ```

4. **Verify deployment:**
   ```bash
   kubectl get pods -l app=movie-backend
   kubectl get pods -l app=movie-frontend
   kubectl get svc movie-backend movie-frontend
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

1. **Get the ingress gateway URL:**
   ```bash
   export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
   export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
   ```

2. **Access the application:**
   ```bash
   # Frontend UI
   curl http://$GATEWAY_URL
   # or open in browser
   open http://$GATEWAY_URL
   
   # Backend API
   curl http://$GATEWAY_URL/api/
   ```

## Testing Traffic Distribution

Use the provided test script to analyze traffic distribution:

```bash
# Make the scripts executable
chmod +x scripts/*.sh

# Test with 100 requests
./scripts/test-traffic.sh test 100

# Monitor real-time traffic
./scripts/test-traffic.sh monitor

# Check current configuration
./scripts/test-traffic.sh config
```

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
kubectl get virtualservice movie-backend -o yaml
kubectl get destinationrule movie-backend -o yaml
```

### Monitor Application Status
```bash
# Watch pods
kubectl get pods -l app=movie-backend -w

# Check backend logs
kubectl logs -f deployment/movie-backend-v1
kubectl logs -f deployment/movie-backend-v2

# Check frontend logs
kubectl logs -f deployment/movie-frontend
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
You can extend the VirtualService to route based on headers:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: movie-backend
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
    - uri:
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

Remove all resources using the cleanup script:
```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

Or use the interactive deployment script:
```bash
./scripts/deploy.sh
# Choose option 10 for cleanup
```

Manual cleanup:
```bash
kubectl delete -f manifests/base/frontend.yaml
kubectl delete -f manifests/base/deployment-v1.yaml
kubectl delete -f manifests/base/deployment-v2.yaml
kubectl delete -f manifests/base/service.yaml
kubectl delete -f manifests/istio/gateway.yaml
kubectl delete -f manifests/istio/destination-rule.yaml
kubectl delete -f manifests/base/configmap.yaml
kubectl delete secret tmdb-api-key
```

## Troubleshooting

### Common Issues

1. **Pods not starting**: Check if Istio injection is enabled
   ```bash
   kubectl get namespace default --show-labels
   kubectl describe pod <pod-name>
   ```

2. **Service not accessible**: Verify the ingress gateway
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway
   kubectl get gateway istio-gateway
   ```

3. **Traffic not splitting**: Check VirtualService configuration
   ```bash
   kubectl describe virtualservice movie-backend
   kubectl get destinationrule movie-backend -o yaml
   ```

4. **API requests failing**: Check backend pod logs
   ```bash
   kubectl logs -f deployment/movie-backend-v1
   kubectl logs -f deployment/movie-backend-v2
   ```

### Debug Commands
```bash
# Check Istio proxy configuration
istioctl proxy-config routes <pod-name>
istioctl proxy-config clusters <pod-name>

# Verify Envoy configuration
kubectl exec deployment/movie-backend-v1 -c istio-proxy -- pilot-agent request GET /config_dump

# Analyze Istio configuration
istioctl analyze
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
