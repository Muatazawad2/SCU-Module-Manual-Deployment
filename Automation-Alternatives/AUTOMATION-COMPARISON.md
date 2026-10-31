# SCU Module — Automating the Data Pull Without PowerShell

Three ways to replace `SCU-Run.ps1`'s data-pull stage, each tried live against
the same dev tenant and the same undocumented Security Copilot usage API.
See [`README.md`](README.md) for the Entra app walkthrough and
[`POWERBI-DASHBOARD.md`](POWERBI-DASHBOARD.md) for the dashboard itself —
this document covers *what pulls the data instead of the script*.

**Shared starting point for all three:** the `SCU-Usage-Puller` app from
[Part 1](README.md), and its already-obtained delegated refresh token
(`Purview.DelegatedAccess` scope). One important finding up front:

> **App-only (client-credentials) authentication does not work against this
> API.** A token minted with the already-consented `Purview.ApplicationAccess`
> app role — correct audience, correct role claim — was rejected with
> `403 Unauthorized to access account` on every endpoint tested. This API only
> accepts delegated, signed-in-user tokens, exactly like the original
> PowerShell script already assumes. Every approach below works around that
> the same way the script does: one human sign-in up front, then silent
> `refresh_token` grants afterward.

---

## Approach 1 — Azure Logic App

**[Full write-up →](LogicApp/summary.html)** · **[ARM template →](LogicApp/azuredeploy.json)**

A Consumption Logic App with a daily Recurrence trigger, an HTTP action that
exchanges the refresh token for an access token, and HTTP actions that call
the SCU usage API directly. Deployed and verified entirely via Azure CLI/ARM
— triggered manually, confirmed `Succeeded`, and the run history shows real
pulled data (21 hourly rows, 90 skillsets) fetched via the Logic Apps run-history REST API.

![Logic App architecture and live proof](LogicApp/01-architecture-and-proof.png)

**Blocker hit along the way:** this tenant's Azure Policy disables public
network access on newly created Key Vault/Storage by default, which would
have blocked a SaaS Logic App from reaching a Key-Vault-backed secret or a
Blob Storage output. Worked around by using a Logic-App-native `securestring`
parameter for the token (encrypted by the platform, no external Key Vault
needed) and skipping the Blob-output step for this proof of concept.

**Portal screenshots:** not captured. Interactive Azure Portal sign-in to
this tenant currently requires a one-time, device-bound passkey registration
that needs the account owner physically present — appropriate not to push
through unattended. Everything shown here was built and verified
non-interactively via Azure CLI / ARM / REST, which was already signed in.

---

## Approach 2 — Power Automate Cloud Flow

**[Full write-up →](PowerAutomate/summary.html)** · **[Flow definition →](PowerAutomate/flow-definition.json)**

Functionally identical to the Logic App (same Workflow Definition Language
under the hood), but authored as a Power Platform cloud flow instead of an
Azure resource.

![Power Automate architecture and live proof](PowerAutomate/01-architecture-and-proof.png)

**Blocker hit:** the Power Automate Maker portal (`make.powerautomate.com`)
hit the *same* interactive-sign-in wall as the Azure Portal — plus a second,
separate problem: my own account has no role on this tenant's real
Dataverse-backed environment (only visible/accessible via the tenant admin
identity).

**Workaround:** Power Automate cloud flows are just `workflow` records in
Dataverse (`category=5`, "Modern Flow"). Using the already-authenticated
tenant-admin session, the flow was created directly via the **Dataverse Web
API** (`POST /api/data/v9.2/workflows`) against the tenant's real Default
Environment, activated with a follow-up `PATCH`, and confirmed genuinely
"Started" via the Power Automate Flow Management API — no Maker Portal
click involved. Manually triggered afterward and confirmed `Succeeded` with
21 real rows pulled.

---

## Approach 3 — Native Power Query (M)

**[Full write-up →](PowerQuery/summary.html)**

The cleanest option for Power BI specifically: skip the external
puller entirely. A Blank Query's M code does the refresh-token exchange and
calls the SCU API directly via `Web.Contents()`, so **Power BI's own Refresh
button is the automation** — no Logic App, no Power Automate, no Azure
resource, no landing-zone file.

![Power Query M code and live result](PowerQuery/00-architecture-and-code.png)

No blockers — this runs entirely inside Power BI Desktop, which doesn't need
the Azure/Power Platform portal sign-ins the other two approaches needed.
Built, pasted into the Advanced Editor, resolved the two expected one-time
data-source trust prompts (Anonymous + Public privacy level for both
`login.microsoftonline.com` and the SCU API host), and refreshed successfully:
**10 columns, 21 rows**, live tenant data.

---

## Comparison

| | Logic App | Power Automate | Power Query (M) |
|---|---|---|---|
| Hosting | Azure (pay-per-action) | Power Platform environment | Inside Power BI itself |
| Needs a landing-zone file? | Yes (e.g. Blob/SharePoint) | Yes (e.g. SharePoint/OneDrive) | **No** |
| Needs Maker/Portal UI to build? | No (ARM/CLI works) | No (Dataverse API works) | No (Power BI Desktop only) |
| Credential storage | Logic App secure parameter | Dataverse-stored workflow definition | Power Query Parameter (recommended) |
| Verified with live tenant data? | ✅ 21 rows | ✅ 21 rows | ✅ 21 rows, 10 columns |
| Best fit | Scheduled, centrally-owned automation, easy to monitor via Azure | Citizen-developer / already-in-Power-Platform orgs | Pure Power BI shops — simplest possible pipeline |

All three are **live and still running** in the dev tenant (daily schedules)
as of this write-up. To stop them: delete resource group
`SCU-Automation-Explore` (Logic App) via Azure Portal/CLI, and deactivate/
delete the Dataverse `workflow` record named "SCU Usage Puller (Power
Automate POC)" (Power Automate). The Power Query approach has nothing
running in the background — it only pulls data when a report with that
query is refreshed.

---

*Private working notes — review before adding to the public `SecurityCopilot` repo.*
