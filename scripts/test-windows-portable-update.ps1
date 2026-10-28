$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo ("target\portable smoke [test]' " + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$source = Join-Path $root 'Stub.cs'
Set-Content -LiteralPath $source -Encoding UTF8 -Value 'using System; using System.IO; class Stub { static void Main() { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "started.txt"), "started"); } }'
$stub = Join-Path $root 'stub.exe'
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x64 "/out:$stub" $source
if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
foreach ($scenario in @('success', 'rollback')) {
    $casePath = Join-Path $root $scenario
    $transaction = Join-Path $casePath '.transaction'
    New-Item -ItemType Directory -Path $transaction -Force | Out-Null
    $target = Join-Path $casePath "Codex++ [test]' app.exe"
    Copy-Item -LiteralPath $stub -Destination $target
    $originalHash = (Get-FileHash -LiteralPath $target).Hash
    $newPath = Join-Path $transaction 'new.exe'
    $newBytes = [IO.File]::ReadAllBytes($stub) + [byte[]]@(1,2,3,4)
    [IO.File]::WriteAllBytes($newPath, $newBytes)
    $newHash = (Get-FileHash -LiteralPath $newPath).Hash
    $env:CODEX_PLUS_UPDATE_TARGET = $target
    $env:CODEX_PLUS_UPDATE_TRANSACTION = $transaction
    $env:CODEX_PLUS_UPDATE_PID = '2147483647'
    $lock = $null
    if ($scenario -eq 'rollback') { $lock = [IO.File]::Open($newPath, 'Open', 'Read', 'None') }
    try {
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'crates/codex-plus-core/src/update/windows-update.ps1')
        $result = $LASTEXITCODE
    } finally { if ($lock) { $lock.Dispose() } }
    $hash = (Get-FileHash -LiteralPath $target).Hash
    if ($scenario -eq 'success' -and ($result -ne 0 -or $hash -ne $newHash)) { throw ('Success failed: ' + (Get-Content -LiteralPath (Join-Path $transaction 'update.log') -Raw)) }
    if ($scenario -eq 'rollback' -and ($result -eq 0 -or $hash -ne $originalHash)) { throw 'Rollback did not restore original executable' }
    for ($i=0; $i -lt 50 -and -not (Test-Path -LiteralPath (Join-Path $casePath 'started.txt')); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath (Join-Path $casePath 'started.txt'))) { throw 'Executable did not restart' }
    Write-Output "$scenario passed"
}
