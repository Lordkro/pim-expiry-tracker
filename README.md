# PIM Expiry Tracker

Automated Azure Function that scans Privileged Identity Management (PIM) eligible role assignments and raises alerts for roles expiring soon. Deployable to client tenants via Bicep IaC.

## Architecture

```
Timer Trigger (daily 2 AM) → Azure Function (PowerShell)
   ↓
Microsoft Graph API (Managed Identity auth)
   ↓
Query: roleEligibilityScheduleInstances, users, role definitions
   ↓
Filter by threshold (e.g., <30 days remaining)
   ↓
Publish events to Event Grid Topic
   ↓
Event Grid subscription → Jira / ServiceNow / Webhook / Logic App
```

## What it does

- Runs daily (configurable schedule)
- Connects to Microsoft Graph using Managed Identity (no secrets)
- Fetches all users in the tenant
- Fetches all eligible PIM role assignments (`/beta/roleManagement/directory/roleEligibilityScheduleInstances`)
- Calculates days remaining until role expiry
- Filters assignments where `DaysRemaining < threshold` (default: 30)
- Publishes an Event Grid event for each expiring assignment
- Event Grid can forward to Jira, ServiceNow, Teams, etc.

## Output Event Grid Schema

```json
{
  "id": "guid",
  "eventType": "PimRoleExpiringSoon",
  "subject": "PIM Role Expiry: user@domain.com - Role Display Name",
  "eventTime": "2025-02-16T02:00:00Z",
  "data": {
    "CollectedAt": "2025-02-16T02:00:00Z",
    "UserPrincipalName": "user@domain.com",
    "RoleName": "Global Administrator",
    "AssignmentId": "guid",
    "EndDateTime": "2025-03-18T00:00:00Z",
    "DaysRemaining": 30
  },
  "dataVersion": "1.0"
}
```

## Prerequisites

- Azure CLI / PowerShell with Az module
- Tenant admin permissions to:
  - Create resources (Function App, Storage, Event Grid Topic)
  - Grant Managed Identity Graph permissions: `User.Read.All` and `RoleManagement.Read.All` (application permissions)

## Deployment

### 1. Clone and prepare

```bash
git clone https://github.com/yourorg/pim-expiry-tracker.git
cd pim-expiry-tracker
```

### 2. Create parameters file

Copy `parameters.example.json` to `parameters.json` and customize:

```json
{
  "functionAppName": "pim-expiry-tracker-<client>",
  "location": "westeurope",
  "eventGridTopicName": "pim-expiry-topic",
  "timerSchedule": "0 0 2 * * *",
  "thresholdDays": 30,
  "applicationInsightsName": "ai-pim-expiry-tracker-<client>"
}
```

### 3. Deploy infrastructure

```bash
az login
az group create --name rg-pim-tracker --location westeurope

az deployment group create \
  --resource-group rg-pim-tracker \
  --template-file main.bicep \
  --parameters @parameters.json
```

Output will include `managedIdentityPrincipalId`.

### 4. Grant Graph permissions to Managed Identity

Run the helper script (must be executed by a Global Admin or Privileged Role Administrator):

```powershell
.\Grant-GraphPermissions.ps1 -ManagedIdentityPrincipalId <principalId-from-output> -TenantId <tenant-id>
```

This assigns `User.Read.All` and `RoleManagement.Read.All` application permissions to the Managed Identity.

**Note:** After assigning application permissions, they may take a few minutes to propagate.

### 5. Deploy function code

```bash
# Package the function
func pack --csharp # if we had C#, but for PowerShell we just zip

# From repo root:
cd PimExpiryTracker
zip -r ../function.zip *

# Deploy
az functionapp deployment source config-zip \
  --resource-group rg-pim-tracker \
  --name <functionAppName> \
  --src ../function.zip
```

Alternatively, use `func azure functionapp publish <functionAppName>` if you have the Azure Functions Core Tools.

### 6. Create Event Grid subscription to route to your ticketing system

In Azure Portal:
- Go to the Event Grid Topic
- Create a new subscription
- Endpoint type: Webhook / Azure Function / Logic App / etc.
- Point to your Jira/ServiceNow webhook URL

Or use Azure CLI:

```bash
az eventgrid event-subscription create \
  --name "to-jira" \
  --source-resource-id $(az eventgrid topic show -g rg-pim-tracker -n pim-expiry-topic --query id -o tsv) \
  --endpoint <webhook-url> \
  --included-event-types "PimRoleExpiringSoon"
```

## Configuration

- **TimerSchedule**: CRON expression (default: daily 2 AM UTC)
- **ThresholdDays**: Alert if expiry within N days (default: 30)
- Set these in `parameters.json` during deployment.

## Testing

- Manually trigger the function: `az functionapp function run --name <app> --resource-group <rg> --function-name Run`
- Check Application Insights for logs
- Verify Event Grid events appear in the topic's metrics

## Cost Estimate (per tenant)

- Function App (Consumption): ~$0-5/month depending on executions
- Event Grid Topic: ~$0.60/month + operations
- Storage: ~$0.10/month
- Application Insights: ~$2-3/month
- **Total**: ~$5-10/month per client

## Multi-Tenant Deployment

This Bicep template is designed to be deployed into each client's Azure subscription/tenant. Use Azure Lighthouse or manual deployment as part of your managed services offering.

## Security

- No secrets stored in code
- Managed Identity for Azure resources
- No service principals with long-lived credentials
- Principle of least privilege: MI only has read access to Graph and write to Event Grid topic

## Roadmap

- [ ] Support for Azure AD PIM for Azure resources (not just Azure AD roles)
- [ ] Configurable filter by role type
- [ ] Include role activation eligibility (not just assignment)
- [ ] HTML email digest option
- [ ] Integration with Teams notifications

## License

MIT

---

**Built by Cass ⚡ for Lordkro**
