# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - LOCAL INGESTION + LOCAL TIME WINDOW
# ==============================================================================

# ---- 1. CORE CONFIGURATION ----
$owner = "pennyvz-stack"
$repo  = "Daily-Compliance-Reporting"

# ---- 2. SECURE INTERACTIVE CREDENTIAL PROMPT ----
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   DAILY COMMIT REPORT - SMTP SECURITY AUTH" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt safely for your fresh Gmail App Password
$gmailUser = "pennyvz@gmail.com"
Write-Host "Please enter your fresh Gmail App Password for email relay:" -ForegroundColor Yellow
$smtpCredential = Get-Credential -UserName $gmailUser -Message "Gmail SMTP Gateway Authentication"

# ---- 3. TARGET WINDOW CONFIGURATION (PURE LOCAL TIME) ----
$targetDate = (Get-Date).Date
$fromDate   = $targetDate.ToString("yyyy-MM-dd 00:00:00")
$toDate     = $targetDate.ToString("yyyy-MM-dd 23:59:59")

# ---- 4. LOCAL GIT LOG INGESTION ----
$response = @()
try {
    Set-Location "C:\Daily-Compliance-Reporting"
    $gitCommits = git log --since="$fromDate" --until="$toDate" --format="%ae|%aI"
    
    foreach ($line in $gitCommits) {
        if ($line) {
            $parts = $line -split '\|'
            $response += [PSCustomObject]@{
                commit = [PSCustomObject]@{
                    author = [PSCustomObject]@{
                        email = $parts[0].Trim()
                        date  = $parts[1].Trim()
                    }
                }
            }
        }
    }
    Write-Host "Success: Loaded commits directly from local Git tracking repository!" -ForegroundColor Green
} catch {
    Write-Host "Failed to query local Git repository logs: $_" -ForegroundColor Red
}

# ---- 5. DYNAMIC DEVELOPER ROSTER (SQL SERVER) ----
$sqlServer = "DESKTOP-LQEABPI\TEST" 
$database  = "DBA_Tools"
$query     = "SELECT DeveloperEmail, TimeZoneID FROM dbo.DeveloperRegistry WHERE IsActive = 1"

try {
    $dbRoster = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query $query
    $developers = @($dbRoster.DeveloperEmail)
    $developerTimeZones = @{}
    foreach ($row in $dbRoster) { $developerTimeZones[$row.DeveloperEmail] = $row.TimeZoneID }
} catch {
    Write-Host "Database Roster Retrieval Failed: $_" -ForegroundColor Red
    exit
}

# ---- 6. CASE-INSENSITIVE DATA COMPUTATION ----
$commitCounts = @{}; $lastCommitLocal = @{}
foreach ($dev in $developers) { $commitCounts[$dev] = 0; $lastCommitLocal[$dev] = $null }

foreach ($commit in $response) {
    $email = $commit.commit.author.email
    $timestamp = [DateTime]$commit.commit.author.date
    
    if ($developers -contains $email) {
        $matchedKey = ($commitCounts.Keys | Where-Object { $_ -eq $email })
        $commitCounts[$matchedKey]++
        
        $localTime = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp.ToUniversalTime(), [TimeZoneInfo]::FindSystemTimeZoneById($developerTimeZones[$matchedKey]))
        if ($lastCommitLocal[$matchedKey] -eq $null -or $localTime -gt $lastCommitLocal[$matchedKey]) { 
            $lastCommitLocal[$matchedKey] = $localTime 
        }
    }
}

# ---- 7. REPORT HTML GENERATION ----
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

# ---- 8. MAIL TRANSMISSION ----
try {
    Send-MailMessage -SmtpServer "smtp.gmail.com" -Port 587 -To "pennyvz@gmail.com" -From "pennyvz@gmail.com" -Subject "Daily Commit Compliance Report - $reportDate" -Body $emailBody -BodyAsHtml -Encoding Utf8 -Credential $smtpCredential -UseSsl
    Write-Host "Success: Compliance report email dispatched successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to dispatch compliance email: $_" -ForegroundColor Red
}