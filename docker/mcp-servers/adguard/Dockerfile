FROM node:20-alpine

LABEL org.opencontainers.image.source="https://github.com/charlieshreck/monit_homelab"
LABEL org.opencontainers.image.description="AdGuard Home MCP Server"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Install the MCP server package
RUN npm install -g @fcannizzaro/mcp-adguard-home@1.0.4

# Run as non-root user
USER node

# Expose MCP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

# Run the server
CMD ["mcp-adguard-home"]
