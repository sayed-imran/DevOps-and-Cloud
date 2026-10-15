# Traffic Shifting Setup Guide

This guide will help you set up and run the traffic shifting demo using Istio service mesh.

## Prerequisites

Before you begin, ensure you have the following installed:

1. **Kubernetes cluster** (v1.20+ recommended)
   - Local: Docker Desktop, minikube, kind, or k3s
   - Cloud: GKE, EKS, AKS, or any managed Kubernetes service

2. **kubectl** configured to connect to your cluster
   ```bash
   kubectl version --client
   ```

3. **Kind & Istio Setup** (automated by `scripts/deploy.sh`)
   ```bash
   # Kind cluster config: infrastructure/kind/kind-config.yaml
   kind create cluster --config infrastructure/kind/kind-config.yaml
   
   # Install Istio with custom NodePort configuration: infrastructure/istio/istio.yaml
   istioctl install -f infrastructure/istio/istio.yaml -y
   
   # Enable automatic sidecar injection for namespace
   kubectl label namespace traffic-shifting-demo istio-injection=enabled --overwrite
   ```

4. **TMDB API Key** (optional but recommended)
   - Sign up at https://www.themoviedb.org/
   - Get your API key from the API settings
   - This enables real movie data instead of dummy data

## Quick Start

1. **Clone the repository** (if not already done)
   ```bash
   git clone <repository-url>
   cd traffic-management/traffic-shifting
   ```

2. **Make scripts executable**
   ```bash
   chmod +x scripts/*.sh
   ```

3. **Deploy the application**
   ```bash
   ./scripts/deploy.sh
   ```
   Follow the interactive menu to:
   - Deploy all resources (option 1, automatically creates Kind cluster & installs Istio)
   - Set initial traffic distribution (options 2-5)

4. **Test traffic distribution**
   ```bash
   ./scripts/test-traffic.sh test 100
   ```

## Manual Deployment Steps

If you prefer to deploy manually:

1. **Create cluster and install Istio**
   ```bash
   kind create cluster --config infrastructure/kind/kind-config.yaml
   istioctl install -f infrastructure/istio/istio.yaml -y
   kubectl apply -f manifests/base/namespace.yaml
   kubectl label namespace traffic-shifting-demo istio-injection=enabled --overwrite
   ```

2. **Create secret for TMDB API key**
   ```bash
   kubectl create secret generic tmdb-api-key \
     --from-literal=TMDB_API_KEY="your_api_key_here" \
     -n traffic-shifting-demo
   ```

3. **Deploy frontend**
   ```bash
   kubectl apply -f manifests/base/frontend.yaml
   ```

4. **Deploy backend versions**
   ```bash
   kubectl apply -f manifests/base/deployment-v1.yaml
   kubectl apply -f manifests/base/deployment-v2.yaml
   kubectl apply -f manifests/base/service.yaml
   ```

5. **Setup networking**
   ```bash
   kubectl apply -f manifests/istio/gateway.yaml
   kubectl apply -f manifests/istio/destination-rule.yaml
   ```

6. **Apply traffic splitting configuration**
   ```bash
   # Start with all traffic to v1
   kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
   ```

## Traffic Distribution Scenarios

The demo includes several pre-configured traffic distribution scenarios:

### Scenario 1: All traffic to V1 (100%-0%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
```

### Scenario 2: Canary deployment (80%-20%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-80-20.yaml
```

### Scenario 3: A/B testing (50%-50%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-50-50.yaml
```

### Scenario 4: Full migration to V2 (0%-100%)
```bash
kubectl apply -f manifests/istio/virtual-services/virtual-service-0-100.yaml
```

## Testing and Monitoring

### Test Traffic Distribution
```bash
# Test with 100 requests
./scripts/test-traffic.sh test 100

# Monitor real-time traffic
./scripts/test-traffic.sh monitor

# Check current configuration
./scripts/test-traffic.sh config
```

### Access the Application
```bash
# Get the ingress URL
./scripts/deploy.sh
# Choose option 7 to get the access URL

# Or manually get the URL
kubectl -n istio-system get service istio-ingressgateway
```

### Monitor with Istio Tools
```bash
# Install Kiali (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Install Grafana (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml

# Access Kiali dashboard
istioctl dashboard kiali

# Access Grafana dashboard
istioctl dashboard grafana
```

## Understanding the Components

### Application Architecture
- **Frontend**: React-based UI serving movie catalog
- **Backend V1**: Serves Bollywood movies from TMDB API
- **Backend V2**: Serves Hollywood movies from TMDB API

### Istio Components
- **Gateway**: Configures ingress traffic
- **VirtualService**: Defines traffic routing rules
- **DestinationRule**: Configures load balancing and subsets
- **ServiceEntry**: (if needed) for external service access

### Files Overview
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

## Troubleshooting

### Common Issues

1. **Pods not starting**
   ```bash
   kubectl get pods
   kubectl describe pod <pod-name>
   kubectl logs <pod-name>
   ```

2. **Istio sidecar not injected**
   ```bash
   kubectl label namespace default istio-injection=enabled
   kubectl rollout restart deployment/movie-backend-v1
   kubectl rollout restart deployment/movie-backend-v2
   ```

3. **Cannot access ingress**
   ```bash
   # Check ingress gateway status
   kubectl -n istio-system get service istio-ingressgateway
   
   # For local testing, use port-forward
   kubectl -n istio-system port-forward service/istio-ingressgateway 8080:80
   ```

4. **Traffic not splitting as expected**
   ```bash
   # Check virtual service configuration
   kubectl get virtualservice -o yaml
   
   # Verify destination rule
   kubectl get destinationrule -o yaml
   ```

### Debug Commands
```bash
# Check Istio proxy configuration
istioctl proxy-config routes <pod-name>
istioctl proxy-config clusters <pod-name>

# Analyze Istio configuration
istioctl analyze

# Check Envoy access logs
kubectl logs <pod-name> -c istio-proxy
```

## Cleanup

To remove all resources:

```bash
./scripts/cleanup.sh
```

Or manually:
```bash
kubectl delete -f .
kubectl delete secret tmdb-api-key
```

## Next Steps

After completing this demo, consider exploring:

1. **Advanced Traffic Management**
   - Fault injection
   - Request timeouts and retries  
   - Circuit breakers

2. **Security Features**
   - mTLS configuration
   - Authorization policies
   - Security scanning

3. **Observability**
   - Distributed tracing with Jaeger
   - Metrics collection with Prometheus
   - Service topology with Kiali

4. **Production Considerations**
   - Multi-cluster deployments
   - GitOps integration
   - Progressive delivery with Flagger/Argo Rollouts
