# Désinstalle le mod Local Splitscreen de Buckshot Roulette.
#   Uninstall.bat                       -> trouve le jeu via Steam
#   Uninstall.bat "D:\...\Buckshot Roulette_windows"
param([string]$GameDir = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

try {
    $GameDir = Resolve-GameDir $GameDir
    Write-Host "Jeu trouvé : $GameDir"

    # 1. Remove the mod's autoload; delete override.cfg if nothing else is left in it
    $cfg = Join-Path $GameDir "override.cfg"
    if (Test-Path -LiteralPath $cfg) {
        $lines = @(Read-CfgLines $cfg | Where-Object { $_ -notmatch '^\s*SplitMod\s*=' })
        $settings = @($lines | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '^\s*\[.*\]\s*$' -and $_ -notmatch '^\s*;' })
        if ($settings.Count -eq 0) {
            Remove-Item -LiteralPath $cfg -Force
        } else {
            # Drop an [autoload] header left without entries.
            $kept = New-Object System.Collections.Generic.List[string]
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*\[autoload\]\s*$') {
                    $j = $i + 1
                    while ($j -lt $lines.Count -and $lines[$j].Trim() -eq "") { $j++ }
                    if ($j -ge $lines.Count -or $lines[$j] -match '^\s*\[.*\]\s*$') { $i = $j - 1; continue }
                }
                $kept.Add($lines[$i])
            }
            Write-CfgLines $cfg $kept
        }
    }
    if (Test-Path -LiteralPath "$cfg.before-splitscreen") { Remove-Item -LiteralPath "$cfg.before-splitscreen" -Force }

    # 2. Mod files
    $target = Join-Path $GameDir $ModFolderName
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }

    Write-Host ""
    Write-Host "Mod désinstallé, le jeu est revenu à l'état d'origine." -ForegroundColor Green
    exit 0
} catch {
    Write-Host ""
    Write-Host "Echec de la désinstallation : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception -is [System.UnauthorizedAccessException]) {
        Write-Host "Essayez : clic droit sur Uninstall.bat > Exécuter en tant qu'administrateur."
    }
    exit 1
}
