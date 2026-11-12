# Portfolio Deployment Configuration
This folder contains the Helm chart for my full-stack portfolio app (`ghcr.io/cyrof/kn-folio:v0.2.0`) on a k3s Raspberry Pi cluster under the `folio` namespace.

The chart targets [KN Folio v0.2.0](https://github.com/Cyrof/kn-folio/releases/tag/v0.2.0), which moves container publishing to GHCR and contact email delivery to Resend.

The deployment uses:
- **Kubernetes Deployment** (stateless)
- **Multiple replicas** 
- **ClusterIP Service**
- **NGINX Ingress**
- **Externally managed Kubernetes Secret for Resend**

## Overview
- Application runs as a Deployment, not a StatefulSet
- Supports horizontal scaling via replicas
- Secrets are not stored in Git and are not managed by Helm
- Traffic is routed internally via ClusterIP Service
- External access is handled by NGINX Ingress + cert-manager

## Architecture Summary 
- **Deployment**
    - Runs the portfolio container (`ghcr.io/cyrof/kn-folio:v0.2.0`)
    - Stateless, safe to scale
- **Service (ClusterIP)**
    - Exposes the app internally on port `3000`
- **Ingress (nginx)**
    - Routes `knfolio.dev` -> `knfolio-service:3000`
    - Terminates TLS using Let's Encrypt
- **Secret**
    - Manually created via `kubectl`
    - Injected into pods as environment variables

## Prerequisites
- k3s cluster running
- NGINX Ingress Controller installed
- cert-manager installed
- `letsencrypt-http01` ClusterIssuer available
- DNS A-record for `knfolio.dev` pointing to your ingress entrypoint
- A verified Resend sending domain and sending API key; see the [application setup guide](https://github.com/Cyrof/kn-folio/blob/v0.2.0/docs/resend-setup.md)
- Anonymous pull access to the GHCR image (the package must be public for this configuration)

The home cluster uses Flux with Traefik and `knfolio.cyrostack.dev`. Its overrides live in `clusters/home/apps/knfolio/values.yaml` and pin the same image and Resend Secret as this chart.

## Installation
### 1. Create namespace
```bash
kubectl create namespace folio
```

### 2. Prepare the Resend Secret before rollout
Use an existing local environment file containing only these three active variables: `RESEND_API_KEY`, `CONTACT_FROM_EMAIL`, and `RECIPIENT_EMAIL`. The sender must belong to your verified Resend domain. Leave values unquoted for kubectl's env-file parser. Keep the file outside this repository.

Create the Secret from that file without putting credentials in command history:
```bash
kubectl -n folio create secret generic knfolio-resend-secrets \
  --from-env-file=/path/to/kn-folio/.env.local \
  --dry-run=client -o yaml | kubectl apply -f -
```
This Secret is referenced by the Helm chart but not managed by Helm. Prepare it before reconciling Flux or upgrading Helm; the new pods require all three keys.

The tracked `clusters/home/apps/knfolio/secret.sops.yaml` still manages the old `knfolio-secrets` Gmail Secret. Keep it during the rollback window. The new Resend Secret must be provisioned separately using the command above, or added to the cluster's SOPS workflow with encrypted values. Do not commit plaintext credentials.

### 3. Deploy using Helm
For a manual Helm installation, render and review before upgrading. For the Flux-managed home cluster, follow the GitOps workflow instead of running a manual Helm upgrade, and use `clusters/home/apps/knfolio/values.yaml` when rendering for review.

From this directory:
```bash
helm lint ./knfolio-chart
helm template knfolio ./knfolio-chart -n folio
helm upgrade --install knfolio ./knfolio-chart -n folio --create-namespace --wait --timeout 5m
```

## Usage
### Verify deployment
```bash
kubectl get deploy,po,svc,ingress -n folio
```

### Test internally
    ```bash
    kubectl port-forward svc/knfolio-service 3000:3000 -n folio
    curl http://localhost:3000
    ```
### Access via domain (once DNS & TLS are set up):
    ```bash
    curl https://knfolio.dev
    ```

## Updating the App
### New release
Update `appVersion` in `knfolio-chart/Chart.yaml` and `image.tag` in both `knfolio-chart/values.yaml` and `../clusters/home/apps/knfolio/values.yaml` to the published version tag. Increment the chart's `version`, render and validate the manifests, then upgrade Helm or reconcile through Flux.

Docker Hub tags at `cyrof/kn-folio` no longer receive releases. Restarting a pod with the old image repository will not fetch v0.2.0.

### Update secrets
Re-run the Secret creation command above with the updated local environment file, then restart pods so they read the new values:
```bash
kubectl rollout restart deployment knfolio -n folio
kubectl rollout status deployment knfolio -n folio
```

After rollout, submit a test message through `/contact` and verify inbox delivery and Reply-To. The pods need outbound DNS and HTTPS access to `api.resend.com:443`. Keep the old Gmail Secret until the new release is verified; rollback also requires restoring the old image and Gmail environment references together.

## Scaling
To scale replicas:
```bash
kubectl scale deployment knfolio -n folio --replicas=3
```
(Replica count can also be managed via Helm values.)

## Notes
- Secrets are intentionally **excluded from Helm** and **not committed**
- TLS is handled by cert-manager using `knfolio-tls`
- Ingress routing depends on the `nginx` ingress class
- This setup is compatible with future migration to HPA or MetalLB
