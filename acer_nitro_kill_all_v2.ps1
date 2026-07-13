#Requires -Version 5.1
<#
.SYNOPSIS
    Neutralise le bloat Acer/Nitro — v2 (croisé avec CORTEX.md / service_audit.md).
.DESCRIPTION
    v2 vs v1 :
      - Ne touche JAMAIS un service de type KERNEL_DRIVER (protège IpuMcdmDriver=NPU,
        ipustack, inpoutx64, WinRing0 par construction, pas par liste codée en dur).
      - Liste KEEP explicite (NPU/EC/WMI) + liste SAFE (télémétrie/agents/NitroSense).
      - Réversible : sauvegarde l'état (StartupType) avant, restaure depuis le JSON.
      - 3 modes : -DryRun (aperçu), -Apply (désactive+stoppe), -Restore.
    Faits croisés :
      - AcerGamingFunction WMI = "Invalid method parameters" sur Strix -> l'EC de l'app
        passe par inpoutx64 direct, aucun service user requis.
      - AcerLightingService entre en conflit avec le RGB HID -> bon a couper.
      - IpuMcdmDriver (KERNEL_DRIVER, RUNNING) = NPU -> exclu (auto via type).
.PARAMETER DryRun   Affiche ce qui serait fait, ne change rien.
.PARAMETER Apply    Désactive + stoppe les services SAFE, sauvegarde l'état.
.PARAMETER Restore  Réactive les services depuis l'état sauvegardé.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File acer_nitro_kill_all_v2.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File acer_nitro_kill_all_v2.ps1 -Apply
    powershell -ExecutionPolicy Bypass -File acer_nitro_kill_all_v2.ps1 -Restore
#>
param(
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$Restore
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$StateFile = Join-Path $PSScriptRoot 'acer_bloat_state_v2.json'

# ── Bloat SÛR à désactiver (télémétrie / agents / NitroSense / lighting) ────────
# Croisé service_audit.md (tous "sains") + ANNEXES (serveurs HTTP télémétrie).
$SAFE = @(
    'AASSvc','AcerCCAgentSvis','AcerDIAgentSvis','AcerQAAgentSvis','UEIPSvc',
    'AcerEZSvc','AcerORDService','AcerPixyService','AcerGAICameraService',
    'AcerARTAIMMXService','AcerARTAIMMXDriverService','AcerDeviceEnablingServiceV2',
    'ASMSvc','AcerAgentService','AcerStartupService','AATService','QuickAccessService',
    'AcerLightingService',            # conflit RGB HID -> couper
    'NitroSense','NitroSenseService','NitroSenseV2'   # re-applique le throttle -> couper
)

# ── À NE JAMAIS toucher (raison) ────────────────────────────────────────────────
$KEEP = @{
    'IpuMcdmDriver'  = 'Pilote NPU XDNA2 (KERNEL) — l arreter = FLM mort'
    'PatchIpustack'  = 'Stack NPU (SHIM)'
    'PredatorService'= 'Fournit inpoutx64 (acces EC de l app)'
    'AcerServiceSvc' = 'Peut soutenir le mapper WMI / HW'
    'WinRing0_1_2_0' = 'RAPL/MSR (app)'
}

function Get-Svc($n){ Get-CimInstance Win32_Service -Filter "Name='$n'" }

if (-not ($DryRun -or $Apply -or $Restore)) {
    Write-Host "Usage : -DryRun | -Apply | -Restore" -ForegroundColor Yellow
    Write-Host "  -DryRun  : apercu (rien change)"
    Write-Host "  -Apply   : desactive+stoppe le bloat (sauvegarde l etat)"
    Write-Host "  -Restore : reactive depuis la sauvegarde"
    exit 0
}

$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (($Apply -or $Restore) -and -not $admin) {
    Write-Host "[!] Admin requis pour -Apply/-Restore. Relance en administrateur." -ForegroundColor Red
    exit 1
}

# ── RESTORE ─────────────────────────────────────────────────────────────────────
if ($Restore) {
    if (-not (Test-Path $StateFile)) { Write-Host "[x] Aucun etat sauvegarde ($StateFile)."; exit 1 }
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $n = 0
    foreach ($p in $state.PSObject.Properties) {
        $svc = Get-Service -Name $p.Name -EA SilentlyContinue
        if (-not $svc) { continue }
        $st = $p.Value; if ($st -eq 'Disabled') { $st = 'Manual' }
        Set-Service -Name $p.Name -StartupType $st -EA SilentlyContinue
        Start-Service -Name $p.Name -EA SilentlyContinue
        Write-Host "  [restore] $($p.Name) -> $st" -ForegroundColor Green
        $n++
    }
    Write-Host "`n[OK] $n service(s) reactive(s)."
    exit 0
}

# ── DRYRUN / APPLY ──────────────────────────────────────────────────────────────
Write-Host "==== Neutralisation bloat Acer v2 ($([DateTime]::Now)) ====" -ForegroundColor Cyan
Write-Host ("Mode : {0}`n" -f ($(if($Apply){'APPLY'}else{'DRY-RUN'})))

$prev = @{}
$acted = 0; $skippedKernel = 0
foreach ($name in ($SAFE | Sort-Object -Unique)) {
    $svc = Get-Svc $name
    if (-not $svc) { continue }                         # absent -> ignore
    if ($svc.ServiceType -match 'Kernel') {             # SECURITE : jamais un driver noyau
        Write-Host "  [SKIP driver] $name (KERNEL_DRIVER)" -ForegroundColor DarkYellow
        $skippedKernel++; continue
    }
    $s = Get-Service -Name $name -EA SilentlyContinue
    $cur = if ($s) { $s.StartType.ToString() } else { 'Manual' }
    Write-Host ("  [{0}] {1,-28} etat={2} start={3}" -f `
        ($(if($Apply){'KILL'}else{'would'})), $name, $svc.State, $cur) -ForegroundColor Yellow
    if ($Apply) {
        $prev[$name] = $cur
        Stop-Service  -Name $name -Force -EA SilentlyContinue
        Set-Service   -Name $name -StartupType Disabled -EA SilentlyContinue
        $acted++
    }
}

# Info : ce qui est protege
Write-Host "`n  Protege (jamais touche) :" -ForegroundColor Cyan
foreach ($k in $KEEP.Keys) {
    $svc = Get-Svc $k
    if ($svc) { Write-Host ("    - {0,-16} {1}" -f $k, $KEEP[$k]) -ForegroundColor DarkCyan }
}

if ($Apply) {
    $prev | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
    Write-Host "`n[OK] $acted service(s) neutralise(s), $skippedKernel driver(s) protege(s)." -ForegroundColor Green
    Write-Host "     Etat sauvegarde : $StateFile"
    Write-Host "     Annuler : .\acer_nitro_kill_all_v2.ps1 -Restore"
} else {
    Write-Host "`n[i] DRY-RUN — rien change. Pour appliquer : -Apply" -ForegroundColor Cyan
}
Write-Host "`n[note] Si l EC/ventilo de l app casse ensuite, PredatorService est protege," -ForegroundColor DarkGray
Write-Host "       mais tu peux le relancer : Start-Service PredatorService" -ForegroundColor DarkGray
