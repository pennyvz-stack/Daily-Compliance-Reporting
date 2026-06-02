# ==============================================================================
# GIT WORKLOAD SIMULATION ENGINE - MULTI-BRANCH MULTI-DEVELOPER MATRIX
# ==============================================================================

# ---- 1. SETUP TARGET DIRECTORIES & IDENTITIES ----
$repoPath1   = "C:\Daily-Compliance-Reporting"
$repoPath2   = "C:\Backup-Restore"
$myEmail     = "pennyvz@gmail.com"
$carlosEmail = "carlos@example.com" 

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "    GENERATING MULTI-BRANCH PAYLOADS FOR AUDIT"      -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Helper function upgraded to dynamically handle toggle switches/branches
function Send-SimulatedCommits ($repoPath, $userEmail, $developerName, $targetBranch) {
    if (Test-Path $repoPath) {
        Set-Location $repoPath
        
        # 1. Ensure we toggle/switch to the right branch context
        Write-Host "`nSwitching workbench to branch [$targetBranch] in $repoPath..." -ForegroundColor Cyan
        git checkout $targetBranch --quiet
        
        # 2. Assign the active identity profile for the transaction
        git config user.email $userEmail
        Write-Host "Active Identity: $userEmail on branch $targetBranch" -ForegroundColor Yellow
        
        # 3. Generate 2 distinct commits per branch to keep the matrix clean
        for ($i = 1; $i -le 2; $i++) {
            if ($developerName -eq "Penny") {
                # For Penny, write physical lines to a tracker log text file
                $testFile = Join-Path $repoPath "${developerName}_batch_marker.txt"
                "Commit block $i generated on branch $targetBranch on $(Get-Date)" | Out-File $testFile -Append
                git add .
                git commit -m "${developerName}: Batch commit #$i on $targetBranch" --quiet
            } else {
                # For Carlos, use --allow-empty to safely simulate his work without conflicting text files
                git commit --allow-empty -m "${developerName}: Optimized batch commit #$i on $targetBranch" --quiet
            }
            Start-Sleep -Seconds 1 # Guarantee unique timestamps
        }
        
        # 4. Push the branch payload up to the cloud storefront
        Write-Host "Pushing commits upstream to origin $targetBranch..." -ForegroundColor Gray
        git push origin $targetBranch --quiet
    } else {
        Write-Host "Directory not found: $repoPath" -ForegroundColor Red
    }
}

# ---- 2. RUN BULK CROSS-BRANCH LOOPS ----

# --- REPOSITORY 1: Daily-Compliance-Reporting ---
Write-Host "`n>>> SCANNING REPOSITORY 1: Daily-Compliance-Reporting" -ForegroundColor Green
# Test main branch activity
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $carlosEmail -developerName "Carlos" -targetBranch "main"
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $myEmail     -developerName "Penny"  -targetBranch "main"

# Test feature branch activity
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $carlosEmail -developerName "Carlos" -targetBranch "feature-multi-branch"
Send-SimulatedCommits -repoPath $repoPath1 -userEmail $myEmail     -developerName "Penny"  -targetBranch "feature-multi-branch"


# --- REPOSITORY 2: Backup-Restore ---
Write-Host "`n>>> SCANNING REPOSITORY 2: Backup-Restore" -ForegroundColor Green
# Test main branch activity
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $carlosEmail -developerName "Carlos" -targetBranch "main"
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $myEmail     -developerName "Penny"  -targetBranch "main"

# Test feature branch activity (Note: Assumes feature-multi-branch exists here as well)
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $carlosEmail -developerName "Carlos" -targetBranch "feature-multi-branch"
Send-SimulatedCommits -repoPath $repoPath2 -userEmail $myEmail     -developerName "Penny"  -targetBranch "feature-multi-branch"


# ---- 3. CLEANUP & RESET ----
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   CLEANING WORKBENCH ENVIRONMENT"                   -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Return Repo 1 back to your safe sandbox branch and reset your default Git email config
if (Test-Path $repoPath1) {
    Set-Location $repoPath1
    git checkout feature-multi-branch --quiet
    git config user.email $myEmail
    Write-Host "Repo 1 reset successfully to feature-multi-branch workspace." -ForegroundColor Gray
}

# Return Repo 2 back to your safe sandbox branch
if (Test-Path $repoPath2) {
    Set-Location $repoPath2
    git checkout feature-multi-branch --quiet
    git config user.email $myEmail
    Write-Host "Repo 2 reset successfully to feature-multi-branch workspace." -ForegroundColor Gray
}

Write-Host "`nAll simulated multi-branch workloads pushed successfully!" -ForegroundColor Green