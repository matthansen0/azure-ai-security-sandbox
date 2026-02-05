# IT Admin Agent API Tests
# Run with: pytest tests/ -v

import pytest
import sys
from unittest.mock import patch, MagicMock, AsyncMock
from fastapi.testclient import TestClient

# Add parent directory to path for imports
sys.path.insert(0, '.')

from app import app, TOOL_FUNCTIONS


client = TestClient(app)


class TestHealthEndpoint:
    """Test /health endpoint."""
    
    def test_health_returns_200(self):
        """Test health check returns 200."""
        response = client.get("/health")
        assert response.status_code == 200
    
    def test_health_returns_healthy_status(self):
        """Test health check returns healthy status."""
        response = client.get("/health")
        data = response.json()
        assert data["status"] == "healthy"
    
    def test_health_includes_timestamp(self):
        """Test health check includes timestamp."""
        response = client.get("/health")
        data = response.json()
        assert "timestamp" in data
    
    def test_health_includes_config_flags(self):
        """Test health check includes configuration flags."""
        response = client.get("/health")
        data = response.json()
        assert "openai_configured" in data
        assert "project_configured" in data


class TestToolsEndpoint:
    """Test /tools endpoint."""
    
    def test_tools_returns_200(self):
        """Test tools endpoint returns 200."""
        response = client.get("/tools")
        assert response.status_code == 200
    
    def test_tools_returns_tools_list(self):
        """Test tools endpoint returns tools in expected format."""
        response = client.get("/tools")
        data = response.json()
        assert "tools" in data
        assert isinstance(data["tools"], list)
        assert len(data["tools"]) == 7
    
    def test_tools_has_description(self):
        """Test tools response includes description."""
        response = client.get("/tools")
        data = response.json()
        assert "description" in data
    
    def test_tools_structure(self):
        """Test each tool has OpenAI function calling structure."""
        response = client.get("/tools")
        data = response.json()
        for tool in data["tools"]:
            assert tool["type"] == "function"
            assert "function" in tool
            assert "name" in tool["function"]


class TestToolInvocationEndpoint:
    """Test /tools/{tool_name} endpoint."""
    
    def test_get_system_config(self):
        """Test direct invocation of get_system_config."""
        response = client.post(
            "/tools/get_system_config",
            json={"resource_name": "web-app-prod", "resource_type": "container_app"}
        )
        assert response.status_code == 200
        data = response.json()
        # Response wraps result in {"tool": ..., "arguments": ..., "result": ...}
        assert data["tool"] == "get_system_config"
        assert data["result"]["resource_name"] == "web-app-prod"
        assert "configuration" in data["result"]
    
    def test_get_system_metrics(self):
        """Test direct invocation of get_system_metrics."""
        response = client.post(
            "/tools/get_system_metrics",
            json={"resource_name": "web-app-prod", "metric_type": "cpu", "time_range": "1h"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "get_system_metrics"
        assert "data" in data["result"]
        assert "cpu" in data["result"]["data"]
    
    def test_get_recent_logs(self):
        """Test direct invocation of get_recent_logs."""
        response = client.post(
            "/tools/get_recent_logs",
            json={"resource_name": "web-app-prod", "severity": "all", "limit": 10}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "get_recent_logs"
        assert "logs" in data["result"]
    
    def test_get_service_health(self):
        """Test direct invocation of get_service_health."""
        response = client.post(
            "/tools/get_service_health",
            json={"service": "Azure SQL", "region": "eastus"}  # Note: "service" not "service_name"
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "get_service_health"
        assert data["result"]["status"] == "degraded"
    
    def test_get_service_health_healthy(self):
        """Test get_service_health for healthy service."""
        response = client.post(
            "/tools/get_service_health",
            json={"service": "Container Apps", "region": "eastus"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["result"]["status"] == "healthy"
    
    def test_get_recent_changes(self):
        """Test direct invocation of get_recent_changes."""
        response = client.post(
            "/tools/get_recent_changes",
            json={"resource_name": "web-app-prod", "days": 7}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "get_recent_changes"
        assert "changes" in data["result"]
    
    def test_check_dependencies(self):
        """Test direct invocation of check_dependencies."""
        response = client.post(
            "/tools/check_dependencies",
            json={"resource_name": "web-app-prod"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "check_dependencies"
        assert "upstream_dependencies" in data["result"]
        assert "downstream_dependencies" in data["result"]
    
    def test_get_resource_details(self):
        """Test direct invocation of get_resource_details."""
        response = client.post(
            "/tools/get_resource_details",
            json={"resource_name": "web-app-prod"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["tool"] == "get_resource_details"
        assert data["result"]["resource_type"] == "container_app"
    
    def test_unknown_tool_returns_404(self):
        """Test unknown tool returns 404."""
        response = client.post(
            "/tools/unknown_tool",
            json={"param": "value"}
        )
        assert response.status_code == 404


class TestChatEndpoint:
    """Test /chat endpoint."""
    
    def test_chat_missing_message(self):
        """Test chat without message returns 422."""
        response = client.post("/chat", json={})
        assert response.status_code == 422
    
    def test_chat_with_empty_message(self):
        """Test chat with empty message."""
        response = client.post("/chat", json={"message": ""})
        # Empty string is technically valid but may produce minimal results
        # The OpenAI call will fail since endpoint isn't configured in tests
        # We're testing the request validation passes
        assert response.status_code in [200, 500]  # 500 if OpenAI not configured
    
    @patch('app.get_openai_client')
    def test_chat_success(self, mock_get_client):
        """Test chat endpoint with mocked OpenAI client."""
        # Create mock response
        mock_message = MagicMock()
        mock_message.content = "Based on my analysis, the web-app-prod system shows high CPU usage."
        mock_message.tool_calls = None
        
        mock_choice = MagicMock()
        mock_choice.message = mock_message
        mock_choice.finish_reason = "stop"
        
        mock_response = MagicMock()
        mock_response.choices = [mock_choice]
        
        # Set up mock client
        mock_client = MagicMock()
        mock_client.chat = MagicMock()
        mock_client.chat.completions = MagicMock()
        mock_client.chat.completions.create = MagicMock(return_value=mock_response)
        mock_get_client.return_value = mock_client
        
        response = client.post(
            "/chat",
            json={"message": "Check web-app-prod"}
        )
        
        # Should get a successful response
        assert response.status_code == 200
        data = response.json()
        assert "response" in data
        assert "conversation_id" in data
    
    @patch('app.get_openai_client')
    def test_chat_with_tool_calls(self, mock_get_client):
        """Test chat endpoint handles tool calls."""
        # First response: tool call
        mock_tool_call = MagicMock()
        mock_tool_call.id = "call_123"
        mock_tool_call.function = MagicMock()
        mock_tool_call.function.name = "get_system_metrics"
        mock_tool_call.function.arguments = '{"resource_name": "web-app-prod", "metric_type": "cpu", "time_range": "1h"}'
        
        mock_message1 = MagicMock()
        mock_message1.content = None
        mock_message1.tool_calls = [mock_tool_call]
        mock_message1.model_dump.return_value = {
            "role": "assistant",
            "content": None,
            "tool_calls": [{
                "id": "call_123",
                "type": "function",
                "function": {
                    "name": "get_system_metrics",
                    "arguments": '{"resource_name": "web-app-prod", "metric_type": "cpu", "time_range": "1h"}'
                }
            }]
        }
        
        mock_choice1 = MagicMock()
        mock_choice1.message = mock_message1
        mock_choice1.finish_reason = "tool_calls"
        
        mock_response1 = MagicMock()
        mock_response1.choices = [mock_choice1]
        
        # Second response: final answer
        mock_message2 = MagicMock()
        mock_message2.content = "The CPU usage on web-app-prod is at 85%, which is concerning."
        mock_message2.tool_calls = None
        
        mock_choice2 = MagicMock()
        mock_choice2.message = mock_message2
        mock_choice2.finish_reason = "stop"
        
        mock_response2 = MagicMock()
        mock_response2.choices = [mock_choice2]
        
        # Set up mock client
        mock_client = MagicMock()
        mock_client.chat = MagicMock()
        mock_client.chat.completions = MagicMock()
        mock_client.chat.completions.create = MagicMock(
            side_effect=[mock_response1, mock_response2]
        )
        mock_get_client.return_value = mock_client
        
        response = client.post(
            "/chat",
            json={"message": "What's the CPU on web-app-prod?"}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert "response" in data
        # Verify tool calls were tracked
        assert "tool_calls" in data


class TestToolFunctions:
    """Test TOOL_FUNCTIONS mapping."""
    
    def test_all_handlers_present(self):
        """Test all tools have handlers registered."""
        expected_tools = [
            "get_system_config",
            "get_system_metrics",
            "get_recent_logs",
            "get_service_health",
            "get_recent_changes",
            "check_dependencies",
            "get_resource_details",
        ]
        for tool_name in expected_tools:
            assert tool_name in TOOL_FUNCTIONS, f"Missing handler for {tool_name}"
    
    def test_handlers_are_callable(self):
        """Test all handlers are callable functions."""
        for name, handler in TOOL_FUNCTIONS.items():
            assert callable(handler), f"Handler for {name} is not callable"


class TestEdgeCases:
    """Test edge cases and error handling."""
    
    def test_tool_unknown_resource(self):
        """Test tool invocation with unknown resource."""
        response = client.post(
            "/tools/get_resource_details",
            json={"resource_name": "unknown-resource"}
        )
        assert response.status_code == 200
        data = response.json()
        # Unknown resources return error in result
        assert "error" in data["result"]


class TestContentTypes:
    """Test content type handling."""
    
    def test_json_content_type(self):
        """Test endpoint accepts JSON content type."""
        response = client.post(
            "/tools/get_system_config",
            json={"resource_name": "web-app-prod", "resource_type": "container_app"},
            headers={"Content-Type": "application/json"}
        )
        assert response.status_code == 200
    
    def test_response_is_json(self):
        """Test response is JSON."""
        response = client.get("/health")
        assert response.headers["content-type"] == "application/json"


class TestConversationEndpoint:
    """Test /conversations/{id} endpoint."""
    
    def test_delete_nonexistent_conversation(self):
        """Test deleting nonexistent conversation returns 404."""
        response = client.delete("/conversations/nonexistent-id")
        assert response.status_code == 404
