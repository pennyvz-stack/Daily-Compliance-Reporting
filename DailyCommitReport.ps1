# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - EXECUTIVE DRILLDOWN ARCHITECTURE
# ==============================================================================

# ---- 1. CORE ENTERPRISE CONFIGURATION & INTERACTIVE PROMPT ----
$owner      = "pennyvz-stack"
$sqlServer  = "DESKTOP-LQEABPI\TEST"
$database   = "DBA_Tools"
$gmailUser  = "pennyvz@gmail.com"
$dashboardPath = "C:\Daily-Compliance-Reporting\AuditDashboard.html"

# Build an interactive Windows Choice Prompt for the operational mode
$Host.UI.RawUI.WindowTitle = "Daily Commit Compliance Engine [DRILLDOWN EDITION]"
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   SELECT OPERATIONAL EXECUTION MODE"               -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " 1) Test Run       - Audit target window forced to TODAY" -ForegroundColor Yellow
Write-Host " 2) Production Run - Automated rolling lookback (Yesterday/Friday/Holidays)" -ForegroundColor Green
Write-Host ""

$choice = $null
while ($choice -notin 1, 2) {
    $input = Read-Host "Enter selection (1 or 2)"
    if ($input -eq "1") { $choice = 1; $TestMode = $true }
    if ($input -eq "2") { $choice = 2; $TestMode = $false }
}

# ---- 2. DYNAMIC SECURE AUTHENTICATION ENGINE ----
Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   INITIALIZING SECURE SECURITY HANDSHAKE"           -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt A: Capture GitHub Personal Access Token
Write-Host "Please enter your GITHUB PAT in the Windows secure prompt:" -ForegroundColor Yellow
$gitCredential = Get-Credential -UserName "GitHub_API_Token" -Message "GitHub Cloud API Authentication Gateway"
$githubToken = $gitCredential.GetNetworkCredential().Password

# Prompt B: Capture Gmail App Password
Write-Host ""
Write-Host "Please enter your GMAIL APP PASSWORD in the Windows secure prompt:" -ForegroundColor Yellow
$smtpCredential = Get-Credential -UserName $gmailUser -Message "Gmail SMTP Gateway Authentication"
$plainPassword = $smtpCredential.GetNetworkCredential().Password


# ---- 3. TARGET WINDOW CONFIGURATION (SMART WEEKEND & HOLIDAY LOOKBACK) ----
if ($TestMode) {
    $targetDate = (Get-Date).Date
    $dateString = $targetDate.ToString("yyyy-MM-dd")
    Write-Host ""
    Write-Host "[TEST MODE ACTIVE] Forcing tracking window to TODAY's date." -ForegroundColor Yellow
} else {
    $daysToLookBack = -1
    $targetDate = (Get-Date).AddDays($daysToLookBack).Date
    $isBusinessDay = $false

    while (-not $isBusinessDay) {
        $dayOfWeek = $targetDate.DayOfWeek
        $dateString = $targetDate.ToString("yyyy-MM-dd")
        
        if ($dayOfWeek -eq "Saturday" -or $dayOfWeek -eq "Sunday") {
            $daysToLookBack--
            $targetDate = (Get-Date).AddDays($daysToLookBack).Date
        } else {
            $holidayCheckQuery = "SELECT COUNT(1) FROM dbo.CompanyHolidays WHERE HolidayDate = '$dateString'"
            try {
                $isHoliday = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $holidayCheckQuery -ErrorAction Stop
                if ($isHoliday[0] -gt 0) {
                    Write-Host "Holiday detected: $dateString. Rolling lookback window backward." -ForegroundColor Yellow
                    $daysToLookBack--
                    $targetDate = (Get-Date).AddDays($daysToLookBack).Date
                } else {
                    $isBusinessDay = $true
                }
            } catch {
                Write-Host "Database holiday lookup failed. Defaulting to standard day tracking." -ForegroundColor Red
                $isBusinessDay = $true
            }
        }
    }
}

# Define the precise lookback window filter strings for the API queries
$sinceUtc = $targetDate.ToString("yyyy-MM-ddT00:00:00Z")
$untilUtc = $targetDate.ToString("yyyy-MM-ddT23:59:59Z")
$staleThresholdDate = (Get-Date).AddDays(-3) # Stale if no pushes upstream in 3 days

Write-Host "Target tracking window finalized: Audit Date is $dateString" -ForegroundColor Green

# ---- 4. REPOSITORY AUTO-DISCOVERY ----
$discoveryUrl = "https://api.github.com/users/$owner/repos?per_page=100"
$headers = @{ 
    "User-Agent"    = "PowerShell-DBA-Audit Engine"
    "Authorization" = "token $githubToken" 
}

try {
    $liveCloudRepos = Invoke-RestMethod -Uri $discoveryUrl -Method Get -Headers $headers -ErrorAction Stop
    foreach ($repo in $liveCloudRepos) {
        $currentRepoName = $repo.name
        $checkRepoQuery = "SELECT COUNT(1) FROM dbo.RepositoryRegistry WHERE RepositoryName = '$currentRepoName'"
        $repoExists = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $checkRepoQuery -ErrorAction Stop
        if ($repoExists[0] -eq 0) {
            $insertRepoQuery = "INSERT INTO dbo.RepositoryRegistry (RepositoryName, IsActive) VALUES ('$currentRepoName', 1);"
            Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $insertRepoQuery -ErrorAction Stop
        }
    }
} catch {
    Write-Host "Warning: Cloud discovery step failed. Falling back strictly to existing SQL records." -ForegroundColor Red
}

# ---- 5. LOAD ROSTERS ----
$repoPullQuery = "SELECT RepositoryName FROM dbo.RepositoryRegistry WHERE IsActive = 1"
$dbRepos = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $repoPullQuery
if ($dbRepos.Count -eq $null) { $repositories = @($dbRepos.RepositoryName) }
else { $repositories = @($dbRepos | ForEach-Object { $_.RepositoryName }) }

$devQuery = "SELECT DeveloperEmail, TimeZoneID FROM dbo.DeveloperRegistry WHERE IsActive = 1"
$dbRoster = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $devQuery
$developers = @($dbRoster.DeveloperEmail)
$developerTimeZones = @{}
foreach ($row in $dbRoster) { $developerTimeZones[$row.DeveloperEmail] = $row.TimeZoneID }

# ---- 6. DATA EXTRACTION (UPGRADED MULTI-BRANCH PARSING PIPELINE) ----
$response = @()
$repoMetadata = @{} # Tracks absolute branch metadata to isolate stale vulnerabilities

Write-Host ""
Write-Host "Executing Cross-Branch Scanning Matrix..." -ForegroundColor Cyan

foreach ($repo in $repositories) {
    $repoMetadata[$repo] = @{
        ActiveTodayCount = 0
        StaleCount       = 0
        BranchList       = @()
    }

    $branchUrl = "https://api.github.com/repos/$owner/$repo/branches?per_page=100"
    try {
        $discoveredBranches = Invoke-RestMethod -Uri $branchUrl -Method Get -Headers $headers -ErrorAction Stop
        Write-Host " -> Repository [$repo]: Found $($discoveredBranches.Count) active branches to scan." -ForegroundColor Gray
        
        foreach ($b in $discoveredBranches) {
            $branchName = $b.name
            
            # Query 1: Get latest raw commit metadata to evaluate absolute chronological freshness/staleness
            $metaUrl = "https://api.github.com/repos/$owner/$repo/branches/$branchName"
            $branchMeta = Invoke-RestMethod -Uri $metaUrl -Method Get -Headers $headers -ErrorAction Stop
            $lastPushDateStr = $branchMeta.commit.commit.author.date
            $lastPushDate = [DateTime]$lastPushDateStr
            
            # Query 2: Extract active commits strictly mapped inside our reporting window
            $apiUrl = "https://api.github.com/repos/$owner/$repo/commits?sha=$branchName&since=$sinceUtc&until=$untilUtc&per_page=100"
            $todayCommitCount = 0
            
            try {
                $cloudCommits = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop
                $todayCommitCount = $cloudCommits.Count
                
                foreach ($commitWrap in $cloudCommits) {
                    $email = $commitWrap.commit.author.email
                    $dateStr = $commitWrap.commit.author.date
                    $sha = $commitWrap.sha 
                    
                    $response += [PSCustomObject]@{
                        repo   = $repo
                        branch = $branchName
                        sha    = $sha
                        commit = [PSCustomObject]@{
                            author = [PSCustomObject]@{ email = $email; date = $dateStr }
                        }
                    }
                }
            } catch {}

            # Evaluate tracking health parameters
            $isStale = $lastPushDate -lt $staleThresholdDate
            if ($todayCommitCount -gt 0) { $repoMetadata[$repo].ActiveTodayCount++ }
            if ($isStale) { $repoMetadata[$repo].StaleCount++ }

            # Append structured payload to build the drilldown HTML panels later
            $repoMetadata[$repo].BranchList += [PSCustomObject]@{
                BranchName     = $branchName
                LastPush       = $lastPushDate
                IsStale        = $isStale
                CommitsToday   = $todayCommitCount
            }
        }
    } catch {
        Write-Host "      Warning: Failed to complete data mapping matrix for $repo." -ForegroundColor Red
    }
}

# ---- 7. PROCESS DRILLDOWN ROSTER RECORDS ----
$devRepoBranchSubtotals = @{}
foreach ($dev in $developers) { $devRepoBranchSubtotals[$dev] = @{} }

foreach ($item in $response) {
    $email = $item.commit.author.email
    $currentRepo = $item.repo
    $currentBranch = $item.branch
    
    if ($developers -contains $email) {
        $matchedKey = ($devRepoBranchSubtotals.Keys | Where-Object { $_ -eq $email })
        $branchKey = "$currentRepo ($currentBranch)"
        if (-not $devRepoBranchSubtotals[$matchedKey].ContainsKey($branchKey)) {
            $devRepoBranchSubtotals[$matchedKey][$branchKey] = 0
        }
        $devRepoBranchSubtotals[$matchedKey][$branchKey]++
    }
}

# ---- 8. GENERATE LEVEL 1: HIGH-LEVEL EXECUTIVE EMAIL BODY ----
$emailRows = ""
foreach ($repo in $repositories) {
    $activeCount = $repoMetadata[$repo].ActiveTodayCount
    $staleCount  = $repoMetadata[$repo].StaleCount
    
    $staleStyle = ""
    $staleLabel = "<span style='color: #888;'>0 Stale</span>"
    if ($staleCount -gt 0) {
        $staleStyle = " background-color: #fce8e6;"
        $staleLabel = "<span style='color: #cc0000; font-weight: bold;'>$staleCount Stale Target(s) ⚠️</span>"
    }

    $activeLabel = "<span style='color: #888;'>0 Active</span>"
    if ($activeCount -gt 0) {
        $activeLabel = "<span style='color: green; font-weight: bold;'>$activeCount Active</span>"
    }

    $emailRows += "<tr style='border-bottom: 1px solid #ddd;$staleStyle'>"
    $emailRows += "<td style='padding: 10px; border: 1px solid #ddd;'><strong>$repo</strong></td>"
    $emailRows += "<td style='padding: 10px; border: 1px solid #ddd; text-align: center;'>$activeLabel</td>"
    $emailRows += "<td style='padding: 10px; border: 1px solid #ddd; text-align: center;'>$staleLabel</td>"
    $emailRows += "</tr>"
}

$emailBody = "<html><body style='font-family: Calibri, Arial, sans-serif; font-size: 14px; color: #333;'>"
$emailBody += "<p>Good morning Vinh,</p>"
$emailBody += "<p>Here is the automated **Enterprise Repository Health Summary** for the business day <strong>$dateString</strong>. This report highlights active workspaces and surfaces unpushed local code risks.</p>"
$emailBody += "<table style='border-collapse: collapse; width: 100%; max-width: 650px; border: 1px solid #ddd;'>"
$emailBody += "<thead><tr style='background-color: #1f4e78; color: white;'><th>Target Repository</th><th style='text-align: center;'>Active Branches (Today)</th><th style='text-align: center;'>Stale Branches (>3 Days Unpushed)</th></tr></thead>"
$emailBody += "<tbody>$emailRows</tbody></table>"
$emailBody += "<p style='margin-top: 20px; font-size: 15px;'>"
$emailBody += "🔗 <strong><a href='file:///$dashboardPath' style='color: #1f4e78; text-decoration: underline;'>Click here to open the Interactive Drilldown Portal</a></strong> for itemized developer counts and branch tracking logs."
$emailBody += "</p><p style='font-size: 11px; color: #777; margin-top: 30px;'>This is an automated risk-mitigation management report.</p></body></html>"


# ---- 9. GENERATE LEVEL 2: INTERACTIVE DRILLDOWN PORTAL (HTML FILE) ----
$dashboardHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>Enterprise Compliance Portal</title>
    <style>
        body { font-family: 'Segoe UI', Calibri, Arial, sans-serif; padding: 30px; background-color: #f4f6f9; color: #333; }
        h2 { color: #1f4e78; margin-bottom: 5px; }
        .meta-header { color: #555; margin-bottom: 25px; font-size: 14px; }
        summary { font-size: 16px; font-weight: bold; padding: 14px; background-color: #1f4e78; color: white; border-radius: 4px; cursor: pointer; margin-top: 12px; outline: none; display: flex; justify-content: space-between; align-items: center; }
        summary:hover { background-color: #2c6b9e; }
        details { margin-bottom: 5px; }
        details[open] summary { border-radius: 4px 4px 0 0; background-color: #1a4266; }
        .drilldown-box { background: white; padding: 20px; border: 1px solid #ddd; border-top: none; border-radius: 0 0 4px 4px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 14px; }
        th { background-color: #f8f9fa; color: #555; padding: 10px; border: 1px solid #ddd; text-align: left; font-weight: 600; }
        td { padding: 10px; border: 1px solid #ddd; vertical-align: top; }
        .stale-row { background-color: #fdf3f2; }
        .stale-alert { color: #cc0000; font-weight: bold; background-color: #fce8e6; padding: 3px 8px; border-radius: 3px; font-size: 12px; border: 1px solid #f9c1bc; }
        .active-tag { color: #1e7e34; font-weight: bold; background-color: #d4edda; padding: 3px 8px; border-radius: 3px; font-size: 12px; border: 1px solid #c3e6cb; }
        .neutral-tag { color: #6c757d; background-color: #e2e3e5; padding: 3px 8px; border-radius: 3px; font-size: 12px; }
    </style>
</head>
<body>
    <h2>Internal Compliance Audit Portal — Team Branch Drilldown</h2>
    <div class="meta-header">Generated on **$dateString** | Targeted Lookback Configuration: 24-Hour Business Window</div>
"@

foreach ($repo in $repositories) {
    $staleCount = $repoMetadata[$repo].StaleCount
    $headerAlert = ""
    if ($staleCount -gt 0) { $headerAlert = " ⚠️ ($staleCount STALE BRANCHES DETECTED)" }
    
    $dashboardHtml += "<details><summary>📦 Repository: $repo $headerAlert <span>Toggle Inspection Block</span></summary><div class='drilldown-box'><table>"
    $dashboardHtml += "<tr><th>Branch Context</th><th style='text-align: center;'>Commits Today</th><th>Upstream Freshness Status</th><th>Last Upstream Date (UTC)</th></tr>"
    
    # Extract branch metadata list sorted by stale items first
    $sortedBranches = $repoMetadata[$repo].BranchList | Sort-Object IsStale -Descending
    foreach ($b in $sortedBranches) {
        $rowClass = ""
        if ($b.IsStale) { 
            $rowClass = " class='stale-row'"
            $statusLabel = "<span class='stale-alert'>RISK: STALE WORK (Unpushed > 3 Days)</span>"
        } elseif ($b.CommitsToday -gt 0) {
            $statusLabel = "<span class='active-tag'>ACTIVE: Sync Complete (Today)</span>"
        } else {
            $statusLabel = "<span class='neutral-tag'>DORMANT: Standard Sync Baseline</span>"
        }

        $dashboardHtml += "<tr$rowClass>"
        $dashboardHtml += "<td><code>$($b.BranchName)</code></td>"
        $dashboardHtml += "<td style='text-align: center;'><strong>$($b.CommitsToday)</strong></td>"
        $dashboardHtml += "<td>$statusLabel</td>"
        $dashboardHtml += "<td>$($b.LastPush.ToString('yyyy-MM-dd HH:mm:ss'))</td>"
        $dashboardHtml += "</tr>"
    }
    $dashboardHtml += "</table></div></details>"
}

$dashboardHtml += "</body></html>"
$dashboardHtml | Out-File -FilePath $dashboardPath -Encoding utf8 -Force
Write-Host "Success: Interactive drilldown dashboard refreshed at $dashboardPath" -ForegroundColor Green

# ---- 10. MAIL TRANSMISSION ENGINE ----
try {
    Write-Host ""
    Write-Host "Establishing secure TLS connection to Gmail SMTP Gateway..." -ForegroundColor Cyan
    
    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = New-Object System.Net.Mail.MailAddress($gmailUser)
    $mail.To.Add($gmailUser) # Switch to $bossEmail when ready to pull the trigger
    $mail.Subject = "Enterprise Commit Compliance & Risk Summary - $dateString"
    $mail.Body = $emailBody
    $mail.IsBodyHtml = $true
    $mail.BodyEncoding = [System.Text.Encoding]::UTF8

    $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential($gmailUser, $plainPassword)
    
    $smtp.Send($mail)
    $smtp.Dispose()
    Write-Host "Success: Executive macro report dispatched to inbox!" -ForegroundColor Green
} catch {
    Write-Host "Failed to dispatch compliance email: $_" -ForegroundColor Red
}