# PIM Expiry Tracker

Automated Azure Function that scans Privileged Identity Management (PIM) eligible role assignments and alerts on roles expiring soon. Deployable to client tenants via Bicep IaC.

## Architecture

```
Timer Trigger (daily 2 AM UTC) → Azure Function (PowerShell 7.4)
   ↓
Microsoft Graph API (Managed Identity — no secrets)
   ↓
Query: roleEligibilityScheduleInstances, users, role definitions
   ↓
Filter by threshold (e.g., < 30 days remaining)
   ↓
Publish events to Event Grid Topic (output binding)
   ↓
Event Grid subscription → Jira / ServiceNow / Webhook / Logic App
```

## What It Does

- Runs daily on a configurable schedule (CRON via app setting)
- Connects to Microsoft Graph using **Managed Identity** (no secrets)
- Fetches all users and builds a lookup by `principalId`
- Fetches all eligible PIM role assignments (`/beta/roleManagement/directory/roleEligibilityScheduleInstances`)
- Calculates days remaining until each role assignment expires
- Filters assignments where `DaysRemaining < ThresholdDays` (configurable, default: 30)
- Publishes an Event Grid event per expiring assignment via output binding
- Event Grid can forward to Jira, ServiceNow, Teams, Logic Apps, etc.

## Project Structure

```
pim-expiry-tracker/
├── infra/                         # Infrastructure as Code
│   ├── main.bicep                 # Bicep template (all Azure resources)
│   └── parameters.example.json   # Example deployment parameters
├── scripts/                       # Deployment & admin scripts
│   ├── Deploy.ps1                 # End-to-end deployment (RG + Bicep)
│   ├── Publish-FunctionCode.ps1   # Zip-deploy function code
│   └── Grant-GraphPermissions.ps1 # Assign Graph API permissions to MI
├── src/                           # Azure Function App code
│   ├── host.json                  # Functions host configuration
│   ├── profile.ps1                # PowerShell worker startup script
│   ├── requirements.psd1          # Managed dependency modules
│   └── Run/                       # Timer-triggered function
│       ├── function.json          # Trigger & output bindings
│       └── run.ps1                # Function entry point
└── README.md
```

## Output Event Schema

```json
{
  "id": "guid",
  "eventType": "PimRoleExpiringSoon",
  "subject": "PIM Role Expiry: user@domain.com - Global Administrator",
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

- Azure CLI installed
- An Azure subscription with permissions to create resources
- **Global Admin** or **Privileged Role Administrator** to grant Graph API permissions
- Required Graph application permissions (assigned to the Managed Identity):
  - `User.Read.All`
  - `RoleManagement.Read.All`

## Deployment

### 1. Clone and prepare

```bash
git clone https://github.com/yourorg/pim-expiry-tracker.git
cd pim-expiry-tracker
```

### 2. Create parameters file

Copy `infra/parameters.example.json` to `infra/parameters.json` and customise:

```json
{
  "functionAppName":          { "value": "pim-expiry-tracker-<client>" },
  "location":                 { "value": "westeurope" },
  "eventGridTopicName":       { "value": "pim-expiry-topic" },
  "timerSchedule":            { "value": "0 0 2 * * *" },
  "thresholdDays":            { "value": 30 },
  "applicationInsightsName":  { "value": "ai-pim-expiry-tracker-<client>" }
}
```

### 3. Deploy infrastructure

```powershell
az login

.\scripts\Deploy.ps1 -ResourceGroup rg-pim-tracker -Location westeurope -FunctionAppName pim-expiry-tracker-<client>
```

This will:
- Create the resource group (if it doesn't exist)
- Deploy all Azure resources via Bicep
- Output the Managed Identity principal ID for the next step

### 4. Grant Graph permissions to Managed Identity

Run as a **Global Admin** or **Privileged Role Administrator**:

```powershell
.\scripts\Grant-GraphPermissions.ps1 -ManagedIdentityPrincipalId <principalId-from-output> -TenantId <tenant-id>
```

> **Note:** Permissions may take a few minutes to propagate after assignment.

### 5. Deploy function code

```powershell
.\scripts\Publish-FunctionCode.ps1 -FunctionAppName pim-expiry-tracker-<client> -ResourceGroup rg-pim-tracker
```

### 6. Create Event Grid subscription

Route events to your ticketing system:

**Azure Portal:** Event Grid Topic → + Event Subscription → choose endpoint type (Webhook, Logic App, etc.)

**Azure CLI:**

```bash
az eventgrid event-subscription create \
  --name "to-jira" \
  --source-resource-id $(az eventgrid topic show -g rg-pim-tracker -n pim-expiry-topic --query id -o tsv) \
  --endpoint <webhook-url> \
  --included-event-types "PimRoleExpiringSoon"
```

## Configuration

| Setting | Description | Default |
|---|---|---|
| `TimerSchedule` | CRON expression for the timer trigger | `0 0 2 * * *` (daily 2 AM UTC) |
| `ThresholdDays` | Alert if assignment expires within N days | `30` |

Both are set via app settings during Bicep deployment (from `parameters.json`).

## Testing

1. Manually trigger the function via the Azure Portal (Function App → Run → Test/Run)
2. Check **Application Insights** → Live Metrics / Logs for execution output
3. Verify events appear in the Event Grid Topic's metrics

## Cost Estimate (per tenant)

| Resource | Estimated Cost |
|---|---|
| Function App (Consumption) | ~$0–5/month |
| Event Grid Topic | ~$0.60/month + operations |
| Storage Account | ~$0.10/month |
| Application Insights | ~$2–3/month |
| **Total** | **~$5–10/month** |

## Multi-Tenant Deployment

This template is designed to be deployed per client Azure subscription/tenant. Use Azure Lighthouse or manual deployment as part of your managed services offering.

## Security

- **No secrets in code** — all auth via Managed Identity
- **Managed Identity** for Graph API access and Storage Account access
- **RBAC-based storage** — `AzureWebJobsStorage` uses identity-based connection (no storage keys for the Functions runtime)
- **Least privilege** — MI only has read access to Graph and write access to Event Grid
- **TLS 1.2 enforced** on storage account
- **HTTPS only** on the Function App

## Roadmap

- [ ] Support for PIM for Azure resources (not just Entra ID roles)
- [ ] Configurable filter by role type
- [ ] Include role activation eligibility (not just assignment)
- [ ] HTML email digest option
- [ ] Integration with Teams notifications

## License

MIT

---
