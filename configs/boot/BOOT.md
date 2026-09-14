# Boot & disk migration plan

Research notes → execution plan for Secure Boot, LUKS2, btrfs subvolumes, timeshift.
Status: **PLANNED for this machine — nothing implemented on the live system.**
This project is the "never risk bootloader/disk/reboot" category: run it as a
deliberate session with a verified backup, not incrementally on a live evening.

Generic, machine-agnostic provisioning for the three features below now lives
in the repo (`configs/boot/{timeshift,sbctl,luks}/`, prompted via `install.sh`
like package groups — see README §Boot disk security). That code only
detects an already-compatible layout and configures it; it does not perform
the layout migration itself. The steps in this file are this machine's actual
migration plan — GPT/ESP conversion, the `@`/`@home` btrfs migration, and the
LUKS2 reinstall — which stay manual, one-off, backup-gated operations.


## Current state (audited 2026-09-13)

- ThinkPad X1-ish, i7-8650U (Kaby Lake R): AES-NI + AVX2, **no VAES** (Ice Lake+ only)
- Lenovo LENSE30512GMSP34MEAT3TA 512 GB NVMe, PCIe 3.0 class, 512e (512 B logical/physical)
- **BIOS/Legacy boot, Limine 12.6.0-1 (`limine-bios.sys`), MBR/dos disklabel** — not UEFI,
  no ESP, Secure Boot unreachable until converted
- Single flat btrfs `nvme0n1p2` (`subvol=/`, set as default, no subvolumes),
  `compress=zstd:3,ssd,discard=async,space_cache=v2`; 161 GiB allocated / 315 GiB free
- `/boot` = FAT32 `nvme0n1p1` (1 GiB), kernels + limine dir, not an ESP
- Swap = zram only (15 GiB), **no disk swap → no hibernation → no LUKS-swap issues**
- TPM 2.0 present (Infineon IFX0763)
- Not installed: sbctl, snapper, snap-pac, grub-btrfs, timeshift, mokutil
- mkinitcpio HOOKS: `base udev autodetect microcode modconf kms plymouth keyboard
  keymap consolefont block filesystems fsck`

## Measured performance implications of LUKS2 (this machine, 2026-09-13)

`cryptsetup benchmark`, memory-only, mitigations on:

| Cipher                        | Encrypt      | Decrypt      |
|-------------------------------|--------------|--------------|
| aes-xts 256b key (AES-128-XTS)| 2981 MiB/s   | 3027 MiB/s   |
| aes-xts 512b key (AES-256-XTS)| 2553 MiB/s   | 2556 MiB/s   |

- Crypto ceiling ≈ 3 GiB/s ≥ stock drive's real throughput → **sequential hit ~0–15%**
- Real cost is **random 4K / low-QD latency** (dm-crypt `kcryptd` workqueue hop per bio):
  typically 5–20% on laptop IO, occasional spikes under heavy concurrent IO
- Kaby Lake is Meltdown-affected → PTI overhead on the crypto syscall path; effective
  in-practice rates land below benchmark numbers (community data ~1.1 GiB/s vs 3 GiB/s
  benchmarked on similar hardware). `kcryptd` visible in top during large copies.
- Argon2id unlock ≈ 2 s CPU (1 GiB / 4 threads), plus typing — or ~0 s with TPM2
- btrfs `compress=zstd:3` helps: compression happens before encryption

Tunables that recover most of the loss:
- `cryptsetup open --perf-no_read_workqueue --perf-no_write_workqueue` (kernel ≥ 5.9)
- **`--sector-size 4096` at LUKS format time** — halves per-bio crypto overhead on this
  512e drive (dm-crypt would default to 512 B sectors)
- AES-128-XTS (aes-xts 256-bit key) default: ~17% faster than AES-256-XTS here
- `--allow-discards` keeps TRIM working (currently `discard=async`); tradeoff: leaks
  which blocks are freed
- Set via `/etc/crypttab` options + `--perf-*` flags persisted at open time

Verdict: on this hardware encryption is cheap; honest cost is small random-IO latency
plus some CPU, largely recoverable with the flags above.

## Target design

- **GPT + ESP** (`nvme0n1p1` reused, 1 GiB), UEFI boot, Limine UEFI binary
  (keep BIOS/MBR entry as fallback until UEFI boot is proven)
- **LUKS2 directly on `nvme0n1p2`, btrfs inside — NO LVM.** Single disk → btrfs subvolumes
  already provide what LVM would; LVM adds a layer + hook for nothing. "LUKS on LVM"
  is the worst variant (per-LV keys, layout visible when locked, slower boot) — it only
  earns its keep multi-disk or mixed enc/unenc VGs. Source: ArchWiki
  dm-crypt/Encrypting_an_entire_system comparison.
- First-level subvolumes at top-level (subvolid=5), default subvol = top-level:
  - `@` — root system (timeshift btrfs-mode requirement)
  - `@home` — user data (excluded from timeshift snapshots by design)
  - `/timeshift` — snapshot target dir (first-level, required by timeshift)
- LUKS options: `--type luks2 --cipher aes-xts-plain64 --key-size 256 --sector-size 4096
  --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue`,
  pbkdf argon2id
- **Secure Boot**: own keys via sbctl in firmware Setup Mode; pacman hooks auto-sign
  kernels/bootloader; `limine-enroll-config` signs `limine_x64.efi`. Community reports
  (CachyOS) say Limine+SB is finicky — prefer **UKIs signed with sbctl** as the robust
  path (also hardens boot chain; Limine supports UKIs).
- **TPM2 auto-unlock**: `systemd-cryptenroll --tpm2-device auto --tpm2-pcrs 7` — PCR 7
  binding is only meaningful with SB on; gives encrypted-at-rest + tamper-gated
  auto-unlock. Keep a passphrase keyslot as backup.
- **Snapshots: timeshift (btrfs mode) + timeshift-autosnap (AUR) pacman hook**
  for pre/post-upgrade snapshots. NOT snapper/snap-pac (redundant with timeshift).
  Timeshift btrfs mode requires the `@`-layout above; RSYNC mode would work on any
  layout but is full hard-linked copies — pointless on btrfs.
- Boot-into-snapshot is GRUB-only (`grub-btrfs`) → with Limine, restore =
  fallback entry / live USB + `timeshift --restore` (subvolume swap, fast).
  If bootable snapshots from the boot menu are wanted, that's the one argument
  for GRUB or systemd-boot+UKI over Limine.

## Caveats to remember

- With SB active, UKI-embedded kernel cmdline is immutable — changing `root=` etc.
  becomes a rebuild, not a bootloader-menu edit
- snapshotted UKIs still verify under SB (sbctl signs them at creation)
- timeshift cleanup levels (boot/daily/weekly defaults) keep snapshot usage bounded;
  315 GiB unallocated headroom is ample
- `cryptsetup reencrypt --encrypt` (in-place) exists but is offline/slow/riskiest on
  the only disk — prefer fresh install or `btrfs send/receive` from verified backup

## Execution sequence (each step reversible until the LUKS migration)

1. Full backup, verified (clone or btrfs send → external disk; verify restore)
2. Convert to GPT + ESP: backup `/boot`, recreate `nvme0n1p1` as ESP (GPT),
   install Limine UEFI binary, keep MBR/BIOS fallback entry; switch firmware to UEFI;
   **verify it boots before continuing**
3. sbctl: create keys in firmware Setup Mode, enroll, sign Limine + kernels/UKIs,
   verify `sbctl verify`; reinstall sbctl to trigger pacman signing hooks
4. Reinstall / migrate into LUKS2 (`@`, `@home`, `/timeshift` subvols, tuned options
   above) from backup — **point of no return, needs the verified backup**
5. timeshift (btrfs mode) + timeshift-autosnap; configure cleanup levels
6. `systemd-cryptenroll --tpm2-device auto --tpm2-pcrs 7` (after SB is on and stable)
7. Provision reproducibly in this repo: install.sh packages (sbctl, timeshift,
   timeshift-autosnap via AUR), mkinitcpio hooks (`encrypt` before `filesystems`),
   /etc/crypttab, /etc/kernel/cmdline, sbctl/uki configs — idempotent, per the
   configs/<tool>/link.sh pattern

## Repo provisioning status (2026-09-13)

`configs/boot/{timeshift,sbctl,luks}/link.sh` exist and are wired into
`install.sh` (opt-in prompt → `boot.conf`, same shape as `groups.conf`).
They handle step 7's detection/configuration halves generically for any
machine — not just this one — and no-op with a clear message when the
precondition for that step isn't met yet:

- `timeshift`: writes `timeshift.json` (btrfs mode) + relies on the
  `timeshift-autosnap` AUR package (added to install.sh base group) for the
  pacman hook, once root is on a named subvolume (`@`)
- `sbctl`: creates/enrolls keys in Setup Mode, signs the ESP + Limine UEFI
  binary once Secure Boot is on, enables the mkinitcpio signing hook
- `luks`: `/etc/crypttab` tuning (`discard`, `perf-no-{read,write}-workqueue`)
  + ensures the mkinitcpio `encrypt` hook, once a LUKS2 partition exists

None of these three touch partitioning, GPT/ESP conversion, or perform the
actual LUKS migration — steps 1–4 above (backup, GPT+ESP conversion, sbctl
Setup Mode work, and the LUKS2 reinstall itself) remain manual, run once, on
this machine, deliberately.

