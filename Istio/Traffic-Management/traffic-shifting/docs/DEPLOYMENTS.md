# Traffic Shifting Demo - Deployments Overview

## Namespace
All resources are deployed in the `traffic-shifting-demo` namespace with Istio injection enabled. The exceptions are two ConfigMaps from `manifests/base/configmap.yaml` (`traffic-policies` and `test-scenarios`), which go to `default`.

## Core Deployments

### 1. Namespace
- **File**: `manifests/base/namespace.yaml`
- **Resource**: Namespace `traffic-shifting-demo`
- **Features**: Istio injection enabled

### 2. Backend Deployments
- **File**: `manifests/base/deployment-v1.yaml`
  - **Resource**: Deployment `movie-backend-v1`
  - **Image**: `sayedimran/istio-sample-app-backend:v1.0.2`
  - **Labels**: `app=movie-backend`, `version=v1`
  
- **File**: `manifests/base/deployment-v2.yaml`  
  - **Resource**: Deployment `movie-backend-v2`
  - **Image**: `sayedimran/istio-sample-app-backend:v1.0.2`
  - **Labels**: `app=movie-backend`, `version=v2`
  - **Environment**: Uses Hollywood data (`DATA_DIR=hollywood-data`)

### 3. Frontend Deployment
- **File**: `manifests/base/frontend.yaml`
  - **Resource**: Deployment `movie-frontend`
  - **Image**: `sayedimran/istio-sample-app-frontend:v1.0.2`
  - **Labels**: `app=movie-frontend`

### 4. Services
- **File**: `manifests/base/service.yaml`
  - **Resource**: Service `movie-backend`
  - **Port**: 8000
  - **Selector**: `app=movie-backend`

- **File**: `manifests/base/frontend.yaml` (includes service)
  - **Resource**: Service `movie-frontend`
  - **Port**: 80
  - **Selector**: `app=movie-frontend`

### 5. Istio Configuration
- **File**: `manifests/istio/gateway.yaml`
  - **Resource**: Gateway `istio-gateway`
  - **Hosts**: `*`
  - **Port**: 80 (HTTP)

- **File**: `manifests/istio/destination-rule.yaml`
  - **Resource**: DestinationRule `movie-backend`
  - **Subsets**: `v1` and `v2` based on version labels

- **File**: `manifests/base/frontend.yaml` (includes VirtualService)
  - **Resource**: VirtualService `movie-frontend`
  - **Routes**: Frontend traffic routing

### 6. Traffic Splitting Virtual Services
- **File**: `manifests/istio/virtual-services/virtual-service-100-0.yaml`
  - **Resource**: VirtualService `movie-backend`
  - **Traffic**: 100% to v1, 0% to v2

- **File**: `manifests/istio/virtual-services/virtual-service-80-20.yaml`
  - **Resource**: VirtualService `movie-backend`
  - **Traffic**: 80% to v1, 20% to v2

- **File**: `manifests/istio/virtual-services/virtual-service-50-50.yaml`
  - **Resource**: VirtualService `movie-backend`
  - **Traffic**: 50% to v1, 50% to v2

- **File**: `manifests/istio/virtual-services/virtual-service-0-100.yaml`
  - **Resource**: VirtualService `movie-backend`
  - **Traffic**: 0% to v1, 100% to v2

### 7. Configuration and Secrets
- **File**: `manifests/base/configmap.yaml`
  - **Resource**: ConfigMap `observability-config` (namespace `traffic-shifting-demo`)
    - **Contains**: Kiali and Grafana configurations
  - **Resource**: ConfigMap `traffic-policies` (namespace `default`)
    - **Contains**: Reference VirtualServices for each traffic split
  - **Resource**: ConfigMap `test-scenarios` (namespace `default`)
    - **Contains**: A load-test pod and a fault-injection VirtualService

- **Secret**: `tmdb-api-key`
  - **Created by**: `scripts/deploy.sh` script
  - **Contains**: TMDB API key for movie data

## Deployment Process

### Prerequisites
1. Docker and Kind (the script creates the `cluster1` Kind cluster if it doesn't exist)
2. `kubectl` and `istioctl` commands available
3. TMDB API key (optional, demo key used if not provided)

### Deployment Steps
The `scripts/deploy.sh` script (option 1, or `./scripts/deploy.sh deploy`) handles the complete deployment:

1. **Create Cluster**: Creates the Kind cluster `cluster1` from `infrastructure/kind/kind-config.yaml`, if it doesn't exist
2. **Install Istio**: Installs Istio from `infrastructure/istio/istio.yaml`, if the ingress gateway isn't already there
3. **Create Namespace**: Creates `traffic-shifting-demo` namespace with Istio injection
4. **Create Secret**: Creates TMDB API key secret
5. **Deploy Frontend**: Deploys frontend application with service and VirtualService
6. **Deploy Backend**: Deploys both v1 and v2 backend deployments
7. **Deploy Services**: Creates backend service
8. **Deploy Networking**: Creates Gateway and DestinationRule
9. **Deploy Config**: Creates the ConfigMaps from `configmap.yaml`
10. **Set Initial Routing**: Applies `virtual-service-100-0.yaml` (100% to v1)
11. **Wait for Ready**: Waits for all deployments to be available

### Traffic Management
Use the deployment script to manage traffic splitting:
- **100% V1**: `./scripts/deploy.sh` → Option 2
- **80% V1, 20% V2**: `./scripts/deploy.sh` → Option 3  
- **50% V1, 50% V2**: `./scripts/deploy.sh` → Option 4
- **100% V2**: `./scripts/deploy.sh` → Option 5

### Monitoring
- **Status Check**: `./scripts/deploy.sh` → Option 6
- **Get URL**: `./scripts/deploy.sh` → Option 7
- **Generate Traffic**: `./scripts/deploy.sh` → Option 8
- **Test Splitting**: `./scripts/deploy.sh` → Option 9

### Cleanup
- **Full Cleanup**: `./scripts/deploy.sh` → Option 10
  - Removes all resources including namespace

## Resource Requirements
- **Frontend**: 512Mi memory, 500m CPU (requests), 1Gi memory, 1 CPU (limits)
- **Backend V1**: 512Mi memory, 500m CPU (requests), 1Gi memory, 1 CPU (limits)  
- **Backend V2**: 512Mi memory, 500m CPU (requests), 1Gi memory, 1 CPU (limits)

## Testing
Test the traffic splitting by:
1. Accessing the frontend URL
2. Making API calls to `/api/movies`
3. Observing logs from different backend versions
4. Using the built-in traffic test pod

All resources are properly configured to run in the `traffic-shifting-demo` namespace with proper isolation and Istio service mesh integration.
