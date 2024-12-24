#!/bin/bash

set -e

echo "Starting Arch Linux installation script..."

# Step 1: List available disks
echo "Available disks:"
lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme|/dev/vd"

# Step 2: Ask user to choose a disk
read -p "Enter the disk name (e.g., /dev/sda or /dev/nvme0n1): " DISK
if [ ! -b "$DISK" ]; then
    echo "Error: Invalid disk selected. Exiting."
    exit 1
fi

# Confirm user selection
read -p "You selected $DISK. Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Installation aborted."
    exit 1
fi

# Step 3: Number of partitions to create
read -p "Enter the number of partitions (e.g., 2 or 3): " NUM_PARTS
if ! [[ "$NUM_PARTS" =~ ^[2-3]$ ]]; then
    echo "Error: Only 2 or 3 partitions are supported. Exiting."
    exit 1
fi

# Variables for customization
HOSTNAME="archlinux"
ROOT_PASSWORD="root"
TIMEZONE="Region/City" # Replace with your timezone, e.g., Asia/Kolkata

# Update system clock
timedatectl set-ntp true

# Step 4: Partition the disk
echo "Partitioning the disk..."
parted --script $DISK mklabel gpt

if [ "$NUM_PARTS" -eq 2 ]; then
    parted --script $DISK \
        mkpart primary fat32 1MiB 512MiB \
        set 1 esp on \
        mkpart primary ext4 512MiB 100%
elif [ "$NUM_PARTS" -eq 3 ]; then
    parted --script $DISK \
        mkpart primary fat32 1MiB 512MiB \
        set 1 esp on \
        mkpart primary linux-swap 512MiB 4GiB \
        mkpart primary ext4 4GiB 100%
fi

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"
if [ "$NUM_PARTS" -eq 3 ]; then
    mkswap "${DISK}2"
    swapon "${DISK}2"
    mkfs.ext4 "${DISK}3"
    ROOT_PART="${DISK}3"
else
    mkfs.ext4 "${DISK}2"
    ROOT_PART="${DISK}2"
fi

# Mount partitions
echo "Mounting partitions..."
mount $ROOT_PART /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
echo "Entering chroot environment..."
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat <<EOL >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Install essential packages
pacman -S --noconfirm grub efibootmgr networkmanager wireless_tools wpa_supplicant dialog \
    bluez bluez-utils usbutils pciutils iputils net-tools openssh base-devel

# Install drivers
pacman -S --noconfirm iwd dhclient usb_modeswitch modemmanager \
    linux-headers rfkill

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sshd
systemctl enable ModemManager

# Install bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Unmount and reboot
echo "Unmounting and rebooting..."
umount -R /mnt
reboot
