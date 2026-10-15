# Stop the programs that run from the bin\ folder given as the argument (eve, evetx, evedb...), so
# that the build can replace the files. Programs from any other folder are left alone.
param([Parameter(Mandatory = $true)][string]$Bin, [switch]$SkipParent)
if (-not (Test-Path -LiteralPath $Bin -PathType Container)) { Write-Host "stop_eve: no folder $Bin, nothing to stop"; exit 0 }
$full = (Resolve-Path -LiteralPath $Bin).Path.TrimEnd('') + ''
if ($full.Length -lt 8) { Write-Host "stop_eve: refusing the folder $full"; exit 1 }
# -SkipParent: `eve --kill` runs this script, so the eve that started it must stay alive to report
$skip = if ($SkipParent) { (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId } else { 0 }
$found = Get-Process | Where-Object { $_.Path -and $_.Id -ne $skip -and $_.Id -ne $PID -and $_.Path.StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase) }
# A program that is killed from outside cannot put its terminal back (the shell then shows mouse codes as numbers),
# so evetx is asked first: it looks for the file evetx.quit beside it, and ends the normal way. Up to 4 seconds.
$tx = @($found | Where-Object { $_.Name -eq 'evetx' })
if ($tx.Count -gt 0) {
    $quit = Join-Path $full 'evetx.quit'
    Set-Content -LiteralPath $quit -Value 'quit' -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        if (-not ($tx | Where-Object { Get-Process -Id $_.Id -ErrorAction SilentlyContinue })) { break }
        Start-Sleep -Milliseconds 200
    }
    Remove-Item -LiteralPath $quit -Force -ErrorAction SilentlyContinue
}
$found = $found | Where-Object { Get-Process -Id $_.Id -ErrorAction SilentlyContinue }
foreach ($p in $found) {
    Write-Host ("stopping {0} (pid {1})" -f $p.Name, $p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
if ($found) { Start-Sleep -Milliseconds 500 }
