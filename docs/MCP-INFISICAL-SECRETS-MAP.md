# MCP Servers - Infisical Secrets Mapping

This document maps MCP server credentials to existing Infisical paths to avoid duplication.

## Existing Infisical Secret Paths

Based on analysis of existing InfisicalSecrets in both repos:

| Application | Path | Keys Already There | Notes |
|-------------|------|-------------------|-------|
| **Proxmox (Ruapehu)** | `/infrastructure/proxmox` | Used by Homepage | Production host (10.10.0.10) |
| **Proxmox (Carrick)** | `/monitoring/proxmox` | Used by Homepage | Monitoring host (10.30.0.10) |
| **OPNsense** | `/infrastructure/opnsense` | Used by Homepage | Firewall |
| **AdGuard Home** | `/infrastructure/adguard` | Used by Homepage | DNS filtering |
| **UniFi Network** | `/apps/unifi` | Used by Homepage | Network controller |
| **Coroot** | `/monitoring/coroot` | Used by Coroot agents | API keys for agents |

## MCP Server Credential Requirements

The MCP servers need these secrets (currently pointing to `/mcp-credentials`):

### ✅ Already Exist - Just Reference Them

| MCP Server | Needs | Already Exists At | Action |
|------------|-------|-------------------|--------|
| proxmox-ruapehu-mcp | PROXMOX_USER<br>PROXMOX_TOKEN_ID<br>PROXMOX_TOKEN_SECRET | `/infrastructure/proxmox` | **Change secretsPath to existing path** |
| proxmox-carrick-mcp | PROXMOX_USER<br>PROXMOX_TOKEN_ID<br>PROXMOX_TOKEN_SECRET | `/monitoring/proxmox` | **Change secretsPath to existing path** |
| opnsense-mcp | OPNSENSE_HOST<br>OPNSENSE_API_KEY<br>OPNSENSE_API_SECRET | `/infrastructure/opnsense` | **Change secretsPath to existing path** |
| adguard-mcp | ADGUARD_HOST<br>ADGUARD_USERNAME<br>ADGUARD_PASSWORD | `/infrastructure/adguard` | **Change secretsPath to existing path** |
| unifi-mcp | UNIFI_HOST<br>UNIFI_USERNAME<br>UNIFI_PASSWORD | `/apps/unifi` | **Change secretsPath to existing path** |

### ⚠️ Need to Add New Secrets

| MCP Server | Needs | Add To Path | Required Values |
|------------|-------|-------------|-----------------|
| infisical-mcp | UNIVERSAL_AUTH_CLIENT_ID<br>UNIVERSAL_AUTH_CLIENT_SECRET | `/infrastructure/infisical` (NEW) | Create Machine Identity in Infisical UI |
| coroot-mcp | COROOT_BASE_URL<br>COROOT_API_KEY | `/monitoring/coroot` (EXISTS) | Add `COROOT_BASE_URL=http://10.30.0.20:32702`<br>Add `COROOT_API_KEY=<from Coroot UI>` |
| kubernetes-prod-mcp | N/A | N/A | Uses kubeconfig ConfigMap (already created) |
| kubernetes-monitoring-mcp | N/A | N/A | Uses in-cluster ServiceAccount |
| talos-mcp | N/A | N/A | Uses talosconfig ConfigMap (already created) |

## Recommended Infisical Structure

```
prod_homelab (project slug: prod-homelab-y-nij)
└── prod (environment)
    ├── /infrastructure
    │   ├── proxmox          ✅ EXISTS (for Ruapehu)
    │   ├── opnsense         ✅ EXISTS
    │   ├── adguard          ✅ EXISTS
    │   └── infisical        ⚠️ NEW (for Infisical MCP Universal Auth)
    │
    ├── /monitoring
    │   ├── proxmox          ✅ EXISTS (for Carrick)
    │   ├── coroot           ✅ EXISTS (add COROOT_BASE_URL + COROOT_API_KEY)
    │   └── grafana          ✅ EXISTS
    │
    └── /apps
        └── unifi            ✅ EXISTS
```

## Action Plan

### Step 1: Update Existing Paths (No Duplication)

Update MCP server InfisicalSecret manifests to use existing paths:

**File**: `/home/monit_homelab/kubernetes/platform/mcp-servers/proxmox-mcp/infisical-secret.yaml` (NEW)

```yaml
---
# Proxmox Ruapehu credentials (use existing infrastructure path)
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: mcp-proxmox-ruapehu
  namespace: mcp-servers
spec:
  hostAPI: https://app.infisical.com/api
  authentication:
    universalAuth:
      credentialsRef:
        secretName: universal-auth-credentials
        secretNamespace: infisical-operator-system
      secretsScope:
        projectSlug: prod-homelab-y-nij
        envSlug: prod
        secretsPath: /infrastructure/proxmox  # ✅ Use existing
  managedSecretReference:
    secretName: mcp-proxmox-ruapehu
    secretNamespace: mcp-servers
    secretType: Opaque
    creationPolicy: Owner
---
# Proxmox Carrick credentials (use existing monitoring path)
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: mcp-proxmox-carrick
  namespace: mcp-servers
spec:
  hostAPI: https://app.infisical.com/api
  authentication:
    universalAuth:
      credentialsRef:
        secretName: universal-auth-credentials
        secretNamespace: infisical-operator-system
      secretsScope:
        projectSlug: prod-homelab-y-nij
        envSlug: prod
        secretsPath: /monitoring/proxmox  # ✅ Use existing
  managedSecretReference:
    secretName: mcp-proxmox-carrick
    secretNamespace: mcp-servers
    secretType: Opaque
    creationPolicy: Owner
```

Same pattern for:
- OPNsense → `/infrastructure/opnsense`
- AdGuard → `/infrastructure/adguard`
- UniFi → `/apps/unifi`

### Step 2: Add Missing Secrets to Existing Paths

**In Infisical UI:**

1. **Path: `/monitoring/coroot`** (already exists, just add these keys):
   ```
   COROOT_BASE_URL=http://10.30.0.20:32702
   COROOT_API_KEY=<get from Coroot UI: http://10.30.0.20:32702 → Settings → API Keys>
   ```

2. **Path: `/infrastructure/infisical`** (NEW path for Infisical MCP Universal Auth):
   ```
   UNIVERSAL_AUTH_CLIENT_ID=<from Infisical: Settings → Machine Identities → Create New>
   UNIVERSAL_AUTH_CLIENT_SECRET=<from Infisical: Settings → Machine Identities>
   ```

### Step 3: Update MCP Server Deployments

Update the deployments to reference the new individual InfisicalSecrets:

**Example: proxmox-ruapehu-mcp deployment.yaml**

```yaml
env:
- name: PROXMOX_HOST
  value: "10.10.0.10"
- name: PROXMOX_USER
  valueFrom:
    secretKeyRef:
      name: mcp-proxmox-ruapehu  # From /infrastructure/proxmox
      key: PROXMOX_USER
- name: PROXMOX_TOKEN_ID
  valueFrom:
    secretKeyRef:
      name: mcp-proxmox-ruapehu
      key: PROXMOX_TOKEN_ID
- name: PROXMOX_TOKEN_SECRET
  valueFrom:
    secretKeyRef:
      name: mcp-proxmox-ruapehu
      key: PROXMOX_TOKEN_SECRET
```

## Benefits of This Approach

1. ✅ **No duplication** - Use same credentials Homepage uses
2. ✅ **Single source of truth** - Update one place, all apps get it
3. ✅ **Organized structure** - Credentials grouped by function (`/infrastructure`, `/monitoring`, `/apps`)
4. ✅ **Clear ownership** - Follows existing pattern
5. ✅ **Easier rotation** - Rotate in one path, affects both Homepage and MCP servers

## Current Status

- ❌ MCP servers using non-existent `/mcp-credentials` path
- ✅ All needed credentials already exist in Infisical
- ⏳ Need to update InfisicalSecret manifests to point to existing paths
- ⏳ Need to add 2 new keys to `/monitoring/coroot`
- ⏳ Need to create `/infrastructure/infisical` path with Universal Auth creds

## Next Steps

1. Create individual InfisicalSecret files for each MCP server pointing to existing paths
2. Add COROOT_BASE_URL and COROOT_API_KEY to `/monitoring/coroot` in Infisical UI
3. Create Machine Identity in Infisical for `/infrastructure/infisical` path
4. Update MCP server deployments to reference individual secrets
5. Remove the single `/mcp-credentials` InfisicalSecret
6. Commit changes and let ArgoCD sync
