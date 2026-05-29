# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - FORCED TODAY TEST
# ==============================================================================

# ---- CONFIG ----
$owner      = "pennyvz-stack"
$repo       = "Daily-Compliance-Reporting"
$ghPat      = "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"

# SMTP Mail Settings (Gmail Relay)
$smtpServer = "smtp.gmail.com"
$smtpPort   = 587
$emailTo    = "pennyvz@gmail.com"
$emailFrom  = "pennyvz@gmail.com" 

# Secure Mail Credentials
$gmailUser    = "pennyvz@gmail.com"
$gmailAppPass = "yfeykmhetvmmookl" 
$SecurePassword = ConvertTo-SecureString $gmailAppPass -AsPlainText -Force
$smtpCredential = New-Object System.Management.Automation.PSCredential($gmailUser, $SecurePassword)

# ---- FORCED FORCE FOR TODAY TESTING ----
# Bypassing the rolling check so it looks strictly at today's calendar date
$targetDate = (Get-Date).Date
$fromDate = $targetDate.ToString("yyyy-MM-ddT00:00:00Z")
$toDate   = $targetDate.ToString("yyyy-MM-ddT23:59:59Z")

# ---- GITHUB API REST DATA INGESTION ----
$headers = @{
    "Authorization" = "token $ghPat"
    "Accept"        = "application/vnd.github.v3+json"
}
$url = "https://api.github.com/repos/$owner/$repo/commits?since=$fromDate&until=$toDate&per_page=100"

try { 
    $response = Invoke-RestMethod -Uri $url -Headers $headers 
} catch { 
    Write-Host "GitHub API call failed: $_" -ForegroundColor Red
    $response = @() 
}

# ---- DYNAMIC DEVELOPER ROSTER (SQL SERVER) ----
$sqlServer = "DESKTOP-LQEABPI\TEST" 
$database  = "DBA_Tools"
$query     = "SELECT DeveloperEmail, TimeZoneID FROM dbo.DeveloperRegistry WHERE IsActive = 1"

try {
    $dbRoster = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $query
    $developers = $dbRoster.DeveloperEmail
    $developerTimeZones = @{}
    foreach ($row in $dbRoster) { $developerTimeZones[$row.DeveloperEmail] = $row.TimeZoneID }
} catch {
    Write-Host "Database Roster Retrieval Failed: $_" -ForegroundColor Red
    exit
}

# ---- DATA COMPUTATION & TIME ZONE TRANSLATION ----
$commitCounts = @{}; $lastCommitLocal = @{}
foreach ($dev in $developers) { $commitCounts[$dev] = 0; $lastCommitLocal[$dev] = $null }

foreach ($commit in $response) {
    $email = $commit.commit.author.email
    $timestamp = [DateTime]$commit.commit.author.date
    if ($commitCounts.ContainsKey($email)) {
        $commitCounts[$email]++
        $localTime = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp.ToUniversalTime(), [TimeZoneInfo]::FindSystemTimeZoneById($developerTimeZones[$email]))
        if ($lastCommitLocal[$email] -eq $null -or $localTime -gt $lastCommitLocal[$email]) { $lastCommitLocal[$email] = $localTime }
    }
}

# ---- REPORT HTML GENERATION ----
$reportDate = $targetDate.ToString("yyyy-MM-dd")
$tableRows = ""
$sortedDevs = $developers | Sort-Object { $lastCommitLocal[$_] } -Descending

foreach ($dev in $sortedDevs) {
    if ($lastCommitLocal[$dev]) {
        $timeStr = $lastCommitLocal[$dev].ToString("yyyy-MM-dd HH:mm:ss")
        $style = ""
    } else {
        $timeStr = "<strong>NO COMMITS</strong>"
        $style = " style='color: #cc0000; background-color: #fce8e6;'"
    }
    $tableRows += "<tr$style><td style='padding: 8px; border: 1px solid #ddd;'>$dev</td><td style='padding: 8px; border: 1px solid #ddd;'>$($developerTimeZones[$dev])</td><td style='padding: 8px; border: 1px solid #ddd; text-align: center;'>$($commitCounts[$dev])</td><td style='padding: 8px; border: 1px solid #ddd;'>$timeStr</td></tr>"
}

$totalCommits = ($commitCounts.Values | Measure-Object -Sum).Sum
$tableRows += "<tr style='background-color: #f2f2f2; font-weight: bold;'><td style='padding: 8px; border: 1px solid #ddd;'>TOTAL</td><td style='padding: 8px; border: 1px solid #ddd;'>N/A</td><td style='padding: 8px; border: 1px solid #ddd; text-align: center;'>$totalCommits</td><td style='padding: 8px; border: 1px solid #ddd;'>-</td></tr>"

$emailBody = "<html><head><style>body { font-family: Calibri, Arial, sans-serif; font-size: 14px; color: #333; } table { border-collapse: collapse; width: 100%; max-width: 700px; margin-top: 15px; } th { background-color: #1f4e78; color: white; padding: 10px; text-align: left; border: 1px solid #ddd; }</style></head><body>"
$emailBody += "<p>Good morning,</p>"
$emailBody += "<p>Here is the automated Daily Commit Report for <strong>$reportDate</strong> tracking developer activity within their localized end-of-day windows.</p>"
$emailBody += "<table><thead><tr><th>Developer</th><th>Local Time Zone</th><th style='text-align: center;'>Commits Today</th><th>Last Commit (Local Time)</th></tr></thead>"
$emailBody += "<tbody>$tableRows</tbody></table>"
$emailBody += "<p style='font-size: 11px; color: #777; margin-top: 25px;'>This is an automated database administration report.</p>"
$emailBody += "</body></html>"

# ---- MAIL TRANSMISSION ----
try {
    Send-MailMessage -SmtpServer $smtpServer -Port $smtpPort -To $emailTo -From $emailFrom -Subject "Daily Commit Compliance Report - $reportDate" -Body $emailBody -BodyAsHtml -Encoding Utf8 -Credential $smtpCredential -UseSsl
    Write-Host "Success: Forced today-view email dispatched." -ForegroundColor Green
} catch {
    Write-Host "Failed to dispatch compliance email: $_" -ForegroundColor Red
}