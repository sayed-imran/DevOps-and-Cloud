# Multi-Cluster Istio on Kind

This demo joins two local Kind clusters into one Istio mesh using the **multi-primary, multi-network** model:

- Each cluster runs its own istiod (primary).
- The clusters are on different Istio networks (`network1`, `network2`), so traffic between them goes through **east-west gateways** on port `15443`.
- Each istiod reads the other cluster's API server through a **remote secret**, which lets it discover services in both clusters.
- Both clusters share one root CA, so mTLS works across clusters.
- **MetalLB** gives the east-west gateways LoadBalancer IPs that the other cluster can reach.

```
            kind-cluster1 (network1)                         kind-cluster2 (network2)
 ┌──────────────────────────────────────┐        ┌──────────────────────────────────────┐
 │ istiod ──── remote secret ───────────┼───────►│ API server                           │
 │ API server ◄─────────────────────────┼─────── │ istiod                               │
 │                                      │        │                                      │
 │ workloads ─► istio-eastwestgateway ◄─┼─15443─►│ istio-eastwestgateway ◄─ workloads   │
 │              (MetalLB LB IP)         │  mTLS  │ (MetalLB LB IP)                      │
 └──────────────────────────────────────┘        └──────────────────────────────────────┘
                         both clusters run on the `kind` Docker network
```

## Cluster Layout

| | cluster1 | cluster2 |
|---|---|---|
| kubectl context | `kind-cluster1` | `kind-cluster2` |
| Nodes | 1 control-plane + 1 worker | 1 control-plane + 1 worker |
| Pod subnet | `10.244.0.0/16` | `10.245.0.0/16` |
| Service subnet | `10.96.0.0/16` | `10.97.0.0/16` |
| MetalLB pool | `172.17.255.1-172.17.255.100` | `172.17.255.101-172.17.255.200` |
| Istio mesh / cluster / network | `mesh1` / `cluster1` / `network1` | `mesh1` / `cluster2` / `network2` |

## Prerequisites

- Docker
- [Kind](https://kind.sigs.k8s.io/)
- `kubectl`
- `istioctl`

### Check the MetalLB pools against your Docker network

Both clusters are attached to the `kind` Docker network. The MetalLB pools must be inside that network's subnet, or the other cluster cannot reach the LoadBalancer IPs. Check the subnet:

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

The pools in `metallb-cluster1.yaml` and `metallb-cluster2.yaml` assume `172.17.0.0/16`. Docker often gives the `kind` network `172.18.0.0/16` instead, because the default bridge already uses `172.17.0.0/16`. In that case, change the pools to two ranges inside your subnet that don't overlap, for example `172.18.255.1-172.18.255.100` and `172.18.255.101-172.18.255.200`.

The `kind` network only exists after the first Kind cluster is created. If it isn't there yet, run `setup.sh`, check the subnet, and re-apply the MetalLB pool files if you need to change them.

> **Note:** The Traffic Shifting demo (`../Traffic-Management/traffic-shifting`) also creates a Kind cluster named `cluster1` with the same subnets. Delete it before you run this demo.

## Setup

Run all commands from this directory (`Istio/MultiCluster-Kind`).

### 1. Create the clusters and install MetalLB

```bash
./setup.sh
```

The script creates both clusters in parallel, installs MetalLB v0.14.9 in each one, and applies that cluster's IP pool.

<details>
<summary>Manual equivalent</summary>

```bash
kind create cluster --config cluster1-config.yaml
kind create cluster --config cluster2-config.yaml

for n in 1 2; do
  kubectl --context kind-cluster$n apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
  kubectl --context kind-cluster$n wait -n metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
  kubectl --context kind-cluster$n apply -f metallb-cluster$n.yaml
done
```

</details>

### 2. Install Istio and the east-west gateways

```bash
./istio-cluster-setup.sh
```

The script:

1. Installs Istio on cluster1 with `cluster1.yaml` (mesh `mesh1`, cluster `cluster1`, network `network1`).
2. Installs the east-west gateway with `eastwest-gateway-cluster1.yaml`, and applies `expose-services.yaml`. That file is a `Gateway` on port `15443` with `AUTO_PASSTHROUGH` TLS for `*.local` hosts, so services can be reached across networks.
3. Exports cluster1's self-signed root CA (`istio-ca-secret`) and applies it to cluster2 before installing Istio there, so both clusters use the same root of trust.
4. Repeats the Istio, east-west gateway, and expose steps on cluster2 with the `cluster2` files.

> **Warning:** Step 3 saves the CA to `istio-ca-secrets.yaml` in the current directory. The file contains the CA **private key**, so delete it once setup is done and never commit it.

Run the script once, on new clusters. It creates the `istio-system` namespace on cluster2 with `kubectl create`, so a second run stops at that step.

Check that both east-west gateways got an external IP from MetalLB:

```bash
kubectl --context kind-cluster1 get svc istio-eastwestgateway -n istio-system
kubectl --context kind-cluster2 get svc istio-eastwestgateway -n istio-system
```

### 3. Exchange remote secrets

```bash
export CTX_CLUSTER1=kind-cluster1
export CTX_CLUSTER2=kind-cluster2
./istio-secrets.sh
```

`istio-secrets.sh` reads `CTX_CLUSTER1` and `CTX_CLUSTER2` from the environment, so export them first. It creates a remote secret for each cluster and applies it to the other one. The kubeconfig points at `127.0.0.1`, which the other cluster can't reach, so the script uses each control-plane container's IP on the `kind` network (port `6443`) as the API server address.

## Verify

Each istiod should list both clusters as `synced`:

```bash
istioctl remote-clusters --context kind-cluster1
istioctl remote-clusters --context kind-cluster2
```

To check cross-cluster traffic, deploy Istio's `helloworld` sample with **v1 in cluster1** and **v2 in cluster2**, then call it from cluster1:

```bash
SAMPLES=https://raw.githubusercontent.com/istio/istio/release-1.30/samples   # match your Istio version

for n in 1 2; do
  kubectl --context kind-cluster$n create namespace sample
  kubectl --context kind-cluster$n label namespace sample istio-injection=enabled
  kubectl --context kind-cluster$n apply -n sample -f $SAMPLES/helloworld/helloworld.yaml -l service=helloworld
  kubectl --context kind-cluster$n apply -n sample -f $SAMPLES/helloworld/helloworld.yaml -l version=v$n
done
kubectl --context kind-cluster1 apply -n sample -f $SAMPLES/curl/curl.yaml

# Should print a mix of "Hello version: v1" and "Hello version: v2"
for i in $(seq 10); do
  kubectl --context kind-cluster1 exec -n sample deploy/curl -c curl -- curl -sS helloworld.sample:5000/hello
done
```

If you only see v1, check the gateway IPs from step 2 and the MetalLB pool subnet described under [Prerequisites](#prerequisites).

## Cleanup

```bash
kind delete cluster --name cluster1
kind delete cluster --name cluster2
rm -f istio-ca-secrets.yaml
```

## Files

| File | Purpose |
|------|---------|
| `cluster1-config.yaml`, `cluster2-config.yaml` | Kind cluster definitions (node image, pod and service subnets) |
| `metallb-cluster1.yaml`, `metallb-cluster2.yaml` | MetalLB `IPAddressPool` and `L2Advertisement` for each cluster |
| `setup.sh` | Creates both clusters and installs MetalLB |
| `cluster1.yaml`, `cluster2.yaml` | `IstioOperator` settings for the control plane (mesh ID, cluster name, network) |
| `eastwest-gateway-cluster1.yaml`, `eastwest-gateway-cluster2.yaml` | `IstioOperator` for the east-west gateway (ports 15021, 15443, 15012, 15017) |
| `expose-services.yaml` | `Gateway` that exposes `*.local` services on port 15443 with `AUTO_PASSTHROUGH` |
| `istio-cluster-setup.sh` | Installs Istio and the east-west gateways, and shares the root CA |
| `istio-secrets.sh` | Creates and exchanges the remote secrets |
