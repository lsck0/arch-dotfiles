# System sensors research: CPU/GPU/RAM/battery widget

Research for the Quickshell bar's system-stats widget (bar segment: cpu/gpu %,
(v)ram, battery; hover panel: CPU/GPU name, usage%, memory, voltage, clock,
temp; RAM/VRAM; battery; powermode toggle). Covers what THIS machine can
expose today, what's possible in general per GPU vendor, and how four other
Quickshell-based shells solve the same problem.

Current implementation: `configs/quickshell/plugins/bar/widgets/system-stats.sh`
(one-shot bash script, polled by the QML widget, emits a JSON object).
Power mode toggle: `toggles/toggle-powermode.sh` (TLP-backed, 3-state cycle).

---

## 1. Ground truth on THIS machine

Machine: ThinkPad, Intel i7-8650U (Kaby Lake-R, 8th gen), UHD Graphics 620
iGPU (i915 driver), Arch Linux. All commands below were run read-only on
2026-09-01; output is real, not illustrative.

### CPU identity

```
$ lscpu | head -20
Architecture:                            x86_64
Vendor ID:                               GenuineIntel
Model name:                              Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz
CPU family:                              6
Model:                                   142
Thread(s) per core:                      2
Core(s) per socket:                      4
Socket(s):                               1
Stepping:                                10
CPU(s) scaling MHz:                      41%
CPU max MHz:                             1900.0000
CPU min MHz:                             400.0000
BogoMIPS:                                4199.88
```

`cpuinfo` model name matches: `Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz` —
directly usable as the "CPU name" the spec asks for, no cleanup needed beyond
maybe stripping `(R)`/`(TM)`.

### GPU identity

```
$ lspci -nn | grep -iE 'vga|display'
00:02.0 VGA compatible controller [0300]: Intel Corporation Kaby Lake-R GT2 [UHD Graphics 620] [8086:5917] (rev 07)
```

Single GPU, no discrete adapter — confirms the current script's comment.
sysfs only gives raw IDs, not the name:

```
$ cat /sys/class/drm/card1/device/vendor   # 0x8086
$ cat /sys/class/drm/card1/device/device   # 0x5917
```

`8086:5917` is the PCI vendor:device pair for UHD 620 — turning that into
"UHD Graphics 620" requires either `lspci`'s `pci.ids` database lookup (what
the script should do: parse `lspci -nn` once at name-detection time, not
every poll) or hardcoding a lookup table. There is no sysfs file that just
hands you the marketing name.

### Voltage — searched exhaustively, none found

```
$ sensors -j | jq keys
["BAT0-acpi-0", "acpitz-acpi-0", "coretemp-isa-0000", "iwlwifi_1-virtual-0",
 "nvme-pci-0400", "pch_skylake-virtual-0", "thinkpad-isa-0000",
 "ucsi_source_psy_USBC000:001-isa-0000", "ucsi_source_psy_USBC000:002-isa-0000"]
```

`ls /sys/class/hwmon/*/name`: `AC, acpitz, BAT0, nvme, thinkpad, pch_skylake,
ucsi_source_psy_USBC000:001, iwlwifi_1, coretemp, ucsi_source_psy_USBC000:002`
— no `nct6775`/`it87`/`w83627` Super-I/O chip, no `k10temp`-style VRM sensor.

The only `inN_input` keys that exist anywhere in `sensors -j` output:

```
BAT0-acpi-0:      in0_input = 11.61   (V)   <- battery pack voltage, not vcore
ucsi_source_psy_USBC000:001-isa-0000: in0_input = 0.00  (USB-PD source, unused)
ucsi_source_psy_USBC000:002-isa-0000: in0_input = 0.00  (USB-PD source, unused)
```

The 11.61 V reading is the battery's own voltage sensor (surfaced through
ACPI, chip name literally `BAT0-acpi-0`), not CPU Vcore. There is no chip on
this system exposing die/core voltage. **Confirmed negative finding**: CPU
voltage is genuinely unavailable here, root or not — no interface exposes
it at all, see §3.4 for why and the best substitute.

### Temperature

`thinkpad-isa-0000` (EC-based, via `thinkpad_acpi`) also reports a `CPU`
temp of 41°C, matching `coretemp-isa-0000`'s `Package id 0` reading the
script already uses via `jq`. `thinkpad-isa-0000.GPU` is an **empty object**
`{}` — the EC exposes a GPU temperature slot but it reads nothing on this
igpu-only model (that field exists for ThinkPads with a dGPU). `fan1_input`
reads `0.000000` (fan idle/stopped at time of sampling, or unreadable at
low RPM — not a missing sensor).

### Power supply / powercap / platform profile

```
$ ls /sys/class/power_supply/
AC  BAT0  ucsi-source-psy-USBC000:001  ucsi-source-psy-USBC000:002

$ ls /sys/class/powercap/
intel-rapl  intel-rapl-mmio  intel-rapl-mmio:0  intel-rapl-mmio:0:0
intel-rapl:0  intel-rapl:0:0  intel-rapl:0:1  intel-rapl:0:2  intel-rapl:1

$ cat /sys/firmware/acpi/platform_profile_choices
NOT PRESENT (no such file)
$ cat /sys/firmware/acpi/platform_profile
NOT PRESENT (no such file)
```

`platform_profile` sysfs (the interface `power-profiles-daemon` and GNOME's
power menu prefer) doesn't exist on this machine at all — it requires
firmware exposing an ACPI `_DSM`/DYTC thermal-profile method, which Lenovo
only started shipping broadly around 2019-2020 ThinkPads. This 8650U-era
model (2018) predates it. **This is not a permissions issue, the interface
is absent.**

RAPL exists (`intel-rapl:0` = package domain, `:0:0`/`:0:1`/`:0:2` =
sub-domains — core/uncore/DRAM depending on platform, `intel-rapl:1` = the
PSys/platform domain, not a second CPU package — this is a single-socket
laptop) but is root-only by default:

```
$ ls -la /sys/class/powercap/intel-rapl:0/energy_uj
-r-------- 1 root root 4096 ...
$ cat /sys/class/powercap/intel-rapl:0/energy_uj
Permission denied (os error 13)
```

**This is the second key negative finding**: RAPL energy counters exist on
this hardware but are unreadable as the logged-in user with the shipped
kernel/udev config. Reading them either needs `sudo`, a `CAP_DAC_OVERRIDE`
polkit-free wrapper, or a udev rule relaxing the permission (`chmod`/`+r`
via a rule, e.g. `SUBSYSTEM=="powercap", RUN+="/bin/chmod 0444 /sys%p/energy_uj"`)
— none of which are currently in this repo's udev config, and adding one is
out of scope for a read-only widget script.

### iGPU counters actually used today

```
$ cat /sys/class/drm/card1/gt/gt0/rc6_residency_ms   # 11300646 (cumulative ms)
$ cat /sys/class/drm/card1/gt_act_freq_mhz            # 650
```

Both readable as a normal user, confirming the current script's approach
works. No `gpu_busy_percent` file exists under `/sys/class/drm/card1/device/`
on this i915 (Gen9.5) card — that sysfs file is AMD-only (see §3).

### Tool availability (important correction to the script's comment)

```
$ command -v intel_gpu_top nvtop radeontop turbostat powertop powerprofilesctl tlp cpupower
intel_gpu_top:     /usr/sbin/intel_gpu_top   <- IS installed
nvtop:             /usr/sbin/nvtop           <- IS installed
radeontop:         NOT FOUND
turbostat:         /usr/sbin/turbostat       <- IS installed
powertop:          NOT FOUND
powerprofilesctl:  NOT FOUND (power-profiles-daemon not installed)
tlp:               /usr/sbin/tlp             <- IS installed
cpupower:          /usr/sbin/cpupower        <- IS installed
```

**The current script's comment ("intel_gpu_top isn't installed") is stale/
wrong right now** — `intel_gpu_top` is present at `/usr/sbin/intel_gpu_top`
(part of `intel-gpu-tools`, pulled in incidentally, likely by `nvtop` or
another package's deps). It still isn't *usable unprivileged*, confirmed
directly:

```
$ cat /proc/sys/kernel/perf_event_paranoid
2
```

`intel_gpu_top`'s primary backend reads the i915 PMU, a system-wide
(not per-process) perf event source — `perf_event_paranoid >= 1` already
blocks unprivileged system-wide CPU/GPU event access, and this machine
ships the common distro default of `2` (kernel profiling also disallowed).
So `intel_gpu_top` genuinely needs root here, installed or not. The rc6-
residency approach the script already uses needs no such privilege.
**The comment should be corrected to describe unprivileged runnability
(confirmed false), not mere installation (true).**

---

## 2. SPEC asks vs achievable here

| Spec field | Achievable on THIS machine | Source | Notes |
|---|---|---|---|
| CPU name | Yes | `/proc/cpuinfo` `model name` | Already clean text |
| CPU usage % | Yes | `/proc/stat` delta (current approach) | Already implemented |
| CPU clock | Yes | `scaling_cur_freq` per-core | Already implemented (cpu0 only; could go per-core) |
| CPU temperature | Yes | `sensors -j coretemp-isa-0000` | Already implemented |
| **CPU voltage** | **NOT POSSIBLE** | — | No hwmon chip exposes it; no Super-I/O; RAPL gives power not voltage. Negative finding, not a bug. |
| CPU power (substitute for voltage) | **Partially** — needs root | `intel-rapl:0/energy_uj` | File exists but is root-only (`-r--------`); needs sudo/udev rule to unprivilege |
| Per-core frequency/throttle state | Yes | `cpuN/cpufreq/scaling_cur_freq`, `/sys/devices/system/cpu/cpu*/thermal_throttle/*` | Good voltage substitute alongside RAPL |
| GPU name | Yes, but not from one file | `lspci -nn` parse or vendor:device sysfs + ID table | No sysfs "model name" file exists for i915 |
| GPU usage % | Yes | `rc6_residency_ms` delta (current approach) | Correct approach for this driver without intel_gpu_top |
| GPU clock | Yes | `gt_act_freq_mhz` | Already implemented |
| GPU temperature | **Effectively no dedicated reading** | `coretemp` package temp is the closest proxy | iGPU shares the CPU package die; `thinkpad-isa-0000.GPU` exists but reads empty on this model |
| **GPU voltage** | **NOT POSSIBLE** | — | Same as CPU — no interface exposes iGPU voltage rail |
| GPU memory / VRAM | **NOT POSSIBLE as "VRAM"** | — | i915 iGPU has no dedicated VRAM; it uses shared system RAM via GTT. No sysfs file for GTT usage either (see §3.1) |
| RAM used/total | Yes | `/proc/meminfo` | Already implemented |
| Battery % / state | Yes | `/sys/class/power_supply/BAT0/` | Not yet in the script; trivial to add |
| Powermode toggle | Yes | `toggles/toggle-powermode.sh` (TLP) | Already exists; see §4 for whether TLP is the right backend |
| ACPI `platform_profile` toggle | **NOT POSSIBLE** | — | Interface doesn't exist in firmware on this ThinkPad generation |

**Bar-level minimum (cpu%, gpu%, ram, vram, battery)**: everything is
achievable except **VRAM**, which should be displayed as "—" / hidden on
this hardware and populated on AMD/NVIDIA/Intel-Xe machines where the value
genuinely exists (see the vendor-conditional design in §7).

**Hover-panel-level (adds name, voltage, clock, temp)**: everything is
achievable except **CPU voltage and GPU voltage**, which are structurally
absent on this hardware and, per the web research below, on essentially all
Intel laptop platforms without a Super-I/O chip. The honest UI move is to
substitute **package power (W)** for voltage where RAPL is readable, and
omit the field (not show a fake `0`) where it isn't.

---

## 3. Per-vendor reference

### 3.1 Intel iGPU (i915 / Xe driver)

- **No sysfs VRAM/GTT usage file exists**, full stop, for either the legacy
  `i915` driver (used on this Kaby Lake-R card) or the newer `xe` driver
  (Meteor Lake+). `mem_info_vram_used`/`mem_info_gtt_used` are **AMD-only**
  sysfs files (`amdgpu` driver) — there's no Intel equivalent path.
- The only ways to get Intel GPU memory usage are:
  - `intel_gpu_top -J`: reads via **perf PMU** counters exposed by the i915
    driver (plus RAPL/uncore-IMC for power/bandwidth). Non-root access is
    gated by `perf_event_paranoid`; on many distros this blocks unprivileged
    reads unless the sysctl is relaxed. Its JSON output nests memory data
    under per-process `ClientStats.memory` regions, not a single system-wide
    number — you'd have to sum it yourself.
  - i915/Xe **fdinfo** (`/proc/<pid>/fdinfo/<fd>` `drm-*` keys, e.g.
    `drm-total-cycles-rcs`, `drm-engine-capacity-rcs`) — same interface
    `intel_gpu_top` and `nvtop`'s Intel backend read, gives per-process
    engine busy time; the Xe driver additionally exposes a
    `DRM_IOCTL_XE_DEVICE_QUERY` ioctl (`DRM_XE_DEVICE_QUERY_MEM_REGIONS`)
    that returns real VRAM/GTT `totalSize`/`used`/`cpuVisibleUsed` per
    memory region — but only on `xe`-driven hardware (Meteor Lake and
    newer), not on this i915-driven Kaby Lake-R card. Noctalia's
    `src/system/intel_gpu.cpp` (C++ helper, see §5) implements exactly this
    ioctl path with a `DrmXeMemRegion` struct mirroring the kernel uapi.
  - i915 **debugfs** (`/sys/kernel/debug/dri/0/i915_gem_objects` etc.) —
    root-only, unstable across kernel versions, not worth building on.
- **Conclusion for this machine**: rc6-residency-derived busy% (current
  approach) is correct and is what the widget should keep using. VRAM/GTT
  usage should be reported as unavailable, not estimated.
- **GPU name**: no sysfs "model name" file. `lspci -nn`'s bracketed name
  (`[UHD Graphics 620]`) or a `pci.ids` vendor:device lookup are the two
  options; caelestia's `gpu.cpp` (see §5) has a good fallback chain worth
  copying: try `nvidia-smi` name query → `glxinfo -B` `Device:` line →
  `lspci` bracketed match → raw vendor:device as last resort.

### 3.2 AMD GPU (amdgpu driver) — for future hardware

- `gpu_busy_percent` — `/sys/class/drm/card0/device/gpu_busy_percent`, a
  plain 0-100 integer, no delta math needed (unlike Intel's rc6 trick).
- `mem_info_vram_used` / `mem_info_vram_total` —
  `/sys/class/drm/card0/device/mem_info_vram_used` (bytes). Also
  `mem_info_vis_vram_{used,total}` (CPU-visible VRAM subset) and
  `mem_info_gtt_{used,total}` (GTT/shared-memory allocations, relevant for
  APUs).
- Temperature/power/voltage via **hwmon**, same `sensors` interface already
  used for CPU: `/sys/class/drm/card0/device/hwmon/hwmon*/temp1_input`,
  and — unlike Intel — AMD's hwmon node typically *does* expose `in0_input`
  (GPU core voltage) on discrete cards, so voltage becomes achievable on
  AMD hardware even though it isn't here.
- GPU name: readable straight from
  `/sys/class/drm/card0/device/product_name` or via `lspci`.

### 3.3 NVIDIA (proprietary driver)

- Everything through one command:
  `nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.gpu,power.draw --format=csv,noheader,nounits`
  — single process, comma-separated, all spec fields (name, usage%, VRAM
  used/total, temp, clock, power as a voltage substitute) in one shot. No
  sysfs path needed/available for the proprietary driver; `nvidia-smi` (or
  NVML directly via a small binding) is the only interface. Nouveau (open
  driver) instead exposes some of this via hwmon + `/sys/class/drm/*/device/`
  but is a secondary path not worth building for first.

### 3.4 CPU voltage — why it's unreadable, and the honest substitute

Vcore on desktop boards is normally read off a **Super-I/O chip**
(`nct6775`, `it87`, etc.) that motherboard vendors wire to VRM sense pins
and expose through the `nct6775`/`w83627ehf` kernel hwmon driver — that's
what desktop `sensors` output's `Vcore` line comes from. **Laptops
essentially never have this.** The VRM is typically integrated into the
PCH/EC's power delivery with no Super-I/O passthrough, so there's no hwmon
chip to read from. This isn't an Arch/kernel-config gap; it's absent
hardware wiring — confirmed empirically on this ThinkPad (§1: no such chip
in `sensors -j` or `/sys/class/hwmon/*/name`).

The two things that *do* exist and approximate the same "how hard is the
CPU working" story:

1. **RAPL package power** (`intel-rapl:0/energy_uj`, joules-scaled counter
   → delta over a sampling window ÷ time = watts). This is the standard
   substitute turbostat/powertop use internally. On this machine it's
   present but **root-only** by file permission (`-r--------`), so a
   userspace widget script can't read it as-is — needs either `sudo` (bad
   for a per-second poll), a udev rule to relax the permission bit, or
   running the read via a small privileged helper. **This should be called
   out honestly in the UI or the value omitted, not silently sudo'd.**
2. **turbostat**: reads Vcore-adjacent numbers (actually still power/freq/
   C-state residency, not literal voltage) via **MSRs**
   (`/dev/cpu/*/msr`), which require root outright — `turbostat` "must be
   invoked as the super-user." Same privilege wall as RAPL, one layer
   lower. Not a realistic per-poll backend for an unprivileged widget.
3. **Per-core frequency** (`scaling_cur_freq`) and **thermal throttle flag**
   (`/sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count` or
   `package_throttle_count`) are both freely readable and make a reasonable
   3rd/4th substitute data point ("is it currently being limited") without
   any privilege escalation.

**Recommendation**: don't chase voltage. Show package temp (have it),
clock (have it), and — if the udev permission is relaxed — RAPL power in
watts. Label the field "Power" not "Voltage" and skip it entirely rather
than showing a stale/fake number when unreadable.

---

## 4. Power-profile backend analysis

Four different interfaces exist on Linux for "set the system to
performance/balanced/powersave," and **they actively conflict** if run
together:

| Backend | What it sets | Present here? |
|---|---|---|
| `power-profiles-daemon` (`powerprofilesctl`) | Writes ACPI `platform_profile` sysfs + tunes some kernel knobs via D-Bus | Not installed |
| TLP (`tlp` CLI / `tlp.service`) | `scaling_governor`, `energy_performance_preference`, PCIe ASPM, USB autosuspend, disk APM, radio state, and dozens of other sysfs knobs via a single config file | Installed, used by `toggle-powermode.sh` |
| `cpupower` | `scaling_governor` / `scaling_min/max_freq` only — narrower, CPU-only | Installed, unused |
| Raw sysfs (`scaling_governor`, `energy_performance_preference`) | Whatever you write directly | Always available, is what all of the above ultimately write to |
| ACPI `platform_profile` | Firmware-level thermal/fan profile (low-power/balanced/performance) | **Not present in firmware on this ThinkPad** (§1) |

**Why they conflict**: `power-profiles-daemon`'s systemd unit ships a
`Conflicts=` directive against `tlp.service` (and `tuned.service`,
`auto-cpufreq.service`) — if both are installed and enabled, whichever
activates last wins and the other's unit gets stopped, silently. Most
distros (Arch included, via package conflicts or docs) tell you to pick
one. This repo has already made that call correctly: **PPD isn't
installed**, TLP owns the job, so there's no live conflict right now — but
it's worth keeping `toggles/toggle-powermode.sh`'s comment (already present:
"not installed, would conflict with TLP anyway") as the enforced invariant:
if anyone ever `pacman -S power-profiles-daemon`, this stops working
correctly and needs an explicit decision, not silent coexistence.

Since `platform_profile` doesn't exist in firmware here, PPD would have
nothing to write to anyway on this specific machine (PPD falls back to a
"generic"/CPU-only driver when no ACPI DYTC profile exists, which is a
much weaker feature set than TLP's). **TLP is the objectively correct
backend for this hardware**, independent of preference.

### Evaluating `toggle-powermode.sh`'s 3 states

Current script (`toggles/toggle-powermode.sh`) cycles `balanced →
performance → power-saver` and calls `sudo tlp <state>`, i.e. it uses TLP's
**own native forced-mode CLI** (`tlp performance|balanced|power-saver`)
rather than hand-picking individual sysfs knobs. This is the right call —
TLP internally keys its config on three profile suffixes, `_ON_AC`,
`_ON_BAT`, and `_ON_SAV` (SAV = the dedicated forced "power SaVer" profile,
a real third state, not just BAT settings re-applied), so the three-way
CLI maps onto config TLP already ships rather than anything hand-rolled.
Read directly off this system (`/usr/share/tlp/defaults.conf` merged with
the site override in `/etc/tlp.conf`; the second block below is this
machine's actual override, which wins):

```
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance   # default
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power        # default
CPU_ENERGY_PERF_POLICY_ON_SAV=power                # default (unused by site conf)
PLATFORM_PROFILE_ON_AC=performance                 # default
PLATFORM_PROFILE_ON_BAT=balanced                   # default
PLATFORM_PROFILE_ON_SAV=low-power                  # default
PCIE_ASPM_ON_AC=default / ON_BAT=default           # defaults.conf

# /etc/tlp.conf overrides (what's actually active on this machine):
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersave
```

So concretely: `tlp performance` applies the `_ON_AC` values (EPP
`performance`, turbo boost forced on) regardless of actual power source;
`tlp power-saver` applies `_ON_SAV` (EPP `power`, the most conservative
platform-profile hint `low-power`) regardless of source; `tlp balanced`
clears the forced override and returns to TLP's normal AC/BAT
auto-detection (EPP `performance` on AC / `balance_power` on battery per
this machine's own override, turbo capped off on battery via
`CPU_BOOST_ON_BAT=0`). `PLATFORM_PROFILE_ON_*` values are configured but
inert here — this ThinkPad has no `platform_profile` sysfs node (§1), so
TLP silently no-ops that particular knob while still applying everything
else in the bundle.

This matches what's readable on the live system right now: `cpu0`'s
`scaling_governor` reads `powersave` and `energy_performance_preference`
reads `balance_power` — consistent with the machine currently sitting in
TLP's on-battery balanced (auto-detect) state.

The widget's hover-panel powermode toggle should keep shelling out to
`toggle-powermode.sh {get|toggle|performance|balanced|power-saver}` rather
than reimplementing any of this in QML/sysfs — the script already owns the
volatile-state tracking (`toggle_get_volatile`/`toggle_set_volatile`) needed
because TLP has no "what's currently forced" query and resets to
auto-detect on every boot.

---

## 5. How other Quickshell/Hyprland shells do it

Surveyed four active projects' actual source (not just docs) for their
system-stats implementation, specifically: shell-out-per-poll vs long-lived
helper, and how each handles GPU vendor detection.

| Project | Mechanism | Files | Efficient-polling shape |
|---|---|---|---|
| **caelestia-dots/shell** | Compiled **Qt/C++ Quickshell plugin**, in-process `TickingService` base class | `plugin/src/Caelestia/Services/{cpu,gpu,sensorslib}.cpp/.hpp` | Best-in-class: no process spawn at all per tick. `Cpu::tick()` re-reads `/proc/stat`/`/proc/cpuinfo` via `QFile`, computing the same idle-delta % this repo's bash script does, but as a compiled loop inside the already-running shell process. GPU name detection is a fallback chain: try `nvidia-smi --query-gpu=name`, then `glxinfo -B`'s `Device:` line, then `lspci -nn`'s bracketed name — worth copying verbatim as a shell-parseable regex chain. |
| **noctalia-dev/noctalia** | Also a compiled **C++ system helper** (not pure QML) | `src/system/{cpu_stat,cpu_freq,cpu_temp_sensor,intel_gpu}.cpp/.h` | `intel_gpu.cpp` is the most sophisticated of the four: talks directly to `/dev/dri/renderD*` via `ioctl()`, using the `xe` uapi struct layouts (`DRM_IOCTL_XE_DEVICE_QUERY`, `DRM_XE_DEVICE_QUERY_MEM_REGIONS`) for real VRAM/GTT numbers on `xe`-driven Intel hardware, and reads i915/xe **fdinfo** `drm-engine-*`/`drm-cycles-*` keys for per-engine busy% on both drivers — the same fdinfo interface `intel_gpu_top` uses, without needing perf-PMU privilege. Not applicable to this i915-only Kaby Lake-R card's memory query. The fdinfo `drm-engine-*` path is **per-process** engine time, not a cheaper system-wide counter — a system-wide busy% needs summing every process's fd, more syscalls per tick than this repo's single `rc6_residency_ms` read; it's the right tool for "which process is using the GPU," not a drop-in replacement for the existing rc6 trick. |
| **AvengeMedia/DankMaterialShell** | Shells out to a **companion Go daemon**, `dgop` (separate repo, `AvengeMedia/dgop`) | `quickshell/Modules/DankBar/Widgets/{CpuMonitor,CpuTemperature,GpuTemperature}.qml` (consumers) + `DgopService` | `dgop` describes itself as "Stateless, cursor-based system and process monitoring" — a standalone Go binary exposing a **CLI and REST API**; DankMaterialShell's `DgopService` singleton queries it (likely long-lived process, HTTP/local-socket calls per refresh, not re-spawning per second). Architecturally the same idea the task brief suggests ("one long-lived helper" beats respawning bash), just implemented as a full daemon with an OpenAPI spec rather than a JSON-lines stream. |
| **end-4/dots-hyprland** ("ii") | **Pure QML**, no external process at all for the basics | `services/ResourceUsage.qml` (CPU/RAM/swap), `modules/common/widgets/Graph.qml` (sparkline) | Uses Quickshell's own `Quickshell.Io` `FileView` objects (`fileMeminfo`, `fileStat`) with a `Timer` calling `.reload()` + `.text()` and regex-parsing `/proc/meminfo` and `/proc/stat` **in QML itself** — zero process spawn, not even a long-lived helper, just direct file reads through Quickshell's native file-watching API. Cheapest possible approach for simple `/proc` counters; doesn't extend to GPU vendor-name detection or anything needing `lspci`/`nvidia-smi`, where a process call is unavoidable. |

**Takeaway for this repo's redesign**: the four projects span the full
spectrum from "spawn bash every second" (current state here) to "read
/proc directly in QML" (end-4) to "long-lived compiled helper" (caelestia,
noctalia) to "long-lived companion daemon with HTTP API" (Dank). Given this
repo's existing convention of small bash toggle/widget scripts (see
`l-quickshell` skill: no C++ plugin infrastructure exists yet, no interest
signaled in building one), the pragmatic middle ground is:

- Move pure **`/proc`/`/sys` counter reads** (RAM, `/proc/stat` CPU%,
  `scaling_cur_freq`, `rc6_residency_ms`, `gt_act_freq_mhz`, battery) into
  Quickshell's own `FileView` polling in QML directly — end-4's approach —
  eliminating the per-second bash spawn entirely for those fields.
- Keep bash only for what genuinely needs an external command: GPU name
  (`lspci` parse, cached, not per-poll) and `sensors -j`/`jq` for temp
  (hwmon numbering like `hwmon8` isn't stable across boots, so `sensors`'
  named chip lookup beats hardcoding the index).
- A future persistent-helper upgrade, fitting this repo's bash-first
  convention without a C++/Go build step, is a **long-lived bash/awk loop
  emitting one JSON line per second**, read via `Quickshell.Io.Process` in
  streaming mode instead of re-spawning — see §7's sketch.

---

## 6. Per-core sparkline / history pattern in QML (brief)

All four projects that show history graphs (only end-4/ii does, of the four
surveyed) use the same shape, worth reusing here:

1. **A `list<real>` history buffer**, normalized 0-1 at write time, capped
   to a fixed length (end-4: default 60 samples) via `.shift()` when it
   overflows — a manual ring buffer via array push+shift.
2. **A `Canvas` element** (immediate-mode, not `QtQuick.Shapes`) with
   `onValuesChanged: requestPaint()`, and an `onPaint` that clears the
   canvas, walks the array (optionally right-to-left, newest sample at the
   right edge), `ctx.lineTo`s each point, `ctx.stroke()`s the outline, then
   closes to the baseline and `ctx.fill()`s it for a filled-area look.
3. **Per-core** sparklines extend this with one history array per core
   (a `Repeater` over `cpuCount` instantiating one `Graph{}` each) rather
   than a shared buffer — each core's `/proc/stat` `cpuN` line already
   gives an independent idle-delta %, so the math is identical, just done
   N times per tick.
4. `requestPaint()` per sample is fine at 1 Hz; throttle only if sampling
   faster than display refresh.

This `Canvas` + ring-buffer-array + `requestPaint()` pattern is the
standard, low-dependency way to do sparklines in Quickshell/QML — no extra
QML module needed beyond stock `QtQuick`.

---

## 7. Recommended `system-stats.sh` v2 design

Given the findings above, the redesign should:

1. **Correct the stale comment** — `intel_gpu_top` is installed but
   confirmed unusable unprivileged (`perf_event_paranoid=2`); keep rc6
   for that reason, not "not installed."
2. **Resolve static info once, not per tick.** CPU name, GPU name (via
   caelestia's `lspci`-parse fallback chain), and total RAM don't change
   between polls — cache at first run or fetch once from QML at
   widget-init instead of every second.
3. **Add battery** (`/sys/class/power_supply/BAT0/{capacity,status}`) —
   currently missing despite being in the spec, trivially cheap to read.
4. **Add a best-effort `powerWatts` field**: read `intel-rapl:0/energy_uj`
   twice with a sleep between (same delta shape as rc6), and on
   `Permission denied` emit `null`, not `0`. Don't `sudo` from a polled
   script.
5. **Never emit a `voltage` field on this hardware** — it's not
   obtainable, so omit it rather than hardcoding a `0`/`null` display
   branch that never fires. For a schema meant to generalize to other
   machines, gate its presence on whether hwmon reports an `inN_input`
   under a GPU/VRM-looking chip at name-detection time, so it appears on
   hardware that has it (most AMD discrete GPUs) with no code change.
6. **Gate VRAM the same way**: check for `mem_info_vram_total` (AMD) or
   `nvidia-smi` (NVIDIA) at name-detection time and pick the matching
   query path; default to "no VRAM" otherwise (this machine, and any
   pre-Xe Intel iGPU). Emit a `gpuVendor` field so QML decides which
   hover-panel rows to show without re-deriving vendor logic itself.
7. **Streaming-helper upgrade is a separate follow-up** (§5): a
   long-running `while true; do …; sleep 1; done` loop emitting one JSON
   line per second, read via Quickshell's `Process` in streaming mode
   instead of re-spawning bash/jq/awk every tick — a pure performance win,
   independent of the vendor-gating work above.

Sketch of the resulting JSON shape (fields in *italics* are new):

```json
{
  "cpu": 12,
  "cpuName": "Intel Core i7-8650U",
  "freqMhz": 1900,
  "tempC": 41,
  "_powerWatts_": null,
  "memUsedGb": 6.1,
  "memTotalGb": 15.5,
  "gpuPct": 8,
  "gpuFreqMhz": 650,
  "_gpuName_": "UHD Graphics 620",
  "_gpuVendor_": "intel",
  "_gpuVramUsedMb_": null,
  "_gpuVramTotalMb_": null,
  "_batteryPct_": 84,
  "_batteryStatus_": "Discharging"
}
```

`null` VRAM/power fields are the correct representation of the two
confirmed-not-possible-here measurements — the QML hover panel should
render "—" or hide the row entirely rather than "0%"/"0 MB", which would
misrepresent an absent sensor as a real zero reading.
