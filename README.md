# SCU Module — Manual Entra App Registration (Screenshot Walkthrough)

This is a screenshot-illustrated re-run of the **SCU Module**'s manual setup
(`docs/APP-REGISTRATION.md`, Method B) performed by hand in a dev/sandbox
tenant instead of running `SCU-Setup.ps1`. Every click below was done live in
the Entra admin center and verified against Microsoft Graph afterward.

**Repository reference:** <https://github.com/Muatazawad2/SecurityCopilot/tree/main/SCU%20Module>

> **Part 2 available:** [`POWERBI-DASHBOARD.md`](POWERBI-DASHBOARD.md) covers
> pulling real usage data with this app and a redesigned, bug-fixed, light-mode
> Power BI template (`PowerBI/SCU-Dashboard-Light.pbit`).
>
> **Part 3 available:** [`Automation-Alternatives/AUTOMATION-COMPARISON.md`](Automation-Alternatives/AUTOMATION-COMPARISON.md)
> replaces `SCU-Run.ps1`'s data pull with a Logic App, a Power Automate flow,
> and native Power Query — all three tried live against this tenant.

## Environment used for this run

| Item | Value |
| --- | --- |
| Tenant | POA Deliverables Lab (`muatazawad.com`) |
| Tenant ID | `e6cf700c-2029-4e98-aedd-f589e62f7316` |
| Signed in as | `admin@MngEnvMCAP018908.onmicrosoft.com` |
| App name | `SCU-Usage-Puller` |
| Application (client) ID | `72bb0a2b-c028-4a0f-bb57-78a81db6fc18` |
| Object ID | `107d4a3f-d91d-43c1-b76d-2191e480d27d` |

> These IDs are specific to this dev tenant — registering in another tenant
> produces different GUIDs, but the steps are identical.

---

## Step 1 — Create the app registration

Entra admin center → **Identity → Applications → App registrations → + New registration**.

![App registrations list](Images/step01-app-registrations-list.png)

Filled in the form: Name `SCU-Usage-Puller`, **Single tenant only**, Redirect URI left blank.

![Register an application form filled in](Images/step02-register-app-form-filled.png)

After clicking **Register**, the app's Overview page shows the generated
**Application (client) ID**, **Object ID**, and **Directory (tenant) ID**.

![App created — Overview page](Images/step03-overview-app-created.png)

---

## Step 2 — Enable device-code sign-in (public client flow)

Left nav → **Authentication (Preview) → Settings** tab → toggle **Allow public client flows** to Enabled.

![Allow public client flows toggled on](Images/step04-authentication-public-client-enabled.png)

Clicked **Save** — confirmed by the "Successfully updated SCU-Usage-Puller" toast.

![Authentication settings saved](Images/step05-authentication-saved.png)

---

## Step 3 — Add the Microsoft Purview API permissions

Starting point: **API permissions** page with only the default Graph `User.Read` delegated permission.

![API permissions — default Graph permission](Images/step06-api-permissions-default.png)

Clicked **+ Add a permission → APIs my organization uses**, then searched by the
Purview AppId (`73c2949e-da2d-457a-9607-fcc665198967`) — it shows up as
**"Azure Purview"** in this tenant (the docs refer to it as "Microsoft Purview";
same AppId, same API, tenant-local display name just differs).

![Searching APIs my organization uses for Purview](Images/step07-apis-my-org-uses-search-purview.png)

Selected it, opening the permission-type picker for **Microsoft Purview** (`https://purview.azure.net`).

![Azure Purview API selected](Images/step08-azure-purview-selected.png)

### 3a — Delegated permission

Chose **Delegated permissions** and checked `Purview.DelegatedAccess`.

![Purview.DelegatedAccess checked](Images/step09-delegated-permission-checked.png)

Clicked **Add permissions** — it now appears under "Microsoft Purview (1)".

![Delegated permission added](Images/step10-delegated-permission-added.png)

### 3b — Application permission

Repeated **+ Add a permission → APIs my organization uses → Azure Purview**,
this time choosing **Application permissions** and checking `Purview.ApplicationAccess`
(the app role the docs call out as id `8d48872e-7710-4001-bfd0-7dac15c28f69`).

![Purview.ApplicationAccess checked](Images/step11-application-permission-checked.png)

Both permissions are now listed, with **Admin consent required** shown and a
"Not granted" warning on the application permission.

![Both permissions listed, not yet granted](Images/step12-both-permissions-added.png)

---

## Step 4 — Grant admin consent

Clicked **Grant admin consent for POA Deliverables Lab**, confirmed the dialog.

![Grant admin consent confirmation dialog](Images/step13-grant-consent-confirmation.png)

Result: both permissions show a green check and **"Granted for POA Deliverables Lab."**

![Admin consent granted — green checks](Images/step14-admin-consent-granted.png)

---

## Verification (Microsoft Graph, via Azure CLI)

```powershell
$appId = '72bb0a2b-c028-4a0f-bb57-78a81db6fc18'
$sp = az ad sp show --id $appId --only-show-errors | ConvertFrom-Json
az rest --method get --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)'" |
    ConvertFrom-Json | Select-Object -ExpandProperty value | Format-Table clientId, consentType, scope
az rest --method get --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignments" |
    ConvertFrom-Json | Select-Object -ExpandProperty value | Format-Table principalDisplayName, resourceDisplayName, appRoleId
```

Confirmed output:

- `oauth2PermissionGrants`: `consentType = AllPrincipals`, `scope = User.Read Purview.DelegatedAccess`
- `appRoleAssignments`: `SCU-Usage-Puller` → `Azure Purview`, `appRoleId = 8d48872e-7710-4001-bfd0-7dac15c28f69`

Both match the expected values in `docs/APP-REGISTRATION.md` exactly.

---

## Next step — pulling data and the Power BI dashboard

This walkthrough focused on the manual/portal configuration path only. The
app is ready to use with:

```powershell
.\SCU-Setup.ps1 -AppId 72bb0a2b-c028-4a0f-bb57-78a81db6fc18 -Capacity "SecCo"
```

to pull real SCU usage data and build the Power BI dashboard — see
[`POWERBI-DASHBOARD.md`](POWERBI-DASHBOARD.md) for the full run (actual
numbers from this dev tenant) plus a redesigned, bug-fixed, light-mode
dashboard template.

---

*Private working notes — review before adding to the public `SecurityCopilot` repo.*
