"""Azure Blob Storage service for document management."""

import logging
import uuid
from datetime import datetime
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.storage.blob.aio import BlobServiceClient

from app.config import Settings

logger = logging.getLogger(__name__)


class StorageService:
    """Service for Azure Blob Storage operations."""
    
    def __init__(self, settings: Settings):
        """Initialize the storage service with managed identity."""
        self.settings = settings
        
        # Use managed identity for authentication
        credential = DefaultAzureCredential()
        
        self.client = BlobServiceClient(
            account_url=settings.azure_storage_blob_endpoint,
            credential=credential
        )
        
        self.container_name = settings.azure_storage_container_name
        
        logger.info(f"Storage service initialized with endpoint: {settings.azure_storage_blob_endpoint}")
    
    async def upload_document(
        self,
        filename: str,
        content: bytes,
        user_id: str = "anonymous"
    ) -> str:
        """
        Upload a document to blob storage.
        
        Args:
            filename: Original filename
            content: File content as bytes
            user_id: User identifier for organizing files
        
        Returns:
            The blob URL
        """
        try:
            container_client = self.client.get_container_client(self.container_name)
            
            # Generate unique blob name
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            unique_id = str(uuid.uuid4())[:8]
            blob_name = f"{user_id}/{timestamp}_{unique_id}_{filename}"
            
            blob_client = container_client.get_blob_client(blob_name)
            
            await blob_client.upload_blob(
                content,
                overwrite=True,
                metadata={
                    "original_filename": filename,
                    "user_id": user_id,
                    "uploaded_at": datetime.utcnow().isoformat()
                }
            )
            
            logger.info(f"Uploaded document: {blob_name}")
            return blob_client.url
        
        except Exception as e:
            logger.error(f"Storage upload error: {e}")
            raise
    
    async def list_documents(self, user_id: str = "anonymous") -> list[dict]:
        """
        List documents for a user.
        
        Args:
            user_id: User identifier
        
        Returns:
            List of document metadata
        """
        try:
            container_client = self.client.get_container_client(self.container_name)
            
            documents = []
            async for blob in container_client.list_blobs(name_starts_with=f"{user_id}/"):
                documents.append({
                    "name": blob.name,
                    "size": blob.size,
                    "created_at": blob.creation_time.isoformat() if blob.creation_time else None,
                    "content_type": blob.content_settings.content_type if blob.content_settings else None
                })
            
            return documents
        
        except Exception as e:
            logger.error(f"Storage list error: {e}")
            return []
    
    async def download_document(self, blob_name: str) -> bytes:
        """
        Download a document from blob storage.
        
        Args:
            blob_name: The blob name/path
        
        Returns:
            File content as bytes
        """
        try:
            container_client = self.client.get_container_client(self.container_name)
            blob_client = container_client.get_blob_client(blob_name)
            
            download = await blob_client.download_blob()
            return await download.readall()
        
        except Exception as e:
            logger.error(f"Storage download error: {e}")
            raise
    
    async def delete_document(self, blob_name: str) -> bool:
        """
        Delete a document from blob storage.
        
        Args:
            blob_name: The blob name/path
        
        Returns:
            True if deleted successfully
        """
        try:
            container_client = self.client.get_container_client(self.container_name)
            blob_client = container_client.get_blob_client(blob_name)
            
            await blob_client.delete_blob()
            logger.info(f"Deleted document: {blob_name}")
            return True
        
        except Exception as e:
            logger.error(f"Storage delete error: {e}")
            return False
