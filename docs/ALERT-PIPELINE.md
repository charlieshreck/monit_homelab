# Alert Pipeline Documentation

## Overview

All alerts from monitoring sources flow through Keep for deduplication, correlation, and forwarding to LangGraph for AI-assisted triage.

```
┌─────────────────────────────────────────────────────────────────┐
│                      ALERT SOURCES                               │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────┤
│ AlertManager│   Coroot    │   Beszel    │   Gatus     │ Manual  │
│  (monit)    │  (monit)    │  (monit)    │  (monit)    │ webhook │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┴────┬────┘
       │             │             │             │           │
       └─────────────┴─────────────┴─────────────┴───────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KEEP (agentic cluster)                       │
│                    10.20.0.40:31105                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Deduplication│→ │ Correlation  │→ │  Workflows   │          │
│  │ (fingerprint)│  │ (incidents)  │  │  (routing)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│               LANGGRAPH (agentic cluster)                       │
│  assess_alert → search_runbooks → [decision] → execute/escalate │
└─────────────────────────────────────────────────────────────────┘
```

## Keep Configuration

| Setting | Value |
|---------|-------|
| **Cluster** | agentic (10.20.0.0/24) |
| **Namespace** | keep |
| **NodePort** | 31105 |
| **External IP** | 10.20.0.40:31105 |
| **API Key** | Stored in Infisical at `/agentic-platform/keep/API_KEY` |

### Keep Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/alerts/event/alertmanager` | AlertManager webhook receiver |
| `/alerts/event/coroot` | Coroot webhook receiver |
| `/alerts/event/webhook` | Generic webhook (Beszel, manual) |
| `/alerts/event/gatus` | Gatus webhook receiver |

## Alert Source Configurations

### 1. AlertManager

**Location**: `/home/monit_homelab/kubernetes/argocd-apps/platform/kube-prometheus-stack-app.yaml`

```yaml
alertmanager:
  config:
    receivers:
      - name: 'keep'
        webhook_configs:
          - url: 'http://10.20.0.40:31105/alerts/event/alertmanager'
            send_resolved: true
```

**Status**: Configured via Helm values

---

### 2. Coroot

**Location**: `/home/monit_homelab/kubernetes/platform/coroot-config/coroot-cr.yaml`

Coroot uses the CRD's `notificationIntegrations.webhook` field (UI config not available with `authAnonymousRole: Viewer`).

```yaml
notificationIntegrations:
  baseURL: "http://10.30.0.20:32702"
  webhook:
    url: "http://10.20.0.40:31105/alerts/event/coroot"
    customHeaders:
      - key: X-API-KEY
        value: "16b7de2a-5d6d-4021-a774-53a083edc28e"
    incidents: true
    deployments: true
    incidentTemplate: |
      {
        "name": "{{ .Application.Name }}@{{ .Application.Namespace }}",
        "status": "{{ if eq .Status \"OK\" }}resolved{{ else }}triggered{{ end }}",
        "source": ["coroot"],
        "severity": "{{ if eq .Status \"CRITICAL\" }}critical{{ else if eq .Status \"WARNING\" }}warning{{ else }}info{{ end }}",
        "description": "{{ range .Reports }}{{ .Check }}: {{ .Message }} {{ end }}",
        "labels": {
          "namespace": "{{ .Application.Namespace }}",
          "application": "{{ .Application.Name }}",
          "kind": "{{ .Application.Kind }}"
        },
        "url": "{{ .URL }}"
      }
```

**Status**: Configured via CRD, synced by ArgoCD

---

### 3. Beszel

**Location**: Beszel UI → Settings → Notifications

Beszel uses Shoutrrr for notifications. A bridge service routes traffic from monit cluster to Keep.

#### Bridge Service

**File**: `/home/monit_homelab/kubernetes/platform/keep-bridge/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: keep
  namespace: monitoring
spec:
  ports:
    - port: 8080
      targetPort: 31105
      name: http
---
apiVersion: v1
kind: Endpoints
metadata:
  name: keep
  namespace: monitoring
subsets:
  - addresses:
      - ip: 10.20.0.40
    ports:
      - port: 31105
        name: http
```

#### Shoutrrr URL

```
generic://X-API-KEY:16b7de2a-5d6d-4021-a774-53a083edc28e@keep.monitoring:8080/alerts/event/webhook?disabletls=yes&template=json&titlekey=name&messagekey=description&$severity=warning&$source=beszel
```

**URL Breakdown**:
- `generic://` - Shoutrrr generic service
- `X-API-KEY:apikey@` - Basic auth format for header injection
- `keep.monitoring:8080` - Bridge service DNS name
- `/alerts/event/webhook` - Keep generic webhook endpoint
- `disabletls=yes` - Required for HTTP (not HTTPS)
- `template=json` - JSON payload format
- `titlekey=name` - Map Beszel title to Keep's `name` field
- `messagekey=description` - Map Beszel message to `description`
- `$severity=warning` - Static field
- `$source=beszel` - Static field

**Status**: Manual UI configuration required

---

### 4. Gatus (Pending)

**Location**: `/home/monit_homelab/kubernetes/applications/gatus/config.yaml`

```yaml
alerting:
  webhook:
    url: "http://10.20.0.40:31105/alerts/event/gatus"
    headers:
      Content-Type: application/json
      X-API-KEY: "16b7de2a-5d6d-4021-a774-53a083edc28e"
```

**Status**: Not yet configured

---

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONIT CLUSTER (10.30.0.0/24)                 │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ AlertManager   │  │ Coroot         │  │ Beszel         │    │
│  │ 10.30.0.x      │  │ 10.30.0.20     │  │ 10.30.0.20     │    │
│  │ :9093          │  │ :32702         │  │ :30090         │    │
│  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘    │
│          │                   │                   │              │
│          │                   │                   ▼              │
│          │                   │           ┌────────────────┐    │
│          │                   │           │ keep-bridge    │    │
│          │                   │           │ Service        │    │
│          │                   │           │ :8080→31105    │    │
│          │                   │           └───────┬────────┘    │
└──────────┼───────────────────┼───────────────────┼──────────────┘
           │                   │                   │
           └───────────────────┴───────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   AGENTIC CLUSTER (10.20.0.0/24)                │
│                                                                  │
│  ┌────────────────┐                                             │
│  │ Keep           │                                             │
│  │ 10.20.0.40     │                                             │
│  │ :31105         │                                             │
│  └────────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Check Keep Health
```bash
# Via MCP
keep_health()

# Via curl
curl http://10.20.0.40:31105/healthcheck
```

### List Alerts in Keep
```bash
# Via MCP
keep_list_alerts(limit=20)
```

### Test Webhook Manually
```bash
curl -X POST http://10.20.0.40:31105/alerts/event/webhook \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: 16b7de2a-5d6d-4021-a774-53a083edc28e" \
  -d '{
    "name": "Test Alert",
    "severity": "warning",
    "description": "Manual test alert",
    "source": "manual"
  }'
```

### Check Beszel Connectivity
```bash
# From monit cluster pod
kubectl exec -n monitoring deploy/beszel -- \
  curl -v http://keep.monitoring:8080/healthcheck
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Beszel "http response to https" | Shoutrrr defaults to HTTPS | Add `disabletls=yes` |
| Beszel 401 Unauthorized | Header not sent correctly | Use basic auth format `user:pass@host` |
| Keep "Provider not found" | Source-specific endpoint | Use `/alerts/event/webhook` for generic |
| Coroot "not allowed" | Anonymous role is Viewer | Configure via CRD YAML, not UI |

## Related Files

- Keep Bridge: `/home/monit_homelab/kubernetes/platform/keep-bridge/`
- Coroot CR: `/home/monit_homelab/kubernetes/platform/coroot-config/coroot-cr.yaml`
- AlertManager: `/home/monit_homelab/kubernetes/argocd-apps/platform/kube-prometheus-stack-app.yaml`
- Plan: `/root/.claude/plans/transient-scribbling-spark.md`
