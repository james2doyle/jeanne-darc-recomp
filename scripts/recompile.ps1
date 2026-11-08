# Recompiles BOOT.BIN to C (data\generated) with a host psprecomp build. Picks the preset for you:
# -Preset wins, otherwise the first configured host build that already has psprecomp, otherwise the
# platform default. Android presets build no host tools, so they are rejected (recompilation always
# runs on the host, even when the game itself targets a device).
#
#   scripts\recompile.ps1                              # auto-detect preset
#   scripts\recompile.ps1 -Preset windows-x64-release -- --help  # extra args go to psprecomp
[CmdletBinding(PositionalBinding = $false)]  # psprecomp arguments must not land in -Preset
param(
    [string]$Preset = '',
    [string]$Boot = 'data\original\PSP_GAME\SYSDIR\BOOT.BIN',
    [string]$OutDir = 'data\generated',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RecompArgs
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Preset) {
    foreach ($c in 'windows-x64-debug', 'windows-x64-release', 'windows-x64-profile', 'linux-x64-debug', 'linux-x64-release') {
        if (Test-Path (Join-Path $root "build\$c\psprecore\tools\psprecomp\psprecomp.exe")) { $Preset = $c; break }
    }
}
if (-not $Preset) { $Preset = 'windows-x64-debug' }
if ($Preset -like 'android-*') { throw "$Preset builds no host tools; pass a host preset (e.g. -Preset windows-x64-debug)" }
Push-Location $root
try {
    # Native tools report warnings on stderr; under 'Stop' PowerShell 5.1 would abort on them. Exit codes are checked.
    $ErrorActionPreference = 'Continue'
    cmake --build --preset $Preset --target psprecomp
    if ($LASTEXITCODE) { throw "psprecomp build failed ($LASTEXITCODE)" }
    $exe = Join-Path $root "build\$Preset\psprecore\tools\psprecomp\psprecomp.exe"
    if (-not (Test-Path $exe)) { throw "$exe not found after building psprecomp" }
    # '--' only separates this script's options from psprecomp's; drop it before forwarding.
    $forwarded = @($RecompArgs | Where-Object { $_ -ne '--' })
    & $exe $Boot $OutDir --overrides (Join-Path $root 'src\decomp') --seeds (Join-Path $root 'seeds.txt') @forwarded
    if ($LASTEXITCODE) { throw "psprecomp failed ($LASTEXITCODE)" }
    Write-Host "done; re-run scripts\build.ps1 -Preset $Preset to pick up the generated code"
} finally {
    Pop-Location
}
