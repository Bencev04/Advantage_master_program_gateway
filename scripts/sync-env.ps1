param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$gatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$systemExamplePath = Join-Path $gatewayRoot "system.env.example"
$systemLocalPath = Join-Path $gatewayRoot "system.local.env"

function New-LocalSecret {
    $raw = "{0}{1}" -f ([guid]::NewGuid().ToString("N")), ([guid]::NewGuid().ToString("N"))
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($raw))
}

function New-LocalPassword {
    return "local-{0}" -f ([guid]::NewGuid().ToString("N"))
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $values
    }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $values
}

function Write-DotEnv {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Values
    )

    $lines = foreach ($key in $Values.Keys) {
        "$key=$($Values[$key])"
    }

    if ($DryRun) {
        Write-Host "Would write $Path"
        return
    }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory = $true)]$Values,
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowEmptyString()][string]$Value
    )

    $Values[$Key] = $Value
}

function Ensure-SystemLocalEnv {
    if (-not (Test-Path $systemLocalPath)) {
        if (-not (Test-Path $systemExamplePath)) {
            throw "Missing $systemExamplePath"
        }

        if ($DryRun) {
            Write-Host "Would create $systemLocalPath from $systemExamplePath"
        }
        else {
            Copy-Item $systemExamplePath $systemLocalPath
            Write-Host "Created system.local.env from system.env.example."
        }
    }

    $system = Read-DotEnv $systemLocalPath
    if ($system.Count -eq 0) {
        $system = Read-DotEnv $systemExamplePath
    }

    $defaults = [ordered]@{
        SYSTEM_ENVIRONMENT = "development"
        SYSTEM_LOG_LEVEL = "info"
        SYSTEM_JWT_ALGORITHM = "HS256"
        SYSTEM_ACCESS_TOKEN_EXPIRE_MINUTES = "480"
        SYSTEM_ACCESS_TOKEN_COOKIE_NAME = "access_token"
        GATEWAY_HTTP_PORT = "80"
        GATEWAY_DASHBOARD_PORT = "8088"
        CALENDAR_HOST = "calendar.advantage.localhost"
        CALENDAR_ALIAS_HOST = "hub.advantage.localhost"
        IDENTITY_HOST = "identity.advantage.localhost"
        SALES_HOST = "sales.advantage.localhost"
        FORWARDING_HOST = "forwarding.advantage.localhost"
        FLEET_HOST = "fleet.advantage.localhost"
        CALENDAR_APP_URL = "http://calendar.advantage.localhost"
        IDENTITY_LOGIN_URL = "http://identity.advantage.localhost/login"
        IDENTITY_LOGOUT_URL = "http://identity.advantage.localhost/logout"
        SALES_APP_URL = "http://sales.advantage.localhost"
        FORWARDING_APP_URL = "http://forwarding.advantage.localhost"
        FLEET_APP_URL = "http://fleet.advantage.localhost"
        PROJECTS_APP_URL = "http://localhost:5173"
        KAFKA_BOOTSTRAP_SERVERS = "localhost:9092"
        IDENTITY_POSTGRES_USER = "advantage_identity"
        IDENTITY_POSTGRES_DB = "advantage_identity"
        SALES_POSTGRES_USER = "advantage"
        SALES_USER_DB = "advantage_user"
        SALES_QUOTATION_DB = "advantage_quotation"
        CALENDAR_DATABASE_URL = ""
        AUDIT_DB_USER = "audit"
        AUDIT_DB_NAME = "advantage_audit"
        AUDIT_SERVICE_URL = "http://host.docker.internal:18130"
    }

    foreach ($key in $defaults.Keys) {
        if (-not $system.Contains($key) -or -not $system[$key] -or $system[$key].StartsWith("REPLACE_ME")) {
            $system[$key] = $defaults[$key]
        }
    }

    if (-not $system.Contains("SYSTEM_SECRET_KEY") -or -not $system["SYSTEM_SECRET_KEY"] -or $system["SYSTEM_SECRET_KEY"].StartsWith("REPLACE_ME")) {
        $system["SYSTEM_SECRET_KEY"] = New-LocalSecret
    }

    if (-not $system.Contains("SYSTEM_POSTGRES_PASSWORD") -or -not $system["SYSTEM_POSTGRES_PASSWORD"] -or $system["SYSTEM_POSTGRES_PASSWORD"].StartsWith("REPLACE_ME")) {
        $system["SYSTEM_POSTGRES_PASSWORD"] = New-LocalPassword
    }

    if (-not $system.Contains("AUDIT_DB_PASSWORD") -or -not $system["AUDIT_DB_PASSWORD"] -or $system["AUDIT_DB_PASSWORD"].StartsWith("REPLACE_ME")) {
        $system["AUDIT_DB_PASSWORD"] = New-LocalPassword
    }

    Write-DotEnv -Path $systemLocalPath -Values $system
    return $system
}

function Update-RepoEnv {
    param(
        [Parameter(Mandatory = $true)][string]$RepoFolder,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Updates
    )

    $repoPath = Join-Path $workspaceRoot $RepoFolder
    $envPath = Join-Path $repoPath ".env"
    $examplePath = Join-Path $repoPath ".env.example"

    if (-not (Test-Path $repoPath)) {
        Write-Warning "$Name repo not found at $repoPath. Skipping."
        return
    }

    if (-not (Test-Path $envPath)) {
        if (-not (Test-Path $examplePath)) {
            Write-Warning "$Name has no .env or .env.example. Skipping."
            return
        }

        if ($DryRun) {
            Write-Host "Would create $Name .env from .env.example"
        }
        else {
            Copy-Item $examplePath $envPath
            Write-Host "Created $Name .env from .env.example."
        }
    }

    $values = Read-DotEnv $envPath
    foreach ($key in $Updates.Keys) {
        Set-EnvValue -Values $values -Key $key -Value $Updates[$key]
    }

    Write-DotEnv -Path $envPath -Values $values
}

$systemValues = Ensure-SystemLocalEnv

$gatewayUpdates = [ordered]@{
    GATEWAY_HTTP_PORT = $systemValues["GATEWAY_HTTP_PORT"]
    GATEWAY_DASHBOARD_PORT = $systemValues["GATEWAY_DASHBOARD_PORT"]
    CALENDAR_HOST = $systemValues["CALENDAR_HOST"]
    CALENDAR_ALIAS_HOST = $systemValues["CALENDAR_ALIAS_HOST"]
    IDENTITY_HOST = $systemValues["IDENTITY_HOST"]
    SALES_HOST = $systemValues["SALES_HOST"]
    FORWARDING_HOST = $systemValues["FORWARDING_HOST"]
    FLEET_HOST = $systemValues["FLEET_HOST"]
}

$identityUpdates = [ordered]@{
    POSTGRES_USER = $systemValues["IDENTITY_POSTGRES_USER"]
    POSTGRES_PASSWORD = $systemValues["SYSTEM_POSTGRES_PASSWORD"]
    POSTGRES_DB = $systemValues["IDENTITY_POSTGRES_DB"]
    IDENTITY_DATABASE_URL = "postgresql+asyncpg://$($systemValues["IDENTITY_POSTGRES_USER"]):$($systemValues["SYSTEM_POSTGRES_PASSWORD"])@db:5432/$($systemValues["IDENTITY_POSTGRES_DB"])"
    SECRET_KEY = $systemValues["SYSTEM_SECRET_KEY"]
    JWT_ALGORITHM = $systemValues["SYSTEM_JWT_ALGORITHM"]
    ACCESS_TOKEN_EXPIRE_MINUTES = $systemValues["SYSTEM_ACCESS_TOKEN_EXPIRE_MINUTES"]
    AUDIT_SERVICE_URL = $systemValues["AUDIT_SERVICE_URL"]
    ENVIRONMENT = $systemValues["SYSTEM_ENVIRONMENT"]
    LOG_LEVEL = $systemValues["SYSTEM_LOG_LEVEL"]
}

$salesUpdates = [ordered]@{
    POSTGRES_USER = $systemValues["SALES_POSTGRES_USER"]
    POSTGRES_PASSWORD = $systemValues["SYSTEM_POSTGRES_PASSWORD"]
    POSTGRES_USER_DB = $systemValues["SALES_USER_DB"]
    USER_DATABASE_URL = "postgresql+asyncpg://$($systemValues["SALES_POSTGRES_USER"]):$($systemValues["SYSTEM_POSTGRES_PASSWORD"])@db:5432/$($systemValues["SALES_USER_DB"])"
    POSTGRES_DB = $systemValues["SALES_QUOTATION_DB"]
    DATABASE_URL = "postgresql+asyncpg://$($systemValues["SALES_POSTGRES_USER"]):$($systemValues["SYSTEM_POSTGRES_PASSWORD"])@db:5432/$($systemValues["SALES_QUOTATION_DB"])"
    SECRET_KEY = $systemValues["SYSTEM_SECRET_KEY"]
    JWT_ALGORITHM = $systemValues["SYSTEM_JWT_ALGORITHM"]
    ACCESS_TOKEN_EXPIRE_MINUTES = $systemValues["SYSTEM_ACCESS_TOKEN_EXPIRE_MINUTES"]
    KAFKA_BOOTSTRAP_SERVERS = $systemValues["KAFKA_BOOTSTRAP_SERVERS"]
    AUDIT_SERVICE_URL = $systemValues["AUDIT_SERVICE_URL"]
    ENVIRONMENT = $systemValues["SYSTEM_ENVIRONMENT"]
    LOG_LEVEL = $systemValues["SYSTEM_LOG_LEVEL"]
}

$observabilityUpdates = [ordered]@{
    ENVIRONMENT = $systemValues["SYSTEM_ENVIRONMENT"]
    LOG_LEVEL = $systemValues["SYSTEM_LOG_LEVEL"]
    AUDIT_DB_USER = $systemValues["AUDIT_DB_USER"]
    AUDIT_DB_NAME = $systemValues["AUDIT_DB_NAME"]
    AUDIT_DB_PASSWORD = $systemValues["AUDIT_DB_PASSWORD"]
    IDENTITY_SHARED_SECRET = $systemValues["SYSTEM_SECRET_KEY"]
    KAFKA_BOOTSTRAP_SERVERS = "host.docker.internal:9092"
}

$calendarUpdates = [ordered]@{
    ENVIRONMENT = $systemValues["SYSTEM_ENVIRONMENT"]
    SECRET_KEY = $systemValues["SYSTEM_SECRET_KEY"]
    JWT_ALGORITHM = $systemValues["SYSTEM_JWT_ALGORITHM"]
    ACCESS_TOKEN_COOKIE_NAME = $systemValues["SYSTEM_ACCESS_TOKEN_COOKIE_NAME"]
    IDENTITY_LOGIN_URL = $systemValues["IDENTITY_LOGIN_URL"]
    IDENTITY_LOGOUT_URL = $systemValues["IDENTITY_LOGOUT_URL"]
    CALENDAR_APP_URL = $systemValues["CALENDAR_APP_URL"]
    SALES_APP_URL = $systemValues["SALES_APP_URL"]
    FORWARDING_APP_URL = $systemValues["FORWARDING_APP_URL"]
    FLEET_APP_URL = $systemValues["FLEET_APP_URL"]
    PROJECTS_APP_URL = $systemValues["PROJECTS_APP_URL"]
    DATABASE_URL = $systemValues["CALENDAR_DATABASE_URL"]
    KAFKA_BOOTSTRAP_SERVERS = $systemValues["KAFKA_BOOTSTRAP_SERVERS"]
}

Update-RepoEnv -RepoFolder "Advantage_master_program_gateway" -Name "Gateway" -Updates $gatewayUpdates
Update-RepoEnv -RepoFolder "Advantage_master_program_identity" -Name "Identity" -Updates $identityUpdates
Update-RepoEnv -RepoFolder "Advantage_master_program_sales" -Name "Sales" -Updates $salesUpdates
Update-RepoEnv -RepoFolder "Advantage_master_program_observability" -Name "Observability" -Updates $observabilityUpdates
Update-RepoEnv -RepoFolder "Advantage_master_program_calender" -Name "Calendar" -Updates $calendarUpdates

Write-Host "System environment sync complete."
Write-Host "Shared local source: $systemLocalPath"
