# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - FULL REPO BREAKDOWN ENGINE WITH REPO SUBTOTALS
# ==============================================================================

# ---- 1. CORE ENTERPRISE CONFIGURATION ----
$owner      = "pennyvz-stack"
$sqlServer  = "DESKTOP-LQEABPI\TEST"
$database   = "DBA_Tools"
$TestMode   = $true  

# ---- 2. INITIALIZATION CONSOLE BANNER ----
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   DAILY COMMIT REPORT - CLOUD AUTO-DISCOVERY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# ---- 3. TARGET WINDOW CONFIGURATION ----
if ($TestMode) {
    $targetDate = (Get-Date).Date
    $dateString = $targetDate.ToString("yyyy-MM-dd")
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
                    $daysToLookBack--
                    $targetDate = (Get-Date).AddDays($daysToLookBack).Date
                } else {
                    $isBusinessDay = $true
                }
            } catch {
                $isBusinessDay = $true
            }
        }
    }
}

$sinceUtc = $targetDate.ToString("yyyy-MM-ddT00:00:00Z")
$untilUtc = $targetDate.ToString("yyyy-MM-ddT23:59:59Z")

# ---- 4. REPOSITORY AUTO-DISCOVERY ----
$discoveryUrl = "https://api.github.com/users/$owner/repos?per_page=100"
$headers = @{ "User-Agent" = "PowerShell-DBA-Audit Engine" }

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
    Write-Host "Warning: Cloud discovery step skipped/failed. Using existing database records." -ForegroundColor Red
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

# ---- 6. DATA EXTRACTION ----
$response = @()
$repoTotals = @{}
foreach ($repo in $repositories) { $repoTotals[$repo] = 0 }

foreach ($repo in $repositories) {
    $apiUrl = "https://api.github.com/repos/$owner/$repo/commits?since=$sinceUtc&until=$untilUtc&per_page=100"
    try {
        $cloudCommits = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop
        foreach ($commitWrap in $cloudCommits) {
            $email = $commitWrap.commit.author.email
            $dateStr = $commitWrap.commit.author.date
            
            $response += [PSCustomObject]@{
                repo   = $repo
                commit = [PSCustomObject]@{
                    author = [PSCustomObject]@{ email = $email; date = $dateStr }
                }
            }
            if ($developers -contains $email) { $repoTotals[$repo]++ }
        }
    } catch {}
}

# ---- 7. CALCULATE SYSTEM COUNTS & SUB-TOTAL METRICS ----
$commitCounts = @{}; $lastCommitLocal = @{}
# Multi-dimensional hash tracking [developer][repo] = count
$devRepoSubtotals = @{} 

foreach ($dev in $developers) { 
    $commitCounts[$dev] = 0
    $lastCommitLocal[$dev] = $null
    $devRepoSubtotals[$dev] = @{}
    foreach ($repo in $repositories) { $devRepoSubtotals[$dev][$repo] = 0 }
}

foreach ($item in $response) {
    $email = $item.commit.author.email
    $timestamp = [DateTime]$item.commit.author.date
    $currentRepo = $item.repo
    
    if ($developers -contains $email) {
        $matchedKey = ($commitCounts.Keys | Where-Object { $_ -eq $email })
        $commitCounts[$matchedKey]++
        $devRepoSubtotals[$matchedKey][$currentRepo]++
        
        $localTime = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp.ToUniversalTime(), [TimeZoneInfo]::FindSystemTimeZoneById($developerTimeZones[$matchedKey]))
        if ($lastCommitLocal[$matchedKey] -eq $null -or $localTime -gt $lastCommitLocal[$matchedKey]) {
            $lastCommitLocal[$matchedKey] = $localTime
        }
    }
}

# ---- 8. GENERATE ITEMIZABLE HTML ROWS ----
$reportDate = $targetDate.ToString("yyyy-MM-dd")
$tableRows = ""
$sortedDevs = $developers | Sort-Object { $commitCounts[$_] } -Descending

foreach ($dev in $sortedDevs) {
    # Dynamically build a detailed string showing repository breakdowns for this user
    $subtotalParts = @()
    foreach ($repo in $repositories) {
        $count = $devRepoSubtotals[$dev][$repo]
        if ($count -gt 0) {
            $subtotalParts += "<li><code>$repo</code>: <strong>$count</strong> commits</li>"
        }
    }
    
    if ($subtotalParts.Count -gt 0) {
        $breakdownHtml = "<ul style='margin: 2px 0; padding-left: 15px; font-size: 12px; list-style-type: circle;'>" + ($subtotalParts -join "") + "</ul>"
    } else {
        $breakdownHtml = "<span style='font-size:12px; color:#888;'>No active tracking across targets</span>"
    }

    if ($lastCommitLocal[$dev]) {
        $timeStr = $lastCommitLocal[$dev].ToString("yyyy-MM-dd HH:mm:ss")
        $style = ""
    } else {
        $timeStr = "<strong>NO COMMITS</strong>"
        $style = " style='color: #cc0000; background-color: #fce8e6;'"
    }
    
    $tableRows += "<tr$style>"
    $tableRows += "<td style='padding: 8px; border: 1px solid #ddd; vertical-align: top;'>$dev</td>"
    $tableRows += "<td style='padding: 8px; border: 1px solid #ddd; vertical-align: top;'>$($developerTimeZones[$dev])</td>"
    $tableRows += "<td style='padding: 8px; border: 1px solid #ddd; text-align: center; vertical-align: top;'><strong>$($commitCounts[$dev])</strong></td>"
    $tableRows += "<td style='padding: 8px; border: 1px solid #ddd; vertical-align: top;'>$breakdownHtml</td>"
    $tableRows += "<td style='padding: 8px; border: 1px solid #ddd; vertical-align: top;'>$timeStr</td>"
    $tableRows += "</tr>"
}

$repoBreakdownHtml = "<h3>Enterprise Repository Volume Breakdown (Total Footprint)</h3><ul style='list-style-type: square;'>"
foreach ($repo in $repositories) {
    $repoBreakdownHtml += "<li><strong>$repo</strong>: $($repoTotals[$repo]) commits recorded</li>"
}
$repoBreakdownHtml += "</ul>"

$totalCommits = ($commitCounts.Values | Measure-Object -Sum).Sum
$tableRows += "<tr style='background-color: #f2f2f2; font-weight: bold;'><td style='padding: 8px; border: 1px solid #ddd;'>TOTAL VOLUME</td><td style='padding: 8px; border: 1px solid #ddd;'>N/A</td><td style='padding: 8px; border: 1px solid #ddd; text-align: center;'>$totalCommits</td><td style='padding: 8px; border: 1px solid #ddd;'>-</td><td style='padding: 8px; border: 1px solid #ddd;'>-</td></tr>"

$emailBody = "<html><head><style>body { font-family: Calibri, Arial, sans-serif; font-size: 14px; color: #333; } table { border-collapse: collapse; width: 100%; max-width: 900px; margin-top: 15px; } th { background-color: #1f4e78; color: white; padding: 10px; text-align: left; border: 1px solid #ddd; }</style></head><body>"
$emailBody += "<p>Good morning,</p>"
$emailBody += "<p>Here is the automated Multi-Repository Daily Commit Report with itemized developer subtotals for the business day <strong>$reportDate</strong>.</p>"
$emailBody += "<table><thead><tr><th>Developer</th><th>Local Time Zone</th><th style='text-align: center;'>Total Commits</th><th>Repository Subtotals</th><th>Last Commit (Local Time)</th></tr></thead>"
$emailBody += "<tbody>$tableRows</tbody></table>"
$emailBody += "<br/>$repoBreakdownHtml"
$emailBody += "<p style='font-size: 11px; color: #777; margin-top: 25px;'>This is an automated database administration report.</p>"
$emailBody += "</body></html>"

# ---- 9. MAIL TRANSMISSION ----
try {
    Write-Host ""
    Write-Host "Establishing secure TLS connection to Gmail SMTP Gateway..." -ForegroundColor Cyan
    
    # !!! INSERT YOUR 16-CHARACTER GMAIL APP PASSWORD HERE !!!
    $plainPassword = "xxx" 
    
    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = New-Object System.Net.Mail.MailAddress("pennyvz@gmail.com")
    $mail.To.Add("pennyvz@gmail.com")
    $mail.Subject = "Remote Multi-Repo Commit Compliance Report - $reportDate"
    $mail.Body = $emailBody
    $mail.IsBodyHtml = $true
    $mail.BodyEncoding = [System.Text.Encoding]::UTF8

    $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential("pennyvz@gmail.com", $plainPassword)
    
    $smtp.Send($mail)
    $smtp.Dispose()
    Write-Host "Success: Compliance report email dispatched successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to dispatch compliance email: $_" -ForegroundColor Red
}