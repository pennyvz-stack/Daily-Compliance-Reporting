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

# ---- 3. AUTHENTICATION ----
$gitCredential  = Get-Credential -UserName "GitHub_API_Token" -Message "Enter GitHub Token"
$githubToken    = $gitCredential.GetNetworkCredential().Password
$smtpCredential = Get-Credential -UserName $gmailUser -Message "Enter Gmail App Password"
$appPassword    = $smtpCredential.GetNetworkCredential().Password

# ---- 4. INITIALIZE DATA STRUCTURES ----
$seenCommits = @{} 
$devStats    = @{} 
$repoStats   = @{}
$repoList    = @()

# Load Roster
$dbDevs = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT DeveloperEmail, TimeZoneID FROM dbo.DeveloperRegistry WHERE IsActive = 1"
foreach ($d in $dbDevs) { $devStats[$d.DeveloperEmail] = @{ TZ = $d.TimeZoneID; Main = 0; Branch = 0; Last = $null } }
$devStats["[UNLISTED/SYSTEM]"] = @{ TZ = "N/A"; Main = 0; Branch = 0; Last = $null }

# Load Repos
$dbRepos = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT RepositoryName FROM dbo.RepositoryRegistry WHERE IsActive = 1"
foreach ($r in @($dbRepos)) { 
    $repoName = $r.RepositoryName.Trim()
    $repoList += $repoName
    $repoStats[$repoName] = @{ Main = 0; Branch = 0; Stale = 0 }
}

# ---- 5. DATE LOGIC ----
if ($TestMode) {
    $targetDate = (Get-Date).Date
    Write-Host "Running in TEST MODE (Date: $targetDate)" -ForegroundColor Yellow
} else {
    $targetDate = (Get-Date).AddDays(-1).Date
    Write-Host "Running in PRODUCTION MODE (Date: $targetDate)" -ForegroundColor Green
}
$dateStr = $targetDate.ToString("MMMM dd, yyyy")
$sinceUtc = $targetDate.ToString("yyyy-MM-ddT00:00:00Z")
$untilUtc = $targetDate.ToString("yyyy-MM-ddT23:59:59Z")
$staleThreshold = (Get-Date).AddDays(-3)

# ---- 6. DATA FETCHING (DEDUPLICATED) ----
$headers = @{ "Authorization" = "Bearer $githubToken" }

Write-Host "Starting Data Collection..." -ForegroundColor Cyan
foreach ($repo in $repoList) {
    Write-Host "Processing Repo: $repo"
    $branches = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/branches" -Headers $headers
    
    foreach ($b in $branches) {
        $meta = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/branches/$($b.name)" -Headers $headers
        
        # Check Stale
        if ($b.name -ne "main" -and [DateTime]$meta.commit.commit.author.date -lt $staleThreshold) { $repoStats[$repo].Stale++ }
        
        # Get Commits
        $commits = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits?sha=$($b.name)&since=$sinceUtc&until=$untilUtc" -Headers $headers
        foreach ($c in $commits) {
            $sha = $c.sha
            $type = if ($b.name -eq "main") { "Main" } else { "Branch" }
            
            # Deduplication
            if (-not $seenCommits.ContainsKey($sha)) {
                $seenCommits[$sha] = @{ Email = $c.commit.author.email; Repo = $repo; Type = $type; Date = [DateTime]$c.commit.committer.date }
            } elseif ($type -eq "Main") {
                $seenCommits[$sha].Type = "Main"
            }
        }
        $devRepoBranchSubtotals[$matchedKey][$branchKey]++
    }
}

# ---- 7. STRICT AGGREGATION ----
Write-Host "Aggregating Totals..." -ForegroundColor Cyan
foreach ($sha in $seenCommits.Keys) {
    $c = $seenCommits[$sha]
    $email = if ($devStats.ContainsKey($c.Email)) { $c.Email } else { "[UNLISTED/SYSTEM]" }
    
    if (-not $devStats.ContainsKey($email)) { $devStats[$email] = @{ TZ = "N/A"; Main = 0; Branch = 0; Last = $null } }
    
    if ($c.Type -eq "Main") { 
        $repoStats[$c.Repo].Main++ 
        $devStats[$email].Main++
    } else { 
        $repoStats[$c.Repo].Branch++ 
        $devStats[$email].Branch++ 
    }
    
    if ($devStats[$email].Last -eq $null -or $c.Date -gt $devStats[$email].Last) { $devStats[$email].Last = $c.Date }
}

# ---- 8. GENERATE HTML TABLES ----
$totalMain = 0
$totalBranch = 0

$repoRows = ""
foreach ($repo in $repoList) {
    $s = $repoStats[$repo]
    $totalMain += $s.Main
    $totalBranch += $s.Branch
    $staleDisplay = if ($s.Stale -gt 0) { "<span style='$redStyle'>$($s.Stale) Stale [ALERT]</span>" } else { "0 Stale" }
    $repoRows += "<tr><td style='border:1px solid #ddd; padding:8px;'><strong>$repo</strong></td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$($s.Main)</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$($s.Branch)</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$staleDisplay</td></tr>"
}
$repoRows += "<tr style='background:#f2f2f2; font-weight:bold;'><td style='border:1px solid #ddd; padding:8px;'>GRAND TOTAL</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$totalMain</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$totalBranch</td><td style='border:1px solid #ddd; padding:8px;'></td></tr>"

$devRows = ""
$devTotalMain = 0
$devTotalBranch = 0

# Sort Logic: 1. No Activity (Top), 2. Active, 3. Unlisted (Bottom)
$sortedKeys = $devStats.Keys | Sort-Object {
    if ($_.ToString() -eq "[UNLISTED/SYSTEM]") { 3 }
    elseif (($devStats[$_].Main + $devStats[$_].Branch) -eq 0) { 1 }
    else { 2 }
}

foreach ($email in $sortedKeys) {
    $d = $devStats[$email]
    $devTotalMain += $d.Main
    $devTotalBranch += $d.Branch
    $lastStr = if ($d.Last -ne $null) { $d.Last.ToString("yyyy-MM-dd HH:mm:ss") } else { "<span style='$redStyle'>NO COMMITS</span>" }
    $devRows += "<tr><td style='border:1px solid #ddd; padding:8px;'>$email</td><td style='border:1px solid #ddd; padding:8px;'>$($d.TZ)</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$($d.Main)</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$($d.Branch)</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$lastStr</td></tr>"
}
$devRows += "<tr style='background:#f2f2f2; font-weight:bold;'><td colspan='2' style='border:1px solid #ddd; padding:8px;'>GRAND TOTAL</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$devTotalMain</td><td style='border:1px solid #ddd; padding:8px; text-align:center;'>$devTotalBranch</td><td></td></tr>"

$emailBody = "<html><body style='font-family:Arial, sans-serif; font-size:14px;'>
    <h3>Daily Repository and Developer Commit Summary ($dateStr)</h3>
    
    <h4>1. Repository Activity Summary</h4>
    <p style='font-size:12px;'>Purpose: To monitor repository health, identify dead repositories, and ensure code is consistently committed to designated branches.</p>
    <table style='border-collapse:collapse; width:100%;'>
    <tr style='background:#1f4e78; color:white;'><th>Target Repository</th><th>Main Commits</th><th>Branch Commits</th><th>Stale Branches</th></tr>
    $repoRows</table>
    
    <h4>2. Developer Commit Counts</h4>
    <p style='font-size:12px;'>Purpose: To perform daily audits of developer commits, ensuring consistent team activity and feature progression. <em>Note: Commit times are shown in the developer's local time zone.</em></p>
    <table style='border-collapse:collapse; width:100%;'>
    <tr style='background:#1f4e78; color:white;'><th>Developer</th><th>Local Time Zone</th><th>Main Commits</th><th>Branch Commits</th><th>Last Commit</th></tr>
    $devRows</table>
    
    <div style='margin-top:20px; padding:10px; background:#f4f4f4; border:1px solid #ccc; font-size:12px;'>
        <strong>Legend:</strong>
        <ul><li><span style='$redStyle'>NO COMMITS</span>: No recorded activity for audited date.</li>
            <li><span style='$redStyle'>Stale [ALERT]</span>: Branch not pushed in > 3 days.</li>
            <li>[UNLISTED/SYSTEM]: Commits from authors not in Registry.</li></ul>
    </div>
    </body></html>"

# ---- 9. SEND EMAIL ----
$emailBody | Out-File -FilePath $dashboardPath -Encoding utf8 -Force
try {
    $mail = New-Object System.Net.Mail.MailMessage($gmailUser, $gmailUser, "Daily Repository and Developer Commit Summary - $dateStr", $emailBody)
    $mail.IsBodyHtml = $true
    $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential($gmailUser, $appPassword)
    $smtp.Send($mail)
    $smtp.Dispose()
    Write-Host "Success! Report sent." -ForegroundColor Green
} catch { Write-Host "Failed to dispatch: $_" -ForegroundColor Red }
