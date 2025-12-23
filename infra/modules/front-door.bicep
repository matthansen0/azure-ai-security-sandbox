// front-door.bicep - Azure Front Door Premium with WAF

param tags object = {}
param frontDoorProfileName string
param frontDoorEndpointName string
param wafPolicyName string
param originHostName string

// Front Door Premium Profile (required for WAF)
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: frontDoorProfileName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
      customBlockResponseStatusCode: 403
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
    }
  }
}

// Front Door Endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: frontDoorEndpointName
  location: 'Global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'appservice-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 120
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin (App Service)
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'appservice-origin'
  properties: {
    hostName: originHostName
    originHostHeader: originHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Route
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: frontDoorEndpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    originPath: '/'
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [origin]
}

// Security Policy (associates WAF with endpoint)
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: frontDoorProfile
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

// App Service access restriction (only allow Front Door)
// This is handled via a separate module call to avoid circular dependencies
// The app service needs to be configured to only accept traffic from Front Door

output frontDoorProfileId string = frontDoorProfile.id
output frontDoorProfileName string = frontDoorProfile.name
output frontDoorEndpointId string = frontDoorEndpoint.id
output frontDoorEndpointHostName string = frontDoorEndpoint.properties.hostName
output wafPolicyId string = wafPolicy.id
