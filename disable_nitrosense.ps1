#Requires -Version 5.1
<#
.SYNOPSIS
    Desactive (ou reactive) NitroSense sur Acer Nitro AN16S-61. Reversible, sans suppression.
.DESCRIPTION
    Ce script cible UNIQUEMENT NitroSense (services + processus + tache planifiee de lancement),
    pour laisser la place a acer_nitro_app.py qui le remplace. Il ne touche a RIEN d'autre :
    ni au NPU (IpuMcdmDriver), ni a l'EC (PredatorService/inpoutx64), ni au WMI (AcerServiceSvc).
    Tout est REVERSIBLE : -Enable remet NitroSense en Manual + relance possible. Aucune desinstallation.
.PARAMETER Disable   Stoppe + met en Manual->Disabled les services NitroSense, tue le process, desactive la tache.
.PARAMETER Enable    Remet les services NitroSense en Manual et reactive la tache (etat par defaut Windows).
.PARAMETER Status    Affiche l'etat actuel (par defaut si aucun parametre).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File disable_nitrosense.ps1 -Status
    powershell -ExecutionPolicy Bypass -File disable_nitrosense.ps1 -Disable
    powershell -ExecutionPolicy Bypass -File disable_nitrosense.ps1 -Enable
#>
param(
    [switch]$Disable,
    [switch]$Enable,
    [switch]$Status
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Cibles NitroSense uniquement ------------------------------------------------
$NS_SERVICES  = @('NitroSense', 'NitroSenseService', 'NitroSenseV2')
$NS_PROCESSES = @('NitroSense', 'NitroSenseService', 'NSDaemon', 'AcerNitroSense')
$NS_TASKS     = @('\NitroSenseLauncher', '\QuickPanelLauncher')

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Split-TaskPath([string]$Combined) {
    $i = $Combined.LastIndexOf('\')
    if ($i -le 0) { return @{ Path = '\'; Name = $Combined.TrimStart('\') } }
    @{ Path = $Combined.Substring(0, $i + 1); Name = $Combined.Substring($i + 1) }
}

# --- STATUS ----------------------------------------------------------------------
function Show-Status {
    Write-Host "==== Etat NitroSense ====" -ForegroundColor Cyan
    foreach ($n in $NS_SERVICES) {
        $s = Get-Service -Name $n -EA SilentlyContinue
        if ($s) {
            $col = if ($s.Status -eq 'Running') { 'Yellow' } else { 'Green' }
            Write-Host ("  Service {0,-20} State={1,-8} Start={2}" -f $n, $s.Status, $s.StartType) -ForegroundColor $col
        }
    }
    foreach ($p in ($NS_PROCESSES | Select-Object -Unique)) {
        $proc = Get-Process -Name $p -EA SilentlyContinue
        if ($proc) { Write-Host ("  Process {0,-20} PID={1} (en cours)" -f $p, ($proc.Id -join ',')) -ForegroundColor Yellow }
    }
    foreach ($t in $NS_TASKS) {
        $sp = Split-TaskPath $t
        $task = Get-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue
        if ($task) { Write-Host ("  Tache   {0,-20} State={1}" -f $t, $task.State) -ForegroundColor Cyan }
    }
}

if ($Status -or (-not $Disable -and -not $Enable)) { Show-Status; if (-not $Disable -and -not $Enable) { exit 0 } }

if (($Disable -or $Enable) -and -not (Test-Admin)) {
    Write-Host "[!] Admin requis. Relance dans une console 'Executer en administrateur'." -ForegroundColor Red
    exit 1
}

# --- DISABLE ---------------------------------------------------------------------
if ($Disable) {
    Write-Host "`n==== Desactivation de NitroSense ====" -ForegroundColor Cyan
    foreach ($n in $NS_SERVICES) {
        $s = Get-Service -Name $n -EA SilentlyContinue
        if (-not $s) { continue }
        Stop-Service -Name $n -Force -EA SilentlyContinue
        Set-Service  -Name $n -StartupType Disabled -EA SilentlyContinue
        Write-Host "  [x] service $n -> stoppe + Disabled" -ForegroundColor Green
    }
    foreach ($p in ($NS_PROCESSES | Select-Object -Unique)) {
        $proc = Get-Process -Name $p -EA SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -EA SilentlyContinue; Write-Host "  [x] process $p -> tue" -ForegroundColor Green }
    }
    foreach ($t in $NS_TASKS) {
        $sp = Split-TaskPath $t
        if (Get-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue) {
            Disable-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue | Out-Null
            Write-Host "  [x] tache $t -> desactivee" -ForegroundColor Green
        }
    }
    Write-Host "`n[OK] NitroSense desactive. Lance acer_nitro_app.py a la place." -ForegroundColor Green
    Write-Host "     Reactiver : .\disable_nitrosense.ps1 -Enable" -ForegroundColor DarkGray
    exit 0
}

# --- ENABLE ----------------------------------------------------------------------
if ($Enable) {
    Write-Host "`n==== Reactivation de NitroSense ====" -ForegroundColor Cyan
    foreach ($n in $NS_SERVICES) {
        $s = Get-Service -Name $n -EA SilentlyContinue
        if (-not $s) { continue }
        Set-Service -Name $n -StartupType Manual -EA SilentlyContinue
        Write-Host "  [+] service $n -> Manual (demarrage a la demande)" -ForegroundColor Green
    }
    foreach ($t in $NS_TASKS) {
        $sp = Split-TaskPath $t
        if (Get-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue) {
            Enable-ScheduledTask -TaskName $sp.Name -TaskPath $sp.Path -EA SilentlyContinue | Out-Null
            Write-Host "  [+] tache $t -> reactivee" -ForegroundColor Green
        }
    }
    Write-Host "`n[OK] NitroSense reactive (redemarre pour qu'il se relance, ou lance-le manuellement)." -ForegroundColor Green
    exit 0
}
