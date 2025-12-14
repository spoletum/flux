# External Secrets Integration for Authentik

This setup demonstrates using External Secrets Operator to manage Authentik credentials.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Source Secrets (SOPS encrypted)                            │
│  clusters/dev/infrastructure/authentik/                     │
│    └── authentik-credentials.sops.yaml                      │
│        (contains: secret_key, postgresql_password)          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Flux decrypts with SOPS
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Secret (flux-system namespace)                  │
│    authentik-credentials                                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ External Secrets reads via SecretStore
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ExternalSecret Resource                                    │
│  external-secret.yaml                                       │
│    - Reads from authentik-credentials                       │
│    - Templates values.yaml for Helm                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ External Secrets Controller creates
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Generated Secret (flux-system namespace)                   │
│    authentik-values                                         │
│      └── values.yaml (templated Helm values)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ HelmRelease references
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Authentik HelmRelease                                      │
│    Uses valuesFrom: authentik-values                        │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Source Secret (SOPS Encrypted)
**File:** `clusters/dev/infrastructure/authentik/authentik-credentials.sops.yaml`

Contains the raw credential values:
- `secret_key` - Authentik secret key
- `postgresql_password` - PostgreSQL password

This is encrypted with SOPS and decrypted by Flux.

### 2. SecretStore
**File:** `infrastructure/base/external-secrets/secret-store.yaml`

Defines how External Secrets accesses secrets:
```yaml
kind: SecretStore
provider:
  kubernetes:
    remoteNamespace: flux-system
```

This allows reading secrets from the flux-system namespace.

### 3. RBAC Configuration
**File:** `infrastructure/base/external-secrets/rbac.yaml`

Grants External Secrets controller permissions to:
- Read secrets from flux-system (source)
- Write secrets to flux-system (target)

### 4. ExternalSecret
**File:** `clusters/dev/infrastructure/authentik/external-secret.yaml`

Defines the transformation:
- Reads `authentik-credentials` secret
- Templates a complete `values.yaml` for Helm
- Creates `authentik-values` secret
- Includes all Authentik configuration (ingress, TLS, etc.)

### 5. HelmRelease
**File:** `infrastructure/base/authentik/release.yaml`

References the generated secret:
```yaml
valuesFrom:
  - kind: Secret
    name: authentik-values
    valuesKey: values.yaml
```

## Benefits

1. **Separation of Concerns**
   - Credentials stored separately from configuration
   - Easy to rotate secrets without touching Helm values

2. **Template Flexibility**
   - Use Go templates in ExternalSecret
   - Compose complex configurations from simple secrets

3. **External Provider Ready**
   - Currently uses Kubernetes secrets
   - Easy to swap for AWS Secrets Manager, Vault, etc.
   - Just change the SecretStore provider

4. **Environment-Specific**
   - Each environment has its own ExternalSecret
   - Can customize templates per environment
   - Shared base authentik configuration

## Migration from Direct SOPS Secret

**Before:**
```yaml
# Direct SOPS secret with full Helm values
kind: Secret
metadata:
  name: authentik-values
stringData:
  values.yaml: |
    # Full Helm chart values here
```

**After:**
```yaml
# Small credentials secret
kind: Secret
metadata:
  name: authentik-credentials
stringData:
  secret_key: xxx
  postgresql_password: yyy

# Separate ExternalSecret for templating
kind: ExternalSecret
spec:
  target:
    template:
      data:
        values.yaml: |
          # Template that uses {{ .secret_key }}
```

## Switching to External Providers

### Example: AWS Secrets Manager

1. Update SecretStore:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-north-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
```

2. Update ExternalSecret:
```yaml
spec:
  secretStoreRef:
    name: aws-secretsmanager
  data:
    - secretKey: secret_key
      remoteRef:
        key: dev/authentik/secret-key
    - secretKey: postgresql_password
      remoteRef:
        key: dev/authentik/postgres-password
```

3. Remove SOPS secret, credentials now in AWS

### Example: HashiCorp Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
```

## Updating Credentials

### Current (Kubernetes + SOPS)
```bash
# Edit the source secret
sops clusters/dev/infrastructure/authentik/authentik-credentials.sops.yaml

# Commit and push - Flux will sync
git add clusters/dev/infrastructure/authentik/authentik-credentials.sops.yaml
git commit -m "Update authentik credentials"
git push

# External Secrets will detect and regenerate authentik-values
# Flux will then update the HelmRelease
```

### With External Provider
Just update the secret in your external provider - External Secrets will sync automatically.

## Troubleshooting

### Check ExternalSecret Status
```bash
kubectl get externalsecret authentik-values -n flux-system
kubectl describe externalsecret authentik-values -n flux-system
```

### Check Generated Secret
```bash
kubectl get secret authentik-values -n flux-system
kubectl get secret authentik-values -n flux-system -o jsonpath='{.data.values\.yaml}' | base64 -d
```

### Check External Secrets Logs
```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Force Refresh
```bash
kubectl annotate externalsecret authentik-values -n flux-system \
  force-sync=$(date +%s) --overwrite
```

## Security Considerations

1. **RBAC**: External Secrets only has access to specific namespaces
2. **SOPS Encryption**: Source credentials encrypted at rest in Git
3. **Rotation**: Easy to rotate by updating source and refreshInterval handles propagation
4. **Audit**: All changes tracked in Git and Kubernetes audit logs
