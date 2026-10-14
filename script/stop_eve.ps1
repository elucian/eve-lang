# Stop the programs that run from the bin\ folder given as the argument (eve, evetx, evedb...), so
# that the build can replace the files. Programs from any other folder are left alone.
param([Parameter(Mandatory = $true)][string]$Bin)
if (-not (Test-Path -LiteralPath $Bin -PathType Container)) { Write-Host "stop_eve: not a folder: $Bin"; exit 1 }
$full = (Resolve-Path -LiteralPath $Bin).Path.TrimEnd('') + ''
if ($full.Length -lt 8) { Write-Host "stop_eve: refusing the folder $full"; exit 1 }
$found = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase) }
foreach ($p in $found) {
    Write-Host ("stopping {0} (pid {1})" -f $p.Name, $p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
if ($found) { Start-Sleep -Milliseconds 500 }
