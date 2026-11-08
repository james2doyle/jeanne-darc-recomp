# Cooks the movie media the game loads besides the disc: PSMF video becomes AV1/IVF and its ATRAC3plus
# audio becomes Ogg (needs FFmpeg with the SVT-AV1 and Vorbis encoders). Existing outputs are kept, so an
# interrupted run can be resumed. Missing audio is silent and missing video is black at runtime.
#
#   scripts\cook.ps1                                   # data\original -> data\cooked
#   scripts\cook.ps1 -Preset windows-x64-release -- --force --limit 1
[CmdletBinding(PositionalBinding = $false)]  # jdcook arguments must not land in -Preset
param(
    [string]$Preset = 'windows-x64-debug',
    [string]$GameDir = 'data\original',
    [string]$CookedDir = 'data\cooked',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$CookArgs
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    # Native tools report warnings on stderr; under 'Stop' PowerShell 5.1 would abort on them. Exit codes are checked.
    $ErrorActionPreference = 'Continue'
    cmake --build --preset $Preset --target jdcook
    if ($LASTEXITCODE) { throw "jdcook build failed ($LASTEXITCODE)" }
    $exe = Join-Path $root "build\$Preset\tools\jdcook\jdcook.exe"
    if (-not (Test-Path $exe)) { throw "$exe not found after building jdcook" }
    # '--' only separates this script's options from jdcook's; drop it before forwarding.
    $forwarded = @($CookArgs | Where-Object { $_ -ne '--' })
    & $exe $GameDir $CookedDir @forwarded
    if ($LASTEXITCODE) { throw "jdcook failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}
