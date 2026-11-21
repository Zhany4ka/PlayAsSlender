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
                        $candidates.Add((Join-Path $norm "steamapps\common\Slender The Arrival"))
                        $vdf = Join-Path $norm "steamapps\libraryfolders.vdf"
                        if (Test-Path $vdf) {
                            $raw = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
                            foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                                $lib = $m.Groups[1].Value -replace "\\\\", "\"
                                $candidates.Add((Join-Path $lib "steamapps\common\Slender The Arrival"))
                            }
                        }
                    }
                }
            } catch {}
        }
    }

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

$TargetGame = Resolve-SlenderGameDir -ExplicitDir $GameDir
$BinDir     = Join-Path $TargetGame "SlenderTheArrival\Binaries\Win64"
$ProxyDll   = Join-Path $BinDir "dwmapi.dll"
$Ue4ssDir   = Join-Path $BinDir "ue4ss"

Get-Process -Name "SlenderTheArrival-Win64-Shipping" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

if (Test-Path $ProxyDll) {
    Remove-Item $ProxyDll -Force
    Write-Host "[Uninstall] Removed $ProxyDll"
}
if (Test-Path $Ue4ssDir) {
    Remove-Item $Ue4ssDir -Recurse -Force
    Write-Host "[Uninstall] Removed $Ue4ssDir"
}

Write-Host ""
Write-Host "PlayAsSlender Mod and UE4SS completely removed from: $TargetGame" -ForegroundColor Green
Write-Host "Game files (.exe, .pak, .ucas, .utoc) remain untouched."
