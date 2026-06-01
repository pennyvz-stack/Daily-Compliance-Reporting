# ==============================================================================
# GIT WORKLOAD SIMULATION ENGINE - MULTI-DEVELOPER COMPLIANCE TESTING
# ==============================================================================

# ---- 1. SETUP TARGET DIRECTORIES & IDENTITIES ----
$repoPath1  = "C:\Daily-Compliance-Reporting"
$repoPath2  = "C:\Backup-Restore"
$myEmail    = "pennyvz@gmail.com"
$carlosEmail = "carlos@yourcompany.com" # Change to the exact email tracked in your SQL DeveloperRegistry

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   GENERATING SIMULATED WORKLOADSHIPS FOR AUDIT"     -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ---- 2. SIMULATE CARLOS COMMITTING TO REPOSITORY 1 ----
if (Test-Path $repoPath1) {
    Set-Location $repoPath1
    Write-Host ""
    Write-Host "Entering Repository: '$repoPath1'" -ForegroundColor Gray
    
    # Switch identity to Carlos
    git config user.email $carlosEmail
    Write-Host "Temporarily shifted Git identity to: $carlosEmail" -ForegroundColor Yellow
    
    # Generate an automated test change file
    $testFile = Join-Path $repoPath1 "carlos_test_marker.txt"
    "Simulated compliance audit payload generated on $(Get-Date)" | Out-File $testFile -Append
    
    # Stage, Commit, and Push
    git add .
    git commit -m "Automated compliance test commit under Carlos profile"
    Write-Host "Pushing Carlos's test payload upstream to GitHub cloud..." -ForegroundColor Cyan
    git push origin main
} else {
    Write-Host "Error: Local directory path not found: $repoPath1" -ForegroundColor Red
}

# ---- 3. SIMULATE PENNY COMMITTING TO REPOSITORY 2 ----
if (Test-Path $repoPath2) {
    Set-Location $repoPath2
    Write-Host ""
    Write-Host "Entering Repository: '$repoPath2'" -ForegroundColor Gray
    
    # Ensure identity matches your compliance profile
    git config user.email $myEmail
    Write-Host "Verified active Git identity as: $myEmail" -ForegroundColor Yellow
    
    # Generate an automated test change file
    $testFile = Join-Path $repoPath2 "penny_test_marker.txt"
    "Simulated compliance audit payload generated on $(Get-Date)" | Out-File $testFile -Append
    
    # Stage, Commit, and Push
    git add .
    git commit -m "Automated compliance test commit under Penny profile"
    Write-Host "Pushing Penny's test payload upstream to GitHub cloud..." -ForegroundColor Cyan
    git push origin main
} else {
    Write-Host "Error: Local directory path not found: $repoPath2" -ForegroundColor Red
}

# ---- 4. GLOBAL ENVIRONMENT CLEANUP & RESTORATION ----
Write-Host ""
Write-Host "Running post-execution environment restoration..." -ForegroundColor Cyan

# Explicitly revert your primary working directory's global profile context back to you
if (Test-Path $repoPath1) {
    Set-Location $repoPath1
    git config user.email $myEmail
    Write-Host " -> Restored $repoPath1 signature context back to: $myEmail" -ForegroundColor Green
}

Write-Host ""
Write-Host "Workload simulation complete! You are now ready to execute your lookback report." -ForegroundColor Green