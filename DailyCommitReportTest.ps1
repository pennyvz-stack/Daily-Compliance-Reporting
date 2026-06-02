# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - MULTI-BRANCH AUDIT ENGINE
# ==============================================================================

# ---- 1. CORE ENTERPRISE CONFIGURATION & INTERACTIVE PROMPT ----
$owner      = "pennyvz-stack"
$sqlServer  = "DESKTOP-LQEABPI\TEST"
$database   = "DBA_Tools"
$gmailUser  = "pennyvz@gmail.com"

# Build an interactive Windows Choice Prompt for the operational mode
$Host.UI.RawUI.WindowTitle = "Daily Commit Compliance Engine [MULTI-BRANCH EDITION]"
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

$sinceUtc = $targetDate.ToString("yyyy-MM-ddT00:00:00Z")
$untilUtc = $targetDate.ToString("yyyy-MM-ddT23:59:59Z")
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
$repoTotals = @{}
foreach ($repo in $repositories) { $repoTotals[$repo] = 0 }

Write-Host ""
Write-Host "Executing Cross-Branch Scanning Matrix..." -ForegroundColor Cyan

foreach ($repo in $repositories) {
    # Step A: Query GitHub to discover every single active branch in this repository
    $branchUrl = "https://api.github.com/repos/$owner/$repo/branches?per_page=100"
    try {
        $discoveredBranches = Invoke-RestMethod -Uri $branchUrl -Method Get -Headers $headers -ErrorAction Stop
        Write-Host " -> Repository [$repo]: Found $($discoveredBranches.Count) active branches to scan." -ForegroundColor Gray
        
        # Step B: Loop through every branch individually to audit its commits
        foreach ($b in $discoveredBranches) {
            $branchName = $b.name
            $apiUrl = "https://api.github.com/repos/$owner/$repo/commits?sha=$branchName&since=$sinceUtc&until=$untilUtc&per_page=100"
            
            try {
                $cloudCommits = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop
                foreach ($commitWrap in $cloudCommits) {
                    $email = $commitWrap.commit.author.email
                    $dateStr = $commitWrap.commit.author.date
                    $sha = $commitWrap.sha # Capture the unique commit hash identity
                    
                    $response += [PSCustomObject]@{
                        repo   = $repo
                        sha    = $sha
                        commit = [PSCustomObject]@{
                            author = [PSCustomObject]@{ email = $email; date = $dateStr }
                        }
                    }
                }
            } catch {
                # Silently catch branch-specific API timeouts or empty logs
            }
        }
    } catch {
        Write-Host "      Warning: Failed to fetch branch directory for $repo." -ForegroundColor Red
    }
}

# ---- 7. CALCULATE SYSTEM COUNTS & SUB-TOTAL METRICS (WITH DE-DUPLICATION) ----
$commitCounts = @{}; $lastCommitLocal = @{}
$devRepoSubtotals = @{} 
$processedHashes = @{} # Tracking index to prevent double-counting shared multi-branch commits

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
    $commitSha = $item.sha
    
    # Check if this developer is in our SQL registry
    if ($developers -contains $email) {
        $matchedKey = ($commitCounts.Keys | Where-Object { $_ -eq $email })
        
        # Unique Hash Verification Check: Only process if we haven't seen this commit SHA yet
        $uniqueTrackingKey = "$matchedKey-$commitSha"
        if (-not $processedHashes.ContainsKey($uniqueTrackingKey)) {
            $processedHashes[$uniqueTrackingKey] = $true
            
            # Increment tracking matrices safely
            $commitCounts[$matchedKey]++
            $devRepoSubtotals[$matchedKey][$currentRepo]++
            $repoTotals[$currentRepo]++
            
            $localTime = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp.ToUniversalTime(), [TimeZoneInfo]::FindSystemTimeZoneById($developerTimeZones[$matchedKey]))
            if ($lastCommitLocal[$matchedKey] -eq $null -or $localTime -gt $lastCommitLocal[$matchedKey]) {
                $lastCommitLocal[$matchedKey] = $localTime
            }
        }
    }
}

# ---- 8. GENERATE ITEMIZABLE HTML ROWS ----
$reportDate = $targetDate.ToString("yyyy-MM-dd")
$tableRows = ""
$sortedDevs = $developers | Sort-Object { $commitCounts[$_] } -Descending

foreach ($dev in $sortedDevs) {
    $subtotalParts = @()
    foreach ($repo in $repositories) {
        $count = $devRepoSubtotals[$dev][$repo]
        if ($count -gt 0) {
            $subtotalParts += "<li><code>$repo</code>: <strong>$count</strong> unique commits</li>"
        }
    }
    
    if ($subtotalParts.Count -gt 0) {
        $breakdownHtml = "<ul style='margin: 2px 0; padding-left: 15px; font-size: 12px; list-style-type: circle;'>" + ($subtotalParts -join "") + "</ul>"
    } else {
        $breakdownHtml = "<span style='font-size:12px; color:#888;'>No cross-branch activity recorded</span>"
    }

    if ($lastCommitLocal[$dev]) {
        $timeStr = $lastCommitLocal[$dev].ToString("yyyy-MM-dd HH:mm:ss")
        $style = ""
    } else {
        $timeStr = "<strong>NO COMMITS RECORDED ANYWHERE</strong>"
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

$repoBreakdownHtml = "<h3>Enterprise Repository Volume Breakdown (Multi-Branch Totals)</h3><ul style='list-style-type: square;'>"
foreach ($repo in $repositories) {
    $repoBreakdownHtml += "<li><strong>$repo</strong>: $($repoTotals[$repo]) unique commits compiled</li>"
}
$repoBreakdownHtml += "</ul>"

$totalCommits = ($commitCounts.Values | Measure-Object -Sum).Sum
$tableRows += "<tr style='background-color: #f2f2f2; font-weight: bold;'><td style='padding: 8px; border: 1px solid #ddd;'>TOTAL VOLUME</td><td style='padding: 8px; border: 1px solid #ddd;'>N/A</td><td style='padding: 8px; border: 1px solid #ddd; text-align: center;'>$totalCommits</td><td style='padding: 8px; border: 1px solid #ddd;'>-</td><td style='padding: 8px; border: 1px solid #ddd;'>-</td></tr>"

$emailBody = "<html><head><style>body { font-family: Calibri, Arial, sans-serif; font-size: 14px; color: #333; } table { border-collapse: collapse; width: 100%; max-width: 900px; margin-top: 15px; } th { background-color: #1f4e78; color: white; padding: 10px; text-align: left; border: 1px solid #ddd; }</style></head><body>"
$emailBody += "<p>Good morning,</p>"
$emailBody += "<p>Here is the automated Multi-Repository Multi-Branch Commit Report with itemized developer subtotals for the business day <strong>$reportDate</strong>.</p>"
$emailBody += "<table><thead><tr><th>Developer</th><th>Local Time Zone</th><th style='text-align: center;'>Total Unique Commits</th><th>Cross-Branch Subtotals</th><th>Last Active Commit (Local Time)</th></tr></thead>"
$emailBody += "<tbody>$tableRows</tbody></table>"
$emailBody += "<br/>$repoBreakdownHtml"
$emailBody += "<p style='font-size: 11px; color: #777; margin-top: 25px;'>This is an automated cross-branch database administration compliance report.</p>"
$emailBody += "</body></html>"

# ---- 9. MAIL TRANSMISSION ENGINE ----
try {
    Write-Host ""
    Write-Host "Establishing secure TLS connection to Gmail SMTP Gateway..." -ForegroundColor Cyan
    
    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = New-Object System.Net.Mail.MailAddress($gmailUser)
    $mail.To.Add($gmailUser)
    $mail.Subject = "Remote Multi-Branch Commit Compliance Report - $reportDate"
    $mail.Body = $emailBody
    $mail.IsBodyHtml = $true
    $mail.BodyEncoding = [System.Text.Encoding]::UTF8

    $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential($gmailUser, $plainPassword)
    
    $smtp.Send($mail)
    $smtp.Dispose()
    Write-Host "Success: Multi-branch compliance report email dispatched successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to dispatch compliance email: $_" -ForegroundColor Red
}