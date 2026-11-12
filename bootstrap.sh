#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (with sudo), not root."
  exit 1
fi

echo "==> 1. Checking internet connectivity..."
sudo rfkill unblock wifi || true
if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
  if command -v nmcli >/dev/null 2>&1; then
    sudo systemctl enable --now NetworkManager
    sleep 2
    nmcli -f SSID,SIGNAL,SECURITY device wifi list || true
    read -rp "Wi-Fi SSID: " WIFI_SSID
    read -rsp "Wi-Fi Password: " WIFI_PASS; echo
    sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"
  elif command -v iwctl >/dev/null 2>&1; then
    sudo systemctl enable --now iwd
    sleep 2
    IFACE="$(ls /sys/class/net | grep -E '^wl' | head -n1 || true)"
    [ -n "$IFACE" ] || { echo "No wireless interface found."; exit 1; }
    iwctl station "$IFACE" scan || true
    iwctl station "$IFACE" get-networks || true
    read -rp "Wi-Fi SSID: " WIFI_SSID
    iwctl station "$IFACE" connect "$WIFI_SSID"
    sleep 3
  else
    echo "Neither nmcli nor iwctl found. Connect Ethernet or install NetworkManager first."
    exit 1
  fi
fi

ping -c1 -W3 archlinux.org >/dev/null 2>&1 || {
  echo "Still offline (check IP/DNS with 'ip a'). Aborting."
  exit 1
}

echo "==> 2. Updating system & installing minimal Hyprland + Intel + Browser + CLI stack..."
sudo pacman -Syu --needed --noconfirm \
  curl git base-devel ripgrep fd jq unzip wl-clipboard \
  networkmanager \
  mesa vulkan-intel intel-media-driver \
  hyprland kitty fuzzel xorg-xwayland \
  xdg-utils xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  gnome-keyring libsecret \
  firefox noto-fonts ttf-dejavu ttf-jetbrains-mono-nerd \
  pipewire pipewire-pulse wireplumber brightnessctl

# Keep existing active iwd running if it got us online; otherwise ensure NetworkManager is enabled
if ! systemctl is-active --quiet iwd.service; then
  sudo systemctl enable --now NetworkManager
fi

echo "==> 3. Installing Google Antigravity CLI (agy)..."
if ! command -v agy >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/agy" ]; then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi

export PATH="$HOME/.local/bin:$PATH"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -qF '.local/bin' "$rc"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  fi
done
[ -f "$HOME/.bashrc" ] || printf 'export PATH="$HOME/.local/bin:$PATH"\n' > "$HOME/.bashrc"

echo "==> 4. Writing minimal Hyprland config (backing up existing if present)..."
mkdir -p "$HOME/.config/hypr"
if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
  cp "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf.bak.$(date +%s)"
fi

cat <<'EOF' > "$HOME/.config/hypr/hyprland.conf"
monitor=,preferred,auto,auto

$mainMod = SUPER
$terminal = kitty
$browser = firefox
$menu = fuzzel

# Critical so agy's OAuth link opens Firefox via xdg-open + portals
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = $terminal

env = XCURSOR_SIZE,24
env = MOZ_ENABLE_WAYLAND,1

general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgba(89b4faee)
    col.inactive_border = rgba(45475aaa)
    layout = dwindle
}

input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = true
        tap-to-click = true
    }
}

bind = $mainMod, Return, exec, $terminal
bind = $mainMod, Q, exec, $terminal
bind = $mainMod, B, exec, $browser
bind = $mainMod, D, exec, $menu
bind = $mainMod, R, exec, $menu
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, V, togglefloating,

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4

bindel = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
EOF

echo "==> 5. Setting Firefox as default handler for OAuth links..."
xdg-mime default firefox.desktop x-scheme-handler/http x-scheme-handler/https text/html || true

echo ""
echo "Done! Launching Hyprland (kitty will auto-open; run 'agy' inside it to sign in)..."
sleep 2

if command -v start-hyprland >/dev/null 2>&1; then
  exec start-hyprland
else
  exec Hyprland
fi
