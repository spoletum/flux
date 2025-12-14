# Flux Infrastructure Setup

This directory contains the FluxCD v2 GitOps configuration for the spoletum.net infrastructure.

## Structure

```
spoletum.net/
├── flux-system/           # Flux system components (auto-generated)
├── infrastructure.yaml    # Main infrastructure Kustomizations
└── infrastructure/        # Infrastructure components
    ├── sources/          # HelmRepository sources
    ├── cert-manager/     # cert-manager installation
    ├── traefik/          # Traefik ingress controller
    └── authentik/        # Authentik SSO
```

## Components

### 1. **cert-manager** (v1.19.2)
- Manages TLS certificates
- Includes Let's Encrypt ClusterIssuer for automatic certificate provisioning
- Email: spoletum@spoletum.net

### 2. **Traefik** (v37.4.0)
- Ingress controller with Kubernetes Gateway API support
- Configured for Hetzner Cloud load balancer
- Location: Helsinki (hel1)

### 3. **Authentik** (v2025.10.2)
- Single Sign-On (SSO) provider
- Values are encrypted with SOPS

## Setup Instructions

### 1. Configure SOPS for Secret Encryption

First, set up SOPS encryption for the authentik secrets:

```bash
# Configure SOPS with your encryption key (GPG, age, or cloud KMS)
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
# or for GPG:
# export SOPS_PGP_FP="your-gpg-fingerprint"
```

### 2. Encrypt Authentik Values

Copy your authentik values from the Terraform configuration and encrypt:

```bash
# Edit the secret with your authentik values
vi flux/spoletum.net/infrastructure/authentik/authentik-values-secret.sops.yaml

# Encrypt it with SOPS
sops -e -i flux/spoletum.net/infrastructure/authentik/authentik-values-secret.sops.yaml
```

### 3. Configure Flux to Use SOPS

Ensure Flux is configured with SOPS decryption support. Create a secret with your decryption key:

```bash
# For age:
cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

# For GPG:
gpg --export-secret-keys --armor "${SOPS_PGP_FP}" | \
kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc=/dev/stdin
```

### 4. Apply Infrastructure

Commit and push the changes:

```bash
cd /home/spoletum/Projects/spoletum/flux
git add spoletum.net/
git commit -m "Add infrastructure components with FluxCD"
git push
```

Then apply the infrastructure Kustomization:

```bash
kubectl apply -f spoletum.net/infrastructure.yaml
```

## Deployment Order

Flux manages dependencies automatically through the `dependsOn` field:

1. **infrastructure-sources** - Helm repositories (runs first)
2. **infrastructure-cert-manager** - cert-manager and Let's Encrypt issuer (depends on sources)
3. **infrastructure-traefik** - Traefik ingress controller (depends on sources)
4. **infrastructure-authentik** - Authentik SSO (depends on sources)

## Health Checks

Each component includes health checks to ensure proper deployment:
- cert-manager: Deployment + Webhook
- Traefik: Deployment
- Authentik: Server deployment

## Monitoring

Check the status of infrastructure components:

```bash
# Watch all Kustomizations
flux get kustomizations

# Watch HelmReleases
flux get helmreleases -A

# Check specific component
flux get helmrelease cert-manager -n flux-system
flux get helmrelease traefik -n flux-system
flux get helmrelease authentik -n flux-system
```

## Troubleshooting

### Check Flux logs
```bash
flux logs --all-namespaces --follow
```

### Check HelmRelease status
```bash
kubectl describe helmrelease cert-manager -n flux-system
kubectl describe helmrelease traefik -n flux-system
kubectl describe helmrelease authentik -n flux-system
```

### Reconcile manually
```bash
flux reconcile kustomization infrastructure-sources --with-source
flux reconcile kustomization infrastructure-cert-manager --with-source
flux reconcile kustomization infrastructure-traefik --with-source
flux reconcile kustomization infrastructure-authentik --with-source
```

## Differences from Terraform

This FluxCD setup replicates the Terraform configuration from `iac/k8s/` with these advantages:

- **GitOps**: All changes are version-controlled and automatically applied
- **Dependency Management**: Flux handles deployment order with health checks
- **Self-healing**: Flux continuously reconciles desired state
- **Secret Management**: Native SOPS integration for encrypted secrets
- **Observability**: Built-in status monitoring and notifications
