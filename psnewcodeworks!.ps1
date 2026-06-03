# ==============================================================================
# DAILY COMMIT COMPLIANCE REPORT - PRODUCTION ENGINE
# ==============================================================================

# ---- 1. CORE ENTERPRISE CONFIGURATION ----
$owner        = "pennyvz-stack"
$sqlServer    = "DESKTOP-LQEABPI\TEST"
$database     = "DBA_Tools"
$gmailUser    = "pennyvz@gmail.com"
$dashboardPath = "C:\Daily-Compliance-Reporting\AuditDashboard.html"
$redStyle     = "color: #cc0000; font-weight: bold;"

# ---- 2. INTERACTIVE PROMPT ----
$Host.UI.RawUI.WindowTitle = "Daily Commit Compliance Engine [PRODUCTION]"
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "    SELECT OPERATIONAL EXECUTION MODE"              -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " 1) Test Run       - Audit target window forced to TODAY" -ForegroundColor Yellow
Write-Host " 2) Production Run - Automated rolling lookback (Yesterday/Friday/Holidays)" -ForegroundColor Green
Write-Host ""

$choice = Read-Host "Enter selection (1 or 2)"
$TestMode = ($choice -eq "1")

# ---- 3. AUTHENTICATION ----
$gitCredential  = Get-Credential -UserName "GitHub_API_Token" -Message "Enter GitHub Token"
$githubToken    = $gitCredential.GetNetworkCredential().Password
$smtpCredential = Get-Credential -UserName $gmailUser -Message "Enter Gmail App Password"
$appPassword    = $smtpCredential.GetNetworkCredential().Password

# ---- 4. SYNC & INITIALIZE DATA STRUCTURES ----
$seenCommits = @{} 
$devStats    = @{} 
$repoStats   = @{}
$repoList    = @()

$headers = @{ "Authorization" = "Bearer $githubToken" }
$allGhRepos = Invoke-RestMethod -Uri "https://api.github.com/users/$owner/repos?per_page=100" -Headers $headers
$ghRepoNames = $allGhRepos.name

# Sync SQL Registry
$sqlRegistry = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT RepositoryName, IsActive FROM dbo.RepositoryRegistry"
foreach ($name in $ghRepoNames) {
    if (-not ($sqlRegistry.RepositoryName -contains $name)) {
        Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "INSERT INTO dbo.RepositoryRegistry (RepositoryName, IsActive) VALUES ('$name', 1)"
    }
}

# Load Registry/Active Devs
$dbDevs = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT DeveloperEmail, TimeZoneID FROM dbo.DeveloperRegistry WHERE IsActive = 1"
foreach ($d in $dbDevs) { $devStats[$d.DeveloperEmail] = @{ TZ = $d.TimeZoneID; Main = 0; Branch = 0; Last = $null } }
$devStats["[UNLISTED/SYSTEM]"] = @{ TZ = "UTC"; Main = 0; Branch = 0; Last = $null }

$dbRepos = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT RepositoryName FROM dbo.RepositoryRegistry WHERE IsActive = 1"
foreach ($r in $dbRepos) { 
    $repoList += $r.RepositoryName.Trim()
    $repoStats[$r.RepositoryName.Trim()] = @{ Main = 0; Branch = 0; Stale = 0 }
}

# ---- 5. TARGET WINDOW CONFIGURATION ----
if ($TestMode) {
    $targetDate = (Get-Date).Date
} else {
    $daysToLookBack = -1
    $targetDate = (Get-Date).AddDays($daysToLookBack).Date
    while ($true) {
        if ($targetDate.DayOfWeek -eq "Saturday" -or $targetDate.DayOfWeek -eq "Sunday") {
            $daysToLookBack--
            $targetDate = (Get-Date).AddDays($daysToLookBack).Date
        } else {
            $dateString = $targetDate.ToString("yyyy-MM-dd")
            $isHoliday = Invoke-SqlCmd -ServerInstance $sqlServer -Database $database -Query "SELECT COUNT(1) FROM dbo.CompanyHolidays WHERE HolidayDate = '$dateString'"
            if ($isHoliday[0].Column1 -gt 0) {
                $daysToLookBack--
                $targetDate = (Get-Date).AddDays($daysToLookBack).Date
            } else { break }
        }
    }
}
$sinceUtc = $targetDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$untilUtc = $targetDate.AddDays(1).AddSeconds(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$staleThreshold = (Get-Date).AddDays(-3)

# ---- 6. DATA FETCHING ----
$headers = @{ "Authorization" = "Bearer $githubToken" }

Write-Host "Starting Data Collection for $dateStr..." -ForegroundColor Cyan
foreach ($repo in $repoList) {
    Write-Host "Processing Repo: $repo"
    
    # Retrieve branches for the current repository
    $branches = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/branches" -Headers $headers
    
    foreach ($b in $branches) {
        # Check for stale branches
        $meta = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/branches/$($b.name)" -Headers $headers
        if ($b.name -ne "main" -and [DateTime]$meta.commit.commit.author.date -lt $staleThreshold) { 
            $repoStats[$repo].Stale++ 
        }
        
        # Retrieve commits for the branch within the time window
        $commits = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits?sha=$($b.name)&since=$sinceUtc&until=$untilUtc" -Headers $headers
        
        foreach ($c in $commits) {
            $sha = $c.sha
            $type = if ($b.name -eq "main") { "Main" } else { "Branch" }
            
            # Create DateTime object and FORCE Kind to UTC to prevent conversion errors
            $utcDate = [DateTime]::SpecifyKind([DateTime]$c.commit.committer.date, [System.DateTimeKind]::Utc)
            
            if (-not $seenCommits.ContainsKey($sha)) {
                $seenCommits[$sha] = @{ Email = $c.commit.author.email; Repo = $repo; Type = $type; Date = $utcDate }
            } elseif ($type -eq "Main") {
                $seenCommits[$sha].Type = "Main"
            }
        }
    }
}
# ---- 7. AGGREGATION & LOCAL TIMEZONE CONVERSION ----
Write-Host "Aggregating Totals..." -ForegroundColor Cyan
foreach ($sha in $seenCommits.Keys) {
    $c = $seenCommits[$sha]
    $email = if ($devStats.ContainsKey($c.Email)) { $c.Email } else { "[UNLISTED/SYSTEM]" }
    
    # Convert to Local Time using the registered TimeZoneID
    $tzId = $devStats[$email].TZ
    $localDate = if ($tzId -eq "N/A" -or $tzId -eq "") { $c.Date } else { 
        [System.TimeZoneInfo]::ConvertTimeFromUtc($c.Date, [System.TimeZoneInfo]::FindSystemTimeZoneById($tzId)) 
    }

    if ($c.Type -eq "Main") { $repoStats[$c.Repo].Main++; $devStats[$email].Main++ } 
    else { $repoStats[$c.Repo].Branch++; $devStats[$email].Branch++ }
    
    if ($devStats[$email].Last -eq $null -or $localDate -gt $devStats[$email].Last) { $devStats[$email].Last = $localDate }
}

# ---- 8. GENERATE HTML TABLES ----
$headerStyle = "background-color:#005b96; color:white; padding:10px; border:1px solid #005b96;"
$cellStyle = "border:1px solid #ddd; padding:8px;"

$totalMain = 0; $totalBranch = 0; $repoRows = ""
foreach ($repo in $repoList) {
    $s = $repoStats[$repo]; $totalMain += $s.Main; $totalBranch += $s.Branch
    $staleDisplay = if ($s.Stale -gt 0) { "<span style='$redStyle'>$($s.Stale) Stale [ALERT]</span>" } else { "0 Stale" }
    $repoRows += "<tr><td style='$cellStyle'><strong>$repo</strong></td><td style='$cellStyle' align='center'>$($s.Main)</td><td style='$cellStyle' align='center'>$($s.Branch)</td><td style='$cellStyle' align='center'>$staleDisplay</td></tr>"
}
$repoRows += "<tr style='background:#f2f2f2; font-weight:bold;'><td style='$cellStyle'>GRAND TOTAL</td><td style='$cellStyle' align='center'>$totalMain</td><td style='$cellStyle' align='center'>$totalBranch</td><td style='$cellStyle'></td></tr>"

$devRows = ""; $devTotalMain = 0; $devTotalBranch = 0
$sortedKeys = $devStats.Keys | Sort-Object { if ($_.ToString() -eq "[UNLISTED/SYSTEM]") { 3 } elseif (($devStats[$_].Main + $devStats[$_].Branch) -eq 0) { 1 } else { 2 } }
foreach ($email in $sortedKeys) {
    $d = $devStats[$email]; $devTotalMain += $d.Main; $devTotalBranch += $d.Branch
    $lastStr = if ($d.Last -ne $null) { $d.Last.ToString("yyyy-MM-dd HH:mm:ss") } else { "<span style='$redStyle'>NO COMMITS</span>" }
    $devRows += "<tr><td style='$cellStyle'>$email</td><td style='$cellStyle'>$($d.TZ)</td><td style='$cellStyle' align='center'>$($d.Main)</td><td style='$cellStyle' align='center'>$($d.Branch)</td><td style='$cellStyle' align='center'>$lastStr</td></tr>"
}
$devRows += "<tr style='background:#f2f2f2; font-weight:bold;'><td colspan='2' style='$cellStyle'>GRAND TOTAL</td><td style='$cellStyle' align='center'>$devTotalMain</td><td style='$cellStyle' align='center'>$devTotalBranch</td><td style='$cellStyle'></td></tr>"

$emailBody = @"
<html>
<body style='font-family:sans-serif;'>
    <h3>Daily Repository and Developer Commit Summary ($dateStr)</h3>
    <h4>1. Repository Activity Summary</h4>
    <p>Purpose: To monitor repository health, identify dead repositories, and ensure code is consistently committed to designated branches.</p>
    <table style='border-collapse:collapse; width:100%;'>
        <tr style='$headerStyle'><th>Target Repository</th><th>Main Commits</th><th>Branch Commits</th><th>Stale Branches</th></tr>
        $repoRows
    </table>
    <h4>2. Developer Commit Counts</h4>
    <p>Purpose: To perform daily audits of developer commits, ensuring consistent team activity and feature progression. <em>Note: Commit times are shown in the developer's local time zone.</em></p>
    <table style='border-collapse:collapse; width:100%;'>
        <tr style='$headerStyle'><th>Developer</th><th>Local Time Zone</th><th>Main Commits</th><th>Branch Commits</th><th>Last Commit</th></tr>
        $devRows
    </table>
    <br>
   <div style='background:#f9f9f9; padding:10px; border:1px solid #ccc; font-size: 0.9em; margin-top: 20px;'>
    <strong>Legend:</strong>
    <ul style='margin: 5px 0; padding-left: 20px;'>
        <li><strong>[UNLISTED/SYSTEM]:</strong> Includes merge commits, automated system service accounts, or developers not yet registered in the SQL audit table.</li>
        <li><strong>NO COMMITS:</strong> No recorded activity for audited date.</li>
        <li><strong>Stale [ALERT]:</strong> Branch not pushed in > 3 days.</li>
    </ul>
</div>
</body>
</html>
"@

# ---- 9. SEND EMAIL ----

$emailBody | Out-File -FilePath $dashboardPath -Encoding utf8 -Force

try {

    $mail = New-Object System.Net.Mail.MailMessage($gmailUser, $gmailUser, "Daily Repository and Developer Commit Summary - $dateStr", $emailBody)

    $mail.IsBodyHtml = $true

    $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)

    $smtp.EnableSsl = $true

    $smtp.Credentials = New-Object System.Net.NetworkCredential($gmailUser, $appPassword)

    $smtp.Send($mail); $smtp.Dispose()

    Write-Host "Success! Report sent." -ForegroundColor Green

} catch { Write-Host "Failed to dispatch: $_" -ForegroundColor Red } 

