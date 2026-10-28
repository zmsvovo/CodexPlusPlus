$ErrorActionPreference = 'Stop'
$targetPath = $env:CODEX_PLUS_UPDATE_TARGET
$transactionPath = $env:CODEX_PLUS_UPDATE_TRANSACTION
$stagedPath = Join-Path $transactionPath 'new.exe'
$backupPath = Join-Path $transactionPath 'previous.exe'
$logPath = Join-Path $transactionPath 'update.log'
$movedOld = $false
$placedNew = $false
function Start-UpdatedApplication {
    # ProcessStartInfo treats brackets and quotes as literal path characters.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $targetPath
    $startInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($targetPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $started = [Diagnostics.Process]::Start($startInfo)
    $started.Dispose()
}
try {
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw 'Current executable is missing.' }
    if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { throw 'Staged executable is missing.' }
    $oldProcess = Get-Process -Id ([int]$env:CODEX_PLUS_UPDATE_PID) -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $transactionPath 'ready') -Value 'ready'
    if ($oldProcess -and -not $oldProcess.WaitForExit(120000)) { throw 'Application did not exit; no files replaced.' }
    # Retry temporary file locks without terminating other processes.
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            Move-Item -LiteralPath $targetPath -Destination $backupPath
            $movedOld = $true
            break
        } catch {
            if ($attempt -eq 29) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    Move-Item -LiteralPath $stagedPath -Destination $targetPath
    $placedNew = $true
    Start-UpdatedApplication
    Set-Content -LiteralPath $logPath -Value 'Updated and restarted. Previous executable retained as previous.exe.'
} catch {
    $failure = $_.Exception.Message
    if ($movedOld) {
        try {
            if ($placedNew) { Move-Item -LiteralPath $targetPath -Destination (Join-Path $transactionPath 'failed.exe') }
            Move-Item -LiteralPath $backupPath -Destination $targetPath
            Start-UpdatedApplication
        } catch { $failure += '; rollback: ' + $_.Exception.Message }
    }
    Set-Content -LiteralPath $logPath -Value $failure
    exit 1
}
