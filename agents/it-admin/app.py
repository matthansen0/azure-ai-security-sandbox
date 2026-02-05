# IT Admin Agent API
# FastAPI application for troubleshooting IT infrastructure issues

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
import os
import json
import logging
from datetime import datetime

from azure.identity import DefaultAzureCredential
from openai import AzureOpenAI

from tools import (
    get_system_config,
    get_system_metrics,
    get_recent_logs,
    get_service_health,
    get_recent_changes,
    check_dependencies,
    get_resource_details,
    TOOL_DEFINITIONS
)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(
    title="IT Admin Agent API",
    description="AI-powered troubleshooting agent for IT administrators",
    version="0.1.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration from environment
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "")
AZURE_OPENAI_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")
AI_PROJECT_ENDPOINT = os.getenv("AI_PROJECT_ENDPOINT", "")

# Azure OpenAI client (lazy initialized)
_openai_client = None

def get_openai_client() -> AzureOpenAI:
    """Get or create Azure OpenAI client with managed identity auth."""
    global _openai_client
    if _openai_client is None:
        credential = DefaultAzureCredential()
        token = credential.get_token("https://cognitiveservices.azure.com/.default")
        _openai_client = AzureOpenAI(
            azure_endpoint=AZURE_OPENAI_ENDPOINT,
            api_version="2024-06-01",
            azure_ad_token=token.token
        )
    return _openai_client

# System prompt for the IT Admin agent
SYSTEM_PROMPT = """You are an expert IT Administrator troubleshooting agent. Your role is to help diagnose and resolve infrastructure issues.

When a user reports a problem:
1. First gather information about the affected system using available tools
2. Analyze metrics, logs, and configuration to identify potential issues
3. Check for recent changes that might have caused the problem
4. Provide a clear diagnosis with supporting evidence
5. Suggest remediation steps

Available tools:
- get_system_config: Get configuration details for Azure resources
- get_system_metrics: Get CPU, memory, latency, and other metrics
- get_recent_logs: Get recent log entries from a system
- get_service_health: Check if there are known Azure service issues
- get_recent_changes: Get recent deployments and configuration changes
- check_dependencies: List services this resource depends on
- get_resource_details: Get detailed information about an Azure resource

Always be thorough in your investigation. Use multiple tools to build a complete picture.
Explain your reasoning as you go. Cite specific data from tool outputs.

If you cannot determine the root cause, suggest what additional information would help."""

# Tool function mapping
TOOL_FUNCTIONS = {
    "get_system_config": get_system_config,
    "get_system_metrics": get_system_metrics,
    "get_recent_logs": get_recent_logs,
    "get_service_health": get_service_health,
    "get_recent_changes": get_recent_changes,
    "check_dependencies": check_dependencies,
    "get_resource_details": get_resource_details,
}


# Request/Response models
class ChatMessage(BaseModel):
    role: str = Field(..., description="Role: 'user' or 'assistant'")
    content: str = Field(..., description="Message content")

class ChatRequest(BaseModel):
    message: str = Field(..., description="User's message describing the issue")
    conversation_id: Optional[str] = Field(None, description="Optional conversation ID for multi-turn")
    context: Optional[Dict[str, Any]] = Field(None, description="Optional context about the environment")

class ToolCall(BaseModel):
    tool_name: str
    arguments: Dict[str, Any]
    result: Any

class ChatResponse(BaseModel):
    response: str = Field(..., description="Agent's response")
    conversation_id: str = Field(..., description="Conversation ID for follow-up")
    tool_calls: List[ToolCall] = Field(default_factory=list, description="Tools called during processing")
    thinking: Optional[str] = Field(None, description="Agent's reasoning process")

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    openai_configured: bool
    project_configured: bool


# In-memory conversation storage (use Cosmos DB in production)
conversations: Dict[str, List[dict]] = {}


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat(),
        openai_configured=bool(AZURE_OPENAI_ENDPOINT),
        project_configured=bool(AI_PROJECT_ENDPOINT)
    )


@app.get("/tools")
async def list_tools():
    """List available tools the agent can use."""
    return {
        "tools": TOOL_DEFINITIONS,
        "description": "These tools are available for the IT Admin agent to gather information about systems."
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Send a message to the IT Admin agent.
    
    The agent will analyze the issue, call relevant tools to gather information,
    and provide a diagnosis with remediation suggestions.
    """
    try:
        # Get or create conversation
        conversation_id = request.conversation_id or f"conv_{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}"
        
        if conversation_id not in conversations:
            conversations[conversation_id] = [
                {"role": "system", "content": SYSTEM_PROMPT}
            ]
        
        # Add user message
        conversations[conversation_id].append({
            "role": "user",
            "content": request.message
        })
        
        # Add context if provided
        if request.context:
            context_msg = f"\n\nEnvironment context: {json.dumps(request.context, indent=2)}"
            conversations[conversation_id][-1]["content"] += context_msg
        
        # Call OpenAI with tools
        client = get_openai_client()
        tool_calls_made = []
        
        # Agentic loop - keep calling until no more tool calls
        max_iterations = 10
        iteration = 0
        
        while iteration < max_iterations:
            iteration += 1
            
            response = client.chat.completions.create(
                model=AZURE_OPENAI_DEPLOYMENT,
                messages=conversations[conversation_id],
                tools=TOOL_DEFINITIONS,
                tool_choice="auto"
            )
            
            assistant_message = response.choices[0].message
            
            # Check if there are tool calls
            if assistant_message.tool_calls:
                # Add assistant message with tool calls
                conversations[conversation_id].append({
                    "role": "assistant",
                    "content": assistant_message.content or "",
                    "tool_calls": [
                        {
                            "id": tc.id,
                            "type": "function",
                            "function": {
                                "name": tc.function.name,
                                "arguments": tc.function.arguments
                            }
                        }
                        for tc in assistant_message.tool_calls
                    ]
                })
                
                # Execute each tool call
                for tool_call in assistant_message.tool_calls:
                    function_name = tool_call.function.name
                    function_args = json.loads(tool_call.function.arguments)
                    
                    logger.info(f"Calling tool: {function_name} with args: {function_args}")
                    
                    if function_name in TOOL_FUNCTIONS:
                        result = TOOL_FUNCTIONS[function_name](**function_args)
                    else:
                        result = {"error": f"Unknown tool: {function_name}"}
                    
                    tool_calls_made.append(ToolCall(
                        tool_name=function_name,
                        arguments=function_args,
                        result=result
                    ))
                    
                    # Add tool result to conversation
                    conversations[conversation_id].append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": json.dumps(result)
                    })
            else:
                # No more tool calls, we have the final response
                final_response = assistant_message.content or "I apologize, but I couldn't generate a response."
                
                # Add final response to conversation
                conversations[conversation_id].append({
                    "role": "assistant",
                    "content": final_response
                })
                
                return ChatResponse(
                    response=final_response,
                    conversation_id=conversation_id,
                    tool_calls=tool_calls_made
                )
        
        # Max iterations reached
        return ChatResponse(
            response="I've gathered a lot of information but reached my processing limit. Here's what I found so far based on the tool calls.",
            conversation_id=conversation_id,
            tool_calls=tool_calls_made
        )
        
    except Exception as e:
        logger.error(f"Error in chat: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/tools/{tool_name}")
async def call_tool_directly(tool_name: str, arguments: Dict[str, Any]):
    """
    Call a tool directly without the agent (for testing/debugging).
    """
    if tool_name not in TOOL_FUNCTIONS:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_name}' not found")
    
    try:
        result = TOOL_FUNCTIONS[tool_name](**arguments)
        return {"tool": tool_name, "arguments": arguments, "result": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/conversations/{conversation_id}")
async def clear_conversation(conversation_id: str):
    """Clear a conversation's history."""
    if conversation_id in conversations:
        del conversations[conversation_id]
        return {"status": "deleted", "conversation_id": conversation_id}
    raise HTTPException(status_code=404, detail="Conversation not found")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
