# Migration Checklist

## ✅ Completed Steps

1. **Created base infrastructure structure**
   - `infrastructure/sources/` - All HelmRepository definitions
   - `infrastructure/base/` - Base configurations for all components

2. **Set up multi-environment clusters**
   - `clusters/spoletum-net/` - Development environment
   - `clusters/spoletum-com/` - Production environment (ready for bootstrap)

3. **Configured environment overlays**
   - Traefik patched with environment-specific load balancer names
   - Authentik ready for environment-specific secrets

4. **Updated Flux sync paths**
   - spoletum-net: `./clusters/spoletum-net`
   - spoletum-com: `./clusters/spoletum-com`

## 🔄 Next Steps

### 1. Test the New Structure

Before deleting the old directory, verify the new structure works:

```bash
cd /home/spoletum/Projects/spoletum/flux

# Validate kustomize builds
kustomize build clusters/spoletum-net/flux-system
kustomize build clusters/spoletum-net/infrastructure/traefik
kustomize build infrastructure/sources

# Check for any errors
echo "If all commands succeeded, the structure is valid!"
```

### 2. Commit and Push Changes

```bash
cd /home/spoletum/Projects/spoletum/flux

git add clusters/ infrastructure/ README.md
git commit -m "Refactor to multi-environment structure

- Move infrastructure to shared base with environment overlays
- Create clusters/spoletum-net for development
- Create clusters/spoletum-com for production
- Each environment can now patch base configurations
- Traefik load balancer names customized per environment
"

# Don't push yet - test first!
```

### 3. Update the Running Cluster

Since you already have a cluster running with the old path, you need to update it:

```bash
# The flux-system Kustomization now points to ./clusters/dev
# This is already configured in gotk-sync.yaml

# Apply the updated sync configuration
kubectl apply -f clusters/dev/flux-system/gotk-sync.yaml

# Watch Flux reconcile the new structure
flux logs --follow
```

### 4. Verify Everything Works

```bash
# Check that all Kustomizations are healthy
flux get kustomizations

# Check HelmReleases
flux get helmreleases -A

# If everything looks good, proceed to cleanup
```

### 5. Clean Up Old Directory

Once you've verified the new structure works:

```bash
cd /home/spoletum/Projects/spoletum/flux

# Remove the old directory
rm -rf spoletum.net/

# Commit the cleanup
git add .
git commit -m "Remove old spoletum.net directory after migration"
git push
```

## 📋 Verification Checklist

Before removing `spoletum.net/`:

- [ ] New structure validated with kustomize build
- [ ] Changes committed to Git
- [ ] Flux reconciled successfully with new paths
- [ ] All infrastructure Kustomizations are healthy
- [ ] All HelmReleases are deployed and healthy
- [ ] No errors in Flux logs

## 🚀 Adding New Environments

To create a new environment:

```bash
# Copy the dev cluster as a template
cp -r clusters/dev clusters/staging

# Update the path in gotk-sync.yaml
sed -i 's|path: ./clusters/dev|path: ./clusters/staging|' clusters/staging/flux-system/gotk-sync.yaml

# Adjust patches in clusters/staging/infrastructure/*/kustomization.yaml as needed

# Bootstrap the new environment
flux bootstrap github \
  --owner=spoletum \
  --repository=flux \
  --branch=main \
  --path=clusters/staging \
  --personal

# Commit and push
git add clusters/staging
git commit -m "Add staging environment"
git push
```

## 🎯 Environment Details

### dev (Development)
- Path: `clusters/dev`
- Traefik LB: `dev`
- Purpose: Development and testing

New environments:
- Share the same base infrastructure definitions from `infrastructure/base/`
- Can be customized via Kustomize patches in `clusters/{env}/infrastructure/`
- Have independent Flux system components
- Can run different versions if needed

## 📝 Post-Migration Benefits

1. **Single Source of Truth**: Infrastructure defined once in `infrastructure/base/`
2. **Easy Environment Creation**: Copy cluster directory and adjust patches
3. **Version Control**: All environment differences visible in Git
4. **Consistent Base**: Same components across all environments
5. **Flexible Customization**: JSON patches for surgical changes
6. **Independent Deployment**: Each environment reconciles independently
