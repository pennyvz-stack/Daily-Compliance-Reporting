Daily Commit Compliance Reporting Tool
An automated administrative solution designed for SQL Server Database Administrators to track, audit, and report cross-regional developer Git commit compliance against localized working schedules.

🚀 General Deployment Steps
Developer Roster Setup: Run 01_DeveloperRegistry.sql in SSMS to build the developer infrastructure registry.

Repository Registry Setup: Run 02_RepositoryRegistry.sql in SSMS to provision the multi-repository tracking tables.

Holiday Reference: Run 03_CompanyHolidays.sql in SSMS to populate the rolling federal lookup calendar.

Script Host Deployment: Save DailyCommitReport.ps1 to your production execution folder and verify execution/security policies.

SQL Agent Automation: Run 04_ProvisionAgentJob.sql in SSMS to schedule the 7:00 AM daily administrative execution.

🌐 Core Engine Architecture: GitHub REST API Integration
Unlike local repository log monitoring, this production engine interfaces directly with the cloud-hosted GitHub REST API v3. This ensures the reporting tool acts as a centralized compliance hub, evaluating developer activity across the entire organization without requiring local repository clones on the host server.

API Data Pipeline & Endpoint Ingestion
Target Endpoint Construction: The script dynamically builds unique URI targets by mapping the target organization and auto-discovered repository contexts directly into the GitHub REST schema:
https://api.github.com/repos/pennyvz-stack/<RepositoryName>/commits

Transport & Authentication: Outbound traffic is dispatched via a secure HTTPS GET request using PowerShell's native Invoke-RestMethod engine. Security credentials are passed explicitly via custom HTTP Request Headers utilizing an explicit User-Agent string to completely bypass anonymous API rate limits.

Server-Side Filtering: To minimize network overhead and processing time, the engine appends query string parameters (?since=...&until=...) directly to the URL string. This forces GitHub's cloud servers to isolate and return only the commit data matching the strict ISO-8601 UTC business window required for the audit.

Payload Handling & Object Parsing: The endpoint streams back a structured native JSON payload. The script catches this data in mid-air, automatically maps the deeply nested attribute paths ($response.commit.author.email and $response.commit.author.date) into local memory arrays, and feeds them directly into the database comparison engine.

📅 Target Window Configuration: Smart Weekend & Holiday Lookback
To prevent false "NO COMMITS" compliance alerts on non-working days, the engine utilizes a dynamic, data-driven lookback window loop rather than static daily math.

Business Day Evaluation Loop
Initial Evaluation: The script initializes by targeting Today - 1 Day.

Weekend Skip: If the evaluated date lands on a Saturday or Sunday, the script decrements the window further into the past.

Database Holiday Check: For weekday targets, the engine executes a direct Invoke-SqlCmd query against dbo.CompanyHolidays. If the date matches a registered corporate or Federal day off, the script skips the holiday and decrements again.

Window Lock: The loop exits only when a valid, active business day is discovered. The final report is then bound strictly to that calendar date from 00:00:00 to 23:59:59.

📧 Corporate Email Infrastructure Integration
While basic SMTP configurations work for testing environments, modern corporate infrastructures (such as Microsoft 365 / Exchange Online) enforce strict security barriers that block anonymous or standard consumer email relays.

Option A: Exchange Online SMTP Auth (Dedicated Service Account)
Relay Host: smtp.office365.com (Port 587, TLS Explicit Encryption Required).

Identity Requirement: A dedicated, non-human corporate mailbox (e.g., db-compliance-alerts@yourcompany.com).

Option B: Microsoft Graph API (Modern Auth - Recommended)
Authentication: An Azure App Registration is provisioned with Mail.Send application permissions.

Execution: The script requests a temporary OAuth 2.0 access token via a client secret or certificate, sending the HTML report payload through a secure POST request to the Microsoft Graph endpoint.

🔐 Enterprise Credential Governance & Security Policy
A. Personal Access Tokens (PATs)
Scope Minimization: When generating a GitHub PAT for this tool, restrict permissions strictly to repo:status and public_repo (read-only metadata access).

Hard Token Expiration Policy: In compliance with corporate data protection policies, all administrative PATs must be configured with a maximum 90-day expiration lifetime. System administrators must schedule quarterly rotation tasks to refresh the token block.

B. Run-Time Secret Injection & Interactive Prompts
Interactive Operational Prompt: To support rapid developer troubleshooting without modifying script variables, the engine utilizes an interactive choice prompt at launch, letting administrators toggle seamlessly between a localized Test Run (Forced to Today) and a Production Run (Rolling Calendar Lookback).

Decoupled Credential Handshake: To enforce zero plain-text password vulnerabilities, the tool leverages the host operating system's native Get-Credential API. The app password/token is unpacked directly inside a transient in-memory network variable and destroyed immediately following SMTP transmission, completely isolating corporate secrets from disk tracking.

📊 Compliance Alert Handling & UI Styling
The reporting engine evaluates developer code submissions against their localized working schedules.

Granular Sub-totals: The reporting payload uses nested memory arrays to build list-itemized repository sub-totals (<li><code>repo</code>: <strong>X</strong> commits</li>), detailing exactly where hours were spent.

Compliance Flags: If a developer fails to push code within their designated business-day lookback window, the reporting script dynamically overrides standard table rows, highlighting the target user in bold red text (background-color: #fce8e6;) within the morning email delivery for immediate executive review.