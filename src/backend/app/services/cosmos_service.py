"""Azure Cosmos DB service for conversation history."""

import logging
import uuid
from datetime import datetime
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.cosmos.aio import CosmosClient
from azure.cosmos import PartitionKey
from azure.cosmos.exceptions import CosmosResourceNotFoundError

from app.config import Settings

logger = logging.getLogger(__name__)


class CosmosService:
    """Service for Azure Cosmos DB operations."""
    
    def __init__(self, settings: Settings):
        """Initialize the Cosmos DB service with managed identity."""
        self.settings = settings
        
        # Use managed identity for authentication
        credential = DefaultAzureCredential()
        
        self.client = CosmosClient(
            url=settings.azure_cosmosdb_endpoint,
            credential=credential
        )
        
        self.database_name = settings.azure_cosmosdb_database_name
        self.container_name = settings.azure_cosmosdb_container_name
        self.container = None
        
        logger.info(f"Cosmos service initialized with endpoint: {settings.azure_cosmosdb_endpoint}")
    
    async def initialize(self):
        """Initialize the database and container references."""
        try:
            database = self.client.get_database_client(self.database_name)
            self.container = database.get_container_client(self.container_name)
            logger.info(f"Connected to container: {self.container_name}")
        except Exception as e:
            logger.error(f"Cosmos initialization error: {e}")
            raise
    
    async def close(self):
        """Close the Cosmos client."""
        await self.client.close()
    
    async def get_or_create_conversation(
        self,
        conversation_id: Optional[str],
        user_id: str
    ) -> dict:
        """
        Get an existing conversation or create a new one.
        
        Args:
            conversation_id: Optional existing conversation ID
            user_id: User identifier (partition key)
        
        Returns:
            The conversation document
        """
        if conversation_id:
            try:
                conversation = await self.container.read_item(
                    item=conversation_id,
                    partition_key=user_id
                )
                return conversation
            except CosmosResourceNotFoundError:
                pass  # Create new conversation
        
        # Create new conversation
        conversation = {
            "id": str(uuid.uuid4()),
            "userId": user_id,
            "title": "New Conversation",
            "messages": [],
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }
        
        await self.container.create_item(body=conversation)
        logger.info(f"Created new conversation: {conversation['id']}")
        
        return conversation
    
    async def get_conversation(self, conversation_id: str, user_id: str) -> Optional[dict]:
        """Get a specific conversation."""
        try:
            return await self.container.read_item(
                item=conversation_id,
                partition_key=user_id
            )
        except CosmosResourceNotFoundError:
            return None
    
    async def get_conversation_messages(self, conversation_id: str) -> list[dict]:
        """
        Get all messages for a conversation.
        
        Args:
            conversation_id: The conversation ID
        
        Returns:
            List of messages
        """
        query = """
        SELECT c.messages
        FROM c
        WHERE c.id = @conversation_id
        """
        
        items = []
        async for item in self.container.query_items(
            query=query,
            parameters=[{"name": "@conversation_id", "value": conversation_id}]
        ):
            items.append(item)
        
        if items and "messages" in items[0]:
            return items[0]["messages"]
        return []
    
    async def add_message(
        self,
        conversation_id: str,
        role: str,
        content: str
    ):
        """
        Add a message to a conversation.
        
        Args:
            conversation_id: The conversation ID
            role: Message role ('user' or 'assistant')
            content: Message content
        """
        # First, get the conversation to find the partition key
        query = """
        SELECT *
        FROM c
        WHERE c.id = @conversation_id
        """
        
        conversations = []
        async for item in self.container.query_items(
            query=query,
            parameters=[{"name": "@conversation_id", "value": conversation_id}]
        ):
            conversations.append(item)
        
        if not conversations:
            raise ValueError(f"Conversation not found: {conversation_id}")
        
        conversation = conversations[0]
        
        # Add the new message
        message = {
            "id": str(uuid.uuid4()),
            "role": role,
            "content": content,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        conversation["messages"].append(message)
        conversation["updated_at"] = datetime.utcnow().isoformat()
        
        # Update title if this is the first user message
        if role == "user" and len(conversation["messages"]) == 1:
            conversation["title"] = content[:50] + ("..." if len(content) > 50 else "")
        
        await self.container.replace_item(
            item=conversation["id"],
            body=conversation
        )
    
    async def list_conversations(self, user_id: str) -> list[dict]:
        """
        List all conversations for a user.
        
        Args:
            user_id: User identifier
        
        Returns:
            List of conversation summaries
        """
        query = """
        SELECT c.id, c.title, c.created_at, c.updated_at, ARRAY_LENGTH(c.messages) as message_count
        FROM c
        WHERE c.userId = @user_id
        ORDER BY c.updated_at DESC
        """
        
        conversations = []
        async for item in self.container.query_items(
            query=query,
            parameters=[{"name": "@user_id", "value": user_id}]
        ):
            conversations.append(item)
        
        return conversations
    
    async def delete_conversation(self, conversation_id: str, user_id: str):
        """Delete a conversation."""
        try:
            await self.container.delete_item(
                item=conversation_id,
                partition_key=user_id
            )
            logger.info(f"Deleted conversation: {conversation_id}")
        except CosmosResourceNotFoundError:
            pass  # Already deleted
