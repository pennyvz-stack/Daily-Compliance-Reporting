# Daily Commit Compliance Reporting Tool

An automated administrative solution designed for SQL Server Database Administrators to track, audit, and report cross-regional developer Git commit compliance against localized working schedules.

## 🚀 General Deployment Steps

1. **Roster Setup:** Run `01_Create_Table.sql` in SSMS to build the developer registry.
2. **Holiday Reference:** Run `02_Company_Holidays.sql` in SSMS to build and populate the 5-year federal lookup table.
3. **Script Host:** Save `DailyCommitReport.ps1` to `C:\Scripts\` and configure execution/security policies.
4. **Automation:** Run `03_Provision_Agent_Job.sql` in SSMS to schedule the 7:00 AM daily execution.

---

## 🌐 Core Engine Architecture: GitHub REST API Integration

Unlike local repository log monitoring, this production engine interfaces directly with the cloud-hosted **GitHub REST API v3**. This ensures the reporting tool acts as a centralized compliance hub, evaluating developer activity across the entire organization without requiring local repository clones on the host server.

### API Data Pipeline & Endpoint Ingestion
* **Target Endpoint Construction:** The script dynamically builds a unique URI target by mapping the target organization and project context directly into the GitHub REST schema:
  `https://api.github.com/repos/pennyvz-stack/Daily-Compliance-Reporting/commits`
* **Transport & Authentication:** Outbound traffic is dispatched via a secure HTTPS `GET` request using PowerShell's native `Invoke-RestMethod` engine. Security credentials are passed explicitly via custom HTTP Request Headers utilizing a restricted Personal Access Token (`Authorization: token <PAT_SECRET>`) and an explicit `User-Agent` string to completely bypass anonymous API rate limits.
* **Server-Side Filtering:** To minimize network overhead and processing time, the engine appends query string parameters (`?since=...&until=...`) directly to the URL string. This forces GitHub's cloud servers to isolate and return only the commit data matching the strict ISO-8601 UTC business window required for the audit.
* **Payload Handling & Object Parsing:** The endpoint streams back a structured native JSON payload. The script catches this data in mid-air, automatically maps the deeply nested attribute paths (`$response.commit.author.email` and `$response.commit.author.date`) into local memory arrays, and feeds them directly into the database comparison engine.

---

## 📅 Target Window Configuration: Smart Weekend & Holiday Lookback

To prevent false "NO COMMITS" compliance alerts on non-working days, the engine utilizes a dynamic, data-driven lookback window loop rather than static daily math.

### Business Day Evaluation Loop
1. **Initial Evaluation:** The script initializes by targeting `Today - 1 Day`.
2. **Weekend Skip:** If the evaluated date lands on a Saturday or Sunday, the script decrements the window further into the past.
3. **Database Holiday Check:** For weekday targets, the engine executes a direct `Invoke-SqlCmd` query against `dbo.CompanyHolidays`. If the date matches a registered corporate or Federal day off, the script skips the holiday and decrements again.
4. **Window Lock:** The loop exits only when a valid, active business day is discovered. The final report is then bound strictly to that calendar date from `00:00:00` to `23:59:59`.

---

## 📧 Corporate Email Infrastructure Integration

While basic SMTP configurations work for testing environments, modern corporate infrastructures (such as **Microsoft 365 / Exchange Online**) enforce strict security barriers that block anonymous or standard consumer email relays. 

### Option A: Exchange Online SMTP Auth (Dedicated Service Account)
* **Relay Host:** `smtp.office365.com` (Port 587, TLS Explicit Encryption Required).
* **Identity Requirement:** A dedicated, non-human corporate mailbox (e.g., `db-compliance-alerts@yourcompany.com`).

### Option B: Microsoft Graph API (Modern Auth - Recommended)
* **Authentication:** An Azure App Registration is provisioned with `Mail.Send` application permissions.
* **Execution:** The script requests a temporary OAuth 2.0 access token via a client secret or certificate, sending the HTML report payload through a secure POST request to the Microsoft Graph endpoint.

---

## 🔐 Enterprise Credential Governance & Security Policy

### A. Personal Access Tokens (PATs)
* **Scope Minimization:** When generating a GitHub PAT for this tool, restrict permissions strictly to `repo:status` and `public_repo` (read-only metadata access).
* **Hard Token Expiration Policy:** In compliance with corporate data protection policies, **all administrative PATs must be configured with a maximum 90-day expiration lifetime.** System administrators must schedule quarterly rotation tasks to refresh the token block.

### B. Run-Time Secret Injection
1. **Windows Credential Manager:** Store the App Secret or PAT securely inside the host operating system's credential locker under the SQL Server Agent service account profile. The script will dynamically call `Get-StoredCredential` at runtime.
2. **Environment Variables:** Inject secrets into the host machine’s System Environment Variables as encrypted strings, which the PowerShell runtime reads directly from memory (`$env:CORP_MAIL_SECRET`).

---

## Compliance Alert Handling & UI Styling

The reporting engine evaluates developer code submissions against their localized working schedules. If a developer fails to push code within their designated business-day lookback window, the reporting script dynamically highlights their row in **bold red text** within the morning email delivery for immediate executive review.
