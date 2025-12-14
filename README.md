# Flux GitOps Repository

This repository manages infrastructure and applications using FluxCD v2 with a multi-environment capable structure.

## Repository Structure

```
flux/
├── infrastructure/                  # Shared infrastructure base
│   ├── sources/                    # HelmRepository definitions (shared)
│   │   ├── jetstack.yaml
│   │   ├── traefik.yaml
│   │   ├── goauthentik.yaml
│   │   ├── external-secrets.yaml
│   │   └── dapr.yaml
│   └── base/                       # Base component configurations
│       ├── cert-manager/           # cert-manager v1.19.2
│       ├── traefik/                # Traefik v37.4.0
│       ├── authentik/              # Authentik v2025.10.2
│       ├── external-secrets/       # External Secrets Operator v0.10.9
│       └── dapr/                   # Dapr v1.14.4
└── clusters/                       # Environment-specific configurations
    └── dev/                        # Development environment
        ├── flux-system/            # Flux system components
        ├── infrastructure.yaml     # Infrastructure Kustomizations
        └── infrastructure/         # Environment-specific overlays
            ├── traefik/           # Traefik patches for dev
            └── authentik/         # Authentik config for dev
```

## Architecture

### Base Infrastructure
All infrastructure components are defined once in `infrastructure/base/`. Each component includes:
- Namespace definition
- HelmRelease specification
- Component-specific configurations

### Environment Overlays
Each cluster has its own overlay directory that:
- References the base infrastructure via Kustomize
- Applies environment-specific patches
- Can override values, change versions, or disable components

### Benefits
- **DRY Principle**: Infrastructure defined once, reused everywhere
- **Environment Parity**: Same base ensures consistency across environments
- **Easy Customization**: JSON patches for environment-specific changes
- **Version Control**: All changes tracked in Git
- **Declarative**: Flux continuously reconciles desired state

## Components

### Shared Infrastructure
1. **cert-manager** - TLS certificate management with Let's Encrypt
2. **External Secrets Operator** - Sync secrets from external providers
3. **Dapr** - Distributed application runtime for microservices

### Environment-Specific
4. **Traefik** - Ingress controller (patched per environment)
5. **Authentik** - SSO provider (configured per environment)

## Bootstrap New Environment

### For dev environment (already bootstrapped)
```bash
flux bootstrap github \
  --owner=spoletum \
  --repository=flux \
  --branch=main \
  --path=clusters/dev \
  --personal
```

### To add new environments
Copy the `clusters/dev` directory as a template and adjust the patches.

## Environment Configuration

### dev (Development)
- Hetzner Load Balancer: `dev`
- Location: Helsinki (hel1)
- Purpose: Development and testing

## Customizing Per Environment

### Example: Change Traefik Load Balancer Name

Edit `clusters/{environment}/infrastructure/traefik/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../infrastructure/base/traefik
patches:
  - target:
      kind: HelmRelease
      name: traefik
    patch: |-
      - op: repdev
        path: /spec/values/service/annotations/load-balancer.hetzner.cloud~1name
        value: my-custom-name
```

### Example: Override Helm Chart Version

```yaml
patches:
  - target:
      kind: HelmRelease
      name: traefik
    patch: |-
      - op: replace
        path: /spec/chart/spec/version
        value: 38.0.0
```

### Example: Add Environment-Specific Values

```yaml
patches:
  - target:
      kind: HelmRelease
      name: traefik
    patch: |-
      - op: add
        path: /spec/values/replicas
        value: 3
```

## Secret Management

Secrets are encrypted with SOPS. Each environment can have its own encryption keys.

### Setup SOPS

```bash
# Configure age or GPG key
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Encrypt a secret
sops -e -i clusters/spoletum-net/infrastructure/authentik/secret.yaml

# Configure Flux to decrypt
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=~/.config/sops/age/keys.txt
```

## Monitoring

### Check All Kustomizations
```bash
flux get kustomizations -A
```

### Check HelmReleases
```bash
flux get helmreleases -A
```

### Watch Reconciliation
```bash
flux logs --all-namespaces --follow
```

### Force Reconciliation
```bash
flux reconcile kustomization flux-system --with-source
```

## Adding New Components

1. **Add HelmRepository** to `infrastructure/sources/`
2. **Create base configuration** in `infrastructure/base/{component}/`
3. **Update** `infrastructure/kustomization.yaml` to include new component
4. **Create environment overlays** in `clusters/{env}/infrastructure/{component}/`
5. **Add Kustomization** to `clusters/{env}/infrastructure.yaml`

## Deployment Order

Flux manages dependencies automatically:
1. `infrastructure-sources` - All Helm repositories
2. `infrastructure-external-secrets`, `infrastructure-dapr`, `infrastructure-cert-manager` - Parallel
3. `infrastructure-traefik`, `infrastructure-authentik` - Parallel (after sources)

## Troubleshooting

### Component Not Deploying
```bash
# Check Kustomization status
kubectl describe kustomization infrastructure-{component} -n flux-system

# Check HelmRelease status
kubectl describe helmrelease {component} -n flux-system

# View logs
flux logs --level=error
```

### Configuration Not Applying
```bash
# Verify kustomize build
cd clusters/spoletum-net/infrastructure/{component}
kustomize build .

# Force reconciliation
flux reconcile kustomization infrastructure-{component} --with-source
```

### Secret Decryption Issues
```bash
# Verify SOPS secret exists
kubectl get secret sops-age -n flux-system

# Test decryption locally
sops -d clusters/spoletum-net/infrastructure/authentik/secret.yaml
```

## Migration Notes

This repository was migrated from a single-environment structure to multi-environment:
- Old: `spoletum.net/infrastructure/` (environment-specific)
- New: `infrastructure/base/` (shared) + `clusters/{env}/infrastructure/` (overlays)

The old `spoletum.net/` directory can be removed after verifying the new structure works.
