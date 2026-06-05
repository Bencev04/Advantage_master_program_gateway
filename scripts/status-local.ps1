$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$repos = @(
    @{ Name = "Gateway"; Folder = "Advantage_master_program_gateway" },
    @{ Name = "Calendar"; Folder = "Advantage_master_program_calender" },
    @{ Name = "Sales"; Folder = "Advantage_master_program_sales" },
    @{ Name = "Identity"; Folder = "Advantage_master_program_identity" },
    @{ Name = "Observability"; Folder = "Advantage_master_program_observability" },
    @{ Name = "Monitoring"; Folder = "Advantage_master_program_observability\monitoring" },
    @{ Name = "Events/Redpanda"; Folder = "Advantage_master_program_events" }
)

foreach ($repo in $repos) {
    $repoPath = Join-Path $workspaceRoot $repo.Folder
    if (-not (Test-Path (Join-Path $repoPath "docker-compose.yml"))) {
        continue
    }

    Write-Host ""
    Write-Host "== $($repo.Name) =="
    Push-Location $repoPath
    try {
        & docker compose ps
    }
    finally {
        Pop-Location
    }
}
