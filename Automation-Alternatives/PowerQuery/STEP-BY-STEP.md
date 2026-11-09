# Pull Security Copilot usage data into Power BI — no PowerShell, no external service

[![Power BI Desktop](https://img.shields.io/badge/Power_BI-Desktop-F2C811?logo=powerbi&logoColor=black)](https://learn.microsoft.com/power-bi/fundamentals/desktop-getting-started)
[![Power Query M](https://img.shields.io/badge/Power_Query-M_language-0078D4?logo=microsoft&logoColor=white)](https://learn.microsoft.com/powerquery-m/power-query-m-function-reference)
[![Microsoft Purview](https://img.shields.io/badge/Microsoft_Purview-Security_Copilot_usage_API-5C2D91?logo=microsoft&logoColor=white)](https://learn.microsoft.com/copilot/security/manage-usage)

A genuine, click-by-click screenshot walkthrough of replacing `SCU-Run.ps1`'s
data-pull stage with a single **Blank Query** inside Power BI Desktop. No
Logic App, no Power Automate, no Azure resource, no landing-zone file —
Power BI's own **Refresh** button *is* the automation. It goes all the way
through **Close & Apply** and a real **table visual** built from the live
result, not just a preview grid inside the editor.

> [!NOTE]
> **These are generic steps — every click here works the same way in any
> tenant.** The screenshots were captured live against one dev/sandbox
> tenant, and the specific row counts, column values, and IDs shown are from
> that one run; none are mocked up or composited, but your own tenant will
> return different (and likely larger) numbers through the exact same steps.

> [!IMPORTANT]
> This is a proof of concept, not a hardened production pattern. The refresh
> token is still a secret value stored inside the `.pbix` file (as a Power
> Query Parameter, not a vault-backed credential). See
> [Good to know](#good-to-know) before using this outside a lab tenant.

## Contents

- [How it works](#how-it-works)
- [Key terms](#key-terms)
- [Before you start](#before-you-start)
- [Part 1: Create a Blank Query](#part-1-create-a-blank-query) (steps 1–3)
- [Part 2: Write and test the M code](#part-2-write-and-test-the-m-code) (steps 4–5)
- [Part 3: Move the secret into a Parameter](#part-3-move-the-secret-into-a-parameter) (steps 6–7)
- [Part 4: Finalize and refresh](#part-4-finalize-and-refresh) (steps 8–9)
- [Part 5: Load it into the report and visualize](#part-5-load-it-into-the-report-and-visualize) (steps 10–14)
- [Part 6: Scaling to a full 3-table live dashboard](#part-6-scaling-to-a-full-3-table-live-dashboard) (steps 15–22)
- [Lab results](#lab-results)
- [Good to know](#good-to-know)
- [Troubleshooting](#troubleshooting)
- [Roll back](#roll-back)
- [Repository layout](#repository-layout)
- [References](#references)

## How it works

1. A **Blank Query** is created with no data source — just an empty canvas
   for hand-written M code.
2. Its M code calls Microsoft Entra's token endpoint directly via
   `Web.Contents`, trading the already-obtained **delegated refresh token**
   for a short-lived access token — the same `refresh_token` grant
   `SCU-Setup.ps1`/`SCU-Run.ps1` already use.
3. With that access token, it calls the Security Copilot usage API's
   `/aggregates/hourly` endpoint for a rolling 7-day window and turns the
   JSON response into a table with `Table.FromRecords`.
4. The refresh token itself is **never inlined in the M code** — it's stored
   in a **Power Query Parameter** (`ScuRefreshToken`) and referenced by name,
   so the query logic and the secret stay separate.
5. Every time the report owner clicks **Refresh**, steps 2–3 repeat. There is
   no scheduled trigger, no intermediate file, and nothing running in the
   background between refreshes.

<p align="center"><img src="00-architecture-and-code.png" alt="Power Query M code and architecture" width="760"><br><sub>The finished M code (left) and the live result it returns (right) — the end state this walkthrough builds up to.</sub></p>

## Key terms

New to Power Query? Here's what each term means in this guide.

| Term | What it means here |
|---|---|
| **Power Query** | The data-transformation engine built into Power BI (also in Excel). You write or record steps in a language called **M**; Power Query runs them every time the report refreshes. |
| **Blank Query** | A Power Query data source with no connector behind it — just a name and whatever M code you write yourself. |
| **M** (the Power Query Formula Language) | The functional language Power Query steps compile down to. The **Advanced Editor** shows and edits it directly as text. |
| **Advanced Editor** | The code-view window for a single query's M code. Normal query building (clicking through the UI) is really just generating M code behind the scenes; this walkthrough writes it by hand instead. |
| **Power Query Parameter** | A named, reusable value (text, number, date, etc.) that any query can reference by name. Used here so the refresh token lives in one place, not pasted inline into the query logic. |
| **Refresh Preview / Refresh** | Re-runs a query's M code and reloads its result. **Refresh Preview** (inside the Power Query Editor) refreshes just the query you're looking at; **Refresh** on the main canvas refreshes every query feeding the report. |
| **Delegated vs. app-only token** | A **delegated** token represents a signed-in user; an **app-only** token represents the app itself with no user present. The Security Copilot usage API only accepts delegated tokens — see [`AUTOMATION-COMPARISON.md`](../AUTOMATION-COMPARISON.md) for how that was confirmed. |
| **`Web.Contents`** | The M function that makes an HTTP request. Used twice here: once against Entra's token endpoint, once against the usage API. |

## Before you start

### What you need

| Item | Details |
|---|---|
| **Power BI Desktop** | Installed locally. No special license or tenant setting needed — this runs entirely client-side. |
| **The `SCU-Usage-Puller` app registration** | From [Part 1](../../README.md) of this repo, with `Purview.DelegatedAccess` consented. |
| **A valid delegated refresh token** | Already obtained by running `SCU-Setup.ps1` once (same one `SCU-Run.ps1` reuses). It's DPAPI-encrypted at rest under the signed-in Windows user — decrypt it only in memory, never paste it in plain text anywhere persistent. |
| **The tenant's Security Copilot pod details** | `PodId`, `Workspace`, and `Capacity` — the same constants `SCU-Run.ps1` already uses to build the usage API URL. |
| **Time** | About 10 minutes, plus however long the first `Web.Contents` call takes to resolve the one-time data-source trust prompts. |

### A note on the refresh token

Treat the decrypted refresh token exactly like a password: never type it
into a chat window, commit it to source control, or leave it visible in a
screenshot. This walkthrough's own screenshots were masked for that reason —
see the callout in [Step 7](#step-7-create-the-scurefreshtoken-parameter).

---

## Part 1: Create a Blank Query

### Step 1: Start Power BI Desktop

**Why:** a Blank Query needs nothing from an existing report — starting from
a brand-new file keeps this walkthrough self-contained.

1. Open **Power BI Desktop**.
2. On the start screen, select **Blank report**.

<p align="center"><img src="Steps/step01-powerbi-start-screen.png" alt="Power BI Desktop start screen" width="760"><br><sub>Power BI Desktop's start screen. <b>Blank report</b> is the leftmost tile.</sub></p>

The report canvas opens with an empty **Page 1** and the standard ribbon.

<p align="center"><img src="Steps/step02-blank-report-opened.png" alt="Blank report opened" width="760"><br><sub>A brand-new, unsaved report. Nothing has been connected yet.</sub></p>

### Step 2: Open Get Data and pick Blank Query

**Why:** every other item in the **Get Data** picker is a connector that asks
for connection details (a server, a file, a URL). **Blank Query** is the one
option that skips all of that and drops straight into an empty M script.

1. **Home → Get data → More…** opens the **Get Data** window.

<p align="center"><img src="Steps/step03-getdata-dialog.png" alt="Get Data dialog" width="760"><br><sub><b>Get Data</b>, defaulting to the <b>All</b> category with <b>Excel Workbook</b> selected.</sub></p>

2. Type `Blank Query` into the search box at the top-left — it's under the
   **Other** category, but searching is faster than navigating there.

<p align="center"><img src="Steps/step04-search-blankquery.png" alt="Search filtered to Blank Query" width="760"><br><sub>Typing narrows the list to a single result: <b>Blank Query</b>.</sub></p>

3. Select **Blank Query**, then **Connect**.

### Step 3: Confirm the Power Query Editor opened

Unlike most connectors, Blank Query has no connection-parameter dialog to
fill in first — selecting it opens the **Power Query Editor** directly, with
a new, empty query named `Query1`.

<p align="center"><img src="Steps/step05-query-editor-opened.png" alt="Power Query Editor opened" width="760"><br><sub>The Power Query Editor, maximized. <b>Query1</b> exists but has no code yet — its <b>Applied Steps</b> pane shows only <code>Source</code>.</sub></p>

---

## Part 2: Write and test the M code

### Step 4: Open the Advanced Editor

**Why:** normal Power Query use builds M code indirectly, by clicking
through transformation buttons. The **Advanced Editor** is the direct route —
it shows the query's actual M code as text, and lets you replace it outright.

1. **Home → Advanced Editor**.
2. A brand-new blank query defaults to the simplest possible script:
   `let Source = "" in Source`.

<p align="center"><img src="Steps/step06-advanced-editor-opened.png" alt="Advanced Editor opened with default code" width="760"><br><sub>The Advanced Editor's default scaffold for a new Blank Query. <b>No syntax errors have been detected</b> confirms the editor is validating as you type.</sub></p>

### Step 5: Paste the M code and run it

**Why this step exists at all:** the fastest way to confirm the request
shape (the token exchange, the API URL, the headers) is correct is to test
it with the token **inlined as a plain string** first — one variable,
easy to swap out — before worrying about where that secret should actually
live. That's exactly what the code's own comment says to do next.

1. Select all the default code and replace it with the full M script below
   (also saved as [`Steps/mcode-placeholder.m`](Steps/mcode-placeholder.m)).
   In place of a real token, this version uses a placeholder string so it's
   safe to paste anywhere, including here:

   ```text
   let
       // In production, store this as a Power Query Parameter (Home > Manage Parameters)
       // rather than inline - shown inline here to keep the POC self-contained.
       ScuRefreshToken = "PASTE_YOUR_REFRESH_TOKEN_HERE",

       GetAccessToken = () =>
           let
               TenantId = "<your-tenant-id>",
               ClientId = "<SCU-Usage-Puller's client ID>",
               ApiAudience = "73c2949e-da2d-457a-9607-fcc665198967",
               TokenEndpoint = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/token",
               FormBody = "grant_type=refresh_token&client_id=" & ClientId & "&refresh_token=" & ScuRefreshToken
                          & "&scope=" & ApiAudience & "%2FPurview.DelegatedAccess%20offline_access",
               Response = Json.Document(Web.Contents(TokenEndpoint, [
                   Headers = [#"Content-Type"="application/x-www-form-urlencoded"],
                   Content = Text.ToBinary(FormBody)
               ])),
               AccessToken = Response[access_token]
           in
               AccessToken,

       PodId = "<your pod ID>", Workspace = "default", Capacity = "<your capacity name>",
       BaseUrl = "https://us.api.securityplatform.microsoft.com/pods/" & PodId & "/workspaces/" & Workspace
                & "/securitycopilot/usage/" & Capacity,

       NowUtc = DateTimeZone.RemoveZone(DateTimeZone.FixedUtcNow()),
       WindowStart = DateTime.ToText(NowUtc - #duration(7,0,0,0), "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
       WindowEnd = DateTime.ToText(NowUtc, "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
       RequestBody = "{""startDate"":""" & WindowStart & """,""endDate"":""" & WindowEnd & """}",

       Token = GetAccessToken(),
       Response = Json.Document(Web.Contents(BaseUrl & "/aggregates/hourly", [
           Headers = [Authorization = "Bearer " & Token, #"Content-Type"="application/json"],
           Content = Text.ToBinary(RequestBody)
       ])),
       Rows = Response[value],
       ResultTable = Table.FromRecords(Rows)
   in
       ResultTable
   ```

   > The copy above redacts `TenantId`, `ClientId`, `PodId`, and `Capacity`
   > with placeholders for this published guide. The actual lab run used the
   > real dev-tenant values (which match the table in the
   > [root README](../../README.md#environment-used-for-this-run)) — only the
   > refresh token itself needs to stay secret.

<p align="center"><img src="Steps/step07-mcode-pasted.png" alt="M code pasted with placeholder token" width="760"><br><sub>The pasted M code, with a placeholder in place of the real token. <b>No syntax errors have been detected</b> — the code is well-formed even though it will fail to authenticate.</sub></p>

2. Select **Done**, then **Home → Refresh Preview**.
3. With a placeholder instead of a real token, expect a `400 Bad Request`
   from the token endpoint — this is the **expected** result, and it
   confirms the request is reaching the right URL with the right shape.

<p align="center"><img src="Steps/step08-placeholder-token-fails.png" alt="Placeholder token produces expected 400" width="760"><br><sub>The expected failure: <code>DataSource.Error: Web.Contents failed to get contents from '…/oauth2/v2.0/token' (400): Bad Request</code>. The <b>Applied Steps</b> pane on the right confirms every step up to <code>ResultTable</code> ran — only the actual token exchange rejected the placeholder.</sub></p>

---

## Part 3: Move the secret into a Parameter

### Step 6: Open Manage Parameters

**Why:** leaving the token inlined (as in Step 5) means it's baked into the
query's saved M code — visible in any export, diff, or screenshot of that
query. A **Power Query Parameter** keeps the same value but stores it as a
separate, named object instead, so the M code itself never contains it.

1. **Home → Manage Parameters** is a split button (it has its own dropdown
   arrow). Selecting it opens two options: **Edit Parameters** and
   **New Parameter**.

<p align="center"><img src="Steps/step09-manage-parameters-menu.png" alt="Manage Parameters menu" width="760"><br><sub><b>Home → Manage Parameters</b>. <b>New Parameter</b> opens a blank form; <b>Edit Parameters</b> (used next) opens every existing parameter on the query.</sub></p>

### Step 7: Create the `ScuRefreshToken` parameter

1. Select **Edit Parameters** (or **New Parameter** for a brand-new one).
2. Fill in the parameter's fields:

| Field | Value | Why |
|---|---|---|
| Name | `ScuRefreshToken` | Matches the identifier the M code will reference — Power Query resolves parameters by name. |
| Type | **Text** | The refresh token is an opaque string, not a number/date/etc. |
| Current Value | *(the decrypted refresh token)* | This is the actual secret. Power Query stores it as part of the query definition — see [Good to know](#good-to-know). |

> [!CAUTION]
> This dialog shows the Current Value field as **plain, unmasked text** —
> there's no password-style dot-masking. Never leave this dialog open in a
> screen share, and never screenshot it with the real value present. The
> screenshot below was taken with a placeholder typed into the field, then
> **Cancel** was selected (not OK) so the real stored value was never
> actually changed by the act of documenting this step.

<p align="center"><img src="Steps/step10-edit-parameters-dialog.png" alt="Edit Parameters dialog" width="760"><br><sub><b>Edit Parameters</b>, showing the <code>ScuRefreshToken</code> parameter's single text field. Shown here with a placeholder in place of the real decrypted token.</sub></p>

3. Select **OK** to save (or **Cancel**, as above, if you're only verifying
   the dialog's layout).

---

## Part 4: Finalize and refresh

### Step 8: Point the M code at the parameter

**Why:** with `ScuRefreshToken` now a Parameter, the query no longer needs to
declare or assign it — Power Query resolves the bare name automatically at
evaluation time, the same way it resolves any other query's name.

1. Open **Advanced Editor** again and replace the inline assignment with a
   bare reference, matching
   [`Steps/mcode-final-parameterized.m`](Steps/mcode-final-parameterized.m):

   ```text
   let
       // ScuRefreshToken is now a Power Query Parameter (Home > Manage Parameters)
       // instead of being inlined here - production-safe pattern.
       GetAccessToken = () =>
           let
               TenantId = "<your-tenant-id>",
               ClientId = "<SCU-Usage-Puller's client ID>",
               ApiAudience = "73c2949e-da2d-457a-9607-fcc665198967",
               TokenEndpoint = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/token",
               FormBody = "grant_type=refresh_token&client_id=" & ClientId & "&refresh_token=" & ScuRefreshToken
                          & "&scope=" & ApiAudience & "%2FPurview.DelegatedAccess%20offline_access",
               Response = Json.Document(Web.Contents(TokenEndpoint, [
                   Headers = [#"Content-Type"="application/x-www-form-urlencoded"],
                   Content = Text.ToBinary(FormBody)
               ])),
               AccessToken = Response[access_token]
           in
               AccessToken,

       PodId = "<your pod ID>", Workspace = "default", Capacity = "<your capacity name>",
       BaseUrl = "https://us.api.securityplatform.microsoft.com/pods/" & PodId & "/workspaces/" & Workspace
                & "/securitycopilot/usage/" & Capacity,

       NowUtc = DateTimeZone.RemoveZone(DateTimeZone.FixedUtcNow()),
       WindowStart = DateTime.ToText(NowUtc - #duration(7,0,0,0), "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
       WindowEnd = DateTime.ToText(NowUtc, "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
       RequestBody = "{""startDate"":""" & WindowStart & """,""endDate"":""" & WindowEnd & """}",

       Token = GetAccessToken(),
       Response = Json.Document(Web.Contents(BaseUrl & "/aggregates/hourly", [
           Headers = [Authorization = "Bearer " & Token, #"Content-Type"="application/json"],
           Content = Text.ToBinary(RequestBody)
       ])),
       Rows = Response[value],
       ResultTable = Table.FromRecords(Rows)
   in
       ResultTable
   ```

2. Select **Done**. The queries list on the left now shows both `Query1`
   and the `ScuRefreshToken` parameter.

<p align="center"><img src="Steps/step11-parameterized-mcode.png" alt="Final M code referencing the parameter" width="760"><br><sub>The final M code — <code>ScuRefreshToken</code> is referenced by name only, with no inline secret anywhere in this screenshot. <b>No syntax errors have been detected.</b></sub></p>

> The Queries pane also previews each parameter's current value next to its
> name (Power Query does this by default for every parameter, not just this
> one). That portion of the screenshot above is masked for the same reason
> as Step 7 — it isn't rendered any differently in the real UI.

### Step 9: Refresh Preview and confirm live data

1. **Home → Refresh Preview** re-runs the query end to end: exchange the
   refresh token for an access token, call the usage API, and return the
   result table.
2. The first refresh may prompt for the data source's **privacy level**
   (Anonymous/Public is fine for both `login.microsoftonline.com` and the
   usage API host) — see [Privacy levels in Power
   Query](https://learn.microsoft.com/power-query/privacy-levels) if you
   haven't seen this prompt before.

<p align="center"><img src="Steps/step12-live-data-result.png" alt="Live data result — 10 columns, 20 rows" width="760"><br><sub><b>10 columns, 20 rows</b> of real hourly usage aggregates, with real timestamps through the current date. <b>PREVIEW DOWNLOADED AT 6:23 PM</b> (bottom-right) confirms this is a live result, not cached.</sub></p>

From here, **Close & Apply** loads the query into the report's data model
like any other source, and every subsequent **Refresh** on the report canvas
repeats this exact flow — no external moving parts, no landing-zone file,
nothing running in the background between refreshes. Part 5 below actually
clicks **Close & Apply** and builds a visual from the result, so there's no
ambiguity about what the finished state looks like.

---

## Part 5: Load it into the report and visualize

### Step 10: Close & Apply

**Why:** everything up to now happened inside the **Power Query Editor**,
which is a staging area — its "Preview" never touches the report itself.
**Close & Apply** is the one action that commits the query into the report's
data model, closes the editor, and returns you to the report canvas.

1. **Home → Close & Apply** is also a split button. Selecting the main
   (left) part runs **Close & Apply** directly; the dropdown arrow exposes
   **Apply** (load without closing the editor) and **Close** (discard
   without loading) as well.

<p align="center"><img src="Steps/step13-close-and-apply-menu.png" alt="Close & Apply split-button menu" width="760"><br><sub><b>Home → Close & Apply</b>. The three options shown are <b>Close & Apply</b> (commit and close), <b>Apply</b> (commit and stay open), and <b>Close</b> (discard).</sub></p>

2. Power BI shows a **Load** dialog while it evaluates the query and any
   parameters one more time before committing the result to the model.

<p align="center"><img src="Steps/step14-apply-loading.png" alt="Load progress dialog" width="760"><br><sub>The one-time <b>Load</b> dialog — <code>Query1: Evaluating…</code> — this is the same M code run as Step 9's Refresh Preview, just loading into the model instead of the editor's preview grid.</sub></p>

### Step 11: Confirm the query landed in the report

Once loading finishes, the Power Query Editor window closes on its own and
you're back on the report canvas, with `Query1` now listed in the **Data**
pane on the right.

<p align="center"><img src="Steps/step15-report-canvas-query-loaded.png" alt="Report canvas with Query1 in the Data pane" width="760"><br><sub>Back on the report canvas. <code>Query1</code> appears in the <b>Data</b> pane — the editor is gone, and the canvas is ready for a visual.</sub></p>

Expand `Query1` in the Data pane to see all 10 columns the query returns.
Only field **names** are listed here — `ScuRefreshToken` doesn't appear at
all, because Parameters aren't part of the data model; they exist only
inside Power Query itself.

<p align="center"><img src="Steps/step16-fields-list-expanded.png" alt="Query1 fields expanded in the Data pane" width="760"><br><sub>All 10 columns from the usage API response, ready to use in any visual: <code>aggregateStartTime</code>, <code>assignedCapacity</code>, <code>isOverageOrRollover</code>, <code>maxAllowedCapacity</code>, <code>overageLimit</code>, <code>overageSCUUsed</code>, <code>overageState</code>, <code>provisionedSCUUsed</code>, <code>unbilledSCUUsed</code>, <code>usedCapacity</code>.</sub></p>

### Step 12: Build a visual from the real data

**Why:** this is the actual point of pulling the data in the first place —
a visual on the report canvas is what a report reader sees. Nothing about
this step is specific to this data source; any table loaded into the model
builds visuals the same way.

1. With no visual selected, checking a field's box in the Data pane creates
   a new **Table** visual automatically and adds that field as a column.
   Checking further boxes adds more columns to the same visual.
2. For this walkthrough, four columns were added: `aggregateStartTime`,
   `usedCapacity`, `assignedCapacity`, `provisionedSCUUsed`.
3. The default visual size is small — **Format visual → General →
   Properties → Size** has explicit **Height**/**Width** fields if you'd
   rather type exact values than drag the resize handles.

<p align="center"><img src="Steps/step17-table-visual-built.png" alt="Table visual built from real Security Copilot usage data" width="760"><br><sub>The finished table — real hourly usage rows, pulled live from the Security Copilot usage API, with zero PowerShell and zero external services involved from here on. This is the end state the whole walkthrough builds up to.</sub></p>

### Step 13: Prove the loop — click Refresh on the report canvas

**Why:** every step so far happened once, by hand. The whole point of this
approach is that **Home → Refresh** on the main report canvas (not
**Refresh Preview** inside the editor) re-runs the entire pull — token
exchange, API call, table reload — with one click and no editor involved.
This step actually clicks it, rather than just asserting it would work.

1. With the table visual already on the canvas, select **Home → Refresh**.
2. Power BI re-evaluates `Query1` (and resolves `ScuRefreshToken` again)
   exactly as Step 9 did, then reloads the visual with whatever the usage
   API returns at that moment.

<p align="center"><img src="Steps/step18-refresh-clicked.png" alt="Refresh button clicked on the report canvas" width="760"><br><sub><b>Home → Refresh</b>, clicked — the button's focus outline confirms it ran. The table reloads in place; no dialogs, no editor, no PowerShell.</sub></p>

### Step 14: Save your work

1. **Ctrl+S** (or **File → Save**) prompts for a name the first time, since
   this report started as an unsaved Blank Query session.

<p align="center"><img src="Steps/step19-save-dialog.png" alt="Save this file dialog" width="760"><br><sub>The one-time naming prompt. Everything after this — folder, OneDrive vs. local — is standard Windows/Power BI save behavior, not specific to this walkthrough.</sub></p>

2. Once saved, the title bar switches from <code>Untitled</code> to the
   file's name, confirming a real <code>.pbix</code> now exists on disk.

<p align="center"><img src="Steps/step20-saved-confirmed.png" alt="Power BI Desktop title bar confirming the file was saved" width="760"><br><sub>Title bar reads the saved file name instead of <code>Untitled</code> — a tangible <code>.pbix</code> deliverable, with the same table visual intact.</sub></p>

> [!CAUTION]
> This `.pbix` still has the real decrypted refresh token sitting in the
> `ScuRefreshToken` parameter (see [Good to know](#good-to-know)). It was
> saved to a local working folder only, deliberately **not** committed to
> this repository — treat any `.pbix` saved from this walkthrough as a
> secret, the same way the [Roll back](#roll-back) section already
> describes.

---

## Part 6: Scaling to a full 3-table live dashboard

Steps 1–14 above proved the pattern with **one** Blank Query and a 7-day
Hourly pull. This part documents scaling that same pattern to drive **all
three core tables** (`Hourly`, `Sessions`, `Daily`) of a real multi-page
dashboard (`SCU-Dashboard-LiveAPI.pbix`) that had previously loaded those
tables from a static `SCU-Report.xlsx` export — plus a genuine credential
wall hit and root-caused one failure mode at a time, and a dead end hit
along the way: an attempt to replace the ad-hoc queries with a proper
custom Power Query connector, which turned out to be impossible on this
specific Power BI Desktop installation for a reason worth recording.

> [!NOTE]
> The architecture and every credential-type failure mode below are generic
> — they'll reproduce in any tenant using this same ad-hoc `Web.Contents`
> pattern. The row counts (31 Daily rows, etc.) and the Microsoft Store/MSIX
> finding in Step 21 are specific to this one run and this one machine's
> Power BI Desktop install — check your own install edition before assuming
> Step 21 applies to you.

> [!IMPORTANT]
> This section never shows a real refresh token, and the `.pbix` itself is
> not committed to this repo. Every screenshot below was taken from
> Table/Report view and Power BI's own **Access Web content** credential
> dialog with the Advanced Editor and DAX/M panes closed, specifically to
> avoid ever capturing the token. The one tenant identifier visible in two
> screenshots (the Entra **Tenant ID**) is already published in plain text
> in [`README.md`](../../README.md)'s environment table — it is not a
> secret. The one M code file included here
> ([`SCUDashboard-connector.pq`](Steps/SCUDashboard-connector.pq)) takes its
> token from a Power BI credential prompt at runtime
> (`Extension.CurrentCredential()`) and contains no secret value at all.

### Goal

Convert `SCU-Dashboard-LiveAPI.pbix`'s three core tables from a static,
point-in-time `SCU-Report.xlsx` export to live, direct-API Power Query
sources — so opening the file and clicking **Refresh** pulls current
Security Copilot usage data straight from the tenant, the same way Steps
1–14 above did with one table, but feeding a full dashboard instead of one
proof table.

### Architecture — one pattern, three endpoints

| Table | Endpoint | Shape | Notes |
|---|---|---|---|
| `Hourly` | `/aggregates/hourly` | Single call, 30-day window | Same call shape as the Part 1–5 proof query. |
| `Sessions` | `/aggregates/dimensional` | **Paginated** (`pageSize: 200`), `List.Generate` loop until a page comes back empty | Per-session rows: user, plugins/skills used, category, status, cost. |
| `Daily` | `/aggregates/dimensional` | Same paginated pull as `Sessions`, then **grouped by calendar day** | Produces `Day`, `SCU_Total`, `Overage_SCU`, `Hours_Active`, rolling 7-/30-day averages, day-over-day deltas, and a simple anomaly flag. |

All three authenticate the same way: a stored delegated refresh token is
traded for a short-lived access token via `grant_type=refresh_token`
against `https://login.microsoftonline.com/<TenantId>/oauth2/v2.0/token`,
requesting the `Purview.DelegatedAccess` scope — identical to
`SCU-Setup.ps1` / `SCU-Run.ps1` and to Steps 1–14.

### Step 15: Hourly and Sessions converted cleanly

Both queries followed the same recipe as Steps 1–14 (`Web.Contents` →
`Json.Document` → `Table.FromRecords` → typed/renamed columns), with
`Sessions` additionally needing the `List.Generate` pagination loop from the
[architecture table](#architecture--one-pattern-three-endpoints) above,
since `/aggregates/dimensional` caps each response at 200 rows. Both
refreshed cleanly once a credential was accepted for their shared API host.

### Step 16: Data source settings — one prompt per host, not per query

**Why:** Power BI's generic data-source credential gate is a separate layer
from the M code itself. It tracks one entry **per exact URL** a query calls
— independent of how many queries share that URL, and independent of
whatever the M code does internally (including this file's pattern of
building its own `Authorization: Bearer <token>` header by hand inside
`Web.Contents`). **File → Options and settings → Data source settings**
lists every URL the file has ever called and lets you inspect or clear its
stored credential one at a time.

<p align="center"><img src="Steps/step21-datasource-settings-three-sources.png" alt="Data source settings dialog listing three web data sources" width="760"><br><sub><b>Data source settings</b> — three entries for this file: the Entra token endpoint, the <code>aggregates/dimensional</code> endpoint (<code>Sessions</code> + <code>Daily</code>), and the <code>aggregates/hourly</code> endpoint. Clearing one entry's permission only affects queries that call that exact URL.</sub></p>

### Step 17: Web API + Key — looks right, fails structurally

**Why this was tried first:** the **Web API** credential type's **Key**
field looks like the obvious match for "paste a token-shaped value in a
box". It isn't, for this M code specifically — and the error below is
consistent and structural, not a typo or a one-off glitch.

1. Triggering a refresh with no stored credential for the
   `aggregates/dimensional` host opens Power BI's **Access Web content**
   dialog.
2. Choosing the **Web API** tab and typing any value into **Key**, then
   clicking **Connect**, fails every time with the same message.

<p align="center"><img src="Steps/step22-webapi-key-structural-error.png" alt="Web API credential type rejecting a key with an ApiKeyName error" width="760"><br><sub><b>"A web API key can only be specified when a web API key name is provided."</b> This credential type only works when the M code itself declares an <code>ApiKeyName</code> option on <code>Web.Contents</code> so Power BI knows which header/query-string parameter to inject the key into. This file's ad-hoc <code>Web.Contents</code> calls never declare one, by design — the Bearer header is already built by hand — so no value typed here will ever satisfy this credential type.</sub></p>

### Step 18: Anonymous — rejected by the API's own preflight check

**Why this was tried next:** "Anonymous" tells Power BI *not* to inject any
credential of its own, which sounds like the right fit for a query that
already builds its own auth header. The nuance is that Power BI still runs
a bare connectivity check against the data source before it will save that
choice — and that check carries no custom headers at all.

<p align="center"><img src="Steps/step23-anonymous-auth-rejected.png" alt="Anonymous credential type rejected with a could not authenticate error" width="760"><br><sub><b>"We couldn't authenticate with the credentials provided."</b> The real usage API legitimately requires the Bearer token this file's M code builds by hand — a bare, header-less preflight request against the same host is correctly rejected. This isn't a bug in the query; it's Power BI validating a credential type before trusting it, using a plainer request than the query's own.</sub></p>

### Step 19: Organizational account — needs a live interactive sign-in

**Why this was tried last among the automatic options:** it's the one
credential type most likely to be genuinely valid for a Microsoft-hosted
API. The catch is what "valid" means here — it hands off to a real,
interactive Microsoft Entra sign-in flow, not this file's existing
refresh-token exchange.

<p align="center"><img src="Steps/step24-organizational-account-signin-wall.png" alt="Organizational account credential type showing a Sign in button" width="760"><br><sub><b>"You aren't signed in"</b> with a <b>Sign in</b> button. This path is correct for connectors that want Power BI to manage a fresh AAD session on your behalf — it isn't what this API wants either way, since the M code already carries its own delegated token end to end.</sub></p>

### Step 20: Side quest — building a real custom connector

Rather than keep working through the generic credential dialog's options,
the next move was to do this properly: a genuine Power Query **custom
connector** (`SCUDashboard.pq` → compiled to `SCUDashboard.mez`) exposing
`Hourly` and `Sessions` as native navigation-table entries under **Get
Data**, with its own first-class **Key** credential type — so Power BI
handles the one-time credential prompt itself, the same way it does for any
built-in connector, instead of the raw `Web.Contents` ad-hoc flow.

The connector source is included here as a reusable reference artifact:
[`SCUDashboard-connector.pq`](Steps/SCUDashboard-connector.pq). It contains
**zero secrets** — the refresh token is never inlined; it's read at runtime
from whatever the user types into Power BI's own credential dialog
(`Extension.CurrentCredential()[Key]`), which is the architecturally
"right" way to do this and strictly more secure than both the ad-hoc
`Web.Contents` pattern and the [Parameter pattern](#part-3-move-the-secret-into-a-parameter)
from Steps 1–14.

Build/placement checklist followed:

- [x] `.mez` built and placed in `%USERPROFILE%\Documents\Power BI Desktop\Custom Connectors\`.
- [x] File verified as a structurally valid zip containing the compiled `.pq`.
- [x] **File → Options → Security → "Allow any extension to load without
      validation or warning"** confirmed enabled (required for *any*
      unsigned custom connector to even be considered).
- [x] Power BI Desktop fully restarted after placing the file.
- [ ] Connector never appeared searching **Get Data** for "Security Copilot"
      or browsing the **Other** category — with **zero** errors, warnings,
      or log entries anywhere.

### Step 21: Root cause — the Microsoft Store edition can't load it

No combination of settings fixed it, because the real cause wasn't a
setting. Checking how Power BI Desktop is installed on this machine:

```powershell
Get-AppxPackage -Name "*PowerBI*" | Select-Object Name, PackageFullName, InstallLocation
```

```
Name            : Microsoft.MicrosoftPowerBIDesktop
PackageFullName : Microsoft.MicrosoftPowerBIDesktop_2.160.579.0_x64__8wekyb3d8bbwe
InstallLocation : C:\Program Files\WindowsApps\Microsoft.MicrosoftPowerBIDesktop_2.160.579.0_x64__8wekyb3d8bbwe
```

This is the **Microsoft Store (MSIX/AppX) edition**. That edition runs in a
Store app sandbox that **cannot load unsigned custom `.mez` connectors at
all** — a hard platform limitation enforced by Store packaging policy, not
documented anywhere inside the Power BI UI itself, and completely
independent of the "allow any extension" security setting (that setting
only matters for the separate, standalone/MSI-installed edition of Power BI
Desktop, downloaded directly from microsoft.com rather than the Store).
That fully explains every symptom observed: a correctly built, correctly
placed, structurally valid connector that silently never appears, with
nothing to debug because nothing is actually attempting to load it.

**Takeaway for next time:** custom connectors on this machine require
uninstalling the Store edition and installing the standalone MSI edition of
Power BI Desktop instead. The connector source above is kept exactly for
that future possibility — it needs no changes to work once run on an
edition that supports it.

### Step 22: Resolution — one real credential entry per host, then it sticks

With the connector path closed off, the fix for `Daily`/`Sessions` turned
out to be the generic credential dialog after all — just with the right
expectation set by Steps 17–19 above: of the five tabs in **Access Web
content** (Anonymous, Windows, Basic, Web API, Organizational account),
only the ones that actually match how the real API authenticates can
succeed, and the dialog's own "Select which level to apply these settings
to" dropdown matters too — it defaults to the bare host, and that's the
scope Power BI remembers the choice against. Once **one** credential entry
for a host is accepted, Power BI trusts that host for every query that
calls it going forward — a plain **Refresh**, with no further prompts,
works exactly like it already did for `Hourly`.

<p align="center"><img src="Steps/step25-daily-table-live-31-rows.png" alt="Daily table in Table view with 31 rows of live data" width="760"><br><sub><b>Daily</b> table in Table view — 31 rows, real dates and SCU figures, pulled live from the usage API.</sub></p>

<p align="center"><img src="Steps/step26-report-view-all-tables-present.png" alt="Report view with Data pane showing all three tables" width="760"><br><sub>Report view — <b>Daily</b>, <b>Hourly</b>, and <b>Sessions</b> all present in the Data pane, no "incomplete data" banner.</sub></p>

### Part 6 results

| Check | Result |
|---|---|
| `Hourly` refresh | **Succeeded** — converted cleanly once its host's credential was accepted |
| `Sessions` refresh | **Succeeded** — paginated pull, shares `Daily`'s host and credential |
| Web API + Key | **Fails structurally** — "A web API key can only be specified when a web API key name is provided" (Step 17); this M code never declares `ApiKeyName`, so no key value fixes it |
| Anonymous | **Rejected** — "We couldn't authenticate with the credentials provided" (Step 18); the API's own preflight check requires the Bearer header this credential type doesn't send |
| Organizational account | **Blocked on automation** — requires a live interactive Entra sign-in (Step 19), not this file's existing token exchange |
| Custom connector (`.mez`) | **Blocked** — Microsoft Store/MSIX edition can't load unsigned connectors (root-caused, not fixed; see [Step 21](#step-21-root-cause--the-microsoft-store-edition-cant-load-it)) |
| `Daily` refresh | **Succeeded** after Step 22 — 31 rows, in-memory data confirmed intact throughout |
| Full model refresh | **Succeeded** — all 3 tables, no errors |
| "Incomplete data" banner | **Gone** — confirmed via Report view |

#### Good to know (Part 6)

- **The live dashboard's queries currently inline the refresh token**, the
  same way Step 5's placeholder does — they were **not** migrated to the
  [Parameter pattern](#part-3-move-the-secret-into-a-parameter), let alone
  the connector's credential-prompt pattern (which is better than both).
  That's a real security gap worth closing: at minimum, move the token into
  a Power Query Parameter like Steps 1–14 do; ideally, revisit the custom
  connector once run on an edition of Power BI Desktop that can load it.
  Either way, **don't share this `.pbix` file as-is** — it has a live
  secret baked into its query definitions in plain text.
- **Power BI's data-source credential gate is generic, not query-aware.**
  It doesn't know this file's M code builds its own Bearer header — it only
  knows "does *something* work for this exact host", using whichever test
  that credential type performs. That's why three different credential
  types failed three different ways instead of one single error.
- **"No errors anywhere" is itself a diagnostic signal.** When a correctly
  built, correctly placed extension produces literally zero trace of itself
  trying (and failing) to load, that's a strong hint the platform isn't
  attempting to load it at all — worth checking the install edition before
  assuming a config or code problem.
- **A query that looks structurally identical to a working one can still
  hit a different credential state.** `Daily` and `Sessions` call the same
  endpoint with the same auth — the only difference is which one had
  already earned a one-time host-level credential trust in this file.

#### Troubleshooting (Part 6)

| Symptom | Likely cause and fix |
|---|---|
| `A web API key can only be specified when a web API key name is provided` | The M code's `Web.Contents` call never declares an `ApiKeyName` option. This credential type cannot work for this query shape — try Anonymous or Organizational account instead, or add `ApiKeyName` to the M code if you want Web API + Key to be the long-term pattern. |
| `We couldn't authenticate with the credentials provided` on Anonymous | The real API requires an `Authorization` header that Anonymous's bare preflight check doesn't send. Confirm the host is actually reachable with a valid Bearer token (e.g. via a REST client) before assuming the query itself is broken. |
| Organizational account shows "You aren't signed in" | Expected — this credential type always requires a real, interactive AAD sign-in. Not suitable for unattended/automated credential setup; use it only when a person is available to click through once. |
| Custom connector never appears in **Get Data**, no errors anywhere | Check the install edition first: `Get-AppxPackage -Name "*PowerBI*"`. If it returns a package, you're on the Store/MSIX edition and unsigned connectors cannot load — switch to the standalone MSI edition. |
| One query refreshes fine, a structurally identical one doesn't | Compare credential trust state per host/data-source (**Data source settings**, Step 16), not the M code. |
| A credential choice is accepted but the next refresh still prompts again | Check the "Select which level to apply these settings to" dropdown in **Access Web content** — a narrower level than intended may have been selected; re-clear and re-enter at the host level shown by default. |

---

## Lab results

| Check | Result |
|---|---|
| Placeholder token (Step 5) | `400 Bad Request` from the token endpoint — expected, confirms request shape |
| Real token via Parameter (Step 9) | **Succeeded** — `10 columns, 20 rows` returned |
| Data freshness | Real hourly timestamps through the current date (rolling 7-day window) |
| Data-source trust prompts | Two, one-time: Anonymous/Public privacy level for `login.microsoftonline.com` and the usage API host |
| Close & Apply (Step 10) | **Succeeded** — `Query1` loaded into the report's data model, editor closed automatically |
| Table visual (Step 12) | **Built successfully** — 4 real columns rendered on the report canvas from the loaded data |
| Canvas Refresh (Step 13) | **Succeeded** — re-ran end to end from the report canvas itself, no editor involved |
| Save (Step 14) | **Succeeded** — title bar confirms a real `.pbix` now exists on disk |
| Anything left running in the background? | **No** — the query only executes when something triggers a refresh |

## Good to know

- **A Power Query Parameter is not a vault.** It's stored as part of the
  query definition inside the `.pbix`/`.pbit` file, in plain text. It's a
  cleaner place to put a secret than inline M code, but it is **not**
  equivalent to Azure Key Vault or a credential store. Don't share the
  `.pbix` file itself without first clearing the parameter's value.
- **M can't write back to its own parameter.** M is a functional, stateless
  language — a refresh can *read* `ScuRefreshToken`, but nothing in the query
  can rotate it automatically. Per the original tool's README, this refresh
  token is valid for roughly 90 days, so daily/weekly scheduled refreshes
  are fine; for long unattended gaps, re-run `SCU-Setup.ps1` once to mint a
  fresh token and paste it back into the parameter.
- **The Edit Parameters dialog shows values unmasked.** There's no
  password-style field for Text parameters — see the callout in
  [Step 7](#step-7-create-the-scurefreshtoken-parameter).
- **The Queries pane previews parameter values next to their names.** Keep
  that in mind before screen-sharing or screenshotting the Power Query
  Editor with a real secret loaded.
- **This API only accepts delegated tokens.** An app-only
  (client-credentials) token was tested against the same endpoints and
  rejected outright — see
  [`AUTOMATION-COMPARISON.md`](../AUTOMATION-COMPARISON.md) for that result.
- **Want to go past one proof table to a full dashboard?** See
  [Part 6: Scaling to a full 3-table live dashboard](#part-6-scaling-to-a-full-3-table-live-dashboard)
  below — it scales this exact pattern to a 3-table live dashboard, works
  through three different credential-type failure modes one at a time, and
  documents a custom-connector dead end root-caused to a Microsoft
  Store/MSIX platform limitation.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `400 Bad Request` from the `…/oauth2/v2.0/token` URL | Expected if you're using the placeholder token from Step 5. If it happens with a real token, the token has likely expired (~90 days) — re-run `SCU-Setup.ps1`. |
| `403 Unauthorized to access account` from the usage API | The access token is app-only, not delegated. Confirm `GetAccessToken` used the `refresh_token` grant, not `client_credentials`. |
| Advanced Editor shows a red underline / "errors have been detected" | Usually a missing comma or quote after pasting — M is whitespace-tolerant but strict about punctuation. Compare against [`mcode-final-parameterized.m`](Steps/mcode-final-parameterized.m). |
| Refresh hangs on a privacy-level or trust prompt | Expected once per new host the query calls. Accept Anonymous/Public for both `login.microsoftonline.com` and the usage API host, or adjust in **File → Options → Privacy**. See [Privacy levels in Power Query](https://learn.microsoft.com/power-query/privacy-levels). |
| `ScuRefreshToken` shows as unrecognized/undefined in the M code | The parameter wasn't created yet, or its name doesn't exactly match (case-sensitive). Re-check **Manage Parameters**. |
| Refresh succeeds but returns 0 rows | The rolling 7-day window may genuinely have no usage in a quiet dev tenant — this isn't an error. Widen `#duration(7,0,0,0)` to test. |

## Roll back

1. Delete the table visual from the report canvas (select it → **Delete**).
2. **Home → Manage Parameters → Edit Parameters**, clear or delete
   `ScuRefreshToken` if you're done testing.
3. Delete `Query1` (right-click in the Data pane → **Delete**) to remove the
   query and its loaded data from the model entirely.
4. The `.pbix` saved in Step 14 has a real token in its parameter — treat
   that file itself as a secret. Don't share it; re-save without the
   parameter's value first, or delete the file entirely if you're done
   testing.

## Repository layout

```text
Automation-Alternatives/PowerQuery/
├── STEP-BY-STEP.md              This guide (Parts 1–6)
├── summary.html                 Polished single-page write-up (composite view, Parts 1–5)
├── 00-architecture-and-code.png M code + live result, side by side
├── 01-live-data-result.png      Live result, full size
└── Steps/                       All screenshots and reference code referenced above
    ├── step01 … step20          Parts 1–5 — single-table proof of concept
    ├── step21 … step26          Part 6 — scaling to the 3-table live dashboard
    ├── mcode-placeholder.m       The Step 5 version (inline placeholder token)
    ├── mcode-final-parameterized.m   The Step 8 version (references the Parameter)
    └── SCUDashboard-connector.pq      Part 6's custom connector source (no secrets —
                                       reusable on a Power BI Desktop edition that can
                                       load unsigned connectors; see Step 20)
```

## References

- [What is Power Query?](https://learn.microsoft.com/power-query/power-query-what-is-power-query)
- [Using the Power Query editor (incl. the Advanced Editor)](https://learn.microsoft.com/power-query/power-query-ui)
- [Parameters in Power Query](https://learn.microsoft.com/power-query/power-query-query-parameters)
- [Privacy levels in Power Query](https://learn.microsoft.com/power-query/privacy-levels)
- [`Web.Contents` — Power Query M reference](https://learn.microsoft.com/powerquery-m/web-contents)
- [`Json.Document` — Power Query M reference](https://learn.microsoft.com/powerquery-m/json-document)
- [Power Query M function reference (full index)](https://learn.microsoft.com/powerquery-m/power-query-m-function-reference)
- [Data refresh in Power BI](https://learn.microsoft.com/power-bi/connect-data/refresh-data)
- [Create and format table visualizations in Power BI](https://learn.microsoft.com/power-bi/visuals/power-bi-visualization-tables)
- [Format pane General tab overview (Size/Position properties)](https://learn.microsoft.com/power-bi/visuals/power-bi-visualization-format-pane-overview)
- [Power Query custom connectors overview](https://learn.microsoft.com/power-query/samples/overview)
- [Handling authentication in a custom connector](https://learn.microsoft.com/power-query/samples/trippin/9-doing-more-with-metadata/tripping9)
- [`Extension.CurrentCredential` — Power Query M reference](https://learn.microsoft.com/powerquery-m/extension-currentcredential)
- [Install Power BI Desktop (Store vs. direct download)](https://learn.microsoft.com/power-bi/fundamentals/desktop-get-the-desktop)

---

*Companion repo to [`Muatazawad2/SecurityCopilot`](https://github.com/Muatazawad2/SecurityCopilot/tree/main/SCU%20Module).*
