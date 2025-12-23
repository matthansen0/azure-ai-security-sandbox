"""
Azure AI Security Sandbox - FastAPI Backend
A RAG chat application with enterprise security controls.
"""

import os
import logging
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, UploadFile, File, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.config import get_settings, Settings
from app.services.openai_service import OpenAIService
from app.services.search_service import SearchService
from app.services.storage_service import StorageService
from app.services.cosmos_service import CosmosService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global service instances
openai_service: Optional[OpenAIService] = None
search_service: Optional[SearchService] = None
storage_service: Optional[StorageService] = None
cosmos_service: Optional[CosmosService] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize services on startup."""
    global openai_service, search_service, storage_service, cosmos_service
    
    settings = get_settings()
    logger.info("Initializing Azure services...")
    
    try:
        openai_service = OpenAIService(settings)
        search_service = SearchService(settings)
        storage_service = StorageService(settings)
        cosmos_service = CosmosService(settings)
        
        await cosmos_service.initialize()
        logger.info("All services initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize services: {e}")
        raise
    
    yield
    
    # Cleanup on shutdown
    if cosmos_service:
        await cosmos_service.close()
    logger.info("Application shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="Azure AI Security Sandbox",
    description="RAG chat application with enterprise security controls",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware (configure appropriately for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request/Response models
class ChatMessage(BaseModel):
    role: str = Field(..., description="Message role: 'user' or 'assistant'")
    content: str = Field(..., description="Message content")


class ChatRequest(BaseModel):
    message: str = Field(..., description="User message")
    conversation_id: Optional[str] = Field(None, description="Conversation ID for history")
    user_id: str = Field(default="anonymous", description="User identifier")
    use_rag: bool = Field(default=True, description="Whether to use RAG for grounded responses")


class ChatResponse(BaseModel):
    message: str = Field(..., description="Assistant response")
    conversation_id: str = Field(..., description="Conversation ID")
    sources: list[dict] = Field(default=[], description="Source documents used")


class ConversationSummary(BaseModel):
    id: str
    title: str
    created_at: str
    message_count: int


class HealthResponse(BaseModel):
    status: str
    timestamp: str
    services: dict


# Endpoints
@app.get("/", response_model=dict)
async def root():
    """Root endpoint with app info."""
    return {
        "name": "Azure AI Security Sandbox",
        "version": "1.0.0",
        "description": "RAG chat application with enterprise security controls",
        "docs": "/docs"
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    services_status = {
        "openai": openai_service is not None,
        "search": search_service is not None,
        "storage": storage_service is not None,
        "cosmos": cosmos_service is not None
    }
    
    return HealthResponse(
        status="healthy" if all(services_status.values()) else "degraded",
        timestamp=datetime.utcnow().isoformat(),
        services=services_status
    )


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Send a chat message and get a response."""
    if not openai_service or not cosmos_service:
        raise HTTPException(status_code=503, detail="Services not initialized")
    
    try:
        # Get or create conversation
        conversation = await cosmos_service.get_or_create_conversation(
            conversation_id=request.conversation_id,
            user_id=request.user_id
        )
        
        # Get conversation history
        history = await cosmos_service.get_conversation_messages(conversation["id"])
        
        # Search for relevant documents if RAG is enabled
        sources = []
        context = ""
        if request.use_rag and search_service:
            search_results = await search_service.search(request.message)
            if search_results:
                context = "\n\n".join([r["content"] for r in search_results[:3]])
                sources = [{"title": r.get("title", "Unknown"), "chunk": r.get("content", "")[:200]} for r in search_results[:3]]
        
        # Generate response
        response = await openai_service.chat(
            message=request.message,
            history=history,
            context=context
        )
        
        # Save messages to history
        await cosmos_service.add_message(conversation["id"], "user", request.message)
        await cosmos_service.add_message(conversation["id"], "assistant", response)
        
        return ChatResponse(
            message=response,
            conversation_id=conversation["id"],
            sources=sources
        )
    
    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/conversations", response_model=list[ConversationSummary])
async def list_conversations(user_id: str = "anonymous"):
    """List all conversations for a user."""
    if not cosmos_service:
        raise HTTPException(status_code=503, detail="Cosmos service not initialized")
    
    try:
        conversations = await cosmos_service.list_conversations(user_id)
        return [
            ConversationSummary(
                id=c["id"],
                title=c.get("title", "Untitled"),
                created_at=c.get("created_at", ""),
                message_count=len(c.get("messages", []))
            )
            for c in conversations
        ]
    except Exception as e:
        logger.error(f"List conversations error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/conversations/{conversation_id}")
async def get_conversation(conversation_id: str, user_id: str = "anonymous"):
    """Get a specific conversation with all messages."""
    if not cosmos_service:
        raise HTTPException(status_code=503, detail="Cosmos service not initialized")
    
    try:
        conversation = await cosmos_service.get_conversation(conversation_id, user_id)
        if not conversation:
            raise HTTPException(status_code=404, detail="Conversation not found")
        return conversation
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Get conversation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/conversations/{conversation_id}")
async def delete_conversation(conversation_id: str, user_id: str = "anonymous"):
    """Delete a conversation."""
    if not cosmos_service:
        raise HTTPException(status_code=503, detail="Cosmos service not initialized")
    
    try:
        await cosmos_service.delete_conversation(conversation_id, user_id)
        return {"status": "deleted", "conversation_id": conversation_id}
    except Exception as e:
        logger.error(f"Delete conversation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/documents/upload")
async def upload_document(file: UploadFile = File(...), user_id: str = "anonymous"):
    """Upload a document for RAG indexing."""
    if not storage_service:
        raise HTTPException(status_code=503, detail="Storage service not initialized")
    
    # Validate file type
    allowed_types = [".txt", ".pdf", ".md", ".docx"]
    file_ext = os.path.splitext(file.filename or "")[1].lower()
    if file_ext not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail=f"File type {file_ext} not supported. Allowed: {allowed_types}"
        )
    
    try:
        # Upload to blob storage
        content = await file.read()
        blob_url = await storage_service.upload_document(
            filename=file.filename or "document",
            content=content,
            user_id=user_id
        )
        
        # TODO: Trigger indexing pipeline
        
        return {
            "status": "uploaded",
            "filename": file.filename,
            "blob_url": blob_url,
            "message": "Document uploaded. Indexing will be processed."
        }
    except Exception as e:
        logger.error(f"Upload error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/documents")
async def list_documents(user_id: str = "anonymous"):
    """List uploaded documents."""
    if not storage_service:
        raise HTTPException(status_code=503, detail="Storage service not initialized")
    
    try:
        documents = await storage_service.list_documents(user_id)
        return {"documents": documents}
    except Exception as e:
        logger.error(f"List documents error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Error handlers
@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "An internal error occurred"}
    )
