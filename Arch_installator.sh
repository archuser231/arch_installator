#!/bin/bash
# Arch_installator.sh - Automated Arch Linux Installer with dialog UI
# Copyright (C) 2025 Thinkpad_ultra7
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

# Automatically remove temporary files on exit
TEMP_FILES=()
trap 'rm -f "${TEMP_FILES[@]}"' EXIT

# Function to create and track temp files
new_temp_file() {
    local tmp
    tmp=$(mktemp)
    TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# Check if dialog is installed
if ! command -v dialog &>/dev/null; then
  echo "'dialog' is not installed, installing..."
  pacman -Sy --noconfirm dialog
fi

### -- 1. Arch version
ARCH_TMP=$(new_temp_file)
dialog --menu "Which version of Arch are you using?" 10 50 2 \
1 "Arch Linux" \
2 "Arch Linux 32" 2> "$ARCH_TMP"

ARCH_CHOICE=$(<"$ARCH_TMP")
if [[ "$ARCH_CHOICE" == "1" ]]; then
    pacman-key --init
    pacman-key --populate archlinux
elif [[ "$ARCH_CHOICE" == "2" ]]; then
    pacman-key --init
    pacman-key --populate archlinux32
else
    dialog --msgbox "Invalid option." 6 30
    exit 1
fi

### -- 2. BIOS or UEFI
BOOTMODE_TMP=$(new_temp_file)
dialog --menu "Are you booting in BIOS or UEFI mode?" 10 50 2 \
1 "UEFI" \
2 "BIOS (Legacy)" 2> "$BOOTMODE_TMP"
BOOTMODE=$(<"$BOOTMODE_TMP")

### -- 3. Disk selection
dialog --infobox "Detecting available disks..." 5 40
sleep 1

lsblk -d -e 7,11 -o NAME,SIZE,TYPE | grep disk | awk '{printf "/dev/%s \"%s\"\n", $1, $2}' > /tmp/disklist.txt
DISK_TMP=$(new_temp_file)
dialog --menu "Select the target disk (ALL DATA WILL BE ERASED):" 20 60 10 $(< /tmp/disklist.txt) 2> "$DISK_TMP"
DEVICE=$(<"$DISK_TMP")

### -- 4. Swap size
SWAP_TMP=$(new_temp_file)
dialog --menu "Choose swap size:" 10 40 3 \
1 "16 GB" \
2 "32 GB" \
3 "64 GB" 2> "$SWAP_TMP"

case $(<"$SWAP_TMP") in
  1) SWAPSIZE="16G" ;;
  2) SWAPSIZE="32G" ;;
  3) SWAPSIZE="64G" ;;
  *) SWAPSIZE="16G" ;;
esac

### -- 5. User info
LAYOUT_TMP=$(new_temp_file)
dialog --inputbox "Keyboard layout (e.g., fr, us, ca):" 8 40 2> "$LAYOUT_TMP"
LAYOUT=$(<"$LAYOUT_TMP")

TIMEZONE_TMP=$(new_temp_file)
dialog --inputbox "Timezone (e.g., America/Toronto):" 8 40 2> "$TIMEZONE_TMP"
TIMEZONE=$(<"$TIMEZONE_TMP")

USERNAME_TMP=$(new_temp_file)
dialog --inputbox "Username:" 8 40 2> "$USERNAME_TMP"
USERNAME=$(<"$USERNAME_TMP")

ROOTPASS_TMP=$(new_temp_file)
dialog --passwordbox "ROOT password:" 8 40 2> "$ROOTPASS_TMP"
ROOTPASS=$(<"$ROOTPASS_TMP")

USERPASS_TMP=$(new_temp_file)
dialog --passwordbox "Password for user $USERNAME:" 8 40 2> "$USERPASS_TMP"
USERPASS=$(<"$USERPASS_TMP")

### -- 6. Wi-Fi credentials
SSID_TMP=$(new_temp_file)
dialog --inputbox "Wi-Fi SSID:" 8 40 2> "$SSID_TMP"
SSID=$(<"$SSID_TMP")

WIFIPASS_TMP=$(new_temp_file)
dialog --passwordbox "Wi-Fi password:" 8 40 2> "$WIFIPASS_TMP"
WIFIPASS=$(<"$WIFIPASS_TMP")

### -- 7. Desktop Environment
DE_TMP=$(new_temp_file)
dialog --menu "Choose your Desktop Environment:" 15 50 5 \
1 "LXDE" \
2 "XFCE" \
3 "MATE" \
4 "KDE Plasma" \
5 "GNOME" 2> "$DE_TMP"

DE_CHOICE=$(<"$DE_TMP")

DE_TYPE_TMP=$(new_temp_file)
dialog --menu "Install full or minimal version?" 10 50 2 \
1 "Full" \
2 "Minimal" 2> "$DE_TYPE_TMP"
DE_TYPE=$(<"$DE_TYPE_TMP")

case "$DE_CHOICE-$DE_TYPE" in
  1-1) DE_PKGS="lxde network-manager-applet gvfs" ;;  # LXDE Full
  1-2) DE_PKGS="lxde" ;;                               # LXDE Minimal
  2-1) DE_PKGS="xfce4 xfce4-goodies network-manager-applet gvfs" ;;  # XFCE Full
  2-2) DE_PKGS="xfce4 network-manager-applet" ;;                   # XFCE Minimal
  3-1) DE_PKGS="mate mate-extra network-manager-applet gvfs" ;;    # MATE Full
  3-2) DE_PKGS="mate network-manager-applet" ;;                    # MATE Minimal
  4-1) DE_PKGS="plasma kde-applications" ;;                        # KDE Full
  4-2) DE_PKGS="plasma" ;;                                         # KDE Minimal
  5-1) DE_PKGS="gnome gnome-extra" ;;                              # GNOME Full
  5-2) DE_PKGS="gnome" ;;                                          # GNOME Minimal
  *) DE_PKGS="lxde network-manager-applet" ;;                      # Fallback
esac


### -- 8. Set temporary keyboard layout
loadkeys "$LAYOUT"

### -- 9. Wi-Fi connection (dynamic device detection)
if command -v iwctl &>/dev/null; then
  WIFIDEV=$(iw dev | awk '$1=="Interface"{print $2; exit}')
  if [[ -n "$WIFIDEV" ]]; then
    iwctl station "$WIFIDEV" connect "$SSID" <<< "$WIFIPASS"
  else
    dialog --msgbox "Error: No wireless interface found!" 8 40
    exit 1
  fi
else
  dialog --msgbox "Error: 'iwctl' not found. Cannot connect to Wi-Fi." 8 40
  exit 1
fi

### -- 10. Auto partitioning
wipefs -a "$DEVICE"
sgdisk -Z "$DEVICE"

if [[ "$BOOTMODE" == "1" ]]; then
    sgdisk -n 1:0:+512M -t 1:ef00 "$DEVICE"
    sgdisk -n 2:0:+"$SWAPSIZE" -t 2:8200 "$DEVICE"
    sgdisk -n 3:0:0 -t 3:8300 "$DEVICE"
    EFI_PART="${DEVICE}1"
    SWAP_PART="${DEVICE}2"
    ROOT_PART="${DEVICE}3"
else
    sgdisk -n 1:0:+"$SWAPSIZE" -t 1:8200 "$DEVICE"
    sgdisk -n 2:0:0 -t 2:8300 "$DEVICE"
    EFI_PART=""
    SWAP_PART="${DEVICE}1"
    ROOT_PART="${DEVICE}2"
fi

partprobe "$DEVICE"
sleep 2

[[ -n "$EFI_PART" ]] && mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

mount "$ROOT_PART" /mnt
if [[ -n "$EFI_PART" ]]; then
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
fi

### -- 11. Base installation
pacstrap /mnt base linux linux-firmware networkmanager sudo vim $DE_PKGS
genfstab -U /mnt >> /mnt/etc/fstab

### -- 12. System configuration inside chroot
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=$LAYOUT" > /etc/vconsole.conf
echo "$USERNAME-PC" > /etc/hostname

cat >> /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $USERNAME-PC.localdomain $USERNAME-PC
EOL

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

echo "root:$ROOTPASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

systemctl enable NetworkManager

# Install and configure GRUB
pacman -Sy --noconfirm grub
if [[ "$BOOTMODE" == "1" ]]; then
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DEVICE"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

### -- 13. Finish
dialog --msgbox " Installation complete! You can now reboot." 10 40

