# MCP Server Docker Images

Pre-built Docker images for MCP (Model Context Protocol) servers used in the homelab monitoring infrastructure.

## Images

All images are published to GitHub Container Registry (ghcr.io):

- `ghcr.io/charlieshreck/proxmox-mcp` - Proxmox VE management
- `ghcr.io/charlieshreck/opnsense-mcp` - OPNsense firewall management
- `ghcr.io/charlieshreck/unifi-mcp` - UniFi Network management
- `ghcr.io/charlieshreck/adguard-mcp` - AdGuard Home DNS management

## Versioning

Images follow semantic versioning:
- `latest` - Latest build from main branch
- `v1.0.0` - Specific version tag
- `v1.0` - Minor version tag
- `v1` - Major version tag
- `main-<sha>` - Git commit SHA

## Automated Builds

GitHub Actions automatically builds and publishes images on:
- Push to main branch
- Creation of version tags (v*)
- Manual workflow dispatch

## Renovate Integration

Renovate Bot monitors npm package versions in Dockerfiles and creates PRs for updates automatically.

## Security

- Images run as non-root user (node)
- Based on Alpine Linux (minimal attack surface)
- Health checks included
- Public images (no authentication required)

## Local Testing

```bash
# Build locally
docker build -t proxmox-mcp:test ./proxmox/

# Run locally
docker run -p 8080:8080 \
  -e PROXMOX_HOST=10.10.0.10 \
  -e PROXMOX_USER=root@pam \
  -e PROXMOX_TOKEN_ID=your-token-id \
  -e PROXMOX_TOKEN_SECRET=your-secret \
  proxmox-mcp:test
```

## Kubernetes Deployment

Images are deployed via ArgoCD from `kubernetes/platform/mcp-servers/` manifests.
