# SCU Module — Part 1: Entra App Registration (Authentication Foundation)

This is a screenshot-illustrated re-run of the **SCU Module**'s manual setup
(`docs/APP-REGISTRATION.md`, Method B) performed by hand in a dev/sandbox
tenant instead of running `SCU-Setup.ps1`. Every click below was done live in
the Entra admin center and verified against Microsoft Graph afterward.

## All parts in this repo

| Part | Document | What it covers |
| --- | --- | --- |
| **Part 1** *(this doc)* | `README.md` | Register the Entra app by hand — the authentication foundation every other part depends on. Steps 1–4 + Graph verification. |
| **Part 2** | [`POWERBI-DASHBOARD.md`](POWERBI-DASHBOARD.md) | Pull usage data with the Part 1 app, fix a Power Query bug caused by partial API responses, redesign the dashboard template into a 10-page, light-mode report. |
| **Part 3** | [`Automation-Alternatives/AUTOMATION-COMPARISON.md`](Automation-Alternatives/AUTOMATION-COMPARISON.md) | Compare three ways to automate the data pull without PowerShell: Azure Logic App, Power Automate cloud flow, and native Power Query. |
| ↳ Power Query walkthrough | [`Automation-Alternatives/PowerQuery/STEP-BY-STEP.md`](Automation-Alternatives/PowerQuery/STEP-BY-STEP.md) | 26-step click-by-click guide. **Parts 1–5** (Steps 1–14): single-table proof of concept, Blank Query → Parameter → Close & Apply → visual → Refresh → Save. **Part 6** (Steps 15–22): scales that pattern to a full 3-table live dashboard, works through three real Power BI credential-type failures one at a time, and documents a custom-connector dead end root-caused to a Microsoft Store/MSIX platform limitation. |

> [!NOTE]
> **These are generic, repeatable steps — follow them in your own tenant.**
> The tenant ID, app name, Client ID, Object ID, and every number or
> screenshot below came from one illustrative run in a dev/sandbox tenant.
> Registering this same app in *your* tenant produces different GUIDs and
> a different sign-in account — only the sequence of steps is what you
> should expect to match.

## Why this part comes first

Every later part — Part 2's dashboard, Part 3's three automation approaches,
and Part 6's live 3-table pull — authenticates the exact same way: exchange a
delegated refresh token for an access token, using **this app's Client ID**
and **this app's granted `Purview.DelegatedAccess` scope**. If the app
doesn't exist yet, or exists but isn't consented, every `Web.Contents`
call in every later part fails at the token-endpoint step before it ever
reaches the usage API. This part isn't optional setup — it's the identity
the rest of the repo authenticates as.

## Why each step is needed

| Step | Why it's required |
| --- | --- |
| **1 — Create the app registration** | Produces the **Application (client) ID** — the one value every later `ClientId =` in every M/PowerShell query hardcodes. No app, no ID, nothing else can run. |
| **2 — Enable public client flow (device code)** | This is a script/Power Query scenario, not a web app — there's no client secret and no redirect URI to catch a browser callback. Public client flow is the only way to sign in interactively without embedding a secret. |
| **3 — Add Purview API permissions (delegated + application)** | `Purview.DelegatedAccess` is the literal scope requested in every token request from here through Part 6. Without it configured on the app, Entra rejects the scope outright — not a usage-API problem, an app-registration problem. |
| **4 — Grant admin consent** | Delegated org-data scopes don't activate just by being added — a tenant admin must explicitly approve them. Skip this and Step 3's permissions sit there "Not granted" forever; no token is ever issued. |
| **Verification (Graph via CLI)** | Confirms the consent actually took effect at the directory level, so if Part 2/3/6 later hit an auth error, you know it's *not* a stale/missing registration — that's already been ruled out here. |

**Repository reference:** <https://github.com/Muatazawad2/SecurityCopilot/tree/main/SCU%20Module>

## Example environment from this walkthrough (yours will differ)

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

## Part 3 — Automating the data pull without PowerShell

Full write-up: [`Automation-Alternatives/AUTOMATION-COMPARISON.md`](Automation-Alternatives/AUTOMATION-COMPARISON.md)

Three substitutes for `SCU-Run.ps1`'s data-pull stage, each built and
verified with **live tenant data** (same dev tenant, same undocumented
Security Copilot usage API). Key finding up front: the API rejects app-only
(client-credentials) tokens outright — delegated, signed-in-user tokens only,
same constraint the original PowerShell already assumes.

> **Note on these screenshots:** interactive sign-in to the Azure Portal and
> the Power Automate Maker portal both hit a one-time, device-bound MFA
> registration wall that needed the account owner physically present — not
> something to push through unattended. So for **Approaches 1 and 2** these
> aren't portal-click screenshots; they're rendered proof-of-work pages
> (architecture + live API output) built because the resources themselves
> were created and verified entirely via CLI/REST instead of the Portal UI.
> **Approach 3 (Power Query) hit no such wall** — it runs entirely inside
> Power BI Desktop, so it has a full, genuine click-by-click screenshot
> walkthrough instead; see its section below. Each links to the underlying
> ARM template / flow definition / M code.

### Approach 1 — Azure Logic App ([ARM template](Automation-Alternatives/LogicApp/azuredeploy.json))

Deployed via `az deployment group create`, triggered manually, confirmed
`Succeeded` — 21 real hourly rows + 90 skillsets pulled.

![Logic App architecture and live proof](Automation-Alternatives/LogicApp/01-architecture-and-proof.png)

### Approach 2 — Power Automate Cloud Flow ([flow definition](Automation-Alternatives/PowerAutomate/flow-definition.json))

Maker portal was unreachable (same MFA wall), so the flow was created
directly via the Dataverse Web API, activated, and confirmed genuinely
"Started" — triggered manually, 21 rows pulled.

![Power Automate architecture and live proof](Automation-Alternatives/PowerAutomate/01-architecture-and-proof.png)

### Approach 3 — Native Power Query (M)

No blockers here — runs entirely inside Power BI Desktop. A Blank Query's M
code calls the SCU API directly via `Web.Contents()`, so Power BI's own
**Refresh** button is the whole automation.

![Power Query M code and live result](Automation-Alternatives/PowerQuery/00-architecture-and-code.png)

This one also has a full **26-step click-by-click screenshot walkthrough**:
[`Automation-Alternatives/PowerQuery/STEP-BY-STEP.md`](Automation-Alternatives/PowerQuery/STEP-BY-STEP.md) —
Blank Query → Advanced Editor → Manage Parameters (moving the refresh token
out of the M code into a Parameter) → a live Refresh Preview → **Close &
Apply** → a real table visual built from that live data → clicking
**Refresh** on the report canvas itself → **Save**, producing a real
`.pbix` file (Steps 1–14) — then **Part 6** of that same guide scales the
pattern to a full 3-table live dashboard, including three real Power BI
credential-type failures worked through one at a time and a custom-connector
dead end root-caused to a Microsoft Store/MSIX platform limitation
(Steps 15–22).

See [`AUTOMATION-COMPARISON.md`](Automation-Alternatives/AUTOMATION-COMPARISON.md)
for the full comparison table and tradeoffs. Each approach's `summary.html`
is a styled version of the same content — GitHub shows it as raw source in
the browser, so download and open it locally (or view the `.md`/images above)
to see it rendered.

---

*Private working notes — review before adding to the public `SecurityCopilot` repo.*
