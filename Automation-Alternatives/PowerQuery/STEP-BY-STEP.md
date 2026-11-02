# Power Query — Step-by-Step Walkthrough (Approach 3)

This is a genuine, click-by-click screenshot walkthrough of building the Power
Query approach from a blank Power BI Desktop file — no PowerShell, no Logic
App, no Power Automate. It supplements [`summary.html`](summary.html) (the
polished write-up) with the actual steps as they happened in the dev tenant.

**Shared starting point:** the `SCU-Usage-Puller` app from [Part 1](../../README.md)
and its already-obtained delegated refresh token. See
[`AUTOMATION-COMPARISON.md`](../AUTOMATION-COMPARISON.md) for why this API
requires a delegated (signed-in-user) token rather than app-only credentials.

---

## Step 1 — Start Power BI Desktop

Opened Power BI Desktop and chose **Blank report** from the start screen.

![Power BI Desktop start screen](Steps/step01-powerbi-start-screen.png)

The report canvas opens with an empty **Page 1** and the standard ribbon.

![Blank report opened](Steps/step02-blank-report-opened.png)

---

## Step 2 — Get Data → Blank Query

**Home → Get data → More…** opens the **Get Data** connector picker.

![Get Data dialog](Steps/step03-getdata-dialog.png)

Typed "Blank Query" into the search box to filter straight to it (no
connection parameters needed for this source).

![Search filtered to Blank Query](Steps/step04-search-blankquery.png)

Selecting **Blank Query** and clicking **Connect** opens the **Power Query
Editor** directly with a new, empty `Query1`.

![Power Query Editor opened](Steps/step05-query-editor-opened.png)

---

## Step 3 — Advanced Editor

**Home → Advanced Editor** opens the M code editor. A brand-new blank query
defaults to `let Source = "" in Source`.

![Advanced Editor opened with default code](Steps/step06-advanced-editor-opened.png)

### 3a — First pass: token inlined (quick, but not how to leave it)

Pasted the full M code with the refresh token **inlined as a literal string**
— the fastest way to confirm the approach works end to end, but not
production-safe (the secret would sit in plain text inside the `.pbix`).

![M code pasted with placeholder token](Steps/step07-mcode-pasted.png)

Running it with a placeholder in place of a real token produces the expected
`400 Bad Request` from the token endpoint — useful confirmation that the query
shape and request plumbing are correct before a real token is ever involved.

![Placeholder token produces expected 400](Steps/step08-placeholder-token-fails.png)

---

## Step 4 — Switch to a Power Query Parameter (the safe way)

Rather than leave the token inlined, moved it to a **Power Query Parameter**
so it never appears in the M code itself. **Home → Manage Parameters** is a
split button — clicking it opens **Edit Parameters** / **New Parameter**.

![Manage Parameters menu](Steps/step09-manage-parameters-menu.png)

**Edit Parameters** shows every parameter on the query by name, with its
current value in an editable box. `ScuRefreshToken` was created here as a
**Text** parameter holding the decrypted refresh token — screenshotted with a
placeholder in the field (`<paste your decrypted refresh token here>`) rather
than the live value, since this dialog shows its contents in plain text with
no masking.

![Edit Parameters dialog](Steps/step10-edit-parameters-dialog.png)

---

## Step 5 — Rewrite the M code to reference the Parameter

With `ScuRefreshToken` now a Parameter, the M code no longer declares or
inlines it — it's referenced as a bare identifier, resolved automatically by
Power Query at evaluation time. The query list on the left shows both
`Query1` and the `ScuRefreshToken` parameter.

![Final M code referencing the parameter](Steps/step11-parameterized-mcode.png)

> The parameter's live value does appear in that left-hand queries list (Power
> Query previews a parameter's current value next to its name). That portion
> is masked/relabeled in this screenshot for the same reason as Step 4 — it's
> not rendered any differently in the real UI.

---

## Step 6 — Refresh and confirm live data

**Home → Refresh Preview** re-runs the query: exchanges the refresh token for
an access token, calls the SCU usage API, and returns the result table.

![Live data result — 10 columns, 20 rows](Steps/step12-live-data-result.png)

**10 columns, 20 rows**, real hourly aggregates with real timestamps,
confirmed by the **"Preview downloaded at …"** status in the bottom-right
corner. From here, clicking **Close & Apply** loads it into the report's data
model like any other query — every subsequent **Refresh** in Power BI repeats
this exact flow with no external moving parts.

---

## Why a Parameter instead of inlining the token

| | Inlined in M code | Power Query Parameter |
|---|---|---|
| Where the secret lives | Inside every copy of the `.pbix` file's query definition | Still inside the `.pbix`, but as a named, swappable value |
| Rotating the token | Edit the M code | Edit one field in Manage Parameters |
| Accidental exposure risk | Shows up in any M code export, screenshot, or diff of the query | Same risk applies to the parameter's value field — treat both as secrets |
| Readability | Secret mixed into logic | Logic and secret cleanly separated |

Either way, the token is **still a secret value stored in Power BI**, not a
vault-backed credential — as called out in `summary.html`, this is a proof of
concept, not a hardened production pattern. For production use, pair this
with Power BI's **[dataset credentials / gateway-level parameter
binding](https://learn.microsoft.com/power-bi/connect-data/power-bi-data-sources)**
or an Azure Key Vault-backed secret instead of a plain Text parameter.

---

*Private working notes — review before adding to the public `SecurityCopilot` repo.*
