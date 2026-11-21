param(
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"

function Resolve-SlenderGameDir {
    param([string]$ExplicitDir)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitDir)) {
        $exe = Join-Path $ExplicitDir "SlenderTheArrival\Binaries\Win64\SlenderTheArrival-Win64-Shipping.exe"
        if (-not (Test-Path $exe)) {
            throw "Game executable not found at: $exe`nPlease pass a valid -GameDir containing SlenderTheArrival\Binaries\Win64\SlenderTheArrival-Win64-Shipping.exe"
        }
        return (Resolve-Path $ExplicitDir).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add("D:\Games\Slender The Arrival")
    $candidates.Add("C:\Games\Slender The Arrival")

    # Check Steam registry + libraryfolders.vdf
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($regPath in @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )) {
        if (Test-Path $regPath) {
            try {
                $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
                foreach ($propName in @("SteamPath", "InstallPath")) {
                    $val = $props.$propName
                    if (-not [string]::IsNullOrWhiteSpace($val)) {
                        $norm = $val -replace "/", "\"
                        if (-not $steamRoots.Contains($norm)) { $steamRoots.Add($norm) }
                    }
                }
            } catch {}
        }
    }
    $steamRoots.Add("${env:ProgramFiles(x86)}\Steam")
    $steamRoots.Add("${env:ProgramFiles}\Steam")

    foreach ($sr in $steamRoots) {
        if ([string]::IsNullOrWhiteSpace($sr)) { continue }
        $candidates.Add((Join-Path $sr "steamapps\common\Slender The Arrival"))
        $candidates.Add((Join-Path $sr "steamapps\common\SlenderTheArrival"))
        $vdf = Join-Path $sr "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            try {
                $raw = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
                foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                    $lib = $m.Groups[1].Value -replace "\\\\", "\"
                    $candidates.Add((Join-Path $lib "steamapps\common\Slender The Arrival"))
                    $candidates.Add((Join-Path $lib "steamapps\common\SlenderTheArrival"))
                }
            } catch {}
        }
    }

    # Check Epic Games LauncherInstalled.dat and common folders
    $epicDat = Join-Path $env:ProgramData "Epic\UnrealEngineLauncher\LauncherInstalled.dat"
    if (Test-Path $epicDat) {
        try {
            $json = Get-Content $epicDat -Raw | ConvertFrom-Json
            foreach ($app in ($json.InstallationList | Where-Object { $_.InstallLocation -match "Slender" -or $_.AppName -match "Slender" })) {
                if ($app.InstallLocation) { $candidates.Add($app.InstallLocation) }
            }
        } catch {}
    }
    foreach ($drive in @("C:", "D:", "E:", "F:")) {
        $candidates.Add("$drive\SteamLibrary\steamapps\common\Slender The Arrival")
        $candidates.Add("$drive\Program Files\Epic Games\SlenderTheArrival")
        $candidates.Add("$drive\Program Files\Epic Games\Slender The Arrival")
        $candidates.Add("$drive\Epic Games\SlenderTheArrival")
        $candidates.Add("$drive\Epic Games\Slender The Arrival")
        $candidates.Add("$drive\Games\SlenderTheArrival")
    }

    foreach ($cand in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($cand)) { continue }
        $exe = Join-Path $cand "SlenderTheArrival\Binaries\Win64\SlenderTheArrival-Win64-Shipping.exe"
        if (Test-Path $exe) {
            return (Resolve-Path $cand).Path
        }
    }

    throw "Could not auto-detect Slender: The Arrival installation directory.`nRun again with -GameDir `"C:\Path\To\Slender The Arrival`""
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Workspace  = Split-Path -Parent $ScriptRoot
$TargetGame = Resolve-SlenderGameDir -ExplicitDir $GameDir
$BinDir     = Join-Path $TargetGame "SlenderTheArrival\Binaries\Win64"
$Ue4ssZip   = Join-Path $Workspace "tools\UE4SS_v4.0.0.zip"
$Ue4ssDir   = Join-Path $BinDir "ue4ss"
$ModsDir    = Join-Path $Ue4ssDir "Mods"
$SrcModDir  = Join-Path $Workspace "mod\PlayAsSlender"
$TplIni     = Join-Path $Workspace "installer\templates\UE4SS-settings.ini"
$TplMods    = Join-Path $Workspace "installer\templates\mods.txt"

if (-not (Test-Path $SrcModDir)) {
    throw "Mod payload missing at: $SrcModDir"
}

Get-Process -Name "SlenderTheArrival-Win64-Shipping" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

if (-not (Test-Path (Join-Path $BinDir "dwmapi.dll")) -or -not (Test-Path (Join-Path $Ue4ssDir "UE4SS.dll"))) {
    if (-not (Test-Path $Ue4ssZip)) {
        throw "UE4SS archive missing at: $Ue4ssZip"
    }
    Write-Host "[Install] Extracting UE4SS v4.0.0 into $BinDir ..."
    Expand-Archive -Path $Ue4ssZip -DestinationPath $BinDir -Force
} else {
    Write-Host "[Install] UE4SS runtime already present in $BinDir"
}

New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null

if (Test-Path $TplIni) {
    Copy-Item $TplIni (Join-Path $Ue4ssDir "UE4SS-settings.ini") -Force
}
if (Test-Path $TplMods) {
    Copy-Item $TplMods (Join-Path $ModsDir "mods.txt") -Force
}

$DstModDir = Join-Path $ModsDir "PlayAsSlender"
if (Test-Path $DstModDir) {
    Remove-Item $DstModDir -Recurse -Force
}
Copy-Item $SrcModDir $DstModDir -Recurse -Force

Write-Host ""
Write-Host "PlayAsSlender Mod installed cleanly (original .exe and .pak/.ucas/.utoc files untouched):" -ForegroundColor Green
Write-Host "  Target Game : $TargetGame"
Write-Host "  UE4SS Proxy : $(Join-Path $BinDir 'dwmapi.dll')"
Write-Host "  Mod Scripts : $DstModDir"
Write-Host "  Keybinds    : $(Join-Path $DstModDir 'keybinds.ini')"
