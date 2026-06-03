param(
    [string]$WorkspaceRoot = "",
    [string]$RemoteBaseUrl = "",
    [Alias("Only")]
    [string[]]$RepoFolders = @(),
    [switch]$IncludeGateway,
    [switch]$SkipPull,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$gatewayRepoName = "Advantage_master_program_gateway"
$defaultRepoFolders = @(
    "Advantage_master_program_calender",
    "Advantage_master_program_comms",
    "Advantage_master_program_depl",
    "Advantage_master_program_design",
    "Advantage_master_program_events",
    "Advantage_master_program_fleet",
    "Advantage_master_program_forwarding",
    "Advantage_master_program_gateway",
    "Advantage_master_program_identity",
    "Advantage_master_program_infra",
    "Advantage_master_program_observability",
    "Advantage_master_program_Sales"
)

$gatewayRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $WorkspaceRoot) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $gatewayRoot "..")).Path
}
elseif (Test-Path $WorkspaceRoot) {
    $WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
}
elseif ($DryRun) {
    Write-Host "[dry-run] Would create workspace root $WorkspaceRoot"
}
else {
    New-Item -ItemType Directory -Path $WorkspaceRoot | Out-Null
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

function Get-GatewayOriginUrl {
    $remote = Invoke-GitRead -Arguments @("-C", $gatewayRoot, "remote", "get-url", "origin") -AllowFailure
    if ($remote.ExitCode -ne 0) {
        return ""
    }

    return ($remote.Output -join "").Trim()
}

function Get-RemoteBaseUrl {
    if ($RemoteBaseUrl) {
        return $RemoteBaseUrl.TrimEnd("/")
    }

    $originUrl = Get-GatewayOriginUrl
    if (-not $originUrl) {
        throw "Could not infer remote base URL because gateway has no origin remote. Re-run with -RemoteBaseUrl, for example: -RemoteBaseUrl https://github.com/Bencev04"
    }

    $escapedGatewayRepoName = [regex]::Escape($gatewayRepoName)
    if ($originUrl -match "^(?<base>.+)/$escapedGatewayRepoName(?:\.git)?/?$") {
        return $Matches["base"].TrimEnd("/")
    }

    if ($originUrl -match "^(?<base>.+:)$escapedGatewayRepoName(?:\.git)?/?$") {
        return $Matches["base"].TrimEnd("/")
    }

    throw "Could not infer remote base URL from gateway origin '$originUrl'. Re-run with -RemoteBaseUrl, for example: -RemoteBaseUrl https://github.com/Bencev04"
}

function Join-RemoteUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$RepoName
    )

    $base = $BaseUrl.TrimEnd("/")
    if ($base.EndsWith(":")) {
        return "$base$RepoName.git"
    }

    return "$base/$RepoName.git"
}

function Get-RepositoryTargets {
    $repoNames = $defaultRepoFolders
    if ($RepoFolders.Count -gt 0) {
        $repoNames = $RepoFolders
    }

    $repoNames |
        Where-Object { $_ -and ($IncludeGateway -or $_ -ne $gatewayRepoName) } |
        Sort-Object -Unique |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_
                Path = Join-Path $WorkspaceRoot $_
            }
        }
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

function Has-UpstreamBranch {
    $upstream = Invoke-GitRead -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}") -AllowFailure
    return $upstream.ExitCode -eq 0
}

function Clone-Repository {
    param(
        [Parameter(Mandatory = $true)]$Repo,
        [Parameter(Mandatory = $true)][string]$BaseUrl
    )

    $remoteUrl = Join-RemoteUrl -BaseUrl $BaseUrl -RepoName $Repo.Name
    Invoke-GitWrite -Arguments @("clone", $remoteUrl, $Repo.Path)
}

function Pull-ExistingRepository {
    param(
        [Parameter(Mandatory = $true)]$Repo
    )

    if ($SkipPull) {
        Write-Host "Repository already exists. Pull skipped."
        return
    }

    Push-Location $Repo.Path
    try {
        if (-not (Test-OriginRemote)) {
            Write-Warning "$($Repo.Name) has no origin remote. Skipping pull."
            return
        }

        $branch = Get-CurrentBranch
        if (-not $branch) {
            throw "Repository has no active branch. Checkout or create a branch before pulling."
        }

        if ($branch -eq "HEAD") {
            throw "Repository is in detached HEAD state. Checkout a branch before pulling."
        }

        if ((Has-CommitHistory) -and (Has-UpstreamBranch)) {
            Invoke-GitWrite -Arguments @("pull", "--rebase", "--autostash")
        }
        else {
            Invoke-GitWrite -Arguments @("fetch", "origin")
            Write-Warning "$($Repo.Name) branch '$branch' has no pull target yet. Fetched origin only."
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not available on PATH. Install Git or open a shell where git is available."
}

$remoteBase = Get-RemoteBaseUrl
$repositories = @(Get-RepositoryTargets)

if ($repositories.Count -eq 0) {
    Write-Warning "No repositories selected."
    exit 0
}

Write-Host "Workspace root: $WorkspaceRoot"
Write-Host "Remote base:    $remoteBase"

if (-not $IncludeGateway) {
    Write-Host "Gateway repo is skipped by default because this script is run from the manually cloned gateway. Use -IncludeGateway to pull it too."
}

$failedRepos = @()

foreach ($repo in $repositories) {
    Write-Host ""
    Write-Host "== $($repo.Name) =="

    try {
        if (Test-Path (Join-Path $repo.Path ".git")) {
            Pull-ExistingRepository -Repo $repo
        }
        elseif (Test-Path $repo.Path) {
            throw "Target path already exists but is not a git repository: $($repo.Path)"
        }
        else {
            Clone-Repository -Repo $repo -BaseUrl $remoteBase
        }
    }
    catch {
        $failedRepos += [pscustomobject]@{ Name = $repo.Name; Error = $_.Exception.Message }
        Write-Error -ErrorAction Continue "$($repo.Name) failed: $($_.Exception.Message)"
    }
}

if ($failedRepos.Count -gt 0) {
    Write-Host ""
    Write-Host "Repository pull completed with failures:" -ForegroundColor Red
    foreach ($failure in $failedRepos) {
        Write-Host "- $($failure.Name): $($failure.Error)" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "Repository pull completed successfully."
