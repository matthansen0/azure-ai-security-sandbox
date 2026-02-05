# Pytest configuration for IT Admin Agent tests

import pytest
import sys
import os

# Ensure the parent directory (agents/it-admin) is in the path
# This allows imports like `from tools import ...` and `from app import ...`
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture
def sample_chat_request():
    """Sample chat request for testing."""
    return {
        "messages": [
            {"role": "user", "content": "Check the health of web-app-prod"}
        ]
    }


@pytest.fixture
def sample_tool_arguments():
    """Sample tool arguments for testing."""
    return {
        "get_system_config": {
            "resource_name": "web-app-prod",
            "resource_type": "container_app"
        },
        "get_system_metrics": {
            "resource_name": "web-app-prod",
            "metric_type": "cpu",
            "time_range": "1h"
        },
        "get_recent_logs": {
            "resource_name": "web-app-prod",
            "severity": "error",
            "limit": 10
        },
        "get_service_health": {
            "service_name": "Azure SQL",
            "region": "eastus"
        },
        "get_recent_changes": {
            "resource_name": "web-app-prod",
            "days": 7
        },
        "check_dependencies": {
            "resource_name": "web-app-prod"
        },
        "get_resource_details": {
            "resource_name": "web-app-prod"
        }
    }


@pytest.fixture
def mock_resources_list():
    """List of mock resource names."""
    return [
        "web-app-prod",
        "sql-db-main",
        "api-gateway",
        "redis-cache-prod",
        "storage-prod"
    ]
