# Istio External VM Setup

This guide will help you set up Istio on a Kubernetes cluster with an external VM. The external VM will be used to simulate an external service that communicates with the services in the Kubernetes cluster.

## Table of Contents

- [Kubernetes](#1-kubernetes)
- [Istio](#2-istio)
  - [Install Istioctl command line tool](#21-install-istioctl-command-line-tool)
  - [Install Istio with workload entry auto-registration and health checks](#22-install-istio-with-workload-entry-auto-registration-and-health-checks)
  - [Install the east-west gateway](#23-install-the-east-west-gateway)
  - [Expose istiod through the east-west gateway](#24-expose-istiod-through-the-east-west-gateway)
- [Sample Application](#3-sample-application)
- [Istio Configuration for External VM](#4-istio-configuration-for-external-vm)
  - [Create workload-group for the external VM](#41-create-workload-group-for-the-external-vm)
  - [Generate VM artifacts that will be used to configure the external VM](#42-generate-vm-artifacts-that-will-be-used-to-configure-the-external-vm)
- [External VM Setup](#5-external-vm-setup)
  - [Creating VM](#51-creating-vm)
  - [Copy the generated files to the external VM](#52-copy-the-generated-files-to-the-external-vm)
  - [Install the Istio sidecar on the external VM](#53-install-the-istio-sidecar-on-the-external-vm)
  - [Move the files into place and start Istio](#54-move-the-files-into-place-and-start-istio)
  - [Final Architecture](#final-architecture)

Run the commands in sections 2–4 from the repository root, because the file paths are relative to it.

### 1. Kubernetes

Any Kubernetes cluster works, including managed services like GKE, EKS, or AKS. Istio uses a Kubernetes service account as a workload's identity. For the external VM to communicate with the services in the cluster, it needs a service account and a Service there. The sample application in step 3 creates the `data-service-sa` service account that the VM's WorkloadGroup uses.

Before getting started with the setup, we need to have Istio pre-requisites installed in the Kubernetes cluster.


### 2. Istio

#### 2.1 Install Istioctl command line tool

At the time of writing this guide, the latest version of Istio is 1.23.2. You can download the latest version of Istio from the [Istio releases page](https://istio.io/latest/docs/setup/getting-started/#download). Note the version you install, because the sidecar package on the VM (step 5.3) must match it.

```bash
curl -L https://istio.io/downloadIstio | sh -
```


#### 2.2 Install istio with workload entry auto-registration and health checks.

```bash
istioctl install \
--set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
--set values.pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_HEALTHCHECKS=true
```

#### 2.3 Install the east-west gateway.

`east-west-gateway.yaml` is an `IstioOperator` that adds only the gateway (`profile: empty`), so install it with `istioctl`, not `kubectl apply`:

```bash
istioctl install -y -f Istio/External-VM/east-west-gateway.yaml
```

#### 2.4 Expose istiod through the east-west gateway

```bash
kubectl apply -f Istio/External-VM/istio-gateway.yaml
```

### 3. Sample Application
We'll be using a sample application to demonstrate the communication between the services in the Kubernetes cluster and the external VM. The sample application is an animal album application that displays images of animals. The details of the same can be found [here](../../Sample-Apps/animal-images-display-app/README.md).


#### Application Flow Diagram

![Animal Album](../../Docs/media/AnimalAppArch.svg)

```bash
kubectl apply -k Kubernetes/animal-album-manifests/
```

### 4. Istio Configuration for External VM

#### 4.1 Create workload-group for the external VM.

```bash
kubectl apply -f Istio/External-VM/workload-group.yaml
```

#### 4.2 Generate VM artifacts that will be used to configure the external VM.

```bash
mkdir vm_files
istioctl x workload entry configure \
     --file Istio/External-VM/workload-group.yaml \
     --output vm_files \
     --autoregister
```

### 5. External VM Setup


#### 5.1 Creating VM

Create a VM (preferably Ubuntu 22.04). I've used Google Cloud Platform to create a VM. You can use any cloud provider. 

```bash
gcloud compute instances create external-vm --tags=external-vm \
  --machine-type=e2-standard-2 \
  --network=default --subnet=default \
  --image-project=ubuntu-os-cloud \
  --image-family=ubuntu-2204-lts
```

#### 5.2 Copy the generated files to the external VM.

```bash
gcloud compute scp  vm_files/* ubuntu@external-vm:
```

#### 5.3 Install the Istio sidecar on the external VM.

Install the package first, because it creates the `istio-proxy` user that owns the files in the next step. Use the same version as the Istio control plane in your cluster.

```bash
ISTIO_VERSION=1.23.2
curl -LO https://storage.googleapis.com/istio-release/releases/${ISTIO_VERSION}/deb/istio-sidecar.deb
sudo dpkg -i istio-sidecar.deb
```

#### 5.4 Move the files into place and start Istio.

```bash
# place the root certificate in its proper place:
sudo mkdir -p /etc/certs
sudo cp ~/root-cert.pem /etc/certs/root-cert.pem

# place the token to the correct location on the file system:
sudo mkdir -p /var/run/secrets/tokens
sudo cp ~/istio-token /var/run/secrets/tokens/istio-token

# copy over the environment file and mesh configuration file:
sudo mkdir -p /var/lib/istio/envoy /etc/istio/config
sudo cp ~/cluster.env /var/lib/istio/envoy/cluster.env
sudo cp ~/mesh.yaml /etc/istio/config/mesh

# add the entry for istiod to the /etc/hosts file:
sudo sh -c 'cat $(eval echo ~$SUDO_USER)/hosts >> /etc/hosts'
sudo mkdir -p /etc/istio/proxy

# make the user "istio-proxy" the owner of all these files:
sudo chown -R istio-proxy /etc/certs /var/run/secrets /var/lib/istio /etc/istio/config /etc/istio/proxy

# start the Istio sidecar:
sudo systemctl start istio
```

The setup is complete now. It takes a while for the external VM to be ready to communicate with the services in the Kubernetes cluster. The connectivity can be confirmed by checking for a resource `workloadentry` in the animal album namespace.

```bash
kubectl get workloadentry -n animal-album
```

Once the WorkloadEntry shows up, traffic can be sent and received between the external VM and the services in the Kubernetes cluster. If it doesn't appear, check the sidecar log on the VM at `/var/log/istio/istio.log`.


## Final Architecture

![Final Architecture](../../Docs/media/IstioExternalVMArch.svg)

