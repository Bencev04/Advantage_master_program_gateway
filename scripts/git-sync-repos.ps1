param(
    [Alias("Message")]
    [string]$CommitMessage = "chore: sync local workspace changes",
    [string]$WorkspaceRoot = "",
    [Alias("Only")]
    [string[]]$RepoFolders = @(),
    [switch]$DryRun,
    [switch]$SkipPull,
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"

if (-not $WorkspaceRoot) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
else {
    $WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode. $output"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Invoke-GitWrite {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if ($DryRun) {
        Write-Host "[dry-run] git $($Arguments -join ' ')"
        return
    }

    Write-Host "git $($Arguments -join ' ')"

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-RepositoryTargets {
    if ($RepoFolders.Count -gt 0) {
        foreach ($folder in $RepoFolders) {
            $repoPath = Join-Path $WorkspaceRoot $folder
            if (-not (Test-Path (Join-Path $repoPath ".git"))) {
                Write-Warning "$folder is not a git repository at $repoPath. Skipping."
                continue
            }

            [pscustomobject]@{ Name = $folder; Path = $repoPath }
        }
        return
    }

    Get-ChildItem -Path $WorkspaceRoot -Directory -Filter "Advantage_master_program_*" |
        Where-Object { Test-Path (Join-Path $_.FullName ".git") } |
        Sort-Object Name |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName } }
}

function Test-OriginRemote {
    $remote = Invoke-GitRead -Arguments @("remote", "get-url", "origin") -AllowFailure
    return $remote.ExitCode -eq 0
}

function Get-CurrentBranch {
    $branch = Invoke-GitRead -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD") -AllowFailure
    if ($branch.ExitCode -eq 0) {
        return ($branch.Output -join "").Trim()
    }

    $detached = Invoke-GitRead -Arguments @("rev-parse", "--abbrev-ref", "HEAD") -AllowFailure
    if ($detached.ExitCode -eq 0) {
        return ($detached.Output -join "").Trim()
    }

    return ""
}

function Has-CommitHistory {
    $head = Invoke-GitRead -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure
    return $head.ExitCode -eq 0
}

function Has-WorkingTreeChanges {
    $status = Invoke-GitRead -Arguments @("status", "--porcelain")
    return @($status.Output).Count -gt 0
}

function Has-UpstreamBranch {
    $upstream = Invoke-GitRead -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}") -AllowFailure
    return $upstream.ExitCode -eq 0
}

$repositories = @(Get-RepositoryTargets)
if ($repositories.Count -eq 0) {
    Write-Warning "No git repositories found under $WorkspaceRoot."
    exit 0
}

$failedRepos = @()

foreach ($repo in $repositories) {
    Write-Host ""
    Write-Host "== $($repo.Name) =="
    Push-Location $repo.Path
    try {
        $hasOrigin = Test-OriginRemote
        $branch = Get-CurrentBranch
        $hasCommits = Has-CommitHistory
        $hasUpstream = Has-UpstreamBranch

        if (-not $branch) {
            throw "Repository has no active branch. Checkout or create a branch before syncing."
        }

        if ($branch -eq "HEAD") {
            throw "Repository is in detached HEAD state. Checkout a branch before syncing."
        }

        if (-not $SkipPull) {
            if ($hasOrigin) {
                if ($hasCommits -and $hasUpstream) {
                    Invoke-GitWrite -Arguments @("pull", "--rebase", "--autostash")
                }
                else {
                    Invoke-GitWrite -Arguments @("fetch", "origin")
                    if ($DryRun) {
                        Write-Warning "$($repo.Name) branch '$branch' has no pull target yet. The script would fetch origin and set upstream after a commit."
                    }
                    else {
                        Write-Warning "$($repo.Name) branch '$branch' has no pull target yet. Fetched origin and will set upstream after a commit."
                    }
                }
            }
            else {
                Write-Warning "$($repo.Name) has no origin remote. Skipping pull."
            }
        }

        if (Has-WorkingTreeChanges) {
            Invoke-GitWrite -Arguments @("add", "-A")
            Invoke-GitWrite -Arguments @("commit", "-m", $CommitMessage)
            $hasCommits = $true
        }
        else {
            Write-Host "No local changes to commit."
        }

        if (-not $SkipPush) {
            if ($hasOrigin) {
                if (-not $hasCommits) {
                    Write-Warning "$($repo.Name) has no commits to push."
                }
                elseif ($hasUpstream) {
                    Invoke-GitWrite -Arguments @("push")
                }
                else {
                    Invoke-GitWrite -Arguments @("push", "--set-upstream", "origin", $branch)
                }
            }
            else {
                Write-Warning "$($repo.Name) has no origin remote. Skipping push."
            }
        }
    }
    catch {
        $failedRepos += [pscustomobject]@{ Name = $repo.Name; Error = $_.Exception.Message }
        Write-Error -ErrorAction Continue "$($repo.Name) failed: $($_.Exception.Message)"
    }
    finally {
        Pop-Location
    }
}

if ($failedRepos.Count -gt 0) {
    Write-Host ""
    Write-Host "Git sync completed with failures:" -ForegroundColor Red
    foreach ($failure in $failedRepos) {
        Write-Host "- $($failure.Name): $($failure.Error)" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "Git sync completed successfully."