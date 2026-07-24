# Product Overview

This doc will provide a quick synopsis of the products available from SUSE (both Infra and Cloud-Native) as well as references to provide an overview


## Rancher Rodeo
Check out the [SUSE Events page](https://www.rancher.com/events) and search for "Rancher Rodeo - North America".
This is a great way to get expose to the feature-functionality without any burden of acquiring hardware, building environments, etc..

    SUSE Rancher Rodeos are free, in-depth online workshops designed to give DevOps and IT teams the hands-on skills they need to deploy and manage Kubernetes everywhere.
    
    The content will be delivered by SUSE’s technical experts and is aimed at educating anyone interested in learning how to use containers or Kubernetes.
    
    During these virtual hands-on workshops, our technical experts will provide a deeper dive into SUSE Rancher Prime, secure application deployments with App Collection and SUSE Observability.

## SUSE Virtualization (Harvester)

> [Harvester OSS Project - Github](https://github.com/harvester/harvester)  
> [Harvester Homepage](https://harvesterhci.io/)  
> [SUSE Virtualization Homepage](https://www.suse.com/products/rancher/virtualization/)

Harvester is essentially the foundation of this homelab and demo environment.  I have complete confidence in proclaiming that Harvester, by far, is the easiest way to deploy a resilient, highly-available, fault tolerant compute platform for hosting Virtual Machines and Kubernetes.  There are some nuance, like any platform, but this repo will address the essentials and leave folks in a good place to explore further.

[HarvesterHCI YouTube](https://www.youtube.com/@HarvesterHCI) - SUSE produces a Harvester specific channel showcasiing the features and updates for Harvester.  
[Clemenko -  Kubernetes Firefighter](https://www.youtube.com/@clemenko) - Andy does a great job explaining many facets of SUSE Products and specifically Harvester.  (He worked at RGS previously)

## SUSE Rancher Manager

> [Rancher OSS Project - Github](https://github.com/rancher/rancher)  
> [Rancher Homepage](https://rancher.com/)  
> [SUSE Rancher Prime Homepage](https://www.suse.com/products/rancher/)

Rancher Manager is central point of administration (single pane of glass) for Virtual Machines, Kubernetes and Containers, configuration management, RBAC throughout the environment.  It allows you to manage multiple Kubernetes clusters...

## SUSE Security (NeuVector)

> [NeuVector OSS Project - Github](https://github.com/neuvector/neuvector)  
> [NeuVector Open Source Docs](https://open-docs.neuvector.com/)  
> [SUSE Security Homepage](https://www.suse.com/products/neuvector/)

NeuVector provides full lifecycle container security, including image vulnerability scanning, runtime threat detection, and a Kubernetes-native firewall that automatically learns and enforces network segmentation between workloads.

## SUSE Observability (StackState)

> [StackState - Github](https://github.com/StackVista)  
> [StackState Homepage](https://www.stackstate.com/)  
> [SUSE Observability Homepage](https://www.suse.com/products/rancher/observability/)

StackState delivers topology-driven observability, correlating metrics, traces, and events across the full stack so teams can quickly pinpoint root cause rather than sifting through disconnected dashboards and alerts.

## SUSE Linux Enterprise (SLE/SLES) / SUSE Linux Enterprise Micro (SL-micro)

> [openSUSE OSS Project - Github](https://github.com/openSUSE)  
> [openSUSE Homepage](https://www.opensuse.org/)  
> [SUSE Linux Enterprise Server Homepage](https://www.suse.com/products/server/)  
> [SUSE Linux Micro Homepage](https://www.suse.com/products/micro/)

SLE/SLES is SUSE's enterprise-grade, general-purpose Linux distribution, while SL-Micro is a minimal, immutable OS purpose-built to host containers and virtual machines with a smaller attack surface and streamlined patching.

## SUSE RKE2 (K3s when needed)

> [RKE2 OSS Project - Github](https://github.com/rancher/rke2)  
> [RKE2 Homepage](https://docs.rke2.io/)  
> [K3s OSS Project - Github](https://github.com/k3s-io/k3s)  
> [K3s Homepage](https://k3s.io/)  
> [SUSE Rancher Prime: RKE2 Homepage](https://www.suse.com/products/rancher-kubernetes-engine/)

RKE2 is a security-hardened, CIS-benchmark-compliant Kubernetes distribution built for government and enterprise workloads, while K3s is its lightweight sibling, optimized for edge, IoT, and resource-constrained environments.

## RGS Hauler

> [Hauler OSS Project - Github](https://github.com/hauler-dev/hauler)  
> [Hauler Homepage](https://hauler.dev/)  
> [Rancher Government Solutions Hauler Product Page](https://ranchergovernment.com/products/hauler)

Hauler is an air-gap tool that packages, transports, and unpacks container images, Helm charts, and files as OCI artifacts, making it well suited for populating registries and Kubernetes clusters in disconnected (enclave) environments.

## Harbor

> [Harbor OSS Project - Github](https://github.com/goharbor/harbor)  
> [Harbor Homepage](https://goharbor.io/)  
> [SUSE Private Registry (powered by Harbor)](https://www.suse.com/c/suse-private-registry-harbor/)

Harbor is an open-source container image registry that secures artifacts with vulnerability scanning, image signing, and role-based access control, and it serves as the backbone for SUSE Private Registry.
