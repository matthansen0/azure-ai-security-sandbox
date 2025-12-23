"""Application configuration using Pydantic settings."""

from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # Azure OpenAI
    azure_openai_endpoint: str = ""
    azure_openai_chat_deployment: str = "gpt-4o"
    azure_openai_embedding_deployment: str = "text-embedding-3-small"
    azure_openai_api_version: str = "2024-08-01-preview"
    
    # Azure AI Search
    azure_search_endpoint: str = ""
    azure_search_index_name: str = "documents"
    
    # Azure Storage
    azure_storage_account_name: str = ""
    azure_storage_blob_endpoint: str = ""
    azure_storage_container_name: str = "documents"
    
    # Azure Cosmos DB
    azure_cosmosdb_endpoint: str = ""
    azure_cosmosdb_database_name: str = "chatdb"
    azure_cosmosdb_container_name: str = "conversations"
    
    # Application Insights
    applicationinsights_connection_string: str = ""
    
    # App settings
    debug: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
