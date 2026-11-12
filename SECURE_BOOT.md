# Phase 1 Runbook: Arch Linux UEFI Secure Boot (`sbctl` + UKI) & Windows 11 Dual-Boot

> Target Hardware: **HP ProBook 440 G7** (dual 512 GB SSDs; Windows 11 BitLocker is disabled).
> Execute each phase sequentially. **Do not skip verification gates.**

---

## Step 1 — Read-Only System Audit (Run First)

Inspect and record the current `archinstall` layout before changing any file:

```bash
lsblk -f
findmnt
df -h / /boot /boot/efi /efi 2>/dev/null || true
efibootmgr -v
bootctl status 2>/dev/null || true
cat /proc/cmdline
grep -E '^(HOOKS|MODULES|FILES)=' /etc/mkinitcpio.conf
ls -la /boot /boot/efi /efi 2>/dev/null || true
ls -la /boot/loader/entries /efi/loader/entries 2>/dev/null || true
pacman -Qs "linux|ucode|grub|systemd|sbctl|refind|snapper"
```

### Audit Checklist (Resolve Before Proceeding)
1. **Identify Disks:** Which SSD is Arch vs. Windows 11? Confirm Arch's ESP is on the Arch SSD (not Windows's 100 MB ESP).
2. **ESP Mount Point (`$ESP`):** Is the ESP mounted at `/boot` (most `archinstall` defaults) or `/efi`?
3. **ESP Capacity:** Check free space in `$ESP`. Need at least ~250–300 MB free (ideally ≥ 512 MB total ESP) for `linux` + `linux-lts` UKIs.
4. **Bootloader:** Did `archinstall` install `systemd-boot` or `grub`?
   - **If `systemd-boot` (recommended):** Keep `systemd-boot` + upgrade to Unified Kernel Images (UKIs). Use HP **F9** at boot to pick Windows 11 (zero cross-disk risk), or optionally add signed `rEFInd` later for a unified menu across both SSDs.
   - **If `grub`:** Either migrate cleanly to `systemd-boot` + UKI (if `$ESP` ≥ 512 MB), or reinstall GRUB with `--modules="tpm ..."` and `--disable-shim-lock` (noting GRUB Secure Boot cannot dynamically load unsigned `.mod` files).

---

## Step 2 — Install Packages & Back Up Boot Config

```bash
mkdir -p ~/arch-backups
sudo cp -a /etc/mkinitcpio.conf /etc/mkinitcpio.d ~/arch-backups/
[ -d /boot/loader ] && sudo cp -a /boot/loader ~/arch-backups/loader-boot || true
[ -d /efi/loader ] && sudo cp -a /efi/loader ~/arch-backups/loader-efi || true

sudo pacman -Syu --needed --noconfirm sbctl intel-ucode linux-lts
```

*(Ensure `sbctl` and `intel-ucode` are installed, plus `linux-lts` as a fallback kernel if `$ESP` has sufficient space — check `df -h` first.)*

---

## Step 3 — Configure Unified Kernel Images (UKIs) with Microcode

> Skip or adapt to GRUB flags only if Step 1 showed GRUB and you explicitly choose to stay on GRUB.

1. **Preserve Exact Kernel Command Line (`/etc/cmdline.d/root.conf`):**
   Read the active `/proc/cmdline` and the existing `options` line in `$ESP/loader/entries/*.conf`.
   Create `/etc/cmdline.d/root.conf` containing the exact `root=UUID=...` and any `rootflags=subvol=...` / `rw` / `quiet` parameters (do **not** copy `initrd=...` or `BOOT_IMAGE=...`).

2. **Ensure Early Microcode Hook in `/etc/mkinitcpio.conf`:**
   Verify `microcode` is in `HOOKS=(...)` (right after `autodetect`):
   ```text
   HOOKS=(base udev autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
   ```
   *(Keep existing hooks such as `btrfs` or `encrypt`/`sd-encrypt` if `archinstall` configured them!)*

3. **Configure UKI Presets (`/etc/mkinitcpio.d/linux.preset` and `linux-lts.preset`):**
   Replace `<ESP>` with the actual mount point (`/boot` or `/efi`):
   ```bash
   sudo mkdir -p <ESP>/EFI/Linux
   ```
   In `/etc/mkinitcpio.d/linux.preset`:
   - Comment out `default_image=...` and `fallback_image=...`
   - Set `default_uki="<ESP>/EFI/Linux/arch-linux.efi"`
   - If `$ESP` ≥ 512 MB, keep `fallback_uki="<ESP>/EFI/Linux/arch-linux-fallback.efi"` or rely on `linux-lts` UKI (`<ESP>/EFI/Linux/arch-linux-lts.efi`) if ESP space is tight (~300–512 MB).
   - Repeat cleanly for `/etc/mkinitcpio.d/linux-lts.preset` → `default_uki="<ESP>/EFI/Linux/arch-linux-lts.efi"`.

4. **Build UKIs & Verify Microcode + Free Space:**
   ```bash
   sudo mkinitcpio -P
   lsinitcpio --early <ESP>/EFI/Linux/arch-linux.efi | grep -i GenuineIntel
   ls -lh <ESP>/EFI/Linux/
   df -h <ESP>
   ```
   Confirm `GenuineIntel.bin` appears and `<ESP>` still has healthy free space (> 100 MB free).

5. **Clean Duplicate Unsigned Loader Entries (Only After UKIs Exist & Verify):**
   Wait until UKIs are generated cleanly. Once `systemd-boot` auto-detects `<ESP>/EFI/Linux/*.efi` (verify with `bootctl list`), remove or archive old plain `loader/entries/*.conf` + old `/boot/initramfs-*.img` **only if** space is needed, or keep `linux-lts` UKI verified before cleaning up.

---

## Step 4 — Put HP ProBook 440 G7 BIOS into Setup Mode (User Manual Step)

Tell the user to reboot into HP BIOS (**Esc → F10** or spam **F10** on power-on):
1. Open **Security** (or **Boot Options**) → **Secure Boot Configuration**.
2. Set Secure Boot to **Disabled** (if enabled).
3. Change Secure Boot key mode from **Standard** to **Custom**.
4. Select **Clear Secure Boot Keys** (or Delete Platform Key / Reset to Setup Mode).
5. **Save & Exit** and boot back into **Arch Linux**.

---

## Step 5 — Create Keys, Enroll (`-m`), Sign All EFI Binaries, Verify

Back in Arch Linux:

1. **Confirm Setup Mode Is Active:**
   ```bash
   sudo sbctl status
   ```
   `Setup Mode` **MUST** show `✓ Enabled` before proceeding. If not, HP BIOS did not clear keys — return to Step 4.

2. **Create & Enroll Keys (WITH Microsoft Keys `-m`):**
   ```bash
   sudo sbctl create-keys
   sudo sbctl enroll-keys -m
   ```
   *(Do **NOT** omit `-m`: Windows 11 and HP UEFI option ROMs require Microsoft certificates.)*

3. **Sign Bootloader + Fallbacks + UKIs (and Save to `sbctl` Database via `-s`):**
   ```bash
   sudo sbctl sign -s <ESP>/EFI/systemd/systemd-bootx64.efi
   [ -f <ESP>/EFI/BOOT/BOOTX64.EFI ] && sudo sbctl sign -s <ESP>/EFI/BOOT/BOOTX64.EFI || true
   for uki in <ESP>/EFI/Linux/*.efi; do
     sudo sbctl sign -s "$uki"
   done
   ```

4. **Install `mkinitcpio` Post-Hook for Manual Rebuilds:**
   Create `/etc/initcpio/post/sbctl` (`chmod +x`) so manual `sudo mkinitcpio -P` runs also sign regenerated UKIs (in addition to `sbctl`'s pacman `zz-sbctl.hook`):
   ```bash
   #!/usr/bin/env bash
   UKI_FILE="$3"
   [[ -n "$UKI_FILE" ]] || exit 0
   if ! sbctl verify "$UKI_FILE" &>/dev/null; then
       sbctl sign -s "$UKI_FILE"
   fi
   ```

5. **Mandatory Pre-Boot Verification Gate:**
   ```bash
   sudo sbctl status
   sudo sbctl verify
   bootctl list
   ```
   - **STOP** if `sbctl verify` shows **any** unsigned file needed for boot (`systemd-bootx64.efi`, `BOOTX64.EFI`, or any `.efi` in `<ESP>/EFI/Linux/`).
   - Do **NOT** touch or re-sign Microsoft's Windows files if Windows lives on a separate ESP; only Arch's ESP binaries need signing by your key.

---

## Step 6 — Enable Secure Boot in HP BIOS & Verify Dual-Boot

Only after `sudo sbctl verify` passes 100%:
1. Ask the user to reboot into **HP BIOS (`F10`)**.
2. Open **Secure Boot Configuration**:
   - Keep mode on **Custom** (do NOT reset to Standard/Factory, or HP wipes your custom keys!).
   - Toggle **Secure Boot** to **Enabled**.
3. Save & Exit → boot into **Arch Linux**.
4. Verify Secure Boot is enforcing in Arch:
   ```bash
   sudo sbctl status
   # Expected: Installed: ✓ Enabled | Setup Mode: ✗ Disabled | Secure Boot: ✓ Enabled
   bootctl status | head -n 20
   ```
5. Reboot and press **F9** (HP Boot Menu) to confirm **Windows Boot Manager** also boots Windows 11 normally with Secure Boot enabled.
