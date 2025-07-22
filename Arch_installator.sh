#!/bin/bash
set -e

# Nettoyage automatique des fichiers temporaires à la fin
TEMP_FILES=()
trap 'rm -f "${TEMP_FILES[@]}"' EXIT

# Fonction mktemp qui stocke les fichiers pour les supprimer plus tard
new_temp_file() {
    local tmp
    tmp=$(mktemp)
    TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# Vérifier la présence de dialog
if ! command -v dialog &>/dev/null; then
  echo "dialog manquant, installation..."
  pacman -Sy --noconfirm dialog
fi

### -- 1. Arch ou Arch32
ARCH_TMP=$(new_temp_file)
dialog --menu "Quelle version d'Arch utilisez-vous ?" 10 50 2 \
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
    dialog --msgbox "Option invalide." 6 30
    exit 1
fi

### -- 2. BIOS ou UEFI
BOOTMODE_TMP=$(new_temp_file)
dialog --menu "Démarrez-vous en BIOS ou UEFI ?" 10 50 2 \
1 "UEFI" \
2 "BIOS (legacy)" 2> "$BOOTMODE_TMP"
BOOTMODE=$(<"$BOOTMODE_TMP")

### -- 3. Sélection du disque
dialog --infobox "Recherche des disques..." 5 40
sleep 1

lsblk -d -e 7,11 -o NAME,SIZE,TYPE | grep disk | awk '{printf "/dev/%s \"%s\"\n", $1, $2}' > /tmp/disklist.txt
DISK_TMP=$(new_temp_file)
dialog --menu "Sélectionnez le disque à utiliser (TOUT sera effacé) :" 20 60 10 $(< /tmp/disklist.txt) 2> "$DISK_TMP"
DEVICE=$(<"$DISK_TMP")

### -- 4. Taille de swap
SWAP_TMP=$(new_temp_file)
dialog --menu "Taille de la swap ?" 10 40 3 \
1 "16 GB" \
2 "32 GB" \
3 "64 GB" 2> "$SWAP_TMP"

case $(<"$SWAP_TMP") in
  1) SWAPSIZE="16G" ;;
  2) SWAPSIZE="32G" ;;
  3) SWAPSIZE="64G" ;;
  *) SWAPSIZE="16G" ;;
esac

### -- 5. Infos utilisateur
LAYOUT_TMP=$(new_temp_file)
dialog --inputbox "Layout clavier (ex: fr, us, ca):" 8 40 2> "$LAYOUT_TMP"
LAYOUT=$(<"$LAYOUT_TMP")

TIMEZONE_TMP=$(new_temp_file)
dialog --inputbox "Timezone (ex: America/Toronto):" 8 40 2> "$TIMEZONE_TMP"
TIMEZONE=$(<"$TIMEZONE_TMP")

USERNAME_TMP=$(new_temp_file)
dialog --inputbox "Nom d'utilisateur :" 8 40 2> "$USERNAME_TMP"
USERNAME=$(<"$USERNAME_TMP")

ROOTPASS_TMP=$(new_temp_file)
dialog --passwordbox "Mot de passe ROOT :" 8 40 2> "$ROOTPASS_TMP"
ROOTPASS=$(<"$ROOTPASS_TMP")

USERPASS_TMP=$(new_temp_file)
dialog --passwordbox "Mot de passe de $USERNAME :" 8 40 2> "$USERPASS_TMP"
USERPASS=$(<"$USERPASS_TMP")

### -- 6. Wi-Fi
SSID_TMP=$(new_temp_file)
dialog --inputbox "Nom SSID Wi-Fi :" 8 40 2> "$SSID_TMP"
SSID=$(<"$SSID_TMP")

WIFIPASS_TMP=$(new_temp_file)
dialog --passwordbox "Mot de passe Wi-Fi :" 8 40 2> "$WIFIPASS_TMP"
WIFIPASS=$(<"$WIFIPASS_TMP")

### -- 7. Choix du Desktop Environment
DE_TMP=$(new_temp_file)
dialog --menu "Choisissez votre DE" 15 50 5 \
1 "LXDE" \
2 "XFCE" \
3 "MATE" \
4 "KDE Plasma" \
5 "Gnome" 2> "$DE_TMP"

case $(<"$DE_TMP") in
  1) DE_PKGS="lxde network-manager-applet" ;;
  2) DE_PKGS="xfce4 xfce4-goodies network-manager-applet" ;;
  3) DE_PKGS="mate mate-extra network-manager-applet" ;;
  4) DE_PKGS="plasma kde-applications" ;;
  5) DE_PKGS="gnome gnome-extra" ;;
  *) DE_PKGS="lxde network-manager-applet" ;;
esac

### -- 8. Config clavier temporaire
loadkeys "$LAYOUT"

### -- 9. Connexion Wi-Fi
if command -v iwctl &>/dev/null; then
  iwctl station wlan0 connect "$SSID" <<< "$WIFIPASS"
else
  dialog --msgbox "Erreur : 'iwctl' introuvable. Impossible de se connecter au Wi-Fi." 8 40
  exit 1
fi

### -- 10. Partitionnement auto
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

### -- 11. Installation de base
pacstrap /mnt base linux linux-firmware networkmanager sudo vim $DE_PKGS
genfstab -U /mnt >> /mnt/etc/fstab

### -- 12. Configuration
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

# GRUB install
pacman -Sy --noconfirm grub
if [[ "$BOOTMODE" == "1" ]]; then
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DEVICE"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

### -- 13. Fin
dialog --msgbox "✅ Installation complète ! Vous pouvez redémarrer." 10 40
