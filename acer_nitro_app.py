# -*- coding: utf-8 -*-
"""
Acer Nitro AN16S-61 — Control Center v2
========================================
Contrôle RGB, ventilateurs, profils de performance, monitoring système et NPU.

Usage:
  python acer_nitro_app.py            # App complète
  python acer_nitro_app.py --widget   # Widget compact flottant seul
"""

from __future__ import annotations
import tkinter as tk
from tkinter import colorchooser
import threading, time, subprocess, sys, os, ctypes, re, json
import traceback, collections
import logging
from logging.handlers import RotatingFileHandler

# AMELIORATION : icone barre systeme -- dependance OPTIONNELLE (pystray + Pillow).
# Le lanceur .bat n'installe rien automatiquement -- si absente, la fonctionnalite
# se desactive proprement (bouton "Reduire" affiche un message d'installation) au
# lieu de faire planter l'app.
try:
    import pystray
    from PIL import Image, ImageDraw
    HAS_TRAY = True
except ImportError:
    HAS_TRAY = False

# ═══════════════════════════════════════════════════════════════════════════════
#  CONSTANTES
# ═══════════════════════════════════════════════════════════════════════════════

def _find_inpout() -> str:
    _cands = [
        r"C:\Windows\System32\DriverStore\FileRepository\predatorservice.inf_amd64_c634eb8e856fb962\inpoutx64.dll",
        r"C:\Windows\System32\inpoutx64.dll",
        r"C:\Program Files\Acer\PredatorService\inpoutx64.dll",
    ]
    for p in _cands:
        if os.path.isfile(p): return p
    _base = r"C:\Windows\System32\DriverStore\FileRepository"
    if os.path.isdir(_base):
        for _d in os.listdir(_base):
            if _d.startswith("predatorservice"):
                _c = os.path.join(_base, _d, "inpoutx64.dll")
                if os.path.isfile(_c): return _c
    return ""
INPOUT = _find_inpout()

HID_GUID = "{4d1e55b2-f16f-11cf-88cb-001111000030}"

def _find_hid_path(hw_id: str) -> str:
    """Resolve HID device path dynamically via PowerShell (sans admin)."""
    ps = (
        "$d=Get-PnpDevice -InstanceId '*" + hw_id + "*' -ErrorAction SilentlyContinue "
        "| Where-Object { $PSItem.DeviceID -match '^HID' -and $PSItem.InstanceId -match '"
        + hw_id + "' } | Select-Object -First 1;"
        "if(-not $d){$d=Get-PnpDevice -InstanceId '*" + hw_id + "*' -ErrorAction SilentlyContinue | Select-Object -First 1;"
        "$hidId=($d.DeviceID -split ' ' | Where-Object{ $PSItem -match '^HID' } | Select-Object -First 1);"
        "if($hidId){$p='\\\\?\\'+($hidId-replace'\\\\','#')+'#" + HID_GUID + "';Write-Output $p}}"
        "else{$p='\\\\?\\'+($d.DeviceID-replace'\\\\','#')+'#" + HID_GUID + "';Write-Output $p}"
    )
    try:
        out = subprocess.check_output(
            ["powershell","-NoProfile","-NonInteractive",
             "-ExecutionPolicy","Bypass","-Command",ps],
            stderr=subprocess.DEVNULL, timeout=5
        ).decode(errors="replace").strip()
        return out.splitlines()[-1] if out else ""
    except Exception:
        return ""

def _find_hid_path_lb() -> str:
    """Resolve lightbar COL01 device path (unique parmi 9 HID cols)."""
    ps = (
        "$d=Get-PnpDevice -InstanceId '*1025174B*' -ErrorAction SilentlyContinue "
        "| Where-Object { $PSItem.InstanceId -match 'COL01' } "
        "| Select-Object -First 1;"
        "if(-not $d){$d=Get-PnpDevice -InstanceId '*1025174B*' -ErrorAction SilentlyContinue | Select-Object -First 1};"
        "if($d){$p='\\\\?\\'+($d.DeviceID-replace'\\\\','#')+'#" + HID_GUID + "';"
        "Write-Output $p}"
    )
    try:
        out = subprocess.check_output(
            ["powershell","-NoProfile","-NonInteractive",
             "-ExecutionPolicy","Bypass","-Command",ps],
            stderr=subprocess.DEVNULL, timeout=5
        ).decode(errors="replace").strip()
        return out.splitlines()[-1] if out else ""
    except Exception:
        return ""

# Amelioration : les deux lookups PowerShell (clavier RGB + lightbar) sont
# independants -> on les lance en parallele au lieu de sequentiel, pour ne
# pas cumuler leurs latences (jusqu'a ~5s chacun) au demarrage de l'app.
def _find_hid_paths_parallel() -> tuple[str, str]:
    import concurrent.futures as _cf
    try:
        with _cf.ThreadPoolExecutor(max_workers=2) as ex:
            f_kb = ex.submit(_find_hid_path, "ENEK5130")
            f_lb = ex.submit(_find_hid_path_lb)
            return f_kb.result(), f_lb.result()
    except Exception:
        # Fallback sequentiel si jamais le pool echoue pour une raison quelconque
        return _find_hid_path("ENEK5130"), _find_hid_path_lb()

HID_KB, HID_LB = _find_hid_paths_parallel()

# CORRECTIF : l'ancien chemin en dur "C:\Windows\System32\AMD\xrt-smi.exe"
# est invalide sur ce systeme -> os.path.isfile() echouait TOUJOURS et l'onglet
# NPU/XRT-SMI restait vide en silence (aucun contexte, TPS=0, etc.).
# Chemin reel confirme (NPU_ARBORESCENCE_FLOWCHART.md / CARTOGRAPHIE_COMPLETE.md) :
# C:\Windows\System32\Runner\xrt-smi.exe -- l'ancien chemin est garde en
# fallback au cas ou une autre machine/version de driver l'installerait ailleurs.
_XRT_SMI_CANDIDATES = [
    r"C:\Windows\System32\Runner\xrt-smi.exe",
    r"C:\Windows\System32\AMD\xrt-smi.exe",
]

def _find_xrt_smi() -> str:
    for _p in _XRT_SMI_CANDIDATES:
        if os.path.isfile(_p):
            return _p
    return _XRT_SMI_CANDIDATES[0]

XRT_SMI = _find_xrt_smi()
CPU_FREQ_MAX_GHZ = 5.0   # Ryzen AI 9 365 (Zen 5) boost max officiel

EC_CPU_TEMP = 0x19
EC_GPU_TEMP = 0x1A
EC_ETP2     = 0x52   
EC_CPUF     = 0x5C
EC_FAN0_HI  = 0xC1   
EC_FAN0_LO  = 0xC0
EC_FAN1_HI  = 0xC3   
EC_FAN1_LO  = 0xC2
EC_FAN_CTRL = 0xCA
EC_PROFILE  = 0x86

PROFILES = {"Eco": 0x0A, "Balanced": 0x0B, "Performance": 0x0E, "Turbo": 0x05}
PROFILE_COLORS = {
    "Eco": "#2ecc71", "Balanced": "#54a0ff",
    "Performance": "#f39c12", "Turbo": "#e74c3c"
}

RGB_EFFECTS = {
    "Static":      0x02,
    "Breathing":   0x04,
    "Neon":        0x05,
    "Wave":        0x03,  # 0x07 eteignait le clavier — essai 0x03
    "Slow Breath": 0x08,
    "Scene 1":     0x09,
    "Scene 2":     0x0A,
    "Scene 3":     0x0B,
}
RGB_ZONES = {"All": 0x0F, "Left": 0x01, "Mid-L": 0x02, "Center": 0x04, "Right": 0x08}

# (name, effect, brightness, R, G, B, zone)
# NOTE couleurs : firmware ENE K5130 — valeurs corrigees 2026-07-01
#   B=0 + R/G>0 -> rouge fixe (firmware bug). Minimum B=5 pour les couleurs chaudes.
#   b=1 + G>0 -> vert matrix (firmware bug secondaire). D'ou minimum B=5.
RGB_PRESETS = [
    ("Blue",   0x02, 160,   0,   0, 255, 0x0F),  # pur bleu    (was 30,120,255 -> cyan)
    ("Red",    0x02, 160, 255,   0,   0, 0x0F),  # inchange    (OK)
    ("Green",  0x02, 160,   0, 255,   0, 0x0F),  # pur vert    (was 0,220,80 -> cyan-violet)
    ("Purple", 0x02, 160, 128,   0, 255, 0x0F),  # violet pur  (was 180,0,255 -> bleu-blanc)
    ("White",  0x02, 120, 255, 255, 255, 0x0F),  # inchange
    ("Cyan",   0x02, 160,   0, 200, 255, 0x0F),  # cyan pur
    ("Orange", 0x02, 160, 255,  60,   5, 0x0F),  # b=5 evite bug b=0 et b=1 (was 255,120,0 -> vert)
    ("Wave",   0x03, 160,   0,   0,   0, 0x0F),  # 0x03 (was 0x07 -> eteignait KB)
    ("Breath", 0x04, 160,   0,   0, 255, 0x0F),  # bleu pur    (was 30,120,255 -> cyan)
    ("OFF",    0x02,   0,   0,   0,   0, 0x0F),  # inchange
]

# Palette UI
C = {
    "bg":      "#0d0d12",
    "bg2":     "#13131c",
    "card":    "#1a1a28",
    "border":  "#282840",
    "accent":  "#5b6bff",
    "accent2": "#00d4aa",
    "cpu":     "#5b8fff",
    "gpu":     "#00d4aa",
    "npu":     "#c06bff",
    "igpu":    "#ffb347",
    "ram":     "#ff9f43",
    "fan":     "#54a0ff",
    "temp_ok": "#00d4aa",
    "temp_mid":"#f39c12",
    "temp_hot":"#e74c3c",
    "text":    "#e8e8f0",
    "text2":   "#6666aa",
    "success": "#2ecc71",
    "warning": "#f39c12",
    "danger":  "#e74c3c",
}
FF = "Segoe UI"
FM = "Consolas"

# [REST OF FILE - too long, showing structure only]
print("Error: File too large to process in single message")
print("Please use: python acer_nitro_app.py")
