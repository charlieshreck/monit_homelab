# MCP Server Removal - Summary & Lessons Learned

## Date
December 21, 2025

## Actions Taken

### Removed from Monitoring Cluster (10.30.0.20)
- ✅ Deleted namespace: `mcp-servers` (force deleted)
- ✅ All pods, services, deployments removed

### Removed from Git Repository
- ✅ `kubernetes/platform/mcp-servers/` (all manifests)
- ✅ `kubernetes/argocd-apps/platform/mcp-servers-app.yaml`
- ✅ `docker/mcp-servers/` (all Dockerfiles)
- ✅ `.github/workflows/build-mcp-images.yaml`

### Removed from ArgoCD (Production Cluster)
- ✅ Deleted application: `mcp-servers` from ArgoCD namespace

## Root Cause Analysis

### What We Tried to Deploy
10 MCP server instances across 7 types:
1. **AdGuard MCP** - `@fcannizzaro/mcp-adguard-home@1.0.4`
2. **UniFi MCP** - `unifi-network-mcp@0.1.3`
3. **OPNsense MCP** - `@richard-stovall/opnsense-mcp-server@0.5.3`
4. **Proxmox MCP** (Carrick + Ruapehu) - `@puregrain/proxmox-emcp-node@0.4.7` ❌
5. **Talos MCP** - `@5dlabs/talos-mcp`
6. **Kubernetes MCP** (Prod + Monitoring) - Custom
7. **Coroot MCP** - Custom
8. **Infisical MCP** - `@infisical/mcp`

### Why They Failed

**Primary Issue: stdio vs HTTP**
- All MCP packages (AdGuard, UniFi, OPNsense, etc.) are **stdio-based servers**
- Designed for desktop MCP clients (Claude Desktop, Cursor, etc.)
- Exit immediately when no stdin is provided
- Result: `Completed` → Kubernetes restarts → `CrashLoopBackOff`

**Example from AdGuard README:**
> "Configure your MCP client to use `mcp-adguard-home` (it's a stdio server)."

**Secondary Issue: Non-existent packages**
- `@puregrain/proxmox-emcp-node@0.4.7` - **Does NOT exist on npm**
- Found via web search but never published
- Build failed: `npm ERR! 404 Not Found`

### What We Learned

1. **stdio MCP ≠ HTTP API**
   - stdio: Desktop tool integration (stdin/stdout communication)
   - HTTP: Kubernetes-ready (REST/SSE endpoints)
   - Cannot mix deployment models

2. **Read Package Documentation Thoroughly**
   - "it's a stdio server" = NOT for Kubernetes
   - Check for `--http` flag support
   - Verify deployment requirements BEFORE implementing

3. **Verify npm Packages Exist**
   - Web search results ≠ published packages
   - Always check: `npm view @package/name`
   - GitHub repos don't guarantee npm publication

4. **GitOps Verification is Critical**
   - Built Dockerfiles before verifying runtime behavior
   - Should have tested locally first
   - IaC/GitOps doesn't prevent design mistakes

## Monitoring Cluster Status (Post-Cleanup)

### ✅ Healthy
```
Namespaces: 6 active
- cilium-secrets
- coroot
- homepage
- infisical-operator-system
- monitoring
- traefik

Monitoring Pods: 15/16 healthy (93.75%)
- Victoria Metrics: Running ✅
- Victoria Logs: Running ✅
- Prometheus: Running ✅
- Grafana: Running ✅
- Alertmanager: Running ✅
- Beszel: Running ✅
- Gatus: Running ✅

ArgoCD Applications:
- homepage-rbac-monitoring: Synced/Healthy ✅
- monitoring-external: Synced/Healthy ✅
- monitoring-platform: Synced/Healthy ✅
```

## Next Steps - MCP Planning

Before implementing MCP servers again, we need to:

### 1. Define Requirements
- **What do we need MCP for?**
  - Remote infrastructure management via AI agents?
  - Desktop integration (Claude Desktop)?
  - API automation?
  
- **Which systems need MCP access?**
  - Proxmox VMs/LXC
  - Kubernetes clusters
  - Network devices (OPNsense, UniFi, AdGuard)
  - Talos nodes
  - Monitoring tools (Coroot, Grafana)

### 2. Choose Deployment Model

**Option A: Desktop MCP Clients (stdio)**
- Use stdio MCP servers on local machine
- Connect Claude Desktop directly to homelab
- **Pros:** Use existing npm packages as-is
- **Cons:** Not in Kubernetes, manual setup per machine

**Option B: HTTP MCP Servers (Kubernetes)**
- Build/find HTTP-native MCP servers
- Deploy in monitoring cluster
- **Pros:** Centralized, scalable, GitOps-managed
- **Cons:** Need to build custom or find HTTP-compatible packages

**Option C: Hybrid Approach**
- stdio wrapper → HTTP proxy (e.g., `mcp-proxy`)
- Deploy wrappers in Kubernetes
- **Pros:** Use existing stdio packages
- **Cons:** Additional complexity, another layer

### 3. Technical Implementation

**For Proxmox MCP:**
- GitHub repos found: `gilby125/mcp-proxmox`, `canvrno/ProxmoxMCP`
- Need to decide: Build from source or write custom
- Must support HTTP/SSE if deploying in Kubernetes

**For Network MCPs:**
- Assess if desktop usage is sufficient
- If Kubernetes needed, explore HTTP wrappers

**For Kubernetes/Talos MCPs:**
- Direct API access may be better than MCP abstraction
- Consider: kubectl, talosctl, Kubernetes client libraries

### 4. Documentation Requirements

Before implementation:
- [ ] Architecture decision document (ADR)
- [ ] Deployment model chosen and documented
- [ ] Package verification completed
- [ ] Local testing successful
- [ ] IaC manifests reviewed
- [ ] Rollback plan defined

## Files for Reference

This summary: `/home/monit_homelab/MCP-REMOVAL-SUMMARY.md`
Commit: `0f9184b` - "Remove all MCP servers - clean slate for proper planning"

## Key Metrics

- **Time spent:** ~6 hours
- **Lines of code removed:** 1,139
- **Files deleted:** 28
- **Docker images built:** 3 (AdGuard, UniFi, OPNsense)
- **GitHub Actions runs:** 2 (both partial failures)
- **Lessons learned:** Priceless 🎓

---

**Conclusion:** Clean slate achieved. Monitoring cluster healthy. Ready for proper MCP planning with full understanding of stdio vs HTTP deployment models.
