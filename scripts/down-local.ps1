param(
    [switch]$Volumes,
    [switch]$SkipEvents,
    [switch]$SkipIdentity,
    [switch]$SkipSales,
    [switch]$SkipCalendar,
    [switch]$SkipGateway
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Invoke-RepoComposeDown {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Folder,
        [switch]$RemoveVolumes
    )

    $repoPath = Join-Path $workspaceRoot $Folder
    if (-not (Test-Path (Join-Path $repoPath "docker-compose.yml"))) {
        Write-Warning "$Name has no docker-compose.yml at $repoPath. Skipping."
        return
    }

    Write-Host "Stopping $Name..."
    Push-Location $repoPath
    try {
        $composeArgs = @("compose", "down")
        if ($RemoveVolumes) {
            $composeArgs += "-v"
        }

        & docker @composeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "$Name docker compose down failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $SkipGateway) {
    Invoke-RepoComposeDown -Name "Gateway" -Folder "Advantage_master_program_gateway" -RemoveVolumes:$Volumes
}

if (-not $SkipCalendar) {
    Invoke-RepoComposeDown -Name "Calendar" -Folder "Advantage_master_program_calender" -RemoveVolumes:$Volumes
}

if (-not $SkipSales) {
    Invoke-RepoComposeDown -Name "Sales" -Folder "Advantage_master_program_Sales" -RemoveVolumes:$Volumes
}

if (-not $SkipIdentity) {
    Invoke-RepoComposeDown -Name "Identity" -Folder "Advantage_master_program_identity" -RemoveVolumes:$Volumes
}

if (-not $SkipEvents) {
    Invoke-RepoComposeDown -Name "Events/Redpanda" -Folder "Advantage_master_program_events" -RemoveVolumes:$Volumes
}

Write-Host "Advantage Master local system stop requested."
