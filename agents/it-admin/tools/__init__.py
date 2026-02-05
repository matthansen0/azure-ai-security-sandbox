# IT Admin Agent Tools
# Mock implementations that return realistic Azure infrastructure data

from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
import random
import json
from pathlib import Path

# Load mock data from files
MOCK_DATA_DIR = Path(__file__).parent / "mock_data"

def _load_mock_data(filename: str) -> Dict[str, Any]:
    """Load mock data from JSON file."""
    filepath = MOCK_DATA_DIR / filename
    if filepath.exists():
        with open(filepath) as f:
            return json.load(f)
    return {}

# Tool definitions for OpenAI function calling
TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "get_system_config",
            "description": "Get the configuration of an Azure resource including SKU, settings, and deployment details",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource (e.g., 'web-app-prod', 'sql-db-main')"
                    },
                    "resource_type": {
                        "type": "string",
                        "description": "Type of resource (e.g., 'container_app', 'sql_database', 'storage_account', 'api_management')",
                        "enum": ["container_app", "sql_database", "storage_account", "api_management", "app_service", "cosmos_db", "redis_cache", "key_vault"]
                    }
                },
                "required": ["resource_name", "resource_type"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_system_metrics",
            "description": "Get performance metrics for an Azure resource including CPU, memory, latency, request counts, and errors",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource"
                    },
                    "metric_type": {
                        "type": "string",
                        "description": "Type of metrics to retrieve",
                        "enum": ["cpu", "memory", "latency", "requests", "errors", "all"]
                    },
                    "time_range": {
                        "type": "string",
                        "description": "Time range for metrics",
                        "enum": ["1h", "6h", "24h", "7d"],
                        "default": "1h"
                    }
                },
                "required": ["resource_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_recent_logs",
            "description": "Get recent log entries from an Azure resource, optionally filtered by severity",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource"
                    },
                    "severity": {
                        "type": "string",
                        "description": "Filter by log severity",
                        "enum": ["all", "error", "warning", "info"],
                        "default": "all"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of log entries to return",
                        "default": 20
                    }
                },
                "required": ["resource_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_health",
            "description": "Check Azure service health for known issues or outages in a region",
            "parameters": {
                "type": "object",
                "properties": {
                    "service": {
                        "type": "string",
                        "description": "Azure service to check (e.g., 'Azure SQL', 'Container Apps', 'Storage')",
                        "enum": ["Azure SQL", "Container Apps", "Storage", "Cosmos DB", "API Management", "App Service", "Azure OpenAI", "Redis Cache"]
                    },
                    "region": {
                        "type": "string",
                        "description": "Azure region (e.g., 'eastus', 'westus2')",
                        "default": "eastus"
                    }
                },
                "required": ["service"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_recent_changes",
            "description": "Get recent deployments, configuration changes, and updates for a resource",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource"
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of days to look back",
                        "default": 7
                    }
                },
                "required": ["resource_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "check_dependencies",
            "description": "List the upstream and downstream dependencies of a resource",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource"
                    }
                },
                "required": ["resource_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_resource_details",
            "description": "Get comprehensive details about an Azure resource including its resource group, subscription, and tags",
            "parameters": {
                "type": "object",
                "properties": {
                    "resource_name": {
                        "type": "string",
                        "description": "Name of the Azure resource"
                    }
                },
                "required": ["resource_name"]
            }
        }
    }
]


# ============ Mock Data for Various Systems ============

MOCK_RESOURCES = {
    "web-app-prod": {
        "type": "container_app",
        "resource_group": "rg-production",
        "subscription": "prod-subscription",
        "region": "eastus",
        "tags": {"environment": "production", "team": "platform", "cost-center": "12345"},
        "config": {
            "sku": "D4",
            "replicas": {"min": 2, "max": 10, "current": 4},
            "cpu": "2.0",
            "memory": "4Gi",
            "image": "myregistry.azurecr.io/webapp:v2.3.1",
            "ingress": {"external": True, "targetPort": 8080},
            "environment_variables": ["DATABASE_URL", "REDIS_URL", "API_KEY"],
            "managed_identity": True
        },
        "dependencies": {
            "upstream": ["sql-db-main", "redis-cache-prod", "storage-prod"],
            "downstream": ["api-gateway", "cdn-endpoint"]
        }
    },
    "sql-db-main": {
        "type": "sql_database",
        "resource_group": "rg-production",
        "subscription": "prod-subscription",
        "region": "eastus",
        "tags": {"environment": "production", "team": "data", "cost-center": "12345"},
        "config": {
            "sku": "GP_Gen5_4",
            "tier": "GeneralPurpose",
            "max_size_gb": 256,
            "current_size_gb": 127,
            "backup_retention_days": 35,
            "geo_redundant_backup": True,
            "connection_policy": "Default",
            "tls_version": "1.2"
        },
        "dependencies": {
            "upstream": [],
            "downstream": ["web-app-prod", "reporting-service", "etl-pipeline"]
        }
    },
    "api-gateway": {
        "type": "api_management",
        "resource_group": "rg-production",
        "subscription": "prod-subscription",
        "region": "eastus",
        "tags": {"environment": "production", "team": "platform"},
        "config": {
            "sku": "Premium",
            "capacity": 2,
            "gateway_url": "https://api.contoso.com",
            "developer_portal": True,
            "virtual_network": "internal",
            "certificates": 3,
            "apis": 12,
            "products": 4
        },
        "dependencies": {
            "upstream": ["web-app-prod", "auth-service"],
            "downstream": ["mobile-app", "partner-integrations"]
        }
    },
    "redis-cache-prod": {
        "type": "redis_cache",
        "resource_group": "rg-production",
        "subscription": "prod-subscription",
        "region": "eastus",
        "tags": {"environment": "production", "team": "platform"},
        "config": {
            "sku": "Premium",
            "capacity": 1,
            "family": "P",
            "shard_count": 2,
            "tls_enabled": True,
            "non_ssl_port_enabled": False,
            "max_memory_policy": "volatile-lru"
        },
        "dependencies": {
            "upstream": [],
            "downstream": ["web-app-prod", "session-service"]
        }
    },
    "storage-prod": {
        "type": "storage_account",
        "resource_group": "rg-production",
        "subscription": "prod-subscription",
        "region": "eastus",
        "tags": {"environment": "production", "team": "platform"},
        "config": {
            "sku": "Standard_GRS",
            "kind": "StorageV2",
            "access_tier": "Hot",
            "https_only": True,
            "min_tls_version": "TLS1_2",
            "blob_public_access": False,
            "containers": ["uploads", "exports", "backups", "logs"]
        },
        "dependencies": {
            "upstream": [],
            "downstream": ["web-app-prod", "backup-service", "log-analytics"]
        }
    }
}


def _generate_metrics(resource_name: str, metric_type: str, time_range: str) -> Dict[str, Any]:
    """Generate realistic-looking metrics based on resource and type."""
    
    # Simulate some performance issues for certain resources
    has_cpu_issue = resource_name == "web-app-prod"
    has_latency_issue = resource_name == "sql-db-main"
    has_error_spike = resource_name == "api-gateway"
    
    now = datetime.utcnow()
    
    metrics = {
        "resource": resource_name,
        "time_range": time_range,
        "collected_at": now.isoformat(),
        "data": {}
    }
    
    if metric_type in ["cpu", "all"]:
        base_cpu = 85 if has_cpu_issue else 35
        metrics["data"]["cpu"] = {
            "current_percent": base_cpu + random.randint(-5, 10),
            "average_percent": base_cpu - 5,
            "max_percent": base_cpu + 15,
            "min_percent": base_cpu - 20,
            "status": "critical" if has_cpu_issue else "healthy"
        }
    
    if metric_type in ["memory", "all"]:
        base_mem = 70 if has_cpu_issue else 45
        metrics["data"]["memory"] = {
            "current_percent": base_mem + random.randint(-5, 10),
            "average_percent": base_mem - 3,
            "used_gb": round(base_mem * 0.04, 2),
            "available_gb": round((100 - base_mem) * 0.04, 2),
            "status": "warning" if has_cpu_issue else "healthy"
        }
    
    if metric_type in ["latency", "all"]:
        base_latency = 850 if has_latency_issue else 45
        metrics["data"]["latency"] = {
            "p50_ms": base_latency,
            "p95_ms": base_latency * 2.5,
            "p99_ms": base_latency * 4,
            "average_ms": base_latency * 1.2,
            "status": "critical" if has_latency_issue else "healthy"
        }
    
    if metric_type in ["requests", "all"]:
        metrics["data"]["requests"] = {
            "total": random.randint(50000, 150000),
            "successful": random.randint(45000, 145000),
            "failed": random.randint(100, 2000) if has_error_spike else random.randint(10, 100),
            "rate_per_second": random.randint(50, 200)
        }
    
    if metric_type in ["errors", "all"]:
        error_count = random.randint(500, 2000) if has_error_spike else random.randint(5, 50)
        metrics["data"]["errors"] = {
            "total": error_count,
            "rate_percent": round(error_count / 1000 * 100, 2),
            "by_type": {
                "500": int(error_count * 0.4),
                "502": int(error_count * 0.3),
                "503": int(error_count * 0.2),
                "timeout": int(error_count * 0.1)
            },
            "status": "critical" if has_error_spike else "healthy"
        }
    
    return metrics


def _generate_logs(resource_name: str, severity: str, limit: int) -> List[Dict[str, Any]]:
    """Generate realistic log entries."""
    
    now = datetime.utcnow()
    logs = []
    
    # Templates for different log types
    error_templates = [
        ("Connection to database timed out after 30s", "sql-db-main"),
        ("Redis connection pool exhausted, waiting for available connection", "redis-cache-prod"),
        ("Request failed with status 503: Service Unavailable", "api-gateway"),
        ("Out of memory: Container killed by OOM killer", "web-app-prod"),
        ("SSL certificate validation failed for upstream", "api-gateway"),
        ("Rate limit exceeded for client IP 203.0.113.42", "api-gateway"),
    ]
    
    warning_templates = [
        ("High CPU utilization detected (>80%)", "web-app-prod"),
        ("Query execution time exceeded threshold (>5s)", "sql-db-main"),
        ("Cache miss rate above normal (>30%)", "redis-cache-prod"),
        ("Slow response detected from downstream service", "web-app-prod"),
        ("Certificate expires in 14 days", "api-gateway"),
        ("Storage account approaching 80% capacity", "storage-prod"),
    ]
    
    info_templates = [
        ("Successfully scaled to 4 replicas", "web-app-prod"),
        ("Deployment completed: v2.3.1", "web-app-prod"),
        ("Database backup completed successfully", "sql-db-main"),
        ("Health check passed", "web-app-prod"),
        ("Configuration reloaded", "api-gateway"),
    ]
    
    # Generate logs based on severity filter
    templates_to_use = []
    if severity in ["all", "error"]:
        templates_to_use.extend([(t, "error", r) for t, r in error_templates])
    if severity in ["all", "warning"]:
        templates_to_use.extend([(t, "warning", r) for t, r in warning_templates])
    if severity in ["all", "info"]:
        templates_to_use.extend([(t, "info", r) for t, r in info_templates])
    
    # Filter by resource if specific resource requested
    if resource_name != "all":
        templates_to_use = [t for t in templates_to_use if t[2] == resource_name or t[2] == "web-app-prod"]
    
    # Generate log entries
    for i in range(min(limit, len(templates_to_use) * 3)):
        template = random.choice(templates_to_use) if templates_to_use else ("No logs available", "info", resource_name)
        timestamp = now - timedelta(minutes=random.randint(1, 360))
        
        logs.append({
            "timestamp": timestamp.isoformat(),
            "severity": template[1],
            "message": template[0],
            "source": template[2],
            "correlation_id": f"corr-{random.randint(10000, 99999)}"
        })
    
    # Sort by timestamp descending
    logs.sort(key=lambda x: x["timestamp"], reverse=True)
    return logs[:limit]


def _generate_changes(resource_name: str, days: int) -> List[Dict[str, Any]]:
    """Generate recent change history."""
    
    now = datetime.utcnow()
    changes = []
    
    change_templates = [
        {
            "type": "deployment",
            "description": "Deployed new version v2.3.1",
            "user": "deploy-pipeline@contoso.com",
            "details": {"old_version": "v2.3.0", "new_version": "v2.3.1", "replicas": 4}
        },
        {
            "type": "configuration",
            "description": "Updated environment variable DATABASE_TIMEOUT",
            "user": "john.smith@contoso.com",
            "details": {"setting": "DATABASE_TIMEOUT", "old_value": "30", "new_value": "60"}
        },
        {
            "type": "scaling",
            "description": "Auto-scaled from 2 to 4 replicas",
            "user": "system",
            "details": {"trigger": "cpu_threshold", "old_replicas": 2, "new_replicas": 4}
        },
        {
            "type": "configuration",
            "description": "Increased max connections pool size",
            "user": "jane.doe@contoso.com", 
            "details": {"setting": "MAX_POOL_SIZE", "old_value": "100", "new_value": "200"}
        },
        {
            "type": "security",
            "description": "Rotated managed identity credentials",
            "user": "security-automation@contoso.com",
            "details": {"credential_type": "managed_identity"}
        },
    ]
    
    # Generate changes spread over the time period
    for i in range(min(days, len(change_templates))):
        template = change_templates[i]
        timestamp = now - timedelta(days=random.randint(0, days), hours=random.randint(0, 23))
        
        changes.append({
            "timestamp": timestamp.isoformat(),
            "resource": resource_name,
            **template
        })
    
    changes.sort(key=lambda x: x["timestamp"], reverse=True)
    return changes


# ============ Tool Implementation Functions ============

def get_system_config(resource_name: str, resource_type: str) -> Dict[str, Any]:
    """Get configuration details for an Azure resource."""
    
    if resource_name in MOCK_RESOURCES:
        resource = MOCK_RESOURCES[resource_name]
        return {
            "resource_name": resource_name,
            "resource_type": resource["type"],
            "region": resource["region"],
            "resource_group": resource["resource_group"],
            "configuration": resource["config"],
            "tags": resource["tags"]
        }
    
    # Return generic config for unknown resources
    return {
        "resource_name": resource_name,
        "resource_type": resource_type,
        "region": "eastus",
        "resource_group": "rg-production",
        "configuration": {
            "status": "running",
            "sku": "Standard",
            "note": "Generic configuration - resource not found in detailed inventory"
        },
        "tags": {"environment": "production"}
    }


def get_system_metrics(resource_name: str, metric_type: str = "all", time_range: str = "1h") -> Dict[str, Any]:
    """Get performance metrics for an Azure resource."""
    return _generate_metrics(resource_name, metric_type, time_range)


def get_recent_logs(resource_name: str, severity: str = "all", limit: int = 20) -> Dict[str, Any]:
    """Get recent log entries from an Azure resource."""
    logs = _generate_logs(resource_name, severity, limit)
    return {
        "resource": resource_name,
        "severity_filter": severity,
        "count": len(logs),
        "logs": logs
    }


def get_service_health(service: str, region: str = "eastus") -> Dict[str, Any]:
    """Check Azure service health for known issues."""
    
    # Simulate a service issue for SQL in eastus
    if service == "Azure SQL" and region == "eastus":
        return {
            "service": service,
            "region": region,
            "status": "degraded",
            "active_incidents": [
                {
                    "incident_id": "SQL-2024-0215",
                    "title": "Intermittent connectivity issues",
                    "status": "investigating",
                    "start_time": (datetime.utcnow() - timedelta(hours=2)).isoformat(),
                    "description": "Some customers may experience intermittent connection timeouts to Azure SQL databases in East US region.",
                    "impacted_services": ["Azure SQL Database", "SQL Managed Instance"],
                    "updates": [
                        {
                            "time": (datetime.utcnow() - timedelta(minutes=30)).isoformat(),
                            "message": "Engineering team has identified the root cause and is implementing a fix."
                        }
                    ]
                }
            ]
        }
    
    return {
        "service": service,
        "region": region,
        "status": "healthy",
        "active_incidents": [],
        "message": f"No known issues affecting {service} in {region}"
    }


def get_recent_changes(resource_name: str, days: int = 7) -> Dict[str, Any]:
    """Get recent changes for a resource."""
    changes = _generate_changes(resource_name, days)
    return {
        "resource": resource_name,
        "time_period_days": days,
        "change_count": len(changes),
        "changes": changes
    }


def check_dependencies(resource_name: str) -> Dict[str, Any]:
    """List dependencies of a resource."""
    
    if resource_name in MOCK_RESOURCES:
        deps = MOCK_RESOURCES[resource_name]["dependencies"]
        return {
            "resource": resource_name,
            "upstream_dependencies": deps["upstream"],
            "downstream_dependencies": deps["downstream"],
            "upstream_count": len(deps["upstream"]),
            "downstream_count": len(deps["downstream"])
        }
    
    return {
        "resource": resource_name,
        "upstream_dependencies": [],
        "downstream_dependencies": [],
        "message": "Resource not found in dependency map"
    }


def get_resource_details(resource_name: str) -> Dict[str, Any]:
    """Get comprehensive details about an Azure resource."""
    
    if resource_name in MOCK_RESOURCES:
        resource = MOCK_RESOURCES[resource_name]
        return {
            "resource_name": resource_name,
            "resource_type": resource["type"],
            "resource_group": resource["resource_group"],
            "subscription": resource["subscription"],
            "region": resource["region"],
            "tags": resource["tags"],
            "provisioning_state": "Succeeded",
            "created_at": (datetime.utcnow() - timedelta(days=180)).isoformat(),
            "last_modified": (datetime.utcnow() - timedelta(hours=2)).isoformat(),
            "resource_id": f"/subscriptions/{resource['subscription']}/resourceGroups/{resource['resource_group']}/providers/Microsoft.App/containerApps/{resource_name}"
        }
    
    return {
        "resource_name": resource_name,
        "error": "Resource not found in inventory",
        "suggestion": "Check resource name spelling or verify the resource exists"
    }
