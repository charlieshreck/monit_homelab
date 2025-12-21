# MCP Architecture - Refined with Hybrid AI Stack

## Executive Summary

This document refines the MCP implementation plan (`MCP-IMPLEMENTATION-PLAN.md`) with the specific tool selections from the hybrid AI architecture reference. Key changes include:

- **Local LLM**: Qwen 2.5 3B / Llama 3.2 3B (not Llama 3.1 70B)
- **Vector DB**: Qdrant (not PostgreSQL + pgvector)
- **Orchestration**: LangGraph + Open WebUI (not custom FastAPI)
- **Hardware**: AMD APU with Vulkan/ROCm (not Nvidia CUDA)
- **Storage**: ZFS + MinIO S3 (integrated with existing TrueNAS)
- **Observability**: Langfuse for LLM tracing

## Revised Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Open WebUI (Port 3000)                          │
│  - Chat interface with pipeline filters                             │
│  - Multi-model support (local + cloud)                              │
│  - User authentication (WEBUI_AUTH=true)                            │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   LangGraph Orchestration Layer                      │
│  - Agent workflow definitions (MCP tool routing)                     │
│  - State persistence (PostgreSQL checkpointer)                       │
│  - Conditional routing based on query complexity                     │
└────────┬──────────────────────────────┬─────────────────────────────┘
         │                               │
         ▼                               ▼
┌──────────────────────┐      ┌─────────────────────────┐
│   Local Inference     │      │   LiteLLM Proxy         │
│   (Ollama)            │      │   (Cloud Escalation)    │
├──────────────────────┤      ├─────────────────────────┤
│ • Qwen 2.5 3B Q4_K_M │      │ • Claude Sonnet 4       │
│ • Llama 3.2 3B Q4_K_M│      │ • Claude Haiku          │
│ • nomic-embed-text   │      │ • Gemini 2.0 Flash      │
│ • BGE-reranker-v2-m3 │      │ • Gemini Flash Thinking │
└────────┬─────────────┘      └────────┬────────────────┘
         │                              │
         └──────────────┬───────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │      MCP Gateway Service          │
        │  - Service discovery (Redis)      │
        │  - Load balancing                 │
        │  - Health checks                  │
        │  - Metrics (Prometheus)           │
        └────────┬──────────────────────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ kmcp    │  │ToolHive │  │ Custom  │
│ MCPs    │  │ MCPs    │  │ MCPs    │
└─────────┘  └─────────┘  └─────────┘
    │            │            │
    └────────────┼────────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │   Qdrant Vector DB     │
    │  - Query embeddings    │
    │  - RAG retrieval       │
    │  - 768d nomic vectors  │
    └────────────────────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │ PostgreSQL + Redis     │
    │ - LangGraph state      │
    │ - Agent checkpoints    │
    │ - Cache + queue        │
    └────────────────────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │ MinIO S3 Storage       │
    │ - Model files          │
    │ - Qdrant snapshots     │
    │ - Backup storage       │
    └────────────────────────┘
```

## Component Specifications

### 1. Ollama with AMD APU Support

**Deployment Configuration**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama-inference
  namespace: mcp-system
spec:
  replicas: 1  # Single instance due to APU limitations
  template:
    spec:
      hostIPC: true  # Required for Vulkan
      containers:
      - name: ollama
        image: ollama/ollama:latest
        env:
        # AMD APU specific configuration
        - name: HSA_OVERRIDE_GFX_VERSION
          value: "10.3.0"
        - name: OLLAMA_FLASH_ATTENTION
          value: "1"
        - name: OLLAMA_KV_CACHE_TYPE
          value: "q8_0"
        - name: OLLAMA_KEEP_ALIVE
          value: "5m"
        - name: OLLAMA_NUM_PARALLEL
          value: "1"
        - name: OLLAMA_MAX_LOADED_MODELS
          value: "1"
        - name: GGML_VULKAN
          value: "1"
        ports:
        - containerPort: 11434
          name: api
        - containerPort: 11435
          name: metrics
        resources:
          requests:
            cpu: 2000m
            memory: 8Gi
          limits:
            cpu: 4000m
            memory: 12Gi
        volumeMounts:
        - name: models
          mountPath: /root/.ollama
        - name: dev-kfd
          mountPath: /dev/kfd
        - name: dev-dri
          mountPath: /dev/dri
      volumes:
      - name: models
        persistentVolumeClaim:
          claimName: ollama-models
      - name: dev-kfd
        hostPath:
          path: /dev/kfd
      - name: dev-dri
        hostPath:
          path: /dev/dri
      # Init container to pull models
      initContainers:
      - name: pull-models
        image: ollama/ollama:latest
        command:
        - /bin/sh
        - -c
        - |
          ollama pull qwen2.5:3b-instruct-q4_K_M
          ollama pull llama3.2:3b-instruct-q4_K_M
          ollama pull nomic-embed-text
          ollama pull bge-reranker-v2-m3
        volumeMounts:
        - name: models
          mountPath: /root/.ollama
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: mcp-system
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "11435"
spec:
  type: ClusterIP
  ports:
  - port: 11434
    name: api
  - port: 11435
    name: metrics
  selector:
    app: ollama-inference
```

**Talos Machine Extension**:
```yaml
# Add to Talos machine config
machine:
  kernel:
    modules:
      - name: amdgpu
  install:
    extensions:
      - image: ghcr.io/siderolabs/amdgpu:20250108
```

**Model Storage Requirements**:
- Qwen 2.5 3B Q4_K_M: ~2GB
- Llama 3.2 3B Q4_K_M: ~2GB
- nomic-embed-text: ~274MB
- BGE-reranker-v2-m3: ~1GB
- **Total**: ~5.3GB

### 2. Qdrant Vector Database

**Deployment**:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: qdrant
  namespace: mcp-system
spec:
  serviceName: qdrant
  replicas: 1
  template:
    spec:
      containers:
      - name: qdrant
        image: qdrant/qdrant:v1.12.0
        ports:
        - containerPort: 6333
          name: http
        - containerPort: 6334
          name: grpc
        env:
        - name: QDRANT__SERVICE__HTTP_PORT
          value: "6333"
        - name: QDRANT__SERVICE__GRPC_PORT
          value: "6334"
        - name: QDRANT__STORAGE__SNAPSHOTS_PATH
          value: "/qdrant/snapshots"
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        volumeMounts:
        - name: qdrant-data
          mountPath: /qdrant/storage
        - name: qdrant-snapshots
          mountPath: /qdrant/snapshots
      # Sidecar for snapshot backups to MinIO
      - name: snapshot-backup
        image: minio/mc:latest
        command:
        - /bin/sh
        - -c
        - |
          mc alias set minio http://minio:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
          while true; do
            sleep 21600  # 6 hours
            curl -X POST http://localhost:6333/collections/mcp_queries/snapshots
            mc mirror /qdrant/snapshots minio/qdrant-backups/$(date +%Y%m%d)
          done
        env:
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        volumeMounts:
        - name: qdrant-snapshots
          mountPath: /qdrant/snapshots
  volumeClaimTemplates:
  - metadata:
      name: qdrant-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 50Gi
  - metadata:
      name: qdrant-snapshots
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: qdrant
  namespace: mcp-system
spec:
  ports:
  - port: 6333
    name: http
  - port: 6334
    name: grpc
  clusterIP: None
  selector:
    app: qdrant
```

**Collection Schema**:
```python
# Initialize Qdrant collections
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams

client = QdrantClient(host="qdrant", port=6333)

# MCP query embeddings
client.create_collection(
    collection_name="mcp_queries",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE),
    optimizers_config={
        "indexing_threshold": 10000,
    },
    hnsw_config={
        "m": 16,
        "ef_construct": 100,
    }
)

# Application context embeddings
client.create_collection(
    collection_name="app_contexts",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE),
)

# MCP server documentation
client.create_collection(
    collection_name="mcp_docs",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE),
)
```

### 3. LangGraph Orchestration

**Architecture**:
```python
# langgraph_mcp/graph.py
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres import PostgresSaver
from typing import TypedDict, Annotated
import operator

class MCPState(TypedDict):
    query: str
    query_embedding: list[float]
    intent: str  # "simple", "mcp_tool", "complex_reasoning"
    mcp_server: str
    mcp_tool: str
    mcp_args: dict
    response: str
    model_used: str
    escalated: bool
    error: str | None

def classify_intent(state: MCPState) -> MCPState:
    """Use Qwen 2.5 3B to classify query intent"""
    response = ollama.chat(
        model="qwen2.5:3b-instruct-q4_K_M",
        messages=[{
            "role": "system",
            "content": """Classify query intent:
- simple: Direct Q&A, no tools needed
- mcp_tool: Requires infrastructure/service interaction
- complex_reasoning: Multi-step analysis, escalate to cloud

Output JSON: {"intent": "...", "reasoning": "..."}"""
        }, {
            "role": "user",
            "content": state["query"]
        }],
        format="json"
    )

    result = json.loads(response["message"]["content"])
    state["intent"] = result["intent"]
    return state

def retrieve_context(state: MCPState) -> MCPState:
    """RAG retrieval from Qdrant"""
    # Generate embedding
    embedding = ollama.embeddings(
        model="nomic-embed-text",
        prompt=state["query"]
    )
    state["query_embedding"] = embedding["embedding"]

    # Search similar queries
    results = qdrant_client.search(
        collection_name="mcp_queries",
        query_vector=state["query_embedding"],
        limit=5
    )

    # Rerank with BGE
    if results:
        reranked = ollama.embeddings(
            model="bge-reranker-v2-m3",
            prompt=state["query"],
            options={"rerank": [r.payload["text"] for r in results]}
        )
        # Use reranked results for context

    return state

def route_query(state: MCPState) -> str:
    """Conditional edge based on intent"""
    if state["intent"] == "simple":
        return "answer_locally"
    elif state["intent"] == "mcp_tool":
        return "select_mcp_server"
    else:
        return "escalate_to_cloud"

def answer_locally(state: MCPState) -> MCPState:
    """Use local Qwen for simple queries"""
    response = ollama.chat(
        model="qwen2.5:3b-instruct-q4_K_M",
        messages=[{"role": "user", "content": state["query"]}]
    )
    state["response"] = response["message"]["content"]
    state["model_used"] = "qwen2.5:3b"
    state["escalated"] = False
    return state

def select_mcp_server(state: MCPState) -> MCPState:
    """Use Qwen to select appropriate MCP server and tool"""
    # Get list of available MCP servers from Redis cache
    mcp_servers = redis_client.get("mcp:servers:list")

    response = ollama.chat(
        model="qwen2.5:3b-instruct-q4_K_M",
        messages=[{
            "role": "system",
            "content": f"""Select MCP server and tool from: {mcp_servers}
Output JSON: {{"server": "...", "tool": "...", "args": {{...}}}}"""
        }, {
            "role": "user",
            "content": state["query"]
        }],
        format="json"
    )

    result = json.loads(response["message"]["content"])
    state["mcp_server"] = result["server"]
    state["mcp_tool"] = result["tool"]
    state["mcp_args"] = result["args"]
    return state

def call_mcp_gateway(state: MCPState) -> MCPState:
    """Execute MCP tool via gateway"""
    try:
        response = requests.post(
            f"http://mcp-gateway:8080/api/v1/mcp/{state['mcp_server']}/tools/{state['mcp_tool']}",
            json=state["mcp_args"],
            timeout=30
        )
        response.raise_for_status()
        state["response"] = response.json()["result"]
        state["model_used"] = "mcp:" + state["mcp_server"]
    except Exception as e:
        state["error"] = str(e)
        state["response"] = f"MCP call failed: {e}"

    return state

def escalate_to_cloud(state: MCPState) -> MCPState:
    """Route to Claude/Gemini via LiteLLM"""
    # Use LiteLLM proxy for automatic fallback
    response = requests.post(
        "http://litellm:4000/chat/completions",
        headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}"},
        json={
            "model": "router",  # LiteLLM intelligent routing
            "messages": [{"role": "user", "content": state["query"]}],
            "metadata": {
                "routing_strategy": "cost-first",  # Gemini Flash first
                "fallback_models": ["claude-sonnet-4", "claude-haiku"]
            }
        }
    )

    result = response.json()
    state["response"] = result["choices"][0]["message"]["content"]
    state["model_used"] = result["model"]
    state["escalated"] = True
    return state

# Build the graph
workflow = StateGraph(MCPState)

# Add nodes
workflow.add_node("classify_intent", classify_intent)
workflow.add_node("retrieve_context", retrieve_context)
workflow.add_node("answer_locally", answer_locally)
workflow.add_node("select_mcp_server", select_mcp_server)
workflow.add_node("call_mcp_gateway", call_mcp_gateway)
workflow.add_node("escalate_to_cloud", escalate_to_cloud)

# Define edges
workflow.set_entry_point("classify_intent")
workflow.add_edge("classify_intent", "retrieve_context")
workflow.add_conditional_edges(
    "retrieve_context",
    route_query,
    {
        "answer_locally": "answer_locally",
        "select_mcp_server": "select_mcp_server",
        "escalate_to_cloud": "escalate_to_cloud"
    }
)
workflow.add_edge("answer_locally", END)
workflow.add_edge("select_mcp_server", "call_mcp_gateway")
workflow.add_edge("call_mcp_gateway", END)
workflow.add_edge("escalate_to_cloud", END)

# Compile with PostgreSQL checkpointer
checkpointer = PostgresSaver.from_conn_string("postgresql://mcp:password@postgres:5432/langgraph")
app = workflow.compile(checkpointer=checkpointer)
```

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: langgraph-mcp
  namespace: mcp-system
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: langgraph-api
        image: ghcr.io/charlieshreck/langgraph-mcp:v1.0.0
        ports:
        - containerPort: 8000
        env:
        - name: OLLAMA_HOST
          value: "http://ollama:11434"
        - name: QDRANT_HOST
          value: "http://qdrant:6333"
        - name: REDIS_URL
          value: "redis://redis:6379/0"
        - name: POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: postgres-langgraph
              key: url
        - name: MCP_GATEWAY_URL
          value: "http://mcp-gateway:8080"
        - name: LITELLM_URL
          value: "http://litellm:4000"
        - name: LITELLM_MASTER_KEY
          valueFrom:
            secretKeyRef:
              name: litellm-credentials
              key: master_key
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
```

### 4. Open WebUI Integration

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open-webui
  namespace: mcp-system
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: open-webui
        image: ghcr.io/open-webui/open-webui:main
        ports:
        - containerPort: 3000
        env:
        - name: OLLAMA_BASE_URL
          value: "http://ollama:11434"
        - name: OPENAI_API_BASE_URL
          value: "http://litellm:4000/v1"
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: litellm-credentials
              key: master_key
        - name: WEBUI_AUTH
          value: "true"
        - name: ENABLE_SIGNUP
          value: "false"
        - name: JWT_EXPIRES_IN
          value: "3600"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-webui
              key: url
        volumeMounts:
        - name: webui-data
          mountPath: /app/backend/data
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: webui-data
        persistentVolumeClaim:
          claimName: open-webui-data
---
apiVersion: v1
kind: Service
metadata:
  name: open-webui
  namespace: mcp-system
spec:
  type: LoadBalancer
  loadBalancerIP: 10.30.0.92  # From Cilium pool
  ports:
  - port: 3000
  selector:
    app: open-webui
```

**Pipeline Filter for MCP Integration**:
```python
# open-webui-pipelines/mcp_filter.py
from typing import List, Optional
from pydantic import BaseModel

class Pipeline:
    class Valves(BaseModel):
        LANGGRAPH_API_URL: str = "http://langgraph-mcp:8000"
        ENABLE_MCP_ROUTING: bool = True

    def __init__(self):
        self.valves = self.Valves()

    async def inlet(self, body: dict, user: Optional[dict] = None) -> dict:
        """Pre-process: Route through LangGraph if MCP keywords detected"""
        if not self.valves.ENABLE_MCP_ROUTING:
            return body

        query = body["messages"][-1]["content"]

        # Keywords that trigger MCP routing
        mcp_keywords = ["show", "list", "get", "status", "deploy", "logs", "pods", "nodes"]

        if any(keyword in query.lower() for keyword in mcp_keywords):
            # Route to LangGraph instead of direct Ollama
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.valves.LANGGRAPH_API_URL}/invoke",
                    json={"query": query},
                    timeout=60.0
                )

                if response.status_code == 200:
                    result = response.json()
                    # Replace message with LangGraph result
                    body["messages"][-1]["content"] = result["response"]
                    body["metadata"] = {
                        "model_used": result["model_used"],
                        "mcp_server": result.get("mcp_server"),
                        "escalated": result.get("escalated", False)
                    }

        return body

    async def outlet(self, body: dict, user: Optional[dict] = None) -> dict:
        """Post-process: Add metadata to response"""
        if "metadata" in body:
            # Append model info to response
            metadata = body["metadata"]
            body["messages"][-1]["content"] += f"\n\n*[Model: {metadata['model_used']}]*"

        return body
```

### 5. LiteLLM Proxy for Cloud Escalation

**Configuration**:
```yaml
# litellm-config.yaml
model_list:
  - model_name: router
    litellm_params:
      model: router
      router_settings:
        routing_strategy: cost-based-routing
        allowed_fails: 3
        cooldown_time: 30
        model_group_alias:
          fast: ["gemini-2.0-flash", "claude-haiku"]
          reasoning: ["claude-sonnet-4", "gemini-2.0-flash-thinking"]

  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash-001
      api_key: os.environ/GEMINI_API_KEY
      rpm: 60
      tpm: 1000000

  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY
      rpm: 50
      tpm: 200000

  - model_name: claude-haiku
    litellm_params:
      model: anthropic/claude-haiku-3-20241121
      api_key: os.environ/ANTHROPIC_API_KEY
      rpm: 100
      tpm: 500000

  - model_name: gemini-flash-thinking
    litellm_params:
      model: gemini/gemini-2.0-flash-thinking-exp-01-21
      api_key: os.environ/GEMINI_API_KEY
      rpm: 30
      tpm: 500000

litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    ttl: 3600
  num_retries: 3
  request_timeout: 60
  fallbacks:
    - ["gemini-2.0-flash", "claude-haiku"]
    - ["claude-sonnet-4", "gemini-flash-thinking"]

router_settings:
  enable_pre_call_checks: true
  model_group_retry_policy:
    fast:
      - "gemini-2.0-flash"
      - "claude-haiku"
    reasoning:
      - "claude-sonnet-4"
      - "gemini-flash-thinking"
```

**Deployment**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
  namespace: mcp-system
data:
  config.yaml: |
    # Full litellm-config.yaml content here
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm
  namespace: mcp-system
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: litellm
        image: ghcr.io/berriai/litellm:main-latest
        ports:
        - containerPort: 4000
        env:
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: ai-model-credentials
              key: ANTHROPIC_API_KEY
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: ai-model-credentials
              key: GOOGLE_API_KEY
        - name: LITELLM_MASTER_KEY
          valueFrom:
            secretKeyRef:
              name: litellm-credentials
              key: master_key
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-litellm
              key: url
        - name: LANGFUSE_PUBLIC_KEY
          valueFrom:
            secretKeyRef:
              name: langfuse-credentials
              key: public_key
        - name: LANGFUSE_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: langfuse-credentials
              key: secret_key
        - name: LANGFUSE_HOST
          value: "http://langfuse:3002"
        volumeMounts:
        - name: config
          mountPath: /app/config.yaml
          subPath: config.yaml
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      volumes:
      - name: config
        configMap:
          name: litellm-config
---
apiVersion: v1
kind: Service
metadata:
  name: litellm
  namespace: mcp-system
spec:
  ports:
  - port: 4000
  selector:
    app: litellm
```

### 6. Observability Stack

**Langfuse for LLM Tracing**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: langfuse
  namespace: mcp-system
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: langfuse
        image: langfuse/langfuse:latest
        ports:
        - containerPort: 3002
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-langfuse
              key: url
        - name: NEXTAUTH_URL
          value: "https://langfuse.kernow.io"
        - name: NEXTAUTH_SECRET
          valueFrom:
            secretKeyRef:
              name: langfuse-credentials
              key: nextauth_secret
        - name: SALT
          valueFrom:
            secretKeyRef:
              name: langfuse-credentials
              key: salt
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: langfuse
  namespace: mcp-system
spec:
  ports:
  - port: 3002
  selector:
    app: langfuse
```

**Prometheus Metrics for Ollama**:
```yaml
# Add ollama-exporter sidecar to Ollama deployment
- name: ollama-exporter
  image: ghcr.io/sammcj/ollama_exporter:latest
  ports:
  - containerPort: 9095
    name: metrics
  env:
  - name: OLLAMA_HOST
    value: "http://localhost:11434"
  - name: OLLAMA_EXPORT_INTERVAL
    value: "30s"
```

**Grafana Dashboard ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-llm
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  llm-dashboard.json: |
    {
      "dashboard": {
        "title": "MCP LLM Infrastructure",
        "panels": [
          {
            "title": "Query Routing Distribution",
            "targets": [
              {
                "expr": "sum by(intent) (rate(langgraph_intent_classification_total[5m]))"
              }
            ]
          },
          {
            "title": "Local vs Cloud Escalation",
            "targets": [
              {
                "expr": "sum(rate(langgraph_local_responses_total[5m]))",
                "legendFormat": "Local (Qwen/Llama)"
              },
              {
                "expr": "sum(rate(langgraph_cloud_escalations_total[5m]))",
                "legendFormat": "Cloud (Claude/Gemini)"
              }
            ]
          },
          {
            "title": "Ollama Inference Latency (p95)",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(ollama_request_duration_seconds_bucket[5m]))"
              }
            ]
          },
          {
            "title": "Token Usage by Model",
            "targets": [
              {
                "expr": "sum by(model) (rate(litellm_tokens_total[1h]))"
              }
            ]
          },
          {
            "title": "MCP Tool Calls by Server",
            "targets": [
              {
                "expr": "sum by(mcp_server) (rate(mcp_gateway_tool_calls_total[5m]))"
              }
            ]
          },
          {
            "title": "Qdrant Vector Search Latency",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(qdrant_search_duration_seconds_bucket[5m]))"
              }
            ]
          },
          {
            "title": "LiteLLM Cost (Last 24h)",
            "targets": [
              {
                "expr": "sum(increase(litellm_cost_usd_total[24h]))"
              }
            ]
          }
        ]
      }
    }
```

## Revised Resource Requirements

### With Lightweight Models (3B)

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage | VRAM |
|-----------|-------------|-----------|----------------|--------------|---------|------|
| Ollama (AMD APU) | 2000m | 4000m | 8Gi | 12Gi | 10Gi (models) | ~6GB |
| Qdrant | 500m | 2000m | 1Gi | 4Gi | 70Gi (data+snapshots) | - |
| PostgreSQL | 1000m | 2000m | 2Gi | 4Gi | 50Gi | - |
| Redis | 200m | 500m | 256Mi | 512Mi | 5Gi | - |
| LangGraph API | 500m | 1000m | 512Mi | 1Gi | - | - |
| Open WebUI | 200m | 500m | 256Mi | 512Mi | 5Gi | - |
| LiteLLM | 200m | 1000m | 256Mi | 1Gi | - | - |
| Langfuse | 200m | 500m | 256Mi | 512Mi | - | - |
| MCP Gateway | 500m | 1000m | 512Mi | 1Gi | - | - |
| kmcp (4x) | 400m | 2000m | 512Mi | 1Gi | - | - |
| ToolHive MCPs (6x) | 600m | 3000m | 768Mi | 1.5Gi | - | - |

**Total**: ~6200m CPU, ~14Gi RAM, ~140Gi storage, ~6GB VRAM

### Comparison to Original Plan

| Metric | Original Plan (70B) | Refined Plan (3B) | Savings |
|--------|---------------------|-------------------|---------|
| CPU | ~9000m | ~6200m | -31% |
| RAM | ~94Gi | ~14Gi | -85% |
| VRAM | ~64GB | ~6GB | -91% |
| Storage | ~200Gi | ~140Gi | -30% |

**Feasibility**: Can run on monitoring cluster with RAM upgrade from 12GB to 24GB (currently at 3.5GB usage).

## Deployment Phases - Refined

### Phase 1: Storage Foundation (Week 1)

**Objective**: Deploy Qdrant, PostgreSQL, Redis, MinIO

**Tasks**:
1. Create `mcp-system` namespace
2. Deploy Qdrant StatefulSet with snapshot backup
3. Deploy PostgreSQL (LangGraph checkpointer + LiteLLM database)
4. Deploy Redis (cache + queue)
5. Configure MinIO for S3 backups (use existing TrueNAS MinIO or deploy new)
6. Initialize Qdrant collections
7. Test backup/restore workflows

**Terraform**:
```hcl
# terraform/talos-single-node/mcp-storage.tf
resource "kubernetes_namespace" "mcp_system" {
  metadata {
    name = "mcp-system"
  }
}

resource "helm_release" "qdrant" {
  name       = "qdrant"
  repository = "https://qdrant.github.io/qdrant-helm"
  chart      = "qdrant"
  version    = "0.8.0"
  namespace  = kubernetes_namespace.mcp_system.metadata[0].name

  values = [file("${path.module}/values/qdrant.yaml")]
}

resource "helm_release" "postgresql" {
  name       = "postgres-mcp"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "13.2.24"
  namespace  = kubernetes_namespace.mcp_system.metadata[0].name

  values = [file("${path.module}/values/postgresql-mcp.yaml")]
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = "18.4.0"
  namespace  = kubernetes_namespace.mcp_system.metadata[0].name

  set {
    name  = "master.persistence.enabled"
    value = "true"
  }

  set {
    name  = "master.persistence.size"
    value = "5Gi"
  }
}
```

**Deliverables**:
- All storage services healthy
- Backup jobs configured
- Database schemas initialized

### Phase 2: Local LLM Infrastructure (Week 2)

**Objective**: Deploy Ollama with AMD APU support and lightweight models

**Tasks**:
1. Add amdgpu extension to Talos machine config
2. Apply Talos config update
3. Deploy Ollama with Vulkan/ROCm configuration
4. Pull models: Qwen 2.5 3B, Llama 3.2 3B, nomic-embed-text, BGE-reranker
5. Deploy ollama-exporter for metrics
6. Test inference with all models
7. Benchmark performance (tokens/sec, VRAM usage)

**Talos Update**:
```bash
# Update talos machine config
talhelper gensecret > talsecret.yaml
talhelper genconfig

# Apply amdgpu extension
talosctl apply-config -n 10.30.0.20 -f clusterconfig/mcp-talos.yaml
talosctl upgrade -n 10.30.0.20 --image=ghcr.io/siderolabs/installer:v1.12.0

# Verify GPU available
talosctl -n 10.30.0.20 dmesg | grep -i amdgpu
```

**Performance Validation**:
```bash
# Test Qwen 2.5 3B inference
curl http://ollama:11434/api/generate -d '{
  "model": "qwen2.5:3b-instruct-q4_K_M",
  "prompt": "Explain Kubernetes in one sentence.",
  "stream": false
}'

# Check VRAM usage
kubectl exec -n mcp-system ollama-xxxxx -- rocm-smi

# Benchmark
kubectl exec -n mcp-system ollama-xxxxx -- ollama run qwen2.5:3b-instruct-q4_K_M --verbose "Test query"
# Target: >20 tokens/sec on AMD APU
```

**Deliverables**:
- Ollama running with GPU acceleration
- All 4 models loaded and tested
- Prometheus metrics available

### Phase 3: LangGraph Orchestration (Week 3)

**Objective**: Deploy LangGraph with MCP routing logic

**Tasks**:
1. Build LangGraph Docker image with graph definition
2. Deploy LangGraph API service
3. Configure PostgreSQL checkpointer
4. Test intent classification with Qwen 2.5 3B
5. Implement RAG retrieval from Qdrant
6. Test end-to-end workflow (query → classification → retrieval → response)
7. Add Prometheus metrics

**Docker Build**:
```bash
# docker/langgraph-mcp/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy graph definition
COPY graph.py .
COPY api.py .

# Expose API
EXPOSE 8000

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Testing**:
```bash
# Test intent classification
curl -X POST http://langgraph-mcp:8000/invoke -d '{
  "query": "Show me pods in namespace monitoring"
}'

# Expected output:
{
  "intent": "mcp_tool",
  "mcp_server": "kubernetes-monitoring-mcp",
  "mcp_tool": "list_pods",
  "mcp_args": {"namespace": "monitoring"}
}
```

**Deliverables**:
- LangGraph API deployed
- All graph nodes tested
- State persistence working

### Phase 4: MCP Gateway & Servers (Week 4)

**Objective**: Deploy MCP Gateway and all MCP servers (kmcp + ToolHive)

**Tasks**:
1. Deploy MCP Gateway service
2. Deploy kmcp for Kubernetes (prod + monitoring)
3. Deploy kmcp for Talos (if available, else custom)
4. Deploy ToolHive-based MCPs (Proxmox, OPNsense, UniFi, AdGuard, Caddy)
5. Register all servers in Redis cache
6. Configure health checks
7. Test via LangGraph

**MCP Gateway with Service Discovery**:
```python
# mcp-gateway/discovery.py
import redis
import asyncio
from kubernetes import client, config

redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

async def discover_mcp_servers():
    """Scan Kubernetes services for MCP servers and cache in Redis"""
    config.load_incluster_config()
    v1 = client.CoreV1Api()

    mcp_servers = []

    for svc in v1.list_namespaced_service("mcp-system").items:
        if svc.metadata.labels.get("app.kubernetes.io/component") == "mcp-server":
            server_info = {
                "name": svc.metadata.name,
                "endpoint": f"http://{svc.metadata.name}.{svc.metadata.namespace}.svc:8080",
                "type": svc.metadata.annotations.get("mcp.shreck.io/type", "standard"),
                "capabilities": svc.metadata.annotations.get("mcp.shreck.io/capabilities", "").split(","),
                "health": await check_health(f"http://{svc.metadata.name}:8080/health")
            }
            mcp_servers.append(server_info)

    # Cache in Redis with 60s TTL
    redis_client.setex(
        "mcp:servers:list",
        60,
        json.dumps(mcp_servers)
    )

    return mcp_servers

# Run discovery every 30s
asyncio.create_task(periodic_discovery())
```

**Deliverables**:
- MCP Gateway running
- 10 MCP servers deployed (4 kmcp, 6 ToolHive)
- All servers healthy and registered

### Phase 5: Cloud Integration & UI (Week 5)

**Objective**: Deploy LiteLLM, Open WebUI, and Langfuse

**Tasks**:
1. Deploy LiteLLM proxy with router configuration
2. Store API keys in Infisical
3. Deploy Langfuse for tracing
4. Deploy Open WebUI with MCP pipeline filter
5. Configure ingress (Traefik + Cloudflare Tunnel)
6. Test cloud escalation workflow
7. Test full UI experience

**Ingress Configuration**:
```yaml
# Traefik (internal)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: open-webui-internal
  namespace: mcp-system
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`mcp.kernow.io`)
    kind: Rule
    services:
    - name: open-webui
      port: 3000
  tls:
    certResolver: letsencrypt

---
# Cloudflare Tunnel (external)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: open-webui-external
  namespace: mcp-system
  annotations:
    kubernetes.io/ingress.class: cloudflare-tunnel
spec:
  rules:
  - host: mcp.kernow.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: open-webui
            port:
              number: 3000
```

**User Acceptance Testing**:
```bash
# Access Open WebUI
https://mcp.kernow.io

# Test queries:
1. "What's the weather?" → Should use local Qwen 2.5 3B
2. "List pods in monitoring namespace" → Should route to kubernetes-monitoring-mcp
3. "Explain the benefits of microservices architecture" → Should escalate to Claude Sonnet
4. "Show Proxmox VMs on Ruapehu" → Should route to proxmox-ruapehu-mcp

# Check Langfuse traces
https://langfuse.kernow.io → View execution traces
```

**Deliverables**:
- Open WebUI accessible internally and externally
- Cloud escalation working
- Langfuse tracing all requests
- End-user documentation

### Phase 6: Automation & Monitoring (Week 6)

**Objective**: Deploy discovery service, PR automation, and monitoring dashboards

**Tasks**:
1. Deploy discovery service (annotation-based registration)
2. Deploy PR automation service
3. Test auto-registration workflow
4. Test auto-PR generation
5. Deploy Grafana dashboard for LLM metrics
6. Configure alerting rules
7. Document operational procedures

**Grafana Alerts**:
```yaml
# prometheus-rules/llm-alerts.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-llm-alerts
  namespace: monitoring
data:
  llm-alerts.yaml: |
    groups:
    - name: llm-infrastructure
      interval: 30s
      rules:
      - alert: OllamaDown
        expr: up{job="ollama"} == 0
        for: 2m
        severity: critical
        annotations:
          summary: "Ollama inference service is down"

      - alert: HighCloudCost
        expr: sum(increase(litellm_cost_usd_total[24h])) > 10
        for: 1h
        severity: warning
        annotations:
          summary: "Cloud API cost exceeded $10 in 24h"

      - alert: LowLocalResponseRate
        expr: sum(rate(langgraph_local_responses_total[5m])) / sum(rate(langgraph_total_queries[5m])) < 0.5
        for: 10m
        severity: warning
        annotations:
          summary: "Less than 50% of queries handled locally (check Ollama performance)"

      - alert: QdrantHighLatency
        expr: histogram_quantile(0.95, rate(qdrant_search_duration_seconds_bucket[5m])) > 1
        for: 5m
        severity: warning
        annotations:
          summary: "Qdrant vector search p95 latency > 1s"
```

**Operational Documentation**:
```markdown
# docs/MCP-OPERATIONS.md

## Daily Operations

### Check System Health
```bash
kubectl get pods -n mcp-system
kubectl get applications -n argocd | grep mcp
```

### View LLM Metrics
- Grafana: https://grafana.kernow.io/d/mcp-llm/
- Langfuse: https://langfuse.kernow.io
- Open WebUI Admin: https://mcp.kernow.io/admin

### Cost Monitoring
```bash
# Query Prometheus for 24h cost
curl -s 'http://prometheus:9090/api/v1/query?query=sum(increase(litellm_cost_usd_total[24h]))' | jq .data.result[0].value[1]
```

### Backup Verification
```bash
# Check Qdrant snapshots
kubectl exec -n mcp-system qdrant-0 -- ls -lh /qdrant/snapshots

# Verify MinIO backups
mc ls minio/qdrant-backups/
```

## Troubleshooting

### Ollama Not Using GPU
```bash
# Check GPU available
kubectl exec -n mcp-system ollama-xxxxx -- rocm-smi

# Verify Vulkan
kubectl exec -n mcp-system ollama-xxxxx -- vulkaninfo

# Check environment variables
kubectl exec -n mcp-system ollama-xxxxx -- env | grep -E "GGML|HSA|OLLAMA"
```

### Slow Inference
```bash
# Check model loaded
curl http://ollama:11434/api/tags

# Monitor GPU utilization during inference
kubectl exec -n mcp-system ollama-xxxxx -- rocm-smi -d

# Check KV cache type (should be q8_0)
kubectl logs -n mcp-system ollama-xxxxx | grep -i cache
```

### Cloud Escalation Failing
```bash
# Check LiteLLM logs
kubectl logs -n mcp-system -l app=litellm --tail=100

# Test API keys
kubectl exec -n mcp-system litellm-xxxxx -- curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model": "claude-haiku-3-20241121", "max_tokens": 10, "messages": [{"role": "user", "content": "Hi"}]}'
```
```

**Deliverables**:
- Full monitoring stack operational
- Auto-discovery working
- PR automation tested
- Operational runbook complete

## Cost Analysis - Revised

### Infrastructure Costs
- **Bare metal**: $0 (existing hardware)
- **Electricity**: ~$20/month additional (lightweight models)

### API Costs (Monthly Estimates)

**Scenario 1: 90% Local, 10% Cloud**
- Gemini Flash: 1M tokens/month = $0.375
- Claude Sonnet: 200K tokens/month = $3.60
- **Total**: ~$4/month

**Scenario 2: 70% Local, 30% Cloud**
- Gemini Flash: 5M tokens/month = $1.875
- Claude Sonnet: 1M tokens/month = $18.00
- Gemini Flash Thinking: 500K tokens/month = $6.25
- **Total**: ~$26/month

**Scenario 3: 50% Local, 50% Cloud (heavy usage)**
- Gemini Flash: 10M tokens/month = $3.75
- Claude Sonnet: 3M tokens/month = $54.00
- Gemini Flash Thinking: 1M tokens/month = $12.50
- **Total**: ~$70/month

**Comparison to Original Plan**:
- Original (mostly cloud): ~$40/month base
- Refined (mostly local): ~$4-26/month typical
- **Savings**: 35-90% depending on usage pattern

## Integration with Existing Infrastructure

### TrueNAS Integration
- **MinIO**: Use existing MinIO deployment on TrueNAS for S3 backups
- **NFS**: Mount TrueNAS NFS for large model storage (optional)
- **Backup target**: Qdrant snapshots → MinIO → TrueNAS replication

### Existing Monitoring Stack
- **Prometheus**: Add LLM scrape configs to existing instance
- **Grafana**: Add LLM dashboard to existing Grafana
- **Victoria Metrics**: Store LLM metrics alongside infrastructure metrics
- **Alertmanager**: Route LLM alerts to existing notification channels

### ArgoCD Integration
```yaml
# Use existing ArgoCD ApplicationSet pattern
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: mcp-infrastructure
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/charlieshreck/monit_homelab.git
      revision: main
      directories:
      - path: kubernetes/platform/mcp-system/*
  template:
    metadata:
      name: 'mcp-{{path.basename}}'
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

## Security Hardening

### PII Detection with Presidio
```python
# langgraph_mcp/pii_filter.py
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine

analyzer = AnalyzerEngine()
anonymizer = AnonymizerEngine()

def filter_pii(query: str) -> tuple[str, bool]:
    """Detect and anonymize PII before sending to cloud"""
    results = analyzer.analyze(
        text=query,
        language="en",
        entities=["PERSON", "EMAIL_ADDRESS", "PHONE_NUMBER", "CREDIT_CARD", "IBAN_CODE"]
    )

    if results:
        # If PII detected, anonymize and flag for local-only processing
        anonymized = anonymizer.anonymize(text=query, analyzer_results=results)
        return anonymized.text, True  # True = contains PII, use local only

    return query, False  # Safe to send to cloud if needed
```

### GLiNER for Entity Recognition
```python
# International name recognition (for PII that Presidio might miss)
from gliner import GLiNER

model = GLiNER.from_pretrained("urchade/gliner_multi-v2.1")

def detect_entities(query: str) -> list:
    """Zero-shot entity detection"""
    labels = ["person", "organization", "location", "date", "ip_address", "api_key"]
    entities = model.predict_entities(query, labels)

    # If sensitive entities found, redact
    if any(e["label"] in ["person", "api_key"] for e in entities):
        return redact_entities(query, entities)

    return query
```

## Next Steps

1. **Review this refined architecture** against the tool selection reference
2. **Validate AMD APU availability** on Talos cluster node
3. **Increase monitoring cluster RAM** from 12GB to 24GB via Terraform
4. **Begin Phase 1**: Deploy storage foundation (Qdrant, PostgreSQL, Redis)
5. **Test Ollama with AMD GPU** before proceeding to Phase 2

## Files to Create

```
monit_homelab/
├── terraform/talos-single-node/
│   ├── mcp-storage.tf          # Qdrant, PostgreSQL, Redis
│   ├── mcp-compute.tf          # Ollama, LangGraph, LiteLLM
│   ├── mcp-ui.tf               # Open WebUI, Langfuse
│   └── values/
│       ├── qdrant.yaml
│       ├── postgresql-mcp.yaml
│       └── redis.yaml
│
├── kubernetes/platform/mcp-system/
│   ├── namespace.yaml
│   ├── ollama/
│   ├── qdrant/
│   ├── langgraph/
│   ├── litellm/
│   ├── open-webui/
│   ├── langfuse/
│   ├── mcp-gateway/
│   └── mcp-servers/
│       ├── kubernetes-prod-mcp/
│       ├── kubernetes-monitoring-mcp/
│       ├── proxmox-ruapehu-mcp/
│       ├── proxmox-carrick-mcp/
│       ├── opnsense-mcp/
│       ├── unifi-mcp/
│       ├── adguard-mcp/
│       └── caddy-mcp/
│
├── docker/mcp-services/
│   ├── langgraph-mcp/
│   │   ├── Dockerfile
│   │   ├── graph.py
│   │   ├── api.py
│   │   └── requirements.txt
│   ├── mcp-gateway/
│   └── discovery-service/
│
├── docs/
│   ├── MCP-ARCHITECTURE-REFINED.md (this file)
│   ├── MCP-OPERATIONS.md
│   ├── MCP-API.md
│   └── TROUBLESHOOTING-MCP.md
│
└── .github/workflows/
    └── build-mcp-services.yaml
```

---

**Document Version**: 1.1
**Date**: 2025-12-21
**Supersedes**: MCP-IMPLEMENTATION-PLAN.md (complementary document)
**Author**: AI Infrastructure Team
