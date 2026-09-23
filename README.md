<!---
title: Snicket Labs Reference Architecture
folder: "Technical Documentation"
status: 2
-->

# Snicket Labs Reference Architecture

A Terraform-based reference architecture for deploying the Snicket Labs system. It provisions a complete environment - Kubernetes cluster, database, cache, object storage, shared storage, secrets, autoscaling, and ingress - onto which the platform helm chart is installed.

> **Important Note**: This reference architecture is intended as a **guide and starting point**. The modules are composable, so you may adapt them to work with an existing project, VPC, or cluster rather than creating everything from scratch.

## Repository layout (multi-cloud)

The repository is organised per cloud provider:

- `environments/aws/` and `initial-state/aws/` — the AWS reference architecture (EKS)
- `environments/gcp/` and `initial-state/gcp/` — the GCP reference architecture (GKE)

## Deployment guides

| Cloud | Guide |
|---|---|
| **AWS (EKS)** | **[`README-aws.md`](./README-aws.md)** |
| **GCP (GKE)** | **[`README-gcp.md`](./README-gcp.md)** |

## Common reference

These topics apply to both clouds and are documented once:

- [Deployment Sizing Options](./docs/deployment-sizing.md)
- [Terraform State](./docs/terraform-state.md)
- [Event Driven Autoscaling (KEDA)](./docs/keda.md)

The resultant environment will be suitable for installing the platform helm chart, which runs the Snicket Labs system.

<!-- deliberate edit to a synced file, to prove the guard blocks it -->
