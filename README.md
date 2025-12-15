# Flux GitOps Repository

This repository manages infrastructure and applications using FluxCD v2 with a multi-environment structure.

## Repository Structure

```
flux/
├── infrastructure/                  # Shared infrastructure components
│   ├── sources/                     # HelmRepository definitions
│   │   ├── jetstack.yaml
│   │   ├── traefik.yaml
│   │   ├── goauthentik.yaml
│   │   ├── grafana.yaml
│   │   └── prometheus-community.yaml
│   └── components/                  # Reusable component definitions
│       ├── cert-manager/            # cert-manager
│       │   ├── namespace.yaml
│       │   ├── release.yaml
│       │   ├── letsencrypt-issuer.yaml
│       │   └── kustomization.yaml
│       ├── traefik/                 # Traefik ingress controller
│       ├── authentik/               # Authentik SSO provider
│       ├── tempo/                   # Tempo tracing backend
│       ├── prometheus/              # Prometheus metrics stack
│       └── grafana/                 # Grafana dashboards
└── clusters/                        # Environment-specific configurations
    └── dev/                         # Development environment
        ├── flux-system/             # Flux bootstrap components
        ├── kustomization.yaml       # Entry point - references infrastructure/
        └── infrastructure/          # Kustomization CRs per component
            ├── sources.yaml         # Deploys infrastructure/sources
            ├── cert-manager.yaml    # Deploys infrastructure/components/cert-manager
            ├── traefik.yaml         # Deploys infrastructure/components/traefik + dev patches
            ├── authentik.yaml       # Deploys infrastructure/components/authentik
            ├── tempo.yaml           # Deploys infrastructure/components/tempo
            ├── prometheus.yaml      # Deploys infrastructure/components/prometheus
            ├── grafana.yaml         # Deploys infrastructure/components/grafana
            └── kustomization.yaml   # Lists all CRs above
```

## Architecture

### Component-Based Infrastructure
Each infrastructure component (cert-manager, traefik, tempo, etc.) is defined once in `infrastructure/components/`. Components are:
- Self-contained with namespace, release, and config
- Deployed via separate Flux Kustomization CRs
- Independently reconciled and versioned

### Environment-Specific Kustomization CRs
Each environment (`clusters/dev/`, `clusters/prod/`, etc.) contains Flux Kustomization CRs that:
- Reference shared components via `path: ./infrastructure/components/{component}`
- Apply environment-specific patches inline
- Manage dependencies via `dependsOn`
- Reconcile independently with their own schedules

### Dependency Management
Flux automatically handles deployment order:
```
infrastructure-sources (Helm repos)
    ↓
infrastructure-cert-manager
    ↓
infrastructure-traefik (depends on cert-manager)
```

### Benefits
- **Independent reconciliation**: Each component syncs on its own schedule
- **Clear visibility**: `flux get kustomizations` shows status of each component
- **Isolated patches**: Environment-specific changes live in the Kustomization CR
- **Explicit dependencies**: `dependsOn` ensures correct deployment order
- **Easy troubleshooting**: Each component has its own status and logs

## Components

### Infrastructure Components
1. **cert-manager** - TLS certificate management with Let's Encrypt
2. **Traefik** - Ingress controller (environment-specific patches applied)
3. **Authentik** - SSO provider (environment-specific configuration)
4. **Tempo** - Trace storage backend
5. **Prometheus** - Metrics collection
6. **Grafana** - Dashboards and visualization

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

Environment-specific changes are applied as patches in the Kustomization CRs located in `clusters/{environment}/infrastructure/`.

### Example: Change Traefik Load Balancer Name

Edit `clusters/dev/infrastructure/traefik.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-traefik
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/components/traefik
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure-sources
    - name: infrastructure-cert-manager
  patches:
    - target:
        kind: HelmRelease
        name: traefik
      patch: |-
        - op: replace
          path: /spec/values/service/annotations/load-balancer.hetzner.cloud~1name
          value: prod
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

1. **Add HelmRepository** to `infrastructure/sources/` (if needed)
2. **Create component directory** in `infrastructure/components/{component}/`:
   ```
   infrastructure/components/myapp/
   ├── namespace.yaml
   ├── release.yaml
   └── kustomization.yaml
   ```
3. **Create Kustomization CR** in `clusters/dev/infrastructure/myapp.yaml`:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: infrastructure-myapp
     namespace: flux-system
   spec:
     interval: 10m
     path: ./infrastructure/components/myapp
     prune: true
     sourceRef:
       kind: GitRepository
       name: flux-system
     dependsOn:
       - name: infrastructure-sources
   ```
4. **Add to kustomization** in `clusters/dev/infrastructure/kustomization.yaml`:
   ```yaml
   resources:
     - sources.yaml
     - cert-manager.yaml
     - traefik.yaml
     - authentik.yaml
     - tempo.yaml
     - prometheus.yaml
     - grafana.yaml
     - myapp.yaml  # Add this
   ```
5. **Commit and reconcile**: Flux will automatically deploy the new component

## Deployment Order

Flux manages dependencies automatically via `dependsOn` in Kustomization CRs:
1. `infrastructure-sources` - All Helm repositories
2. `infrastructure-cert-manager` - Depends on sources
3. `infrastructure-traefik` - Depends on sources + cert-manager

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

## Design Principles

This repository follows these conventions:

1. **Component-based architecture**: Each infrastructure component is self-contained in `infrastructure/components/`
2. **Kustomization CRs over overlays**: Use Flux Kustomization resources with inline patches instead of deep kustomize overlay hierarchies
3. **Explicit dependencies**: Always specify `dependsOn` to control deployment order
4. **Environment isolation**: Each environment is a separate cluster directory with its own Kustomization CRs
5. **Minimal nesting**: Avoid deep directory structures - keep paths simple and relative paths short
6. **Git as source of truth**: All changes go through Git, Flux reconciles automatically
