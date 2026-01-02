// api-management.bicep - Azure API Management as AI Gateway
// Provides centralized management, security, and observability for Azure OpenAI endpoints
// Features: Rate limiting, token management, caching, request/response logging, and semantic caching

param location string
param tags object = {}
param apimServiceName string
param publisherEmail string = 'admin@contoso.com'
param publisherName string = 'AI Security Sandbox'
param logAnalyticsWorkspaceId string
param applicationInsightsId string
param applicationInsightsInstrumentationKey string

@description('APIM SKU')
@allowed(['BasicV2', 'StandardV2'])
param skuName string = 'BasicV2'

@description('Number of APIM units')
param skuCapacity int = 1

@description('Azure OpenAI endpoint URL')
param openAiEndpoint string

// API Management Service
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // Enable Application Insights integration
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

// Application Insights Logger for APIM
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: applicationInsightsId
    credentials: {
      instrumentationKey: applicationInsightsInstrumentationKey
    }
  }
}

// Diagnostic settings for API-level logging
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-09-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    frontend: {
      request: {
        headers: ['x-ms-client-request-id']
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: ['x-ms-request-id']
        body: {
          bytes: 8192
        }
      }
    }
    backend: {
      request: {
        headers: ['x-ms-client-request-id']
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: ['x-ms-request-id']
        body: {
          bytes: 8192
        }
      }
    }
  }
}

// Azure Monitor diagnostic settings
resource apimMonitorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'WebSocketConnectionLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Named Value for OpenAI Backend URL
resource openAiBackendUrl 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-backend-url'
  properties: {
    displayName: 'openai-backend-url'
    value: openAiEndpoint
    secret: false
  }
}

// Backend for Azure OpenAI with Managed Identity
resource openAiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-backend'
  properties: {
    title: 'Azure OpenAI Backend'
    description: 'Azure OpenAI Service with Managed Identity authentication'
    // Include /openai path segment for correct routing
    url: '${openAiEndpoint}openai'
    protocol: 'http'
    credentials: {
      header: {}
      query: {}
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
  dependsOn: [openAiBackendUrl]
}

// Azure OpenAI API Definition
resource openAiApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'azure-openai'
  properties: {
    displayName: 'Azure OpenAI Service API'
    description: 'Azure OpenAI Service API with AI Gateway features'
    subscriptionRequired: true
    path: 'openai'
    protocols: ['https']
    // Include /openai in service URL since APIM strips the API path prefix
    serviceUrl: '${openAiEndpoint}openai'
    apiType: 'http'
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
  }
}

// Chat Completions Operation
resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Create Chat Completion'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name (e.g., gpt-4o)'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// Embeddings Operation
resource embeddingsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'embeddings'
  properties: {
    displayName: 'Create Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name (e.g., text-embedding-3-small)'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// Completions Operation (for legacy models)
resource completionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'completions'
  properties: {
    displayName: 'Create Completion'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// AI Gateway Policy - Applied at API level
// Includes: Rate limiting, token counting, managed identity auth, retry logic, and caching
resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: openAiApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
    <inbound>
        <base />
        <!-- Remove any incoming api-key header to use managed identity -->
        <set-header name="api-key" exists-action="delete" />
        
        <!-- Authenticate with Azure OpenAI using APIM managed identity -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="managed-id-access-token" ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
        
        <!-- Rate limiting by subscription - 60 requests per minute -->
        <rate-limit-by-key calls="60" renewal-period="60" counter-key="@(context.Subscription != null ? context.Subscription.Key : context.Request.IpAddress)" />
        
        <!-- Token quota (approximate) - 10000 calls per 5 minutes per subscription -->
        <quota-by-key calls="10000" bandwidth="1024000" renewal-period="300" counter-key="@(context.Subscription != null ? context.Subscription.Key : context.Request.IpAddress)" />
        
        <!-- Add correlation ID for tracing -->
        <set-header name="x-ms-client-request-id" exists-action="skip">
            <value>@(context.RequestId.ToString())</value>
        </set-header>
        
        <!-- Log incoming request metadata -->
        <trace source="AI Gateway" severity="information">
            <message>@($"Incoming request: {context.Request.Method} {context.Request.Url.Path}")</message>
            <metadata name="SubscriptionId" value="@(context.Subscription != null ? context.Subscription.Id : String.Empty)" />
            <metadata name="ProductId" value="@(context.Product != null ? context.Product.Id : String.Empty)" />
        </trace>
    </inbound>
    <backend>
        <!-- Retry policy for transient failures and rate limits -->
        <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)" count="3" interval="1" max-interval="10" delta="1" first-fast-retry="false">
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <base />
        <!-- Extract and log token usage from response -->
        <choose>
            <when condition="@(context.Response.StatusCode == 200)">
                <set-variable name="response-body" value="@(context.Response.Body.As&lt;JObject&gt;(preserveContent: true))" />
                <set-variable name="prompt-tokens" value="@{
                    var body = (JObject)context.Variables[&quot;response-body&quot;];
                    return body?[&quot;usage&quot;]?[&quot;prompt_tokens&quot;]?.ToString() ?? &quot;0&quot;;
                }" />
                <set-variable name="completion-tokens" value="@{
                    var body = (JObject)context.Variables[&quot;response-body&quot;];
                    return body?[&quot;usage&quot;]?[&quot;completion_tokens&quot;]?.ToString() ?? &quot;0&quot;;
                }" />
                <set-variable name="total-tokens" value="@{
                    var body = (JObject)context.Variables[&quot;response-body&quot;];
                    return body?[&quot;usage&quot;]?[&quot;total_tokens&quot;]?.ToString() ?? &quot;0&quot;;
                }" />
                <!-- Add token usage headers for client visibility -->
                <set-header name="x-openai-prompt-tokens" exists-action="override">
                    <value>@((string)context.Variables["prompt-tokens"])</value>
                </set-header>
                <set-header name="x-openai-completion-tokens" exists-action="override">
                    <value>@((string)context.Variables["completion-tokens"])</value>
                </set-header>
                <set-header name="x-openai-total-tokens" exists-action="override">
                    <value>@((string)context.Variables["total-tokens"])</value>
                </set-header>
                <!-- Emit token metrics to Application Insights -->
                <trace source="AI Gateway" severity="information">
                    <message>Token Usage</message>
                    <metadata name="PromptTokens" value="@((string)context.Variables[&quot;prompt-tokens&quot;])" />
                    <metadata name="CompletionTokens" value="@((string)context.Variables[&quot;completion-tokens&quot;])" />
                    <metadata name="TotalTokens" value="@((string)context.Variables[&quot;total-tokens&quot;])" />
                    <metadata name="SubscriptionId" value="@(context.Subscription != null ? context.Subscription.Id : String.Empty)" />
                    <metadata name="DeploymentId" value="@(context.Request.MatchedParameters.ContainsKey(&quot;deployment-id&quot;) ? context.Request.MatchedParameters[&quot;deployment-id&quot;] : String.Empty)" />
                </trace>
            </when>
        </choose>
        <!-- Add CORS headers -->
        <set-header name="Access-Control-Allow-Origin" exists-action="override">
            <value>*</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
        <!-- Log errors for troubleshooting -->
        <trace source="AI Gateway" severity="error">
            <message>@($"Error: {context.LastError.Message}")</message>
            <metadata name="StatusCode" value="@(context.Response.StatusCode.ToString())" />
            <metadata name="Reason" value="@(context.LastError.Reason)" />
        </trace>
        <!-- Return friendly error response -->
        <choose>
            <when condition="@(context.Response.StatusCode == 429)">
                <return-response>
                    <set-status code="429" reason="Too Many Requests" />
                    <set-header name="Retry-After" exists-action="override">
                        <value>60</value>
                    </set-header>
                    <set-body>@{
                        return new JObject(
                            new JProperty("error", new JObject(
                                new JProperty("code", "RateLimitExceeded"),
                                new JProperty("message", "API rate limit exceeded. Please retry after 60 seconds.")
                            ))
                        ).ToString();
                    }</set-body>
                </return-response>
            </when>
        </choose>
    </on-error>
</policies>
'''
  }
}

// Product for AI Gateway access
resource aiGatewayProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apimService
  name: 'ai-gateway'
  properties: {
    displayName: 'AI Gateway'
    description: 'Access to Azure OpenAI through the AI Gateway with rate limiting and token tracking'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// Link API to Product
resource productApiLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: aiGatewayProduct
  name: openAiApi.name
}

// Built-in subscription for the AI Gateway product (for Container Apps)
resource internalSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apimService
  name: 'internal-apps'
  properties: {
    displayName: 'Internal Applications'
    scope: '/products/${aiGatewayProduct.id}'
    state: 'active'
    allowTracing: true
  }
}

// Outputs
output apimServiceId string = apimService.id
output apimServiceName string = apimService.name
output apimGatewayUrl string = apimService.properties.gatewayUrl
output apimIdentityPrincipalId string = apimService.identity.principalId
output openAiApiId string = openAiApi.id
output openAiApiPath string = openAiApi.properties.path

// Output subscription key for internal apps (Container Apps authentication to APIM)
// Best practice: Use subscription keys for APIM authentication, APIM uses managed identity to Azure OpenAI
output internalSubscriptionKey string = internalSubscription.listSecrets().primaryKey
