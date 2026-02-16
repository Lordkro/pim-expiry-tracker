// PIM Expiry Tracker — Azure Infrastructure as Code (Bicep)
// Deploys: Function App (PowerShell), Storage, Event Grid Topic, Role Assignments

param location string = resourceGroup().location
param functionAppName string
param eventGridTopicName string = '${functionAppName}-topic'
param timerSchedule string = '0 0 2 * * *'  // daily 2 AM UTC
param thresholdDays int = 30
param applicationInsightsName string = 'ai-${functionAppName}'

// Storage account for function
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${uniqueString(resourceGroup().id, functionAppName)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-06-01' = {
  name: eventGridTopicName
  location: location
  kind: 'azure'
  sku: {
    name: 'Basic'
  }
}

// App Service plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-03-01' = {
  name: 'asp-${functionAppName}'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value};EndpointSuffix=core.windows.net'
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
          name: 'EVENT_GRID_TOPIC_URL'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_TOPIC_KEY'
          value: listKeys(eventGridTopic.id, eventGridTopic.apiVersion).key1
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
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/azure-functions/powershell:4'
    }
  }
  dependsOn: [
    storageAccount
    appInsights
    eventGridTopic
  ]
}

// Role Assignment: Function MI -> EventGrid Topic Data Sender (to publish to topic)
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.identity.principalId, 'b0e97697-49f0-4b64-8b2c-1a8e5f9083a5') // EventGrid Topic Sender role def ID
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0e97697-49f0-4b64-8b2c-1a8e5f9083a5') // EventGrid Topic Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    functionApp
    eventGridTopic
  ]
}

// Outputs
output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output storageAccountName string = storageAccount.name
output managedIdentityPrincipalId string = functionApp.identity.principalId
output applicationInsightsName string = appInsights.name

