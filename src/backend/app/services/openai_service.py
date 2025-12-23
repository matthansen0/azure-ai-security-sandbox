"""Azure OpenAI service for chat completions."""

import logging
from typing import Optional

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AsyncAzureOpenAI

from app.config import Settings

logger = logging.getLogger(__name__)


class OpenAIService:
    """Service for interacting with Azure OpenAI."""
    
    def __init__(self, settings: Settings):
        """Initialize the OpenAI service with managed identity."""
        self.settings = settings
        
        # Use managed identity for authentication
        credential = DefaultAzureCredential()
        token_provider = get_bearer_token_provider(
            credential,
            "https://cognitiveservices.azure.com/.default"
        )
        
        self.client = AsyncAzureOpenAI(
            azure_endpoint=settings.azure_openai_endpoint,
            azure_ad_token_provider=token_provider,
            api_version=settings.azure_openai_api_version
        )
        
        self.chat_deployment = settings.azure_openai_chat_deployment
        self.embedding_deployment = settings.azure_openai_embedding_deployment
        
        logger.info(f"OpenAI service initialized with endpoint: {settings.azure_openai_endpoint}")
    
    async def chat(
        self,
        message: str,
        history: list[dict] = None,
        context: str = "",
        system_prompt: str = None
    ) -> str:
        """
        Generate a chat response.
        
        Args:
            message: The user's message
            history: Previous messages in the conversation
            context: Additional context from RAG search
            system_prompt: Custom system prompt
        
        Returns:
            The assistant's response
        """
        if history is None:
            history = []
        
        # Build system message
        if system_prompt is None:
            system_prompt = self._build_system_prompt(context)
        
        # Build messages array
        messages = [{"role": "system", "content": system_prompt}]
        
        # Add conversation history
        for msg in history[-10:]:  # Limit history to last 10 messages
            messages.append({
                "role": msg.get("role", "user"),
                "content": msg.get("content", "")
            })
        
        # Add current user message
        messages.append({"role": "user", "content": message})
        
        try:
            response = await self.client.chat.completions.create(
                model=self.chat_deployment,
                messages=messages,
                temperature=0.7,
                max_tokens=2000
            )
            
            return response.choices[0].message.content or ""
        
        except Exception as e:
            logger.error(f"OpenAI chat error: {e}")
            raise
    
    async def get_embedding(self, text: str) -> list[float]:
        """
        Generate an embedding for text.
        
        Args:
            text: The text to embed
        
        Returns:
            The embedding vector
        """
        try:
            response = await self.client.embeddings.create(
                model=self.embedding_deployment,
                input=text
            )
            
            return response.data[0].embedding
        
        except Exception as e:
            logger.error(f"OpenAI embedding error: {e}")
            raise
    
    def _build_system_prompt(self, context: str = "") -> str:
        """Build the system prompt with optional RAG context."""
        base_prompt = """You are an AI assistant for the Azure AI Security Sandbox.
You help users understand Azure security best practices, AI/ML security, and cloud security concepts.
Be helpful, accurate, and concise in your responses.

If you're unsure about something, say so rather than making up information.
When discussing security topics, prioritize accuracy and best practices."""
        
        if context:
            base_prompt += f"""

Use the following context from our knowledge base to help answer the user's question.
If the context doesn't contain relevant information, you can still answer based on your general knowledge,
but mention that the information comes from your training data rather than the knowledge base.

Context:
{context}"""
        
        return base_prompt
