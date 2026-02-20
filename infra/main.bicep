// PIM Expiry Tracker — Azure Infrastructure as Code (Bicep)
// Deploys: Function App (PowerShell), Storage, Event Grid Topic, App Insights, Role Assignments

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Function App')
param functionAppName string

@description('Name of the Event Grid Topic')
param eventGridTopicName string = '${functionAppName}-topic'

@description('CRON schedule for the timer trigger (default: daily 2 AM UTC)')
param timerSchedule string = '0 0 2 * * *'

@description('Alert threshold in days for expiring PIM assignments')
@minValue(1)
param thresholdDays int = 30

@description('Name of the Application Insights instance')
param applicationInsightsName string = 'ai-${functionAppName}'

// ---------- Storage (Managed Identity access — no keys) ----------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${uniqueString(resourceGroup().id, functionAppName)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

// ---------- Application Insights ----------

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// ---------- Event Grid Topic ----------

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-06-01-preview' = {
  name: eventGridTopicName
  location: location
  sku: { name: 'Basic' }
  identity: { type: 'None' }
}

// ---------- App Service Plan (Consumption / Windows) ----------

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${functionAppName}'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: false  // Windows
  }
}

// ---------- Function App ----------

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_TOPIC_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'TimerSchedule'
          value: timerSchedule
        }
        {
          name: 'ThresholdDays'
          value: string(thresholdDays)
        }
      ]
    }
  }
}

// ---------- RBAC: Function MI → Storage Blob Data Owner ----------

resource storageBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b') // Storage Blob Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- RBAC: Function MI → Storage Account Contributor ----------

resource storageAccountContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- RBAC: Function MI → Storage Queue Data Contributor ----------

resource storageQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88') // Storage Queue Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- RBAC: Function MI → Event Grid Data Sender ----------

resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'd5a91429-5739-47e2-a06b-3470a27159e7')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- Outputs ----------

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output storageAccountName string = storageAccount.name
output managedIdentityPrincipalId string = functionApp.identity.principalId
output applicationInsightsName string = appInsights.name
