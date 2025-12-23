# Azure AI Security Sandbox - Python Backend

This is a FastAPI-based RAG (Retrieval-Augmented Generation) chat application that integrates with Azure OpenAI, Azure AI Search, Azure Storage, and Cosmos DB.

## Features

- **Chat with AI**: Powered by Azure OpenAI GPT-4o
- **Document Search**: RAG using Azure AI Search for grounded responses
- **Chat History**: Persisted in Azure Cosmos DB
- **Document Upload**: Store documents in Azure Blob Storage
- **Secure by Default**: Uses managed identity for all Azure service authentication

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables (see .env.example)
export AZURE_OPENAI_ENDPOINT="https://your-openai.openai.azure.com/"
# ... other variables

# Run the application
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL |
| `AZURE_OPENAI_CHAT_DEPLOYMENT` | Chat model deployment name (e.g., gpt-4o) |
| `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` | Embedding model deployment name |
| `AZURE_SEARCH_ENDPOINT` | Azure AI Search endpoint URL |
| `AZURE_SEARCH_INDEX_NAME` | Search index name |
| `AZURE_STORAGE_BLOB_ENDPOINT` | Azure Blob Storage endpoint |
| `AZURE_COSMOSDB_ENDPOINT` | Cosmos DB endpoint |
| `AZURE_COSMOSDB_DATABASE_NAME` | Cosmos DB database name |
| `AZURE_COSMOSDB_CONTAINER_NAME` | Cosmos DB container name |

## API Endpoints

- `GET /` - Health check and app info
- `GET /health` - Health check
- `POST /chat` - Send a chat message
- `GET /conversations` - List user conversations
- `GET /conversations/{id}` - Get a specific conversation
- `DELETE /conversations/{id}` - Delete a conversation
- `POST /documents/upload` - Upload a document
- `GET /documents` - List uploaded documents
