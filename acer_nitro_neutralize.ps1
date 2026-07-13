#Requires -Version 5.1
<#
.SYNOPSIS
    Neutralise le bloat Acer / Nitro / Predator de facon KERNEL-SAFE et 100% reversible.

.DESCRIPTION
    Script consolide (fusion des 4 scripts precedents : kill_all_v2 = base kernel-safe,
    + taches planifiees reversibles issues de acer_nitro_control.ps1).

    Ce qu'il FAIT :
      - Desactive + stoppe UNIQUEMENT les services "SAFE" (telemetrie / agents / NitroSense
        / lighting), apres avoir sauvegarde leur etat exact dans un JSON.
      - Optionnel (-IncludeTasks) : desactive les taches planifiees Acer/UEIP
        (Disable-ScheduledTask = totalement reversible, aucune suppression).
      - Restaure tout depuis le JSON avec -Restore (StartupType + demarrage si le service
        tournait avant, re-Enable des taches qui etaient actives).

    Ce qu'il NE FAIT JAMAIS (securite / croisement CORTEX.md, service_audit, ANNEXES) :
      - Ne touche JAMAIS un service de type KERNEL_DRIVER (detecte via
        Win32_Service.ServiceType) => IpuMcdmDriver (NPU XDNA2), ipustack, inpoutx64,
        WinRing0 sont proteges PAR CONSTRUCTION, pas par une liste codee en dur.
      - Protege en plus une liste KEEP explicite (NPU / EC / WMI / RAPL).
      - Aucune suppression / desinstallation / prise de possession NTFS / IFEO / firewall.
        (Ces actions agressives des anciens scripts block_nitro.ps1 / control.ps1 ont ete
         volontairement ecartees : trop invasives, moins proprement reversibles.)

    Faits croises :
      - service_audit + CORTEX 4.1 : les 15 services Acer sont LocalSystem user-mode, "sains".
      - ANNEXES : 7 serveurs HTTP/WS locaux de telemetrie (AcerAgentService:46933,
        AcerSysMonitorService:46753, etc.) -> agents coupes par la liste SAFE.
      - AcerGamingFunction WMI = "Invalid method parameters" sur Strix -> l'EC de l'app
        passe par inpoutx64 direct, aucun service user requis pour ventilo/EC.
      - AcerLightingService entre en conflit avec le RGB HID -> bon a couper.
      - IpuMcdmDriver (KERNEL_DRIVER, RUNNING) = NPU -> exclu automatiquement (type).

.PARAMETER DryRun
    Aperçu : affiche ce qui serait fait, ne change rien.
.PARAMETER Apply
    Applique : desactive + stoppe les services SAFE, sauvegarde l'etat.
.PARAMETER Restore
    Restaure les services (et taches) depuis l'etat sauvegarde.
.PARAMETER IncludeTasks
    Inclut les taches planifiees Acer/UEIP (avec -DryRun / -Apply / -Restore).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File acer_nitro_neutralize.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File acer_nitro_neutralize.ps1 -Apply
    powershell -ExecutionPolicy Bypass -File acer_nitro_neutralize.ps1 -Apply -IncludeTasks
    powershell -ExecutionPolicy Bypass -File acer_nitro_neutralize.ps1 -Restore
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$Restore,
    [switch]$IncludeTasks
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$StateFile = Join-Path $PSScriptRoot 'acer_nitro_neutralize_state.json'

# --- Bloat SUR a desactiver (telemetrie / agents / NitroSense / lighting) --------
# Croise service_audit.md (tous "sains") + ANNEXES (serveurs HTTP/WS de telemetrie).
$SAFE = @(
    'AASSvc','AcerCCAgentSvis','AcerDIAgentSvis','AcerQAAgentSvis','UEIPSvc',
    'AcerEZSvc','AcerORDService','AcerPixyService','AcerGAICameraService',
    'AcerARTAIMMXService','AcerARTAIMMXDriverService','AcerDeviceEnablingServiceV2',
    'ASMSvc','AcerAgentService','AcerStartupService','AATService','QuickAccessService',
    'AcerLightingService',                              # conflit RGB HID -> couper
    'NitroSense','NitroSenseService','NitroSenseV2'     # re-applique le throttle -> couper
)

# --- A NE JAMAIS toucher (raison) -----------------------------------------------
# Filet supplementaire par-dessus le skip automatique des KERNEL_DRIVER.
$KEEP = [ordered]@{
    'IpuMcdmDriver'  = 'Pilote NPU XDNA2 (KERNEL) - l arreter = NPU/FLM mort'
    'PatchIpustack'  = 'Stack/shim NPU'
    'PredatorService'= 'Fournit inpoutx64 (acces EC de l app)'
    'AcerServiceSvc' = 'Peut soutenir le mapper WMI / HW'
    'WinRing0_1_2_0' = 'RAPL/MSR (app)'
    'WinRing0'       = 'RAPL/MSR (app)'
    'ipustack'       = 'Driver noyau NPU'
    'inpoutx64'      = 'Driver noyau EC'
}

# --- Taches planifiees Acer/UEIP (optionnelles, Disable = reversible) ------------
$TASKS = @(
    '\NitroSenseLauncher'
    '\QuickPanelLauncher'
    '\Oem\AcerJumpstartTask'
    '\Oem\wlanBrokerTask'
    '\UEIPInvitation'
    '\UbtFrameworkService'
)

# ------------------------------------------------------------------ helpers ------
function Get-Svc([string]$n) { Get-CimInstance Win32_Service -Filter "Name='$n'" -EA SilentlyContinue }

function Split-TaskPath([string]$Combined) {
    $i = $Combined.LastIndexOf('\')
    if ($i -le 0) { return @{ Path = '\'; Name = $Combined.TrimStart('\') } }
    return @{ Path = $Combined.Substring(0, $i + 1); Name = $Combined.Substring($i + 1) }
}
function Get-AcerTask([string]$Combined) {
    $p = Split-TaskPath $Combined
    Get-ScheduledTask -TaskName $p.Name -TaskPath $p.Path -EA SilentlyContinue
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ------------------------------------------------------------------ usage --------
if (-not ($DryRun -or $Apply -or $Restore)) {
    Write-Host "Usage : -DryRun | -Apply | -Restore  [-IncludeTasks]" -ForegroundColor Yellow
    Write-Host "  -DryRun        : apercu (rien ne change)"
    Write-Host "  -Apply         : desactive+stoppe le bloat (sauvegarde l'etat)"
    Write-Host "  -Restore       : reactive depuis la sauvegarde"
    Write-Host "  -IncludeTasks  : traite aussi les taches planifiees Acer/UEIP"
    exit 0
}

# Auto-elevation pour Apply / Restore
if (($Apply -or $Restore) -and -not (Test-Admin)) {
    if ($PSCommandPath) {
        Write-Host "[!] Admin requis - relance en administrateur..." -ForegroundColor Yellow
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
        if ($Apply)        { $argList += '-Apply' }
        if ($Restore)      { $argList += '-Restore' }
        if ($DryRun)       { $argList += '-DryRun' }
        if ($IncludeTasks) { $argList += '-IncludeTasks' }
        try {
            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs | Out-Null
            Write-Host "    Acceptez l'UAC dans la nouvelle fenetre." -ForegroundColor Cyan
        } catch {
            Write-Host "[x] Elevation refusee. Relance en admin : $PSCommandPath" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Admin requis pour -Apply/-Restore. Relance en administrateur." -ForegroundColor Red
    }
    exit 1
}

# ============================================================ RESTORE ============
if ($Restore) {
    if (-not (Test-Path $StateFile)) {
        Write-Host "[x] Aucun etat sauvegarde ($StateFile)." -ForegroundColor Red; exit 1
    }
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $nSvc = 0; $nTask = 0

    Write-Host "==== Restauration bloat Acer ($([DateTime]::Now)) ====" -ForegroundColor Cyan

    if ($state.Services) {
        foreach ($p in $state.Services.PSObject.Properties) {
            $svc = Get-Service -Name $p.Name -EA SilentlyContinue
            if (-not $svc) { continue }
            $startType = $p.Value.StartType
            if (-not $startType -or $startType -eq 'Disabled') { $startType = 'Manual' }
            Set-Service -Name $p.Name -StartupType $startType -EA SilentlyContinue
            if ($p.Value.Status -eq 'Running') {
                Start-Service -Name $p.Name -EA SilentlyContinue
                Write-Host "  [restore] $($p.Name) -> $startType + start" -ForegroundColor Green
            } else {
                Write-Host "  [restore] $($p.Name) -> $startType" -ForegroundColor Green
            }
            $nSvc++
        }
    }

    if ($state.Tasks) {
        foreach ($p in $state.Tasks.PSObject.Properties) {
            $t = Get-AcerTask $p.Name
            if (-not $t) { continue }
            if ($p.Value.State -eq 'Ready' -or $p.Value.State -eq 'Running') {
                $sp = Split-TaskPath $p.Name
                Enable-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue | Out-Null
                Write-Host "  [restore-task] $($p.Name) -> Enabled" -ForegroundColor Green
                $nTask++
            }
        }
    }

    Write-Host "`n[OK] $nSvc service(s) et $nTask tache(s) reactive(s)." -ForegroundColor Green
    exit 0
}

# ======================================================= DRY-RUN / APPLY ========
Write-Host "==== Neutralisation bloat Acer ($([DateTime]::Now)) ====" -ForegroundColor Cyan
$modeStr = if ($Apply) { 'APPLY' } else { 'DRY-RUN' }
if ($IncludeTasks) { $modeStr = "$modeStr + TACHES" }
Write-Host "Mode : $modeStr`n"

$prevServices = @{}
$prevTasks    = @{}
$acted = 0; $skippedKernel = 0; $skippedKeep = 0

# ---- Services ----
foreach ($name in ($SAFE | Sort-Object -Unique)) {
    if ($KEEP.Contains($name)) { $skippedKeep++; continue }   # ne devrait pas arriver, ceinture
    $svc = Get-Svc $name
    if (-not $svc) { continue }                               # absent -> ignore
    if ($svc.ServiceType -match 'Kernel') {                   # SECURITE : jamais un driver noyau
        Write-Host "  [SKIP driver] $name (KERNEL_DRIVER)" -ForegroundColor DarkYellow
        $skippedKernel++; continue
    }
    $s   = Get-Service -Name $name -EA SilentlyContinue
    $cur = if ($s) { $s.StartType.ToString() } else { 'Manual' }
    $st  = if ($s) { $s.Status.ToString() }    else { 'Unknown' }
    $verb = if ($Apply) { 'KILL ' } else { 'would' }
    Write-Host ("  [{0}] {1,-30} etat={2,-8} start={3}" -f $verb, $name, $svc.State, $cur) -ForegroundColor Yellow
    if ($Apply) {
        $prevServices[$name] = @{ StartType = $cur; Status = $st }
        Stop-Service -Name $name -Force -EA SilentlyContinue
        Set-Service  -Name $name -StartupType Disabled -EA SilentlyContinue
        $acted++
    }
}

# ---- Taches planifiees (optionnel) ----
$taskActed = 0
if ($IncludeTasks) {
    Write-Host "`n  Taches planifiees Acer/UEIP :" -ForegroundColor Cyan
    foreach ($tn in $TASKS) {
        $t = Get-AcerTask $tn
        if (-not $t) { continue }
        $tverb = if ($Apply) { 'DISBL' } else { 'would' }
        Write-Host ("  [{0}] {1,-32} state={2}" -f $tverb, $tn, $t.State) -ForegroundColor Yellow
        if ($Apply) {
            $prevTasks[$tn] = @{ State = $t.State.ToString() }
            $sp = Split-TaskPath $tn
            Disable-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue | Out-Null
            $taskActed++
        }
    }
}

# ---- Info : ce qui est protege ----
Write-Host "`n  Protege (jamais touche) :" -ForegroundColor Cyan
foreach ($k in $KEEP.Keys) {
    $svc = Get-Svc $k
    if ($svc) { Write-Host ("    - {0,-16} {1}" -f $k, $KEEP[$k]) -ForegroundColor DarkCyan }
}

# ---- Sauvegarde + bilan ----
if ($Apply) {
    $out = [ordered]@{
        SavedAt  = (Get-Date).ToString('s')
        Services = $prevServices
        Tasks    = $prevTasks
    }
    $out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StateFile -Encoding UTF8
    Write-Host "`n[OK] $acted service(s) + $taskActed tache(s) neutralise(s), $skippedKernel driver(s) noyau protege(s)." -ForegroundColor Green
    Write-Host "     Etat sauvegarde : $StateFile"
    Write-Host "     Annuler : .\acer_nitro_neutralize.ps1 -Restore"
} else {
    Write-Host "`n[i] DRY-RUN - rien n'a change. Pour appliquer : -Apply" -ForegroundColor Cyan
}

Write-Host "`n[note] Si le ventilo/EC de l'app casse ensuite, PredatorService est protege" -ForegroundColor DarkGray
Write-Host "       (inpoutx64) ; tu peux le relancer : Start-Service PredatorService" -ForegroundColor DarkGray
