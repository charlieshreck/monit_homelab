# MCP Infrastructure Implementation Plan

## Executive Summary

This plan outlines the deployment of a production-grade Model Context Protocol (MCP) infrastructure on a Talos bare metal Kubernetes cluster using IaC and GitOps principles. The architecture features an AI-first design with LLM triage, multi-model querying (Gemini + Claude), automated PR workflows, and comprehensive context management via PostgreSQL vector database.

**Key Principles:**
- **AI-First Architecture**: LLM triage layer handles initial query routing
- **Multi-Model Intelligence**: Gemini and Claude for complex reasoning
- **Full IaC/GitOps**: Terraform + ArgoCD, zero manual operations
- **Automated Development**: PR automation for infrastructure changes
- **Context Persistence**: PostgreSQL + pgvector for long-term memory
- **Service Discovery**: Automatic MCP registration and health monitoring

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Query                               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LLM Triage Layer                              │
│  (Ollama/vLLM hosting Llama 3.1 70B or similar)                 │
│  - Intent classification                                         │
│  - Simple query handling                                         │
│  - MCP routing decisions                                         │
│  - Context retrieval from vector DB                              │
└────────────┬────────────────────────────────┬───────────────────┘
             │                                 │
             ▼                                 ▼
    ┌────────────────┐              ┌──────────────────┐
    │ Direct Response│              │  Route to MCP    │
    │  (Simple Q&A)  │              │    Gateway       │
    └────────────────┘              └────────┬─────────┘
                                              │
                                              ▼
                            ┌─────────────────────────────────┐
                            │      MCP Gateway Service        │
                            │  - Unified API endpoint         │
                            │  - Load balancing               │
                            │  - Request routing              │
                            │  - Health checking              │
                            └────────┬────────────────────────┘
                                     │
                ┌────────────────────┼────────────────────┐
                │                    │                    │
                ▼                    ▼                    ▼
    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
    │  Cluster MCPs   │  │  External MCPs  │  │  Custom MCPs    │
    │  (kmcp)         │  │  (ToolHive)     │  │  (Standard)     │
    ├─────────────────┤  ├─────────────────┤  ├─────────────────┤
    │ • Kubernetes    │  │ • Proxmox       │  │ • Discovery     │
    │   (prod)        │  │ • OPNsense      │  │   Service       │
    │ • Kubernetes    │  │ • UniFi         │  │ • Context DB    │
    │   (monitoring)  │  │ • AdGuard       │  │ • PR Automation │
    │ • Talos (prod)  │  │ • Caddy         │  │                 │
    │ • Talos (mon)   │  │                 │  │                 │
    └─────────────────┘  └─────────────────┘  └─────────────────┘
                │                    │                    │
                └────────────────────┼────────────────────┘
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │  PostgreSQL + pgvector │
                        │  - Query history       │
                        │  - Context embeddings  │
                        │  - MCP metadata        │
                        │  - Service discovery   │
                        └────────────────────────┘
                                     │
                                     ▼
                ┌─────────────────────────────────────────┐
                │     Multi-Model Query Engine            │
                │  - Gemini API (Google)                  │
                │  - Claude API (Anthropic)               │
                │  - Model selection based on task        │
                │  - Response aggregation                 │
                └─────────────────────────────────────────┘
```

## Technology Stack

### Core Infrastructure
- **Kubernetes**: Talos Linux bare metal cluster
- **IaC**: Terraform 1.6+
- **GitOps**: ArgoCD 2.9+
- **Secrets**: Infisical Universal Auth
- **Networking**: Cilium CNI with LoadBalancer IP pool
- **Ingress**: Traefik (internal) + Cloudflare Tunnel (external)

### AI/ML Components
- **Local LLM**: Ollama with Llama 3.1 70B (or vLLM for production scale)
- **Vector DB**: PostgreSQL 16 with pgvector extension
- **Embeddings**: text-embedding-3-small (OpenAI) or nomic-embed-text (local)
- **Multi-Model**: Gemini API + Claude API

### MCP Deployment Methods

| Method | Use Case | Services | Transport |
|--------|----------|----------|-----------|
| **kmcp** | Kubernetes-native APIs | Prod K8s, Monitoring K8s, Talos nodes | HTTP/SSE auto-generated |
| **ToolHive** | External stdio-based tools | Proxmox, OPNsense, UniFi, AdGuard, Caddy | Sidecar proxy (stdio→HTTP) |
| **Standard Docker** | Custom services | Discovery, Context DB, PR automation | Custom HTTP/SSE |

### Development Workflow
- **Version Control**: GitHub (monit_homelab repo)
- **CI/CD**: GitHub Actions
- **PR Automation**: Auto-generation of infrastructure PRs based on discovery
- **Testing**: Local validation with kind/k3s before bare metal deployment

## Detailed Component Design

### 1. LLM Triage Layer

**Purpose**: First-line AI that handles simple queries and routes complex ones

**Deployment**: Talos cluster namespace `mcp-system`

**Implementation**:
```yaml
# Ollama deployment with Llama 3.1 70B
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-triage
  namespace: mcp-system
spec:
  replicas: 2  # HA
  template:
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        resources:
          requests:
            cpu: 4000m
            memory: 32Gi
          limits:
            cpu: 8000m
            memory: 64Gi
        volumeMounts:
        - name: models
          mountPath: /root/.ollama
      # Init container to pull model
      initContainers:
      - name: pull-model
        image: ollama/ollama:latest
        command: ['ollama', 'pull', 'llama3.1:70b']
```

**Triage Logic**:
1. **Simple queries** → Direct LLM response (no MCP needed)
2. **Infrastructure operations** → Route to appropriate MCP server
3. **Complex reasoning** → Escalate to Gemini/Claude
4. **Context retrieval** → Query vector DB first, then respond

**API Endpoints**:
- `POST /api/v1/query` - Main query endpoint
- `GET /api/v1/health` - Health check
- `GET /api/v1/metrics` - Prometheus metrics

### 2. PostgreSQL Vector Database

**Purpose**: Long-term memory, context storage, service discovery metadata

**Deployment**: Dedicated StatefulSet with persistent storage

**Schema Design**:
```sql
-- Query history with embeddings
CREATE TABLE query_history (
    id BIGSERIAL PRIMARY KEY,
    query_text TEXT NOT NULL,
    query_embedding vector(1536),  -- OpenAI text-embedding-3-small
    response_text TEXT,
    llm_model VARCHAR(50),
    mcp_servers_used TEXT[],
    execution_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- MCP server registry
CREATE TABLE mcp_servers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    type VARCHAR(50) NOT NULL,  -- 'kmcp', 'toolhive', 'standard'
    endpoint VARCHAR(255) NOT NULL,
    health_status VARCHAR(20) DEFAULT 'unknown',
    capabilities JSONB,  -- List of available tools
    last_seen TIMESTAMP,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Application context
CREATE TABLE app_contexts (
    id SERIAL PRIMARY KEY,
    app_name VARCHAR(100) NOT NULL,
    context_type VARCHAR(50),  -- 'config', 'state', 'logs', 'metrics'
    context_data JSONB,
    context_embedding vector(1536),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes
CREATE INDEX ON query_history USING ivfflat (query_embedding vector_cosine_ops);
CREATE INDEX ON app_contexts USING ivfflat (context_embedding vector_cosine_ops);
CREATE INDEX ON query_history (created_at DESC);
CREATE INDEX ON mcp_servers (health_status);
```

**InfisicalSecret for Postgres**:
```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: postgres-vector-db-credentials
  namespace: mcp-system
spec:
  hostAPI: https://app.infisical.com/api
  authentication:
    universalAuth:
      credentialsRef:
        secretName: universal-auth-credentials
        secretNamespace: infisical-operator-system
      secretsScope:
        projectSlug: monit-homelab
        envSlug: prod
        secretsPath: /mcp-system/postgres
  managedSecretReference:
    secretName: postgres-vector-db
    secretNamespace: mcp-system
```

**Persistent Volume**:
- **Storage Class**: `mayastor-3` (if using Mayastor) or local-path
- **Size**: 100Gi initial, expandable
- **Backup**: Daily pgBackRest to TrueNAS NFS

### 3. MCP Gateway Service

**Purpose**: Unified API gateway for all MCP servers

**Features**:
- Service discovery integration
- Load balancing across MCP instances
- Health checking and circuit breaking
- Request/response logging to vector DB
- Prometheus metrics

**Implementation**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mcp-gateway
  namespace: mcp-system
spec:
  type: LoadBalancer
  loadBalancerIP: 10.30.0.91  # From Cilium pool
  ports:
  - port: 8080
    name: http
  - port: 8081
    name: metrics
  selector:
    app: mcp-gateway
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-gateway
  namespace: mcp-system
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: gateway
        image: ghcr.io/charlieshreck/mcp-gateway:v1.0.0
        env:
        - name: POSTGRES_HOST
          value: postgres-vector-db
        - name: POSTGRES_DATABASE
          value: mcp_context
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-vector-db
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-vector-db
              key: password
        - name: DISCOVERY_INTERVAL
          value: "30s"
```

### 4. MCP Server Deployments

#### 4.1 Kubernetes MCP (kmcp)

**Target**: Production and monitoring Kubernetes clusters

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-prod-mcp
  namespace: mcp-system
spec:
  template:
    spec:
      serviceAccountName: mcp-kubernetes-reader
      containers:
      - name: kmcp
        image: ghcr.io/strowk/kmcp:latest
        args:
        - serve
        - --kubeconfig=/etc/kubernetes/kubeconfig
        - --port=8080
        volumeMounts:
        - name: kubeconfig
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: kubeconfig
        secret:
          secretName: prod-cluster-kubeconfig
---
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-prod-mcp
  namespace: mcp-system
spec:
  ports:
  - port: 8080
  selector:
    app: kubernetes-prod-mcp
```

**RBAC**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mcp-kubernetes-reader
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
```

#### 4.2 Proxmox MCP (ToolHive)

**Target**: Proxmox VE hosts (Ruapehu, Carrick)

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: proxmox-ruapehu-mcp
  namespace: mcp-system
spec:
  template:
    spec:
      containers:
      # Sidecar: ToolHive HTTP proxy
      - name: toolhive-proxy
        image: ghcr.io/toolhive/toolhive:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: STDIO_COMMAND
          value: "npx"
        - name: STDIO_ARGS
          value: "@modelcontextprotocol/server-everything"
        - name: MCP_SERVER_NAME
          value: "proxmox-ruapehu"

      # Main container: Proxmox MCP (stdio-based)
      - name: proxmox-mcp
        image: node:20-alpine
        command: ['sleep', 'infinity']  # Kept alive by ToolHive
        env:
        - name: PROXMOX_HOST
          value: "10.10.0.10"
        - name: PROXMOX_USER
          value: "root@pam"
        - name: PROXMOX_TOKEN_ID
          valueFrom:
            secretKeyRef:
              name: mcp-proxmox-ruapehu
              key: TOKEN_ID
        - name: PROXMOX_TOKEN_SECRET
          valueFrom:
            secretKeyRef:
              name: mcp-proxmox-ruapehu
              key: API_TOKEN
---
apiVersion: v1
kind: Service
metadata:
  name: proxmox-ruapehu-mcp
  namespace: mcp-system
spec:
  ports:
  - port: 8080
  selector:
    app: proxmox-ruapehu-mcp
```

**Duplicate for Carrick** (10.30.0.10)

#### 4.3 Network MCPs (ToolHive)

**OPNsense**:
```yaml
# Similar ToolHive pattern
containers:
- name: toolhive-proxy
  image: ghcr.io/toolhive/toolhive:latest
- name: opnsense-mcp
  image: node:20-alpine
  env:
  - name: OPNSENSE_HOST
    value: "10.10.0.1"
  - name: OPNSENSE_API_KEY
    valueFrom:
      secretKeyRef:
        name: mcp-opnsense
        key: key
  - name: OPNSENSE_API_SECRET
    valueFrom:
      secretKeyRef:
        name: mcp-opnsense
        key: secret
```

**UniFi, AdGuard, Caddy**: Same ToolHive sidecar pattern

#### 4.4 Discovery Service (Standard Docker)

**Purpose**: Automatically discover and register new MCP-capable services

**Custom Implementation**:
```python
# discovery-service/main.py
import asyncio
import httpx
from kubernetes import client, watch
from pgvector.asyncpg import register_vector
import asyncpg

async def discover_kubernetes_services():
    """Scan Kubernetes services for MCP annotations"""
    v1 = client.CoreV1Api()
    for svc in v1.list_service_for_all_namespaces().items:
        annotations = svc.metadata.annotations or {}
        if 'mcp.shreck.io/enabled' in annotations:
            await register_mcp_server({
                'name': f"{svc.metadata.namespace}/{svc.metadata.name}",
                'type': annotations.get('mcp.shreck.io/type', 'standard'),
                'endpoint': f"http://{svc.metadata.name}.{svc.metadata.namespace}.svc.cluster.local",
                'capabilities': annotations.get('mcp.shreck.io/capabilities', '').split(',')
            })

async def register_mcp_server(server_info):
    """Register MCP server in PostgreSQL"""
    conn = await asyncpg.connect(
        host='postgres-vector-db',
        database='mcp_context',
        user=os.getenv('POSTGRES_USER'),
        password=os.getenv('POSTGRES_PASSWORD')
    )
    await conn.execute("""
        INSERT INTO mcp_servers (name, type, endpoint, capabilities, metadata, last_seen)
        VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (name) DO UPDATE SET
            endpoint = EXCLUDED.endpoint,
            capabilities = EXCLUDED.capabilities,
            last_seen = NOW()
    """, server_info['name'], server_info['type'], server_info['endpoint'],
        server_info['capabilities'], json.dumps(server_info))
    await conn.close()
```

### 5. Multi-Model Query Engine

**Purpose**: Route complex queries to Gemini or Claude based on task type

**Implementation**:
```python
# multi-model-engine/router.py
from anthropic import Anthropic
import google.generativeai as genai

class MultiModelRouter:
    def __init__(self):
        self.anthropic = Anthropic(api_key=os.getenv('ANTHROPIC_API_KEY'))
        genai.configure(api_key=os.getenv('GOOGLE_API_KEY'))
        self.gemini = genai.GenerativeModel('gemini-2.0-flash-001')

    async def route_query(self, query: str, context: dict) -> dict:
        """Determine which model to use based on query characteristics"""

        # Gemini for: speed, multimodal, large context
        if self._is_multimodal(query) or len(context.get('history', [])) > 50:
            return await self._query_gemini(query, context)

        # Claude for: reasoning, code generation, structured output
        if self._requires_reasoning(query) or 'code' in query.lower():
            return await self._query_claude(query, context)

        # Default to Gemini (faster)
        return await self._query_gemini(query, context)

    async def _query_claude(self, query: str, context: dict) -> dict:
        response = self.anthropic.messages.create(
            model="claude-sonnet-4-5-20250929",
            max_tokens=4096,
            messages=[
                {"role": "user", "content": self._build_prompt(query, context)}
            ]
        )
        return {
            'model': 'claude-sonnet-4.5',
            'response': response.content[0].text,
            'usage': response.usage.dict()
        }

    async def _query_gemini(self, query: str, context: dict) -> dict:
        response = self.gemini.generate_content(
            self._build_prompt(query, context)
        )
        return {
            'model': 'gemini-2.0-flash',
            'response': response.text,
            'usage': {'tokens': response.usage_metadata.total_token_count}
        }
```

### 6. PR Automation Service

**Purpose**: Automatically create PRs when infrastructure changes are detected

**Triggers**:
1. Discovery service finds new MCP-capable service
2. Health checks detect configuration drift
3. Manual request via API

**Implementation**:
```python
# pr-automation/github_pr.py
from github import Github
import jinja2

async def create_mcp_registration_pr(server_info: dict):
    """Create PR to add new MCP server to IaC"""

    g = Github(os.getenv('GITHUB_TOKEN'))
    repo = g.get_repo('charlieshreck/monit_homelab')

    # Create branch
    main = repo.get_branch('main')
    branch_name = f"auto/add-mcp-{server_info['name']}"
    repo.create_git_ref(f"refs/heads/{branch_name}", main.commit.sha)

    # Generate manifests from template
    template = jinja2.Template(open('templates/mcp-deployment.yaml.j2').read())
    manifest = template.render(server_info)

    # Commit file
    repo.create_file(
        path=f"kubernetes/platform/mcp-servers/{server_info['name']}/deployment.yaml",
        message=f"Add MCP server: {server_info['name']} (auto-discovered)",
        content=manifest,
        branch=branch_name
    )

    # Create PR
    pr = repo.create_pull(
        title=f"[Auto] Add MCP server: {server_info['name']}",
        body=f"""
## Auto-Discovery PR

New MCP-capable service discovered by discovery service.

**Service Details:**
- Name: {server_info['name']}
- Type: {server_info['type']}
- Endpoint: {server_info['endpoint']}
- Capabilities: {', '.join(server_info['capabilities'])}

**Deployment Method:** {server_info['type']}

This PR was automatically generated. Please review the manifests before merging.
        """,
        head=branch_name,
        base='main'
    )

    # Add labels
    pr.add_to_labels('auto-generated', 'mcp-infrastructure')

    return pr.html_url
```

## Deployment Plan

### Phase 1: Foundation (Week 1)

**Objective**: Bootstrap core infrastructure

**Tasks**:
1. Create `mcp-system` namespace via Terraform
2. Deploy PostgreSQL with pgvector
3. Deploy Infisical operator and secrets
4. Create ArgoCD ApplicationSet for MCP servers
5. Setup Cilium LoadBalancer IP pool (10.30.0.90-10.30.0.99)

**Terraform**:
```hcl
# terraform/talos-single-node/mcp-system.tf
resource "kubernetes_namespace" "mcp_system" {
  metadata {
    name = "mcp-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "argocd.argoproj.io/managed-by" = "argocd"
    }
  }
}

resource "helm_release" "postgresql_vector" {
  name       = "postgres-vector-db"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "13.2.24"
  namespace  = kubernetes_namespace.mcp_system.metadata[0].name

  values = [file("${path.module}/values/postgresql-vector.yaml")]
}
```

**ArgoCD ApplicationSet**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: mcp-servers
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/charlieshreck/monit_homelab.git
      revision: main
      directories:
      - path: kubernetes/platform/mcp-servers/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: platform
      source:
        repoURL: https://github.com/charlieshreck/monit_homelab.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: mcp-system
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

**Deliverables**:
- PostgreSQL with pgvector running
- Database schema initialized
- Secrets synced from Infisical
- ArgoCD monitoring mcp-servers directory

### Phase 2: LLM Triage Layer (Week 2)

**Objective**: Deploy local LLM for query triage

**Tasks**:
1. Deploy Ollama with Llama 3.1 70B
2. Create triage API service
3. Implement query routing logic
4. Setup Prometheus metrics
5. Configure Traefik ingress

**Resource Requirements**:
- **CPU**: 8 cores dedicated
- **Memory**: 64GB (for 70B model)
- **GPU**: Optional (speeds up inference 10x)

**Alternative for limited resources**: Use Llama 3.1 8B (requires only 8GB RAM)

**API Service**:
```python
# triage-service/api.py
from fastapi import FastAPI
from pydantic import BaseModel
import ollama

app = FastAPI()

class Query(BaseModel):
    text: str
    context: dict = {}

@app.post("/api/v1/query")
async def triage_query(query: Query):
    # Generate embedding for vector search
    embedding = ollama.embeddings(model='nomic-embed-text', prompt=query.text)

    # Search vector DB for similar past queries
    similar = await search_vector_db(embedding['embedding'])

    # Determine routing
    response = ollama.chat(model='llama3.1:70b', messages=[{
        'role': 'system',
        'content': 'You are a query router. Determine if this query needs MCP tools or can be answered directly.'
    }, {
        'role': 'user',
        'content': f"Query: {query.text}\nSimilar past: {similar}"
    }])

    if 'needs_mcp' in response['message']['content'].lower():
        return await route_to_mcp_gateway(query)
    else:
        return {'source': 'triage_llm', 'response': response['message']['content']}
```

**Deliverables**:
- Ollama deployment with pulled model
- Triage API accessible at `http://mcp-triage.mcp-system.svc:8080`
- Ingress at `https://mcp.kernow.io` (Cloudflare Tunnel)

### Phase 3: MCP Servers - Cluster Resources (Week 3)

**Objective**: Deploy kmcp for Kubernetes and Talos access

**Tasks**:
1. Create ServiceAccounts with RBAC
2. Deploy kmcp for prod Kubernetes
3. Deploy kmcp for monitoring Kubernetes
4. Deploy Talos MCP (if HTTP-compatible exists, else custom)
5. Test via MCP Gateway

**MCP Servers**:
- `kubernetes-prod-mcp` → 10.10.0.40:6443
- `kubernetes-monitoring-mcp` → 10.30.0.20:6443
- `talos-prod-mcp` → Talos API (10.10.0.4x)
- `talos-monitoring-mcp` → Talos API (10.30.0.20)

**Testing**:
```bash
# Via MCP Gateway
curl -X POST http://10.30.0.91:8080/api/v1/mcp/kubernetes-prod-mcp/tools/list_pods \
  -H "Content-Type: application/json" \
  -d '{"namespace": "default"}'
```

**Deliverables**:
- 4 MCP servers running (2x Kubernetes, 2x Talos)
- Registered in vector DB mcp_servers table
- Health checks passing

### Phase 4: MCP Servers - External Services (Week 4)

**Objective**: Deploy ToolHive-based MCPs for external infrastructure

**Tasks**:
1. Build ToolHive sidecar images
2. Deploy Proxmox MCPs (Ruapehu + Carrick)
3. Deploy OPNsense MCP
4. Deploy UniFi MCP
5. Deploy AdGuard MCP
6. Deploy Caddy MCP (if applicable)

**ToolHive Pattern**:
Each deployment has:
- Main container: stdio MCP server (npm package)
- Sidecar: ToolHive HTTP proxy
- Service: Exposes port 8080 (ToolHive proxy)

**Deliverables**:
- 6 external service MCPs running
- All services responding to HTTP MCP requests
- Gateway routing working

### Phase 5: Discovery & Automation (Week 5)

**Objective**: Implement auto-discovery and PR automation

**Tasks**:
1. Deploy discovery service
2. Annotate existing services with MCP metadata
3. Test auto-registration
4. Deploy PR automation service
5. Test PR generation workflow
6. Configure GitHub Actions for PR validation

**Service Annotations**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    mcp.shreck.io/enabled: "true"
    mcp.shreck.io/type: "standard"
    mcp.shreck.io/capabilities: "dashboards,alerts,datasources"
    mcp.shreck.io/port: "3000"
```

**PR Workflow**:
1. Discovery service finds annotated service
2. Generates MCP manifest from template
3. Creates GitHub PR via API
4. GitHub Actions runs validation (terraform plan, yaml lint)
5. Human reviews and merges
6. ArgoCD syncs new MCP server

**Deliverables**:
- Discovery service running on 30s poll cycle
- At least 1 auto-generated PR created successfully
- Documentation for adding MCP annotations

### Phase 6: Multi-Model Integration (Week 6)

**Objective**: Connect Gemini and Claude for advanced queries

**Tasks**:
1. Store API keys in Infisical
2. Deploy multi-model router service
3. Integrate with triage layer
4. Implement model selection logic
5. Add response caching
6. Setup cost tracking (API usage)

**API Key Management**:
```yaml
# Infisical: /mcp-system/ai-models
ANTHROPIC_API_KEY: sk-ant-api03-...
GOOGLE_API_KEY: AIzaSy...
OPENAI_API_KEY: sk-proj-...  # For embeddings
```

**Model Selection Logic**:
```python
def select_model(query_type: str, context_size: int) -> str:
    """Choose optimal model based on task"""

    # Gemini 2.0 Flash: Fast, cheap, 1M token context
    if context_size > 100_000 or query_type == 'summarization':
        return 'gemini-2.0-flash'

    # Claude Sonnet 4.5: Best reasoning, code generation
    if query_type in ['reasoning', 'code', 'analysis']:
        return 'claude-sonnet-4.5'

    # Claude Haiku: Fast, cheap for simple tasks
    if query_type == 'classification':
        return 'claude-haiku-3.5'

    # Default
    return 'gemini-2.0-flash'
```

**Deliverables**:
- Multi-model router deployed
- All 3 APIs tested and working
- Cost dashboard in Grafana
- Response time comparison metrics

## Infrastructure as Code Structure

```
monit_homelab/
├── terraform/
│   └── talos-single-node/
│       ├── mcp-system.tf              # Namespace, PostgreSQL
│       ├── mcp-secrets.tf             # Infisical configs
│       ├── mcp-loadbalancer.tf        # Cilium IP pool
│       └── values/
│           └── postgresql-vector.yaml
│
├── kubernetes/
│   ├── platform/
│   │   └── mcp-servers/
│   │       ├── namespace.yaml
│   │       ├── mcp-gateway/
│   │       │   ├── deployment.yaml
│   │       │   ├── service.yaml
│   │       │   └── infisical-secret.yaml
│   │       ├── ollama-triage/
│   │       │   ├── deployment.yaml
│   │       │   ├── service.yaml
│   │       │   ├── ingress.yaml
│   │       │   └── pvc.yaml
│   │       ├── postgres-vector-db/
│   │       │   ├── statefulset.yaml
│   │       │   ├── service.yaml
│   │       │   ├── pvc.yaml
│   │       │   └── init-schema.yaml
│   │       ├── discovery-service/
│   │       ├── pr-automation/
│   │       ├── multi-model-router/
│   │       ├── kubernetes-prod-mcp/
│   │       ├── kubernetes-monitoring-mcp/
│   │       ├── proxmox-ruapehu-mcp/
│   │       ├── proxmox-carrick-mcp/
│   │       ├── opnsense-mcp/
│   │       ├── unifi-mcp/
│   │       ├── adguard-mcp/
│   │       └── caddy-mcp/
│   │
│   └── argocd-apps/
│       └── platform/
│           └── mcp-servers-appset.yaml
│
├── docker/
│   └── mcp-services/
│       ├── mcp-gateway/
│       │   ├── Dockerfile
│       │   └── src/
│       ├── ollama-triage/
│       ├── discovery-service/
│       ├── pr-automation/
│       └── multi-model-router/
│
├── .github/
│   └── workflows/
│       ├── build-mcp-services.yaml
│       ├── validate-pr.yaml
│       └── deploy-to-talos.yaml
│
└── docs/
    ├── MCP-ARCHITECTURE.md
    ├── MCP-API.md
    ├── ADDING-MCP-SERVERS.md
    └── TROUBLESHOOTING-MCP.md
```

## Resource Requirements

### Talos Cluster Capacity

**Minimum Requirements**:
- **CPU**: 16 cores (8 for LLM, 4 for MCP servers, 4 for platform)
- **Memory**: 80GB (64GB for LLM, 8GB for PostgreSQL, 8GB for MCP servers)
- **Storage**: 200GB (100GB for PostgreSQL, 50GB for Ollama models, 50GB for logs)

**Recommended for Production**:
- **CPU**: 32 cores
- **Memory**: 128GB
- **Storage**: 500GB NVMe

### Per-Component Allocations

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| Ollama (70B) | 4000m | 8000m | 32Gi | 64Gi | 50Gi (models) |
| PostgreSQL | 2000m | 4000m | 4Gi | 8Gi | 100Gi (data) |
| MCP Gateway | 500m | 1000m | 512Mi | 1Gi | - |
| Triage API | 1000m | 2000m | 1Gi | 2Gi | - |
| Discovery | 200m | 500m | 256Mi | 512Mi | - |
| PR Automation | 200m | 500m | 256Mi | 512Mi | - |
| Multi-Model Router | 500m | 1000m | 512Mi | 1Gi | - |
| kmcp (each) | 100m | 500m | 128Mi | 256Mi | - |
| ToolHive MCP (each) | 100m | 500m | 128Mi | 256Mi | - |

**Total**: ~9000m CPU, ~42Gi RAM (without LLM 70B), ~94Gi RAM (with LLM 70B)

## Security Considerations

### 1. Secret Management
- All secrets stored in Infisical, synced via Infisical Operator
- Separate Infisical paths per component:
  - `/mcp-system/postgres` - Database credentials
  - `/mcp-system/ai-models` - API keys (Anthropic, Google, OpenAI)
  - `/infrastructure/proxmox` - Proxmox API tokens
  - `/infrastructure/opnsense` - OPNsense API credentials
  - etc.
- Kubernetes secrets type: `Opaque`, managed by operator
- No hardcoded credentials in git

### 2. Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mcp-servers-ingress
  namespace: mcp-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: mcp-server
  policyTypes:
  - Ingress
  ingress:
  # Only allow from MCP Gateway
  - from:
    - podSelector:
        matchLabels:
          app: mcp-gateway
    ports:
    - port: 8080
```

### 3. RBAC
- MCP servers get minimal RBAC (read-only by default)
- ServiceAccounts per MCP server
- No cluster-admin permissions
- Audit logging enabled for all MCP API calls

### 4. API Authentication
- MCP Gateway requires Bearer token
- Tokens stored in vector DB with expiration
- Rate limiting per client (100 req/min)
- IP allowlist for external access

### 5. Egress Control
- External MCP servers (Proxmox, OPNsense) only reach specific IPs
- AI model APIs allowed via egress NetworkPolicy
- No unrestricted internet access

## Monitoring & Observability

### Metrics (Prometheus)

**MCP-specific metrics**:
```promql
# Request rate by MCP server
rate(mcp_requests_total[5m])

# P95 latency
histogram_quantile(0.95, mcp_request_duration_seconds_bucket)

# Error rate
rate(mcp_requests_errors_total[5m]) / rate(mcp_requests_total[5m])

# LLM token usage (cost tracking)
sum(rate(llm_tokens_total[1h])) by (model)

# Vector DB query latency
histogram_quantile(0.99, pgvector_query_duration_seconds_bucket)
```

**Grafana Dashboard**: `MCP Infrastructure Overview`
- Active MCP servers health map
- Request rate and latency graphs
- LLM usage and cost projection
- Database performance metrics
- PR automation success rate

### Logging (Victoria Logs)

**Log aggregation**:
- All MCP servers send structured JSON logs
- Triage layer logs query routing decisions
- Gateway logs all requests (sampling: 10%)
- Discovery service logs new registrations

**Example query**:
```logql
{namespace="mcp-system"} | json | model="claude-sonnet-4.5" | cost > 0.01
```

### Alerting (Prometheus Alertmanager)

**Critical alerts**:
```yaml
- alert: MCPServerDown
  expr: up{job="mcp-servers"} == 0
  for: 5m
  severity: critical

- alert: LLMHighLatency
  expr: histogram_quantile(0.95, rate(ollama_request_duration_seconds_bucket[5m])) > 30
  for: 10m
  severity: warning

- alert: VectorDBDiskFull
  expr: kubelet_volume_stats_available_bytes{persistentvolumeclaim="postgres-vector-db-data"} / kubelet_volume_stats_capacity_bytes < 0.1
  for: 5m
  severity: critical

- alert: HighAICost
  expr: sum(increase(llm_tokens_total[1d])) * 0.000001 > 10  # $10/day threshold
  for: 1h
  severity: warning
```

## Testing Strategy

### Unit Tests
- Python services: `pytest` with `pytest-asyncio`
- Go services: `go test` with table-driven tests
- Coverage target: 80%

### Integration Tests
```bash
# Test MCP Gateway routing
curl -X POST http://mcp-gateway:8080/api/v1/query \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"server": "kubernetes-prod-mcp", "tool": "list_pods", "args": {"namespace": "default"}}'

# Test LLM triage
curl -X POST http://mcp-triage:8080/api/v1/query \
  -d '{"text": "Show me pods in namespace monitoring"}'

# Test discovery
kubectl annotate svc/test-service mcp.shreck.io/enabled=true -n default
# Wait 30s, check mcp_servers table

# Test PR automation
curl -X POST http://pr-automation:8080/api/v1/create-pr \
  -d '{"server_name": "test-mcp", "type": "standard", "endpoint": "http://test:8080"}'
```

### Load Tests
- Apache Bench: `ab -n 1000 -c 10 http://mcp-gateway:8080/health`
- k6 for complex scenarios
- Target: 100 req/s sustained, p95 < 500ms

### Chaos Engineering
- Kill random MCP server pods (test gateway failover)
- Inject network latency to external services
- Simulate PostgreSQL outage (test retry logic)

## Cost Analysis

### Infrastructure Costs
- **Talos cluster**: Bare metal (no cloud costs)
- **Electricity**: ~$50/month (estimated for additional compute)

### API Costs (Monthly Estimates)

**Gemini 2.0 Flash** (primary model):
- Input: $0.075 / 1M tokens
- Output: $0.30 / 1M tokens
- Est. 10M tokens/month = $3.75

**Claude Sonnet 4.5** (reasoning tasks):
- Input: $3.00 / 1M tokens
- Output: $15.00 / 1M tokens
- Est. 2M tokens/month = $36.00

**OpenAI Embeddings** (vector search):
- text-embedding-3-small: $0.02 / 1M tokens
- Est. 5M tokens/month = $0.10

**Total AI API costs**: ~$40/month

**Cost Optimization**:
- Cache frequent queries in vector DB
- Use local Ollama for simple queries (free)
- Implement response streaming to reduce perceived latency
- Monitor per-user usage, set quotas

## Migration from Current State

### Current State
- Monitoring cluster: Talos single-node, 12GB RAM, 4 vCPU
- Running: Victoria Metrics, Logs, Grafana, Prometheus, Beszel, Gatus
- No MCP infrastructure (recently removed)

### Migration Steps

**Option A: Deploy to Monitoring Cluster** (if resources sufficient)
1. Increase monitoring cluster to 32GB RAM, 8 vCPU via Terraform
2. Follow deployment phases 1-6
3. MCP servers run alongside existing monitoring

**Option B: New Dedicated Cluster** (recommended)
1. Provision new Talos cluster (32GB RAM, 16 vCPU) on separate Proxmox host
2. Deploy only MCP infrastructure
3. Keep monitoring cluster as-is
4. Use kmcp to manage both clusters from MCP cluster

**Option C: Hybrid** (balance resources)
1. Deploy PostgreSQL + LLM to monitoring cluster (increase to 24GB RAM)
2. Deploy lightweight MCP servers (kmcp, discovery, gateway)
3. Use ToolHive for external services (minimal resource impact)

### Recommended: Option A
- Simpler management (one cluster)
- Monitoring cluster already has Infisical, ArgoCD, Traefik configured
- Terraform already manages this cluster
- Can share PostgreSQL between monitoring metrics and MCP context

**Resource Check**:
- Current usage: ~3.5GB RAM, ~2000m CPU
- MCP addition: ~42Gi RAM (with 70B LLM) or ~10Gi (with 8B LLM)
- Total needed: 48Gi RAM or 16Gi RAM

**Recommendation**: Use Llama 3.1 8B for triage (only 8GB RAM), increase cluster to 16GB total.

## Success Metrics

### Technical Metrics
- **Availability**: 99.5% uptime for MCP Gateway
- **Latency**: p95 < 500ms for MCP tool calls, p95 < 5s for LLM queries
- **Error Rate**: < 1% of requests
- **Discovery**: 100% of annotated services auto-registered within 60s
- **PR Automation**: 95% of auto-generated PRs pass validation

### Business Metrics
- **Time to add new MCP**: < 5 minutes (with auto-discovery)
- **Query success rate**: > 95% (user satisfaction)
- **Cost per query**: < $0.01 (mostly local LLM)
- **Developer productivity**: 50% reduction in manual infrastructure queries

## Troubleshooting Guide

### MCP Server Not Responding
```bash
# Check pod status
kubectl get pods -n mcp-system -l app=kubernetes-prod-mcp

# Check logs
kubectl logs -n mcp-system -l app=kubernetes-prod-mcp --tail=100

# Test directly (bypass gateway)
kubectl port-forward -n mcp-system svc/kubernetes-prod-mcp 8080:8080
curl http://localhost:8080/health

# Check registration in DB
kubectl exec -n mcp-system postgres-vector-db-0 -- psql -U mcp_user -d mcp_context -c "SELECT * FROM mcp_servers WHERE name='kubernetes-prod-mcp';"
```

### LLM Triage Not Routing Correctly
```bash
# Check Ollama model loaded
kubectl exec -n mcp-system ollama-triage-0 -- ollama list

# Test embedding generation
curl -X POST http://mcp-triage:8080/api/v1/embed -d '{"text": "test query"}'

# Check vector DB connectivity
kubectl logs -n mcp-system -l app=ollama-triage | grep -i postgres
```

### PostgreSQL Vector Search Slow
```sql
-- Check index usage
EXPLAIN ANALYZE SELECT * FROM query_history ORDER BY query_embedding <-> '[...]' LIMIT 10;

-- Rebuild index if needed
REINDEX INDEX query_history_query_embedding_idx;

-- Check table bloat
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE tablename='query_history';

-- Vacuum
VACUUM ANALYZE query_history;
```

### PR Automation Not Creating PRs
```bash
# Check GitHub token
kubectl get secret -n mcp-system github-token -o jsonpath='{.data.token}' | base64 -d

# Check service logs
kubectl logs -n mcp-system -l app=pr-automation

# Test GitHub API access
kubectl exec -n mcp-system -it pr-automation-xxxxx -- curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
```

## Future Enhancements

### Short-term (3 months)
- [ ] Add support for more MCP types (databases, cloud providers)
- [ ] Implement query caching layer (Redis)
- [ ] Add web UI for MCP management
- [ ] Create MCP server SDK for easy custom server development
- [ ] Add support for streaming responses (SSE)

### Medium-term (6 months)
- [ ] Multi-cluster MCP federation (share MCP across homelab clusters)
- [ ] Fine-tune local LLM on homelab-specific queries
- [ ] Implement RAG (Retrieval Augmented Generation) with vector DB
- [ ] Add voice interface (Whisper → Triage → TTS)
- [ ] Build MCP server marketplace (community contributions)

### Long-term (12 months)
- [ ] Agent orchestration (multi-MCP workflows)
- [ ] Predictive maintenance using historical query data
- [ ] Self-healing infrastructure (MCP detects issues, auto-creates PRs for fixes)
- [ ] Integration with Home Assistant (smart home MCPs)
- [ ] Mobile app for MCP access

## Conclusion

This plan provides a comprehensive, production-ready MCP infrastructure deployment using IaC, GitOps, and AI-first principles. The phased approach allows for incremental validation and adjustment, while the modular architecture ensures each component can be independently scaled or replaced.

**Key Success Factors**:
1. **Start small**: Deploy Phase 1-2 first, validate before expanding
2. **Monitor costs**: AI API usage can grow quickly, set alerts
3. **Document everything**: MCP servers will be discovered automatically, but manual documentation helps onboarding
4. **Iterate**: Expect to tune LLM prompts, model selection logic, and resource allocations over first month

**Next Steps**:
1. Review this plan with stakeholders
2. Provision additional resources if needed (increase Talos cluster RAM)
3. Begin Phase 1 implementation (PostgreSQL + namespace setup)
4. Set up monitoring dashboards before deploying LLM (baseline metrics)

---

**Document Version**: 1.0
**Date**: 2025-12-21
**Author**: AI Infrastructure Team
**Repository**: `https://github.com/charlieshreck/monit_homelab`
