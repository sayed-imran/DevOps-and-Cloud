# Istio Service Mesh Demos

Hands-on demos of Istio's traffic management, security, and mesh expansion features. Each folder is a self-contained demo with its own manifests and, where available, its own README and scripts.

## Demos at a Glance

| Demo | What it shows | Key Istio resources | Docs |
|------|---------------|---------------------|------|
| [Traffic Shifting](Traffic-Management/traffic-shifting/) | Manual weighted routing between two backend versions | `Gateway`, `VirtualService`, `DestinationRule` | [README](Traffic-Management/traffic-shifting/README.md) · [SETUP](Traffic-Management/traffic-shifting/docs/SETUP.md) · [DEPLOYMENTS](Traffic-Management/traffic-shifting/docs/DEPLOYMENTS.md) |
| [Flagger Canary Release](Traffic-Management/flagger-canary-release/) | Automated, metrics-driven canary promotion and rollback | Flagger `Canary`, generated `VirtualService` | [README](Traffic-Management/flagger-canary-release/README.md) · [SETUP](Traffic-Management/flagger-canary-release/SETUP.md) |
| [External Auth](External%20Auth/) | Delegating authorization to a custom auth service | `AuthorizationPolicy` (`CUSTOM`), mesh `extensionProviders` | This page |
| [JWT Auth](JWT%20Auth/) | Validating JWTs and denying unauthenticated requests | `RequestAuthentication`, `AuthorizationPolicy` (`DENY`) | This page |
| [External VM](External-VM/) | Adding a VM outside Kubernetes to the mesh | `WorkloadGroup`, east-west gateway | [README](External-VM/README.md) |
| [Multi-Cluster on Kind](MultiCluster-Kind/) | Multi-primary mesh across two clusters on separate networks | `IstioOperator`, east-west gateways, remote secrets | [README](MultiCluster-Kind/README.md) |

## Directory Layout

```
Istio/
├── Traffic-Management/
│   ├── traffic-shifting/          # Weighted routing (100/0 → 80/20 → 50/50 → 0/100)
│   │   ├── infrastructure/        # Kind cluster config + IstioOperator profile
│   │   ├── manifests/             # base/ (app workloads) and istio/ (gateway, rules, weights)
│   │   ├── scripts/               # deploy.sh, test-traffic.sh, cleanup.sh
│   │   └── docs/                  # SETUP.md, DEPLOYMENTS.md
│   └── flagger-canary-release/    # Flagger canary + deploy/test/cleanup scripts
├── External Auth/
│   ├── api/                       # FastAPI items service (Deployment + NodePort Service)
│   ├── ext-auth-server/           # FastAPI auth server that checks a `role` header
│   └── ExternalAuthorizationPolicy.yaml
├── JWT Auth/
│   ├── api/                       # FastAPI items service (Deployment + NodePort Service)
│   ├── templates/                 # Jinja2 templates for the Istio resources
│   ├── variables.py               # Signs a JWT and renders the templates
│   └── run.py                     # Writes the rendered manifests to disk
├── External-VM/                   # East-west gateway, istiod exposure, WorkloadGroup
└── MultiCluster-Kind/             # Two Kind clusters + MetalLB + multi-primary Istio
```

## Prerequisites

| Tool | Needed for |
|------|------------|
| `kubectl` | All demos |
| `istioctl` | All demos (installing Istio and generating config) |
| [Kind](https://kind.sigs.k8s.io/) + Docker | Traffic Shifting, Multi-Cluster on Kind |
| Helm | Flagger Canary Release (installs Flagger and its load tester) |
| Python 3 with `jinja2` and `jwcrypto` | JWT Auth (generating manifests and a token) |
| `gcloud` (or another cloud CLI) | External VM (the guide creates the VM on GCP) |
| TMDB API key (optional) | Both Traffic Management demos, for real movie data |

The Kind configurations pin `kindest/node:v1.34.3`.

> **Note:** The Traffic Shifting demo and the Multi-Cluster demo both create a Kind cluster named `cluster1` with the same pod and service subnets. Run one at a time, or delete the cluster before switching.

---

## Traffic Management

### Traffic Shifting

Two versions of a movie backend sit behind one service: **v1** serves Bollywood titles and **v2** serves Hollywood titles. A React frontend calls the backend through the Istio ingress gateway, and swapping the `VirtualService` changes how traffic is split between the versions.

```
Client → Ingress Gateway → VirtualService (weights) → DestinationRule (v1 / v2 subsets) → movie-backend pods
```

```bash
cd Traffic-Management/traffic-shifting
./scripts/deploy.sh      # interactive menu
```

Choosing **option 1** in the menu creates the Kind cluster `cluster1`, installs Istio from `infrastructure/istio/istio.yaml`, and deploys the app into the `traffic-shifting-demo` namespace. The ingress gateway runs as NodePort `30000`, which Kind maps to port `80` on your host. Further options switch between the four weight presets in `manifests/istio/virtual-services/` (100/0, 80/20, 50/50, 0/100) and generate test traffic.

Run the scripts from the `traffic-shifting/` directory because they use relative paths.

### Flagger Canary Release

Flagger watches the `movie-backend` Deployment. When the pod template changes, Flagger runs a pre-rollout acceptance test and a load test, then shifts traffic to the canary **10% at a time up to 50%**, checking metrics every minute:

- request success rate ≥ 99%
- P99 request duration ≤ 500 ms
- rollback after 10 failed checks

```
Client → Ingress Gateway → Flagger-managed VirtualService → movie-backend-primary / movie-backend-canary
```

```bash
cd Traffic-Management/flagger-canary-release
./deploy.sh                                                        # menu: option 3 installs Istio, Prometheus, Flagger and the load tester; option 4 deploys
kubectl set env deployment/movie-backend DATA_DIR=hollywood-data   # change the pod template to start a canary release
kubectl get canary canary-release -w                               # watch the analysis
./cleanup.sh
```

The Gateway and routes use the host `devops.imran`, so send `-H "Host: devops.imran"` when calling the ingress gateway.

---

## Security

### External Auth

An `AuthorizationPolicy` with `action: CUSTOM` makes the sidecar of `fastapi-app` call `ext-auth-server` before it forwards a matching request. The auth server allows the request (`200`) when the request has the header `role: admin`, and rejects it (`401`) otherwise.

**1. Register the auth server as an extension provider.** The policy refers to a provider named `ext-authz`, which must exist in the mesh config. One way to add it is with `kubectl edit configmap istio -n istio-system`:

```yaml
mesh: |-
  extensionProviders:
    - name: ext-authz
      envoyExtAuthzHttp:
        service: ext-auth-server.default.svc.cluster.local
        port: 8000
        includeRequestHeadersInCheck: ["role"]   # forward the header the auth server checks
```

**2. Deploy the services and the policy** into a namespace with sidecar injection enabled:

```bash
cd "External Auth"
kubectl label namespace default istio-injection=enabled --overwrite
kubectl apply -f ext-auth-server/deploy.yaml
kubectl apply -f api/deploy.yaml
kubectl apply -f ExternalAuthorizationPolicy.yaml
```

**3. Test.** The API is exposed on NodePort `30070`, and its routes are under `/api/v1/` (for example `/api/v1/items`).

```bash
curl -i                  http://<node-ip>:30070/api/v1/items   # 401
curl -i -H "role: admin" http://<node-ip>:30070/api/v1/items   # 200
```

The policy only sends requests whose path matches its `rules[].to[].operation.paths` to the auth server, so those paths must match the API routes you want to protect.

### JWT Auth

`variables.py` signs an RS256 JWT with a local private key (issuer `sayedimran@crazeops.tech`, claim `role: admin`, valid for 24 hours) and renders four manifests from `templates/`:

| Generated file | Purpose |
|----------------|---------|
| `RequestAuthentication.yaml` | Validates tokens from the issuer against the key's public JWKS |
| `AuthzPolicy.yaml` | `DENY` requests that have no valid request principal, so a token is required |
| `IstioGateway.yaml` | Gateway `fastapi-gateway` for host `fastapi-app.default.domain.local` |
| `Virtualservice.yaml` | Routes that host to the `fastapi-app` service |

```bash
cd "JWT Auth"
pip install jinja2 jwcrypto
mkdir -p keys && openssl genrsa -out keys/private-key.pem 2048   # keys/ is git-ignored
python run.py                                                    # prints the signed token, writes the manifests

kubectl apply -f api/deploy.yaml
kubectl apply -f RequestAuthentication.yaml -f AuthzPolicy.yaml -f IstioGateway.yaml -f Virtualservice.yaml
```

Expected behavior: a request with no token returns `403` (denied by the policy), a request with an invalid token returns `401`, and a request with `Authorization: Bearer <token>` reaches the API.

---

## Mesh Expansion

### External VM

This guide registers a GCP VM as a mesh workload for the [animal album sample app](../Sample-Apps/animal-images-display-app/README.md). It installs Istio with WorkloadEntry auto-registration and health checks, exposes istiod through an east-west gateway, creates a `WorkloadGroup` (`data-service` in the `animal-album` namespace), generates the VM bootstrap files with `istioctl x workload entry configure`, and installs the Istio sidecar package on the VM.

Full steps: [External-VM/README.md](External-VM/README.md)

![External VM architecture](../Docs/media/IstioExternalVMArch.svg)

### Multi-Cluster on Kind

This demo sets up a **multi-primary, multi-network** mesh (`mesh1`) across two local Kind clusters. MetalLB gives each cluster LoadBalancer IPs on the shared Docker network, so the east-west gateways can reach each other.

| | cluster1 | cluster2 |
|---|---|---|
| Istio network | `network1` | `network2` |
| Pod / Service CIDR | `10.244.0.0/16` / `10.96.0.0/16` | `10.245.0.0/16` / `10.97.0.0/16` |
| MetalLB pool | `172.17.255.1–100` | `172.17.255.101–200` |

```bash
cd MultiCluster-Kind
./setup.sh                    # create both Kind clusters and install MetalLB
./istio-cluster-setup.sh      # install Istio + east-west gateway on each cluster, share cluster1's CA with cluster2

export CTX_CLUSTER1=kind-cluster1 CTX_CLUSTER2=kind-cluster2
./istio-secrets.sh            # exchange remote secrets so each istiod can discover the other cluster's endpoints
```

`istio-secrets.sh` reads `CTX_CLUSTER1` and `CTX_CLUSTER2` from the environment, so export them first. It points each remote secret at the other cluster's control-plane container IP, because the kubeconfig's `127.0.0.1` address cannot be reached from inside the other cluster.

> **Note:** The MetalLB pools assume the `kind` Docker network is `172.17.0.0/16`. If yours is different (often `172.18.0.0/16`), edit the pools first. Also, `istio-cluster-setup.sh` saves the shared CA, including its private key, to `istio-ca-secrets.yaml`, so delete that file after setup. The [Multi-Cluster README](MultiCluster-Kind/README.md) covers both.

Cleanup: `kind delete cluster --name cluster1 && kind delete cluster --name cluster2`

---

## Author

**Sayed Imran** – DevOps and Cloud Engineer
