[CmdletBinding()]
param(
    [switch]$Worker,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$repoPath = $PSScriptRoot

if (-not $Worker) {
    $logDirectory = 'E:\.tmp\codex-lb-restart'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $LogPath = Join-Path $logDirectory (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    $LogPath += '.log'
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path `
        -ArgumentList @('-NoProfile', '-File', "`"$PSCommandPath`"", '-Worker', '-LogPath', "`"$LogPath`"") `
        -WorkingDirectory $repoPath -WindowStyle Hidden -PassThru
    Write-Output "Restart worker PID: $($process.Id)"
    Write-Output "Log: $LogPath"
    return
}

Set-Location -LiteralPath $repoPath
Start-Transcript -LiteralPath $LogPath | Out-Null
$exitCode = 1

function Invoke-Compose {
    param([string[]]$ComposeArguments)
    & docker compose --project-directory $repoPath @ComposeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed with exit code $LASTEXITCODE."
    }
}

try {
    Invoke-Compose @('config', '--quiet')
    # Keep PostgreSQL running. Never take the stack down or remove volumes.
    Invoke-Compose @('up', '-d', 'postgres')
    # The runtime fetches the latest Codex client version on startup.
    # Reuse the deployed image rather than building unrelated local edits.
    Invoke-Compose @('up', '-d', '--no-deps', '--no-build', '--force-recreate', 'codex-lb')

    $deadline = (Get-Date).AddMinutes(5)
    do {
        try {
            $null = Invoke-RestMethod 'http://127.0.0.1:2455/health/ready' -TimeoutSec 5
            break
        }
        catch {
            if ((Get-Date) -ge $deadline) { throw 'CodexLB did not become ready within five minutes.' }
            Start-Sleep -Seconds 3
        }
    } while ($true)

    if ($env:CODEX_LB_API_KEY) {
        $catalog = Invoke-RestMethod `
            'http://127.0.0.1:2455/backend-api/codex/models?client_version=0.170.0' `
            -Headers @{ Authorization = "Bearer $env:CODEX_LB_API_KEY" } -TimeoutSec 30
        foreach ($slug in @('gpt-6.2-astra', 'gpt-6.2-sol')) {
            if (-not ($catalog.models | Where-Object { $_.slug -eq $slug -and $_.visibility -eq 'list' })) {
                throw "Model is not visible after restart: $slug"
            }
            Write-Output "Enabled: $slug"
        }
    }
    Write-Output 'CodexLB is ready.'
    $exitCode = 0
}
catch {
    Write-Output "Restart verification failed: $($_.Exception.Message)"
    # Attempt recovery even if recreation or verification failed.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & docker compose --project-directory $repoPath up -d --no-build postgres codex-lb
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 5
    }
}
finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
