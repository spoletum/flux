# AI Agent Guidelines for Flux Repository

This document provides instructions for AI agents (like GitHub Copilot, Claude, etc.) working with this FluxCD GitOps repository.

## Repository Architecture

This is a **FluxCD v2 GitOps repository** using a **component-based architecture** with **Flux Kustomization CRs**.

### Key Structure

```
infrastructure/
  sources/           # Helm repository definitions
  components/        # Self-contained infrastructure components
    {component}/
      namespace.yaml
      release.yaml
      kustomization.yaml

clusters/
  {environment}/
    flux-system/              # Flux bootstrap (DO NOT EDIT)
    kustomization.yaml        # References infrastructure/
    infrastructure/
      {component}.yaml        # Flux Kustomization CR per component
      kustomization.yaml      # Lists all CRs
```

## Critical Rules

### 1. Use Flux Kustomization CRs, Not Kustomize Overlays

❌ **DON'T** create nested kustomize overlay directories:
```
clusters/dev/infrastructure/traefik/
  kustomization.yaml
  patches.yaml
```

✅ **DO** create Flux Kustomization CRs with inline patches:
```yaml
# clusters/dev/infrastructure/traefik.yaml
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
  patches:
    - target:
        kind: HelmRelease
        name: traefik
      patch: |-
        - op: replace
          path: /spec/values/service/annotations/load-balancer.hetzner.cloud~1name
          value: dev
```

### 2. Keep Paths Simple

- Use **short relative paths** from repository root: `./infrastructure/components/{name}`
- Avoid paths like `../../../../infrastructure/sources` - these break Flux's security model
- All `path:` fields in Kustomization CRs must be relative to repository root

### 3. Always Define Dependencies

Every Kustomization CR must have `dependsOn` to control deployment order:

```yaml
dependsOn:
  - name: infrastructure-sources  # Always depend on sources for Helm components
  - name: infrastructure-cert-manager  # If you need cert-manager ready first
```

### 4. One Kustomization CR Per Component

Each infrastructure component gets its own Kustomization CR:
- `clusters/dev/infrastructure/sources.yaml`
- `clusters/dev/infrastructure/cert-manager.yaml`
- `clusters/dev/infrastructure/traefik.yaml`
- `clusters/dev/infrastructure/authentik.yaml`
- `clusters/dev/infrastructure/tempo.yaml`
- `clusters/dev/infrastructure/prometheus.yaml`
- `clusters/dev/infrastructure/grafana.yaml`

Benefits:
- Independent reconciliation schedules
- Clear status visibility: `flux get kustomizations`
- Isolated failures - one component failing doesn't block others
- Easier debugging

### 5. Component Structure

Each component in `infrastructure/components/` must be self-contained:

```
infrastructure/components/myapp/
├── namespace.yaml          # Create namespace
├── release.yaml            # HelmRelease or raw manifests
├── kustomization.yaml      # Lists resources
└── (optional configs)      # Secrets, ConfigMaps, etc.
```

### 6. Environment-Specific Changes

Apply environment customizations via **patches in the Kustomization CR**, not by duplicating component files:

```yaml
# clusters/prod/infrastructure/traefik.yaml
spec:
  path: ./infrastructure/components/traefik
  patches:
    - target:
        kind: HelmRelease
        name: traefik
      patch: |-
        - op: replace
          path: /spec/values/replicas
          value: 3
        - op: replace
          path: /spec/values/service/annotations/load-balancer.hetzner.cloud~1name
          value: prod
```

### 7. Commit Before Reconciling

Flux reads from Git, not local filesystem:
1. Make changes to files
2. `git add` + `git commit` + `git push`
3. `flux reconcile kustomization flux-system --with-source`

Never run `flux reconcile` on uncommitted changes - it won't see them.

## Common Tasks

### Adding a New Component

1. Create component directory:
```bash
mkdir -p infrastructure/components/newapp
```

2. Create component files:
```yaml
# infrastructure/components/newapp/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: newapp

# infrastructure/components/newapp/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: newapp
  namespace: newapp
spec:
  interval: 30m
  chart:
    spec:
      chart: newapp
      version: 1.0.0
      sourceRef:
        kind: HelmRepository
        name: newapp-repo
        namespace: flux-system

# infrastructure/components/newapp/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - release.yaml
```

3. Create Kustomization CR for the environment:
```yaml
# clusters/dev/infrastructure/newapp.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-newapp
  namespace: flux-system
spec:
  interval: 10m
  path: ./infrastructure/components/newapp
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure-sources
```

4. Add to parent kustomization:
```yaml
# clusters/dev/infrastructure/kustomization.yaml
resources:
  - sources.yaml
  - cert-manager.yaml
  - traefik.yaml
  - newapp.yaml  # Add this line
```

5. Commit and reconcile:
```bash
git add infrastructure/components/newapp clusters/dev/infrastructure/
git commit -m "feat: add newapp component"
git push
flux reconcile kustomization flux-system --with-source
```

### Modifying an Existing Component

**Option 1: Change base component** (affects all environments)
- Edit files in `infrastructure/components/{component}/`

**Option 2: Environment-specific change** (affects one environment)
- Add/modify patches in `clusters/{env}/infrastructure/{component}.yaml`

### Adding a New Environment

1. Copy cluster directory:
```bash
cp -r clusters/dev clusters/prod
```

2. Update patches in all `clusters/prod/infrastructure/*.yaml` files

3. Bootstrap Flux:
```bash
flux bootstrap github \
  --owner=spoletum \
  --repository=flux \
  --branch=main \
  --path=clusters/prod \
  --personal
```

## Troubleshooting Checklist

When something isn't working:

1. **Did you commit and push?** Flux reads from Git
2. **Are paths relative to repo root?** Use `./infrastructure/...`
3. **Are dependencies correct?** Check `dependsOn` fields
4. **Is the Kustomization reconciling?** Run `flux get kustomizations`
5. **Any path errors?** Avoid `../../../..` paths that escape build directory

## What NOT to Do

❌ Create deep kustomize overlay hierarchies  
❌ Use paths like `../../../../infrastructure/`  
❌ Edit `clusters/{env}/flux-system/` files (Flux-managed)  
❌ Forget `dependsOn` in Kustomization CRs  
❌ Try to reconcile before committing changes  
❌ Create separate files for patches - use inline patches in CRs  
❌ Duplicate component files across environments  

## Validation Commands

Before committing changes:

```bash
# Test kustomize build locally
kustomize build clusters/dev/infrastructure/

# Validate a specific component
kustomize build infrastructure/components/{component}/

# Check Flux will accept it
flux diff kustomization flux-system --path clusters/dev

# After committing
flux reconcile kustomization flux-system --with-source
flux get kustomizations  # Check all are Ready
```

## Naming Conventions

- **Kustomization CRs**: `infrastructure-{component}` (e.g., `infrastructure-traefik`)
- **Component directories**: `infrastructure/components/{component}` (lowercase, hyphenated)
- **HelmRelease names**: Match component name (e.g., `traefik`, `cert-manager`)
- **Namespaces**: Usually match component name

## Ingress and TLS Configuration

This repository uses **traditional Kubernetes Ingress** (not Gateway API) with Traefik as the ingress controller.

### Ingress Configuration Pattern

Ingress resources live in application components and use automated TLS via cert-manager:

```yaml
# applications/components/myapp/route.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - myapp.dev.spoletum.net
      secretName: myapp-tls
  rules:
    - host: myapp.dev.spoletum.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-service
                port:
                  number: 80
```

### TLS Certificate Automation

Certificates are **automatically created by cert-manager** using the `cert-manager.io/cluster-issuer` annotation:

- **ClusterIssuer**: `letsencrypt` (configured in `infrastructure/components/cert-manager/letsencrypt-issuer.yaml`)
- **Certificate location**: Same namespace as the Ingress resource
- **Challenge type**: HTTP-01 (via Traefik)
- **Auto-renewal**: cert-manager handles renewal automatically

You do **NOT** need to create separate Certificate resources - cert-manager creates them from the Ingress annotation.

### Complete Application Component Structure

```
applications/components/myapp/
├── namespace.yaml          # Create app namespace
├── deployment.yaml         # Application workload
├── service.yaml            # ClusterIP service
├── route.yaml              # Ingress resource with TLS
└── kustomization.yaml      # Lists all resources
```

### Adding HTTPS to an Existing Application

1. **Add annotations and TLS section** to your Ingress:
   ```yaml
   metadata:
     annotations:
       cert-manager.io/cluster-issuer: letsencrypt
       traefik.ingress.kubernetes.io/router.entrypoints: websecure
   spec:
     tls:
       - hosts:
           - myapp.example.com
         secretName: myapp-tls
   ```

2. **Wait for certificate issuance** (usually 30-60 seconds):
   ```bash
   kubectl get certificate -n myapp
   kubectl describe certificate myapp-tls -n myapp
   ```

3. **Test the HTTPS endpoint**:
   ```bash
   curl -v https://myapp.example.com
   ```

### Common Pitfalls

❌ **Wrong ClusterIssuer name** - Check `kubectl get clusterissuer` (it's `letsencrypt`, not `letsencrypt-prod`)
❌ **Missing ingressClassName** - Must be `traefik`
❌ **Wrong entrypoint annotation** - Use `websecure` for HTTPS
❌ **Mismatched hostnames** - Must match in both `tls.hosts` and `rules.host`
❌ **DNS not configured** - Ensure hostname resolves to load balancer IP before cert issuance

### Troubleshooting Commands

```bash
# Check Ingress status
kubectl get ingress -A
kubectl describe ingress myapp -n myapp

# Check certificate issuance
kubectl get certificate -n myapp
kubectl describe certificate myapp-tls -n myapp

# Check certificate request (if stuck)
kubectl get certificaterequest -n myapp
kubectl describe certificaterequest myapp-tls-xxxxx -n myapp

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50

# Test HTTPS endpoint
curl -v https://myapp.example.com

# Verify DNS resolution
dig myapp.example.com
```

### HTTP to HTTPS Redirect

Traefik automatically redirects HTTP to HTTPS when using the `websecure` entrypoint. No additional configuration needed.

## Summary for AI Agents

When working with this repository:
1. **Understand it's component-based**: Each component is independent
2. **Use Flux Kustomization CRs**: Not traditional kustomize overlays
3. **Keep it simple**: Avoid deep nesting and complex relative paths
4. **Dependencies matter**: Always specify `dependsOn`
5. **Commit before reconcile**: Flux reads from Git
6. **Test locally**: Use `kustomize build` to validate before pushing
7. **Ingress pattern**: Use traditional Ingress resources with cert-manager annotations
8. **TLS Certificates**: Automatically managed by cert-manager from Ingress annotations

This architecture scales well, keeps environments synchronized, and makes troubleshooting straightforward.
