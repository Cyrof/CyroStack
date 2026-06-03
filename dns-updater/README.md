# Cyro DDNS &mdash; Porkbun Dynamic DNS (Kubernetes/k3s)

This directory contains the Helm chart and supporting configuration used to deploy a Porkbun Dynamic DNS updater into a Kubernetes (k3s) cluster.

The updater periodically:

1. Detects the current external (public) IP of your router
2. Compares it against the existing Porkbun DNS record
3. Updates the DNS record only if the IP has changed

This actual updater logic lives in the `porkbun-dns/` submodule located in this repository:

- See [porkbun-dns/README.md](/porkbun-dns-updater/porkbun-dns/README.md) for:
    - Local usage
    - Docker image builds
    - Script behavior and requirements

## High-level Design

- Helm-managed CronJobs
    - Daily run (sanity check)
    - Frequent run (DDNS sync)
- Secrets managed outside Helm
    - Created from local env files
    - Never committed to Git
- Single domain, multiple records
    - `knfolio.dev`
    - `vpn.knfolio.dev`

## CronJob Behavior (Important Safeguards)

To prevent runaway Jobs and stuck Pods, the CronJobs are configured with:

- `concurrencyPolicy: Forbid`
    - prevents overlapping runs
- `startingDeadlineSeconds`
    - avoids "catch-up" job storms
- `activeDeadlineSeconds`
    - kills hung jobs automatically
- Tight job history + TTL cleanup

This avoids the issue where frequent CronJobs pile up indefinitely.

## Secrets Configuration (Required)

Secrets are not mmanaged by Helm and must be created manually from local env files.

### Create the secrets directory (local only)

```bash
mkdir -p secrets
```

### Shared configuration (base)

`secrets/base.env`

```env
PORKBUN_API_KEY=pk1_...
PORKBUN_API_SECRET=sk1_...
PORKBUN_DOMAIN=knfolio.dev
PORKBUN_TTL=300
```

This file contains values shared by all records.

### Record-specific overrides

#### Main domain (`knfolio.dev`)

`secrets/main.env`

```env
PORKBUN_SUBDOMAIN=
```

#### VPN record (`vpn.knfolio.dev`)

`secrets/vpn.env`

```env
PORKBUN_SUBDOMAIN=vpn
```

### Create / update Kubernetes Secrets

```bash
kubectl create namespace cyro-ddns --dry-run=client -o yaml | kubectl apply -f -
```

#### Main domain secret

```bash
kubectl -n cryo-ddns create secret generic porkbun-creds \
    --from-env-file=secrets/base.env \
    --from-env-file=secrets/main.env \
    --dry-run=client -o yaml | kubectl apply -f -
```

#### VPN domain secret

```bash
kubectl -n cryo-ddns create secret generic porkbun-creds-vpn \
    --from-env-file=secrets/base.env \
    --from-env-file=secrets/vpn.env \
    --dry-run=client -o yaml | kubectl apply -f -
```

> Kubernetes automatically base64-encodes values internally &mdash; no manual encoding required.

## Helm Deployment

### Install / upgrade the release

```bash
helm upgrade --install cyro-ddns ./cryo-ddns \
    --namespace cyro-ddns \
    --create-namespace
```

### Verify CronJobs

```bash
kubectl get cronjob -n cryo-ddns
```

You should see:

- main daily
- main frequent
- vpn daily
- vpn frequent

## Manual Testing

Trigger a one-off run to verify behavior immediately.

### Main DDNS test

```bash
kubectl -n cyro-ddns create job \
    --from=cronjob/porkbun-ddns-main-frequent \
    manual-ddns-test-main
```

### VPN DDNS test

```bash
kubectl -n  cyro-ddns create job \
    --from=cronjob/porkbun-ddns-vpn-frequent \
    manual-ddns-test-vpn
```

### Watch logs

```bash
kubectl logs -f job/manual-ddns-test-main -n cryo-ddns
```

Successful runs should:

- Fetch external IP
- Compare with existing DNS record
- Exit cleanly (even if no update is needed)

## Verification (Outside the Cluster)

```bash
dig +short knfolio.dev
dig +short vpn.knfolio.dev

curl -s https://api.ipify.org
```

The DNS records should eventually resolve to the current public IP (subject to TTL).

## Notes & Requirements

- Cluster must be able to reach:
    - `api.porkbun.com`
    - `api.ipify.org`
- DNS records must already exist in Porkbun
- TTL should remain short (e.g. 300s) for DDNS use
- Secrets directory must be gitignored

```gitignore
secrets/
*.env
```
