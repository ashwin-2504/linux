# Arch Linux Autonomous Agent Rules (`GEMINI.md`)

You (`agy`) are running inside the user's cloned `~/linux` repository on **Arch Linux** (`archinstall` on the 2nd SSD) on an **HP ProBook 440 G7**.

---

## Verified Hardware & Dual-Boot Context
- **Machine:** HP ProBook 440 G7 (`Intel Core i5-10210U`, `Intel UHD Graphics`, ~16 GB RAM)
- **Storage:** Two separate physical 512 GB SSDs (`SAMSUNG SSD SM871 2.5 7mm 512GB` and `INTEL SSDPEKNW512G8H`).
- **Windows 11 Dual-Boot:** Windows 11 lives on the other physical SSD. **Windows BitLocker is disabled**, and Windows must continue booting normally alongside Arch with **UEFI Secure Boot enabled**.

---

## Current Mission Priority
1. **Priority 1 — UEFI Secure Boot + Dual-Boot Safety:** Follow [SECURE_BOOT.md](./SECURE_BOOT.md) strictly, step by step, before moving on to full system polish or Hyprland UI ricing.
2. **Priority 2 — System Hardening & Laptop Polish:** Snapshots (if Btrfs), firewall, power/thermals, PipeWire, Bluetooth, clean NetworkManager setup.
3. **Priority 3 — Polished Custom Hyprland Rice:** Modular, git-tracked dotfiles and theming only *after* Secure Boot and dual-boot are verified working across reboots.

---

## Non-Negotiable Safety Guardrails

### 1. Read-Only Discovery First (Never Guess)
Before modifying `/etc`, `/boot`, `/efi`, `mkinitcpio`, or bootloader files, inspect live state:
- `lsblk -f`, `findmnt`, `df -h`
- `efibootmgr -v`, `bootctl status 2>/dev/null`
- `cat /proc/cmdline` and existing bootloader entry configs

### 2. Dual-Boot & Disk Non-Destruction
- **NEVER** format, resize, delete, or overwrite any partition on the Windows 11 SSD or Windows EFI System Partition.
- Preserve a working Windows Boot Manager UEFI entry at all times.
- Measure ESP free space (`df -h`) before creating UKIs or installing extra kernels so the ESP never runs out of space.

### 3. Kernel Cmdline & Bootloader Preservation
- Always preserve the exact `root=`, `rootflags=` (especially Btrfs `subvol=@`), `cryptdevice=`/`rd.luks.name=`, and storage parameters from the live `/proc/cmdline` or existing `archinstall` entry when configuring UKIs or `/etc/cmdline.d/`.
- Maintain a **signed fallback kernel** (`linux-lts` UKI or fallback UKI) alongside the primary `linux` UKI.
- Back up existing `/boot/loader` (or `/efi/loader`) and `/etc/mkinitcpio*` files to `~/arch-backups/` before editing.

### 4. Secure Boot (`sbctl`) Verification Gate
- **ALWAYS enroll Microsoft certificates alongside custom keys:** `sudo sbctl enroll-keys -m` (required for Windows 11 and HP UEFI firmware/option ROMs).
- **NEVER** tell the user to enable Secure Boot in BIOS or reboot after boot/kernel/initramfs edits unless:
  1. `sudo mkinitcpio -P` exited with code `0`
  2. `lsinitcpio --early <uki>` confirms `GenuineIntel.bin` microcode is embedded (for UKIs)
  3. `sudo sbctl verify` shows **every** active EFI binary and UKI signed (`✓`)

### 5. Live-Session Survival
- **NEVER** run `reboot`, `shutdown`, or restart `Hyprland`, `greetd`, `sddm`, `NetworkManager`, or `iwd` without explicit user approval after reporting verification results.
- Keep `~/linux` synced via Git after each verified milestone.
