# ==============================================================================
# GIT WORKLOAD SIMULATION ENGINE - MULTI-COMMITS PER DEVELOPER (FIXED LOOP)
# ==============================================================================

# ---- 1. SETUP TARGET DIRECTORIES & IDENTITIES ----
$repoPath1  = "C:\Daily-Compliance-Reporting"
$repoPath2  = "C:\Backup-Restore"
$myEmail    = "pennyvz@gmail.com"
$carlosEmail = "carlos@example.com" 

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   GENERATING MULTI-COMMIT PAYLOADS FOR AUDIT"       -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Helper function to generate multiple distinct commits
function Send-SimulatedCommits ($repoPath, $userEmail, $developerName) {
    if (Test-Path $repoPath) {
        Set-Location $repoPath
        git config user.email $userEmail
        Write-Host "Active Identity: $userEmail on $repoPath" -ForegroundColor Yellow
        
        # FIXED: Changed from -eq to -le so the loop runs exactly 3 times
        for ($i = 1; $i -le 3; $i++) {
            $testFile = Join-Path $repoPath "$($developerName)_batch_marker.txt"
            "Commit block $i generated on $(Get-Date)" | Out-File $testFile -Append
            
            git add .
            git commit -m "Simulated batch commit #$i for $developerName" --quiet
            Start-Sleep -Seconds 1 # Ensure distinct timestamps
        }
        Write-Host "Pushing 3 commits upstream for $developerName..." -ForegroundColor Cyan
        git push origin main
    } else {
        Write-Host "Directory not found: $repoPath" -ForegroundColor Red
    }
}

# ---- 2. RUN BULK LOOPS ----
# Repo 1 Commits
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $carlosEmail -developerName "Carlos"
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $myEmail     -developerName "Penny"

# Repo 2 Commits
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $carlosEmail -developerName "Carlos"
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $myEmail     -developerName "Penny"

# ---- 3. CLEANUP ----
if (Test-Path $repoPath1) {
    Set-Location $repoPath1
    git config user.email $myEmail
}
Write-Host "`nAll simulated workloads pushed successfully!" -ForegroundColor Green