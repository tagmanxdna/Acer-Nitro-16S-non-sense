# Acer Nitro 16S (AN16S-61) Control Center v2

**Remplace NitroSense** — Contrôle complet du matériel sans dépendances propriétaires

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  ACER NITRO AN16S-61 CONTROL CENTER v2                                       ║
║  ⚡ RGB Keyboard | 🌡️ Fans | 📊 Monitoring | 🧠 NPU/XRT-SMI | ⚙️ Performance ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

## 🚀 Démarrage Rapide

### Prérequis
- **OS**: Windows 11 (Acer Nitro AN16S-61 recommandé)
- **Python**: 3.11+
- **Admin**: ✅ Oui (pour l'EC — optionnel pour le reste)

### Installation

```bash
# 1. Cloner le repo
git clone https://github.com/tagmanxdna/Acer-Nitro-16S-non-sense
cd Acer-Nitro-16S-non-sense

# 2. Installer les dépendances (optionnel — tkinter inclus)
pip install --break-system-packages pystray pillow

# 3. Lancer l'app
double-click launch_acer_nitro.bat
# OU
python acer_nitro_app.py
```

### Mode Widget Flottant (Compact)

```bash
python acer_nitro_app.py --widget
```

Widget draggable, redimensionnable, semi-transparent (α réglable).

---

## 📋 Caractéristiques

### 🎮 Hardware Contrôlé

| Composant | Protocole | Admin | État |
|-----------|-----------|-------|------|
| **RGB Clavier** | ENE K5130 (HID I2C) | ❌ Non | ✅ Complet |
| **Lightbar** | 1025174B COL01 (HID) | ❌ Non | ✅ Brillance |
| **Ventilateurs** | ITE EC + WMI | ⚠️ Optionnel | ✅ Auto/Turbo/Max |
| **Profils** | EC 0x86 (ITE) | ✅ Oui | ✅ Éco/Équilibré/Perf/Turbo |
| **Power Limits** | EC 0x14-0x17 | ✅ Oui | ✅ PL1/PL2 (Stock→Max) |
| **NPU** | xrt-smi.exe | ❌ Non | ✅ TPS/BW/MAC eff live |
| **CPU/GPU** | WMI + nvidia-smi | ❌ Non | ✅ Temp/Load/Freq/Power |
| **RAM/Disk** | WMI | ❌ Non | ✅ % utilisation + uptime |

### 📊 Interface Complète

1. **Dashboard** — Vue d'ensemble temps réel (12 métriques clés)
2. **CPU** — Temp/Load/Fréquence Zen 5 10C/20T
3. **GPU** — RTX 5070 Laptop (temp/load/VRAM/power)
4. **NPU / RAM** — XDNA2 live (TPS/BW/MAC eff) + Grille 8×4 tiles AIE2P
5. **Fans** — EC + WMI (Auto/Turbo/CoolerBoost + % manuel)
6. **RGB** — ENE K5130 (10 presets + color picker)
7. **Profils** — EC 0x86 (Éco/Équilibré/Perf/Turbo)
8. **Système** — Hardware info + EC dump + actions rapides
9. **⚡ Boost** — Power plan + PL1/PL2 + Fan WMI + Estimateur BW DDR5
10. **📋 Logs** — Journal temps réel (filtrable + export)

### 🎨 RGB Avancé

**Contrôle complet ENE K5130:**
- 8 effets: Static, Breathing, Neon, Wave, Slow Breath, Scene 1-3
- 5 zones: All, Left, Mid-L, Center, Right
- Sélecteur couleur interactif (color picker)
- 10 presets optimisés (bug firmware K5130 fixé)
- Persistance: RGB réappliqué au redémarrage

**Correction firmware K5130** (2026-07-01):
```
B=0 + R/G>0  → bug rouge fixe    → force B≥5
B=1 + G>0    → bug vert matrix   → force B≥5
B=0+R/G=0    → allumer = off     → brightness→0
```

### 🌡️ Ventilateurs (EC + WMI)

**Sans admin (WMI AcerGamingFunction):**
- Auto / Silent / Balanced / Turbo / CoolerBoost
- % manuel par ventilateur (CPU 0x01 / GPU 0x04)

**Avec admin (EC ITE fallback):**
- Mode Auto: 0xCA = 0x00
- Mode Full (30720 RPM): 0xCA = 0x01

**Exemple CLI:**
```python
from acer_nitro_app import ECController
ec = ECController()
ec.set_fan_auto()     # Mode Auto
ec.set_fan_full()     # Mode Full 30720 RPM
ec._wmi_fan_speed(0x01, 75)  # CPU 75%
```

### ⚡ Boost Mémoire & Puissance

**Power Limits (EC 0x14-0x17):**
```
Stock  : PL1=28W (0x00E0)  | PL2=65W (0x0208)
Boost  : PL1=35W (0x0118)  | PL2=70W (0x0230)
Perf   : PL1=45W (0x0168)  | PL2=80W (0x0280)
Max    : PL1=54W (0x01B0)  | PL2=90W (0x02D0)
```

**Plan alimentation:**
- Ultimate Performance (si dispo)
- High Performance (fallback)

**Bande passante DDR5-5600:**
- Estimateur FCLK 1:1
- ~89.6 GB/s (locked) vs ~54 GB/s (stock)

### 🧠 NPU XDNA2 (xrt-smi live)

**Métriques temps réel:**
- **TPS**: Tokens/s (layer_main) — averaging smoothing 30-samples
- **BW**: GB/s observée vs 21.93 GB/s théorique
- **MAC Eff**: % vs 51.3 TOPS
- **Roofline**: Détection BW-BOUND vs COMPUTE
- **Grille 8×4 AIE2P**: Couleurs (idle/actif/compute)

**Contexts (top 4):**
```
pid{PID} [name] kernel sub={} {mem}
Ex: pid 1234  [flm_local] layer_main sub=150 512M
```

### 📝 Persistance des Réglages

Sauvegardés dans `acer_nitro_settings.json` (même répertoire que le script):
```json
{
  "rgb_effect": "Static",
  "rgb_brightness": 160,
  "rgb_r": 30, "rgb_g": 120, "rgb_b": 255,
  "rgb_zone": "All",
  "profile_name": "Balanced",
  "pl_preset": "Stock  (28W/65W)",
  "fan_mode": "Auto"
}
```

**Réapplication au démarrage** (thread daemon):
- RGB appliqué
- Profil restauré
- Preset PL appliqué
- Mode ventilateur défini

### 🛡️ Sécurité EC

**Deux niveaux de vérification (fail-closed):**

**Niveau 1 — Machine:**
- ✅ Fabricant = Acer
- ✅ Modèle série AN16S
- ⚠️ Variante -61 (warning si différent)
- ✅ BIOS non blacklisté
- ⚠️ BIOS connu (warning si nouveau)

**Niveau 2 — EC Sanity:**
- ✅ Profil 0x86 dans {0x00,0x01,0x04,0x05,0x0A,0x0B,0x0E}
- ⚠️ Fan ctrl 0xCA plausible
- ✅ Temp CPU 5-115°C
- ⚠️ RPM < 15000 (0 OK en silencieux)

**État:**
- ✅ **LECTURE-ÉCRITURE** si les 2 niveaux passent
- ❌ **LECTURE SEULE** si un niveau échoue

Affichage badge dans l'interface:
```
🛡️ Admin       (droits OK)
⚠️ Non-admin   (fallback WMI)
⛔ LECTURE SEULE — [raison]  (vérif échouée)
```

---

## 🔧 Architecture Interne

### Classes Principales

```python
ECController          # EC ITE (0x66/0x62) + WMI fans + Power limits
RGBController         # ENE K5130 HID (11-byte RID 0xA4)
LightbarController    # 1025174B COL01 HID (65-byte RID 0xA0)
MemBoostCtrl          # Power plan + PL + Fan WMI + RTX lock + BW estimator
MetricsCollector      # Thread daemon: EC/CPU/GPU/RAM/NPU/XRT-SMI
NitroApp(tk.Tk)       # App principale (tabs)
CompactWidget         # Widget flottant (draggable, α var)
```

### Threads

1. **MetricsCollector** (daemon) — Collecte ~1.5s:
   - EC: temp/fans/profil
   - CPU: load/freq/temp (WMI + powrprof.dll)
   - GPU: nvidia-smi
   - RAM/Disk: WMI
   - Battery: WMI
   - NPU: xrt-smi (toutes les 4.5s)

2. **RGB Keep-alive** (daemon) — Renvoi ~25s pour éviter reset firmware

3. **Action handlers** — Chaque clic EC/WMI/RGB = nouveau thread

### Logging

**In-memory (400 max):**
- Affichage live dans l'onglet "Logs"
- Filtrable par niveau (ALL/INFO/WARNING/ERROR/DEBUG)

**Fichier rotatif:**
- `acer_nitro.log` (max 2 MB × 3 backup)
- Incluant timestamp, logger name, message

---

## 📚 Utilisation Avancée

### API Python

```python
from acer_nitro_app import ECController, RGBController, MetricsCollector

# EC
ec = ECController()
if ec.writable:
    ec.set_profile(0x0E)  # Performance
    ec.set_fan_full()     # 30720 RPM
else:
    print(f"Lecture seule: {ec.read_only_reason}")

# RGB
rgb = RGBController()
rgb.send(effect=0x02, brightness=160, r=255, g=0, b=0, zone=0x0F)  # Red all

# Metrics
col = MetricsCollector(ec)
col.start()
time.sleep(2)
m = col.snapshot()
print(f"CPU: {m.cpu_temp}°C @ {m.cpu_freq:.2f} GHz")
print(f"NPU: {m.npu_tps:.2f} t/s | {m.npu_bw_gbs:.2f} GB/s")
col.stop()
```

### CLI (Batch)

```batch
# Widget compact
python acer_nitro_app.py --widget

# Logs
python -c "from acer_nitro_app import *; LOG.info('Test')"
```

### Config via JSON

Éditer `acer_nitro_settings.json` avant le lancement:
```json
{
  "profile_name": "Turbo",
  "pl_preset": "Max    (54W/90W)",
  "fan_mode": "CoolerBoost",
  "rgb_effect": "Breathing",
  "rgb_brightness": 200
}
```

---

## ⚠️ Limitations & Fallbacks

| Fonctionnalité | Admin | Fallback |
|---|---|---|
| EC temp/fans | ✅ Oui | WMI (moins précis) |
| Power limits | ✅ Oui | ❌ Aucun |
| Profils | ✅ Oui | ❌ Aucun |
| RGB | ❌ Non | Inclus (HID user) |
| WMI fans | ❌ Non | EC (si admin) |
| NPU xrt-smi | ❌ Non | Skipped si absent |
| Lightbar | ❌ Non | Détection auto |

---

## 🐛 Troubleshooting

### "Admin refuse — demarrage en mode limité"

→ Relancer via `launch_acer_nitro.bat` (UAC)

### "EC N/A — pas d'écriture autorisée"

→ Les lectures EC échouent (aucun admin) → utiliser WMI/RGB uniquement

### "RGB OFF" ou "RGB FAIL"

→ VérifierENE K5130 présent:
```powershell
Get-PnpDevice | grep -i ENE
```

### "xrt-smi N/A"

→ AMD AI drivers non installés
→ Installer depuis https://www.amd.com/en/technologies/ai-pc

### "Reduce to tray indisponible: pip install pystray pillow"

→ Optionnel — fenêtrer normal fonctionne toujours

---

## 📦 Fichiers

```
.
├── launch_acer_nitro.bat       # Lanceur (auto-admin + Python detect)
├── acer_nitro_app.py           # App complète (5000+ lignes)
├── acer_nitro.log              # Log rotatif (généré au démarrage)
├── acer_nitro_settings.json    # Reglages persistés (généré à la 1e utilisation)
└── README.md                   # Cette documentation
```

---

## 🛠️ Dépannage EC

**Dump registres EC:**

Onglet "Système" → Bouton "EC Dump":
```
0x19=42°C 0x1A=35°C 0x52=28°C 0x5C=0x50 ...
```

**Lecture brute:**
```python
ec = ECController()
print(f"Profile: 0x{ec.read(0x86):02X}")
print(f"Fan ctrl: 0x{ec.read(0xCA):02X}")
print(f"CPU temp: {ec.get_cpu_temp()}°C")
print(f"Fan 0 RPM: {ec.get_fan0_rpm()}")
print(f"Fan 1 RPM: {ec.get_fan1_rpm()}")
```

---

## 📄 Licences & Remerciements

**Outils intégrés:**
- xrt-smi: AMD (inclus dans les drivers)
- nvidia-smi: NVIDIA (drivers)
- tkinter: Python std lib

**Dépendances optionnelles:**
- pystray: BSD-3 (tray icon)
- Pillow: HPND (image)

**Références:**
- ENE K5130 reverse-engineering (2026-06-30)
- ITE EC protocol (PredatorService)
- AMD XDNA2 roofline analysis
- AN16S-61 BIOS V1.53 (Insyde)

---

## 🎯 Roadmap

- [ ] Export graphiques temps réel (matplotlib)
- [ ] Profils custom (écran/gaming/bureau)
- [ ] TDP profile sync (Windows Ultimate Performance)
- [ ] Gestionnaire tâches processeur intégré
- [ ] Dark/Light themes
- [ ] Multi-language (FR/EN/DE)

---

## 📞 Support

**Problème:**
1. Vérifier logs: Onglet "📋 Logs" (exporter)
2. Chercher dans le repo: Issues/Discussions
3. EC dump: Système → EC Dump
4. Admin: Badge 🛡️ en haut

**Report bug:**
```
github.com/tagmanxdna/Acer-Nitro-16S-non-sense/issues

📋 Inclure:
- logs acer_nitro.log
- EC dump
- BIOS version
- OS build
```

---

**Remplace NitroSense. Reste maître de votre machine.** ⚡
