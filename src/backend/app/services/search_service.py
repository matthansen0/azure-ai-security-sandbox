"""Azure AI Search service for document retrieval."""

import logging
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.search.documents.aio import SearchClient
from azure.search.documents.models import VectorizedQuery

from app.config import Settings

logger = logging.getLogger(__name__)


class SearchService:
    """Service for Azure AI Search operations."""
    
    def __init__(self, settings: Settings):
        """Initialize the search service with managed identity."""
        self.settings = settings
        
        # Use managed identity for authentication
        credential = DefaultAzureCredential()
        
        self.client = SearchClient(
            endpoint=settings.azure_search_endpoint,
            index_name=settings.azure_search_index_name,
            credential=credential
        )
        
        logger.info(f"Search service initialized with endpoint: {settings.azure_search_endpoint}")
    
    async def search(
        self,
        query: str,
        top: int = 5,
        embedding: list[float] = None
    ) -> list[dict]:
        """
        Search for documents matching the query.
        
        Args:
            query: The search query text
            top: Number of results to return
            embedding: Optional pre-computed embedding for vector search
        
        Returns:
            List of matching documents
        """
        try:
            # Perform hybrid search (text + vector if embedding provided)
            search_options = {
                "search_text": query,
                "top": top,
                "select": ["id", "title", "content", "source"],
                "query_type": "semantic",
                "semantic_configuration_name": "default"
            }
            
            # Add vector search if embedding is provided
            if embedding:
                search_options["vector_queries"] = [
                    VectorizedQuery(
                        vector=embedding,
                        k_nearest_neighbors=top,
                        fields="contentVector"
                    )
                ]
            
            results = []
            async for result in self.client.search(**search_options):
                results.append({
                    "id": result.get("id"),
                    "title": result.get("title", "Untitled"),
                    "content": result.get("content", ""),
                    "source": result.get("source", ""),
                    "score": result.get("@search.score", 0)
                })
            
            return results
        
        except Exception as e:
            logger.error(f"Search error: {e}")
            # Return empty results on error rather than failing
            return []
    
    async def close(self):
        """Close the search client."""
        await self.client.close()
