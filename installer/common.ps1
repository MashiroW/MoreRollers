# Shared helpers for install.ps1 / uninstall.ps1.

$ModFolderName = "splitscreen_mod"
$GameExeName = "Buckshot Roulette.exe"

function Test-GameDir([string]$Dir) {
    return ($Dir -ne "") -and (Test-Path -LiteralPath (Join-Path $Dir $GameExeName))
}

# Steam install folders, from the registry and libraryfolders.vdf.
function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $steamPaths = @()
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($item.SteamPath) { $steamPaths += $item.SteamPath }
            if ($item.InstallPath) { $steamPaths += $item.InstallPath }
        } catch {}
    }
    $steamPaths += "C:\Program Files (x86)\Steam"
    foreach ($steam in $steamPaths) {
        $steam = $steam -replace "/", "\"
        [void]$libs.Add($steam)
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace "\\\\", "\"
                [void]$libs.Add($lib)
            }
        }
    }
    return $libs
}

# Folder that holds "Buckshot Roulette.exe": the argument if given, else found through Steam, else asked.
function Resolve-GameDir([string]$Given) {
    if ($Given -ne "") {
        $Given = $Given.Trim('"').TrimEnd("\")
        if (Test-GameDir $Given) { return $Given }
        if (Test-GameDir (Join-Path $Given "Buckshot Roulette_windows")) { return (Join-Path $Given "Buckshot Roulette_windows") }
        throw "Impossible de trouver '$GameExeName' dans : $Given"
    }
    foreach ($lib in Get-SteamLibraries) {
        foreach ($sub in @("steamapps\common\Buckshot Roulette\Buckshot Roulette_windows", "steamapps\common\Buckshot Roulette")) {
            $dir = Join-Path $lib $sub
            if (Test-GameDir $dir) { return $dir }
        }
    }
    Write-Host "Je n'ai pas trouve le jeu automatiquement."
    $answer = Read-Host "Collez le chemin du dossier qui contient '$GameExeName'"
    return (Resolve-GameDir $answer)
}

function Read-CfgLines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @([System.IO.File]::ReadAllText($Path) -split "`r?`n")
}

# Godot reads override.cfg as UTF-8; write it without a BOM.
function Write-CfgLines([string]$Path, $Lines) {
    $text = (($Lines -join "`n").TrimEnd() + "`n")
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Test-GameRunning {
    return $null -ne (Get-Process -Name "Buckshot Roulette" -ErrorAction SilentlyContinue)
}
