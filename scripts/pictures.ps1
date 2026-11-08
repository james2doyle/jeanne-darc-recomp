# Picture check: replays recordings unthrottled and writes a fixed set of pictures (Vulkan frames and smooth
# motion's pictures in between, the other drawing paths, the software renderer), then compares them with a reference
# set. Next to regress.ps1 (the game's RAM): the pictures, for changes that must not alter what is drawn. Pictures
# and recordings stay local (they show the game).
#
# The runs below are placeholders (vblanks picked during first boot): update them with your own recordings (see docs/testing.md).
#
#   scripts\pictures.ps1 -Out build\pictures-ref                            # write a reference set
#   scripts\pictures.ps1 -Out build\pictures-new -Reference build\pictures-ref   # write and compare
param(
    [Parameter(Mandatory)] [string]$Out,
    [string]$Reference,
    [string]$Dir = 'data\recordings',
    [string]$Exe = 'build\windows-x64-release\jdarc.exe',
    [string]$GameDir = 'data\original',
    [string]$CookedDir = 'data\cooked'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path $Exe)) { throw "$Exe not found; build first (scripts\build.ps1 -Preset windows-x64-release)" }
    $exe = (Resolve-Path $Exe).Path
    $game = (Resolve-Path $GameDir).Path
    $cooked = (Resolve-Path $CookedDir).Path
    $recordings = (Resolve-Path $Dir).Path
    New-Item -ItemType Directory -Force $Out | Out-Null
    $out = (Resolve-Path $Out).Path
    $ref = if ($Reference) { (Resolve-Path $Reference).Path } else { $null }
    Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item  # (pictures this script wrote before)

    # Settings without anything that differs from run to run (the FPS counter).
    $ini = Join-Path $out 'pictures.ini'
    $settings = @('renderer=vulkan', 'fullscreen=0', 'volume=0', 'frame_limit=1', 'vsync=1', 'refresh_60hz=1',
                  'show_fps=0', 'button_glyphs=playstation', 'frame_skip=1', 'hd_textures=1', 'fill_screen=0',
                  'smooth_motion=1', 'msaa=1', 'scale=2')

    Set-Content -Encoding ascii $ini ($settings + 'scale=2')

    # name, recording, settings, extra arguments, last vblank (placeholders: fill in with real runs)
    $runs = @(
        @('boot', 'boot.txt', $ini, @('--screenshot-every', "300:$out\boot"), 3600)
    )
    Set-Location (Join-Path $root 'run')  # (test games run from run\: its pipeline cache and settings)
    foreach ($r in $runs) {
        $name, $rec, $settingsFile, $extra, $last = $r
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ErrorActionPreference = 'Continue'
        & $exe $game --cooked $cooked --no-audio --unthrottled --settings $settingsFile --replay (Join-Path $recordings $rec) --vblanks $last @extra 2>&1 |
            Out-File -Width 400 (Join-Path $out "$name.log")
        $ErrorActionPreference = 'Stop'
        Write-Host ("{0,-15} {1,3} pictures  {2:0} s" -f $name, @(Get-ChildItem $out -Filter "$name*.png").Count, $sw.Elapsed.TotalSeconds)
    }

    if ($ref) {
        $differ = 0
        $names = @(Get-ChildItem $ref -Filter *.png | ForEach-Object Name) + @(Get-ChildItem $out -Filter *.png | ForEach-Object Name) | Sort-Object -Unique
        foreach ($n in $names) {
            $a = Join-Path $ref $n
            $b = Join-Path $out $n
            if (-not (Test-Path $a)) { Write-Host "new      $n"; $differ++; continue }
            if (-not (Test-Path $b)) { Write-Host "missing  $n"; $differ++; continue }
            if ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash) { Write-Host "differs  $n"; $differ++ }
        }
        if ($differ) { throw "$differ of $($names.Count) pictures differ from $Reference" }
        Write-Host "all $($names.Count) pictures identical to $Reference"
    }
} finally {
    Pop-Location
}
