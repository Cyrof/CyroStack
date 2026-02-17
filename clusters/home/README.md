# CyroStack &mdash; Home Cluster (FLux GitOps)

This directory contains the GitOps configuration for the **CyroStack home Kubernetes cluster**, managed by **FluxCD**.

All infrastructure and applications in this cluster are declaratively managed through this folder.

## Architecture Overview

Flux watches this repository and continuously reconciles:

```text
clusters/home
```

Any commit pushed to the tracked branch will automatically be applied to the cluster

### Reconciliation Flow

```bash
Git -> Flux GitRepository -> Flux Kustomization -> HelmRelease / Manifests -> Cluster
```

## Directory Structure

```psql
clusters/home/
├── apps
├── flux-system
├── infra
├── kustomization.yaml
└── README.md
```

## Flux Bootstrap

Flux was bootstrapped into the cluster using

```bash
flux bootstrap github \
  --owner=<your-github-username> \
  --repository=<your-repo-name> \
  --branch=stable \
  --path=clusters/home \
  --personal \
```

This created:

```perl
flux-system/
├── gotk-components.yaml
├── gotk-sync.yaml
└── kustomization.yaml
```

These files:

- Install Flux controllers
- Configures Git repository source
- Define reconciliation path (`./cluster/home`)

## Infrastructure Layer (`infra/`)

The `infra/` directory contains cluster-wide infrastructure components

### Examples:

- cert-manager
- ingress-nginx
- weave-gitops
- porkbun-dns-updater

Each components typically includes:

```cpp
component/
├── helmrelease.yaml
├── helmrepository.yaml
├── namespace.yaml
├── values.yaml
└── kustomization.yaml
```

These are deployed using Flux `HelmRelease` objects.

## Application Layer (`apps/`)

Application workloads live under:

```text
apps
```

Example:

```bash
apps/wakeonlan/
```

Application are separated from infrastructure to maintain clean layering:

- `infra` = cluster-level services
- `apps` = user workloads

## Secret Management (SOPS + age)

This cluster uses SOPS with age encryption

Encrypted files follow:

```text
*.sops.yaml
```

Example

```bash
infra/porkbun-dns-updater/secret-main.sops.yaml
```

### Descryption Configuration

- age private key stored as Kubernetes secret:
    ```bash
    flux-system/sops-age
    ```
- Flux kustomiza-controller configured with:
  `ini
  --sops-age-secret=sops-age
  `
  Secrets are encrypted in Git and decrypted only inside the cluster during reconciliation.

## How Reconciliation Works

Root Kustomication:

```yaml
spec:
    path: ./clusters/home
    prune: true
    interval: 10m
```

This means:

- Every 10 minutes Flux checks for changes
- Drift is automatically corrected
- Removed manifests are pruned

Manual reconcile:

```bash
flux reconcile kustomization flux-system
```

## Observability

Check status:

```bash
flux get kustomizations -A
flux get helmreleases -A
```

Inspect failures:

```bash
kubectl -n flux-system logs deploy/kustomize-controller
```

## Design Principles

This cluster follows:

- Infrastructure as Code
- GitOps-first workflow
- Layered architecture (infra vs apps)
- Encrypted secrets in Git
- Declarative Helm management

## Operational Notes

- Do NOT apply manifests manually with kubectl.
- All changes must go through Git.
- Flux is the single source of truth.
- Any manual drift will be reverted automatically.

## Deployment Workflow

1. Modify manifests in this directory
2. Commit and push
3. Flux detects changes
4. Controllers reconcile
5. Cluster state updated
