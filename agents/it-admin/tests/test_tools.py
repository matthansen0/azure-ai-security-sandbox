# IT Admin Agent Unit Tests
# Run with: pytest tests/ -v

import pytest
import sys
import json
from datetime import datetime
from unittest.mock import patch, MagicMock

# Add parent directory to path for imports
sys.path.insert(0, '.')

from tools import (
    TOOL_DEFINITIONS,
    MOCK_RESOURCES,
    get_system_config,
    get_system_metrics,
    get_recent_logs,
    get_service_health,
    get_recent_changes,
    check_dependencies,
    get_resource_details,
)


class TestToolDefinitions:
    """Test tool definitions are properly structured for OpenAI function calling."""
    
    def test_tool_definitions_count(self):
        """Verify all 7 tools are defined."""
        assert len(TOOL_DEFINITIONS) == 7
    
    def test_tool_definitions_structure(self):
        """Verify each tool has required OpenAI function calling structure."""
        for tool in TOOL_DEFINITIONS:
            assert "type" in tool
            assert tool["type"] == "function"
            assert "function" in tool
            assert "name" in tool["function"]
            assert "description" in tool["function"]
            assert "parameters" in tool["function"]
            assert "type" in tool["function"]["parameters"]
            assert tool["function"]["parameters"]["type"] == "object"
    
    def test_tool_names_unique(self):
        """Verify all tool names are unique."""
        names = [t["function"]["name"] for t in TOOL_DEFINITIONS]
        assert len(names) == len(set(names))
    
    def test_required_parameters_defined(self):
        """Verify required parameters are defined in properties."""
        for tool in TOOL_DEFINITIONS:
            params = tool["function"]["parameters"]
            if "required" in params:
                for req in params["required"]:
                    assert req in params["properties"], \
                        f"Required param '{req}' not in properties for {tool['function']['name']}"


class TestMockResources:
    """Test mock resource data is properly structured."""
    
    def test_mock_resources_exist(self):
        """Verify mock resources are defined."""
        assert len(MOCK_RESOURCES) >= 5
    
    def test_web_app_prod_exists(self):
        """Verify web-app-prod mock resource exists with required fields."""
        assert "web-app-prod" in MOCK_RESOURCES
        resource = MOCK_RESOURCES["web-app-prod"]
        assert "type" in resource
        assert "config" in resource
        assert "dependencies" in resource
    
    def test_mock_resources_have_dependencies(self):
        """Verify all mock resources have dependency definitions."""
        for name, resource in MOCK_RESOURCES.items():
            assert "dependencies" in resource, f"Missing dependencies for {name}"
            assert "upstream" in resource["dependencies"]
            assert "downstream" in resource["dependencies"]


class TestGetSystemConfig:
    """Test get_system_config tool function."""
    
    def test_known_resource(self):
        """Test config retrieval for known resource."""
        result = get_system_config("web-app-prod", "container_app")
        assert result["resource_name"] == "web-app-prod"
        assert result["resource_type"] == "container_app"
        assert "configuration" in result
        assert "replicas" in result["configuration"]
    
    def test_unknown_resource(self):
        """Test config retrieval for unknown resource returns generic config."""
        result = get_system_config("unknown-resource", "container_app")
        assert result["resource_name"] == "unknown-resource"
        assert "configuration" in result
        assert result["configuration"]["status"] == "running"
    
    def test_all_mock_resources(self):
        """Test all mock resources return valid config."""
        for resource_name in MOCK_RESOURCES:
            result = get_system_config(resource_name, "any")
            assert result["resource_name"] == resource_name
            assert "configuration" in result


class TestGetSystemMetrics:
    """Test get_system_metrics tool function."""
    
    def test_cpu_metrics(self):
        """Test CPU metrics retrieval."""
        result = get_system_metrics("web-app-prod", "cpu", "1h")
        assert "data" in result
        assert "cpu" in result["data"]
        assert "current_percent" in result["data"]["cpu"]
        assert "status" in result["data"]["cpu"]
    
    def test_all_metrics(self):
        """Test 'all' metric type returns all metrics."""
        result = get_system_metrics("web-app-prod", "all", "1h")
        assert "cpu" in result["data"]
        assert "memory" in result["data"]
        assert "latency" in result["data"]
        assert "requests" in result["data"]
        assert "errors" in result["data"]
    
    def test_web_app_prod_has_high_cpu(self):
        """Test web-app-prod shows high CPU (simulated issue)."""
        result = get_system_metrics("web-app-prod", "cpu", "1h")
        # CPU should be ~85% (simulated issue)
        assert result["data"]["cpu"]["current_percent"] >= 75
        assert result["data"]["cpu"]["status"] in ["warning", "critical"]
    
    def test_sql_db_has_high_latency(self):
        """Test sql-db-main shows high latency (simulated issue)."""
        result = get_system_metrics("sql-db-main", "latency", "1h")
        # Latency should be >500ms (simulated issue)
        assert result["data"]["latency"]["p50_ms"] >= 500
        assert result["data"]["latency"]["status"] == "critical"
    
    def test_time_range_included(self):
        """Test time range is included in response."""
        result = get_system_metrics("web-app-prod", "cpu", "24h")
        assert result["time_range"] == "24h"


class TestGetRecentLogs:
    """Test get_recent_logs tool function."""
    
    def test_returns_logs(self):
        """Test logs are returned."""
        result = get_recent_logs("web-app-prod", "all", 20)
        assert "logs" in result
        assert "count" in result
        assert len(result["logs"]) > 0
    
    def test_log_structure(self):
        """Test log entries have required structure."""
        result = get_recent_logs("web-app-prod", "all", 10)
        for log in result["logs"]:
            assert "timestamp" in log
            assert "severity" in log
            assert "message" in log
            assert "source" in log
    
    def test_error_filter(self):
        """Test error severity filter."""
        result = get_recent_logs("web-app-prod", "error", 20)
        for log in result["logs"]:
            assert log["severity"] == "error"
    
    def test_limit_respected(self):
        """Test limit parameter is respected."""
        result = get_recent_logs("web-app-prod", "all", 5)
        assert len(result["logs"]) <= 5
    
    def test_logs_sorted_by_time(self):
        """Test logs are sorted by timestamp (most recent first)."""
        result = get_recent_logs("web-app-prod", "all", 10)
        timestamps = [log["timestamp"] for log in result["logs"]]
        assert timestamps == sorted(timestamps, reverse=True)


class TestGetServiceHealth:
    """Test get_service_health tool function."""
    
    def test_healthy_service(self):
        """Test healthy service returns healthy status."""
        result = get_service_health("Container Apps", "eastus")
        assert result["status"] == "healthy"
        assert result["active_incidents"] == []
    
    def test_azure_sql_eastus_degraded(self):
        """Test Azure SQL in eastus shows degraded status (simulated incident)."""
        result = get_service_health("Azure SQL", "eastus")
        assert result["status"] == "degraded"
        assert len(result["active_incidents"]) > 0
        assert "incident_id" in result["active_incidents"][0]
    
    def test_service_and_region_in_response(self):
        """Test service and region are included in response."""
        result = get_service_health("Storage", "westus2")
        assert result["service"] == "Storage"
        assert result["region"] == "westus2"


class TestGetRecentChanges:
    """Test get_recent_changes tool function."""
    
    def test_returns_changes(self):
        """Test changes are returned."""
        result = get_recent_changes("web-app-prod", 7)
        assert "changes" in result
        assert "change_count" in result
        assert len(result["changes"]) > 0
    
    def test_change_structure(self):
        """Test change entries have required structure."""
        result = get_recent_changes("web-app-prod", 7)
        for change in result["changes"]:
            assert "timestamp" in change
            assert "type" in change
            assert "description" in change
            assert "user" in change
    
    def test_time_period_included(self):
        """Test time period is included in response."""
        result = get_recent_changes("web-app-prod", 14)
        assert result["time_period_days"] == 14


class TestCheckDependencies:
    """Test check_dependencies tool function."""
    
    def test_known_resource_dependencies(self):
        """Test dependencies for known resource."""
        result = check_dependencies("web-app-prod")
        assert "upstream_dependencies" in result
        assert "downstream_dependencies" in result
        assert len(result["upstream_dependencies"]) > 0
        assert "sql-db-main" in result["upstream_dependencies"]
    
    def test_unknown_resource_dependencies(self):
        """Test dependencies for unknown resource returns empty lists."""
        result = check_dependencies("unknown-resource")
        assert result["upstream_dependencies"] == []
        assert result["downstream_dependencies"] == []
    
    def test_dependency_counts(self):
        """Test dependency counts are correct."""
        result = check_dependencies("web-app-prod")
        assert result["upstream_count"] == len(result["upstream_dependencies"])
        assert result["downstream_count"] == len(result["downstream_dependencies"])


class TestGetResourceDetails:
    """Test get_resource_details tool function."""
    
    def test_known_resource_details(self):
        """Test details for known resource."""
        result = get_resource_details("web-app-prod")
        assert result["resource_name"] == "web-app-prod"
        assert result["resource_type"] == "container_app"
        assert result["resource_group"] == "rg-production"
        assert "tags" in result
        assert "provisioning_state" in result
    
    def test_unknown_resource_details(self):
        """Test details for unknown resource returns error."""
        result = get_resource_details("unknown-resource")
        assert "error" in result
        assert "suggestion" in result
    
    def test_resource_id_format(self):
        """Test resource ID has correct ARM format."""
        result = get_resource_details("web-app-prod")
        assert result["resource_id"].startswith("/subscriptions/")
        assert "/resourceGroups/" in result["resource_id"]


class TestToolFunctionExports:
    """Test that all tools referenced in TOOL_DEFINITIONS are exportable."""
    
    def test_all_tool_functions_exist(self):
        """Verify all defined tools have corresponding functions."""
        from tools import (
            get_system_config,
            get_system_metrics,
            get_recent_logs,
            get_service_health,
            get_recent_changes,
            check_dependencies,
            get_resource_details,
        )
        
        tool_name_to_function = {
            "get_system_config": get_system_config,
            "get_system_metrics": get_system_metrics,
            "get_recent_logs": get_recent_logs,
            "get_service_health": get_service_health,
            "get_recent_changes": get_recent_changes,
            "check_dependencies": check_dependencies,
            "get_resource_details": get_resource_details,
        }
        
        for tool in TOOL_DEFINITIONS:
            name = tool["function"]["name"]
            assert name in tool_name_to_function, f"No function exported for tool: {name}"
            assert callable(tool_name_to_function[name])


class TestAgenticScenarios:
    """Test realistic scenarios an agent might encounter."""
    
    def test_investigate_slow_web_app(self):
        """Simulate investigating a slow web app report."""
        # Step 1: Get resource details
        details = get_resource_details("web-app-prod")
        assert details["resource_type"] == "container_app"
        
        # Step 2: Check metrics
        metrics = get_system_metrics("web-app-prod", "all", "1h")
        assert metrics["data"]["cpu"]["status"] in ["warning", "critical"]
        
        # Step 3: Check dependencies
        deps = check_dependencies("web-app-prod")
        assert "sql-db-main" in deps["upstream_dependencies"]
        
        # Step 4: Check dependency health
        sql_metrics = get_system_metrics("sql-db-main", "latency", "1h")
        assert sql_metrics["data"]["latency"]["status"] == "critical"
        
        # Step 5: Check service health
        service_health = get_service_health("Azure SQL", "eastus")
        assert service_health["status"] == "degraded"
    
    def test_investigate_error_spike(self):
        """Simulate investigating an error spike."""
        # Check logs for errors
        logs = get_recent_logs("api-gateway", "error", 10)
        assert len(logs["logs"]) > 0
        
        # Check error metrics
        metrics = get_system_metrics("api-gateway", "errors", "1h")
        assert metrics["data"]["errors"]["total"] > 100
        
        # Check recent changes
        changes = get_recent_changes("api-gateway", 7)
        assert len(changes["changes"]) > 0
