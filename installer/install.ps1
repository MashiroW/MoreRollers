# Installe le mod Local Splitscreen de Buckshot Roulette.
#   Install.bat                         -> trouve le jeu via Steam
#   Install.bat "D:\...\Buckshot Roulette_windows"
param([string]$GameDir = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

try {
    $source = Join-Path (Split-Path -Parent $PSScriptRoot) "mod"
    foreach ($f in @("loader.gd", "splitscreen.pck")) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $f))) { throw "Fichier du mod manquant : mod\$f" }
    }

    $GameDir = Resolve-GameDir $GameDir
    Write-Host "Jeu trouvé : $GameDir"
    if (Test-GameRunning) { Write-Host "Le jeu est ouvert : le mod sera actif au prochain lancement." -ForegroundColor Yellow }

    # 1. Mod files
    $target = Join-Path $GameDir $ModFolderName
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -LiteralPath (Join-Path $source "loader.gd") -Destination $target -Force
    Copy-Item -LiteralPath (Join-Path $source "splitscreen.pck") -Destination $target -Force

    # 2. override.cfg: Godot reads it at startup and loads loader.gd as the "SplitMod" autoload
    $cfg = Join-Path $GameDir "override.cfg"
    $loaderPath = (Join-Path $target "loader.gd") -replace "\\", "/"
    $entry = 'SplitMod="*' + $loaderPath + '"'
    # Back up an override.cfg that holds settings of its own (not one that only has this mod's line).
    $foreign = @(Read-CfgLines $cfg | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '^\s*\[.*\]\s*$' -and $_ -notmatch '^\s*;' -and $_ -notmatch '^\s*SplitMod\s*=' })
    if ($foreign.Count -gt 0 -and -not (Test-Path -LiteralPath "$cfg.before-splitscreen")) {
        Copy-Item -LiteralPath $cfg -Destination "$cfg.before-splitscreen"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Read-CfgLines $cfg)) { if ($l -notmatch '^\s*SplitMod\s*=') { $lines.Add($l) } }
    $header = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[autoload\]\s*$') { $header = $i; break } }
    if ($header -ge 0) {
        $lines.Insert($header + 1, $entry)
    } else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") { $lines.Add("") }
        $lines.Add("[autoload]")
        $lines.Add("")
        $lines.Add($entry)
    }
    Write-CfgLines $cfg $lines

    Write-Host ""
    Write-Host "Mod installé." -ForegroundColor Green
    Write-Host "Lancez le jeu : 'LOCAL SPLITSCREEN' apparaît dans le menu principal, sous MULTIPLAYER."
    exit 0
} catch {
    Write-Host ""
    Write-Host "Echec de l'installation : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception -is [System.UnauthorizedAccessException]) {
        Write-Host "Essayez : clic droit sur Install.bat > Exécuter en tant qu'administrateur."
    }
    exit 1
}
