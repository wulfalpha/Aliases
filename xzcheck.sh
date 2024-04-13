#!/bin/bash

# Check for systemd-boot
if [ -d "/boot/EFI/systemd" ] || [ -d "/efi/EFI/systemd" ]; then
    echo "systemd-boot is installed."
else
    echo "systemd-boot is not installed."
fi

# Check for GRUB
if [ -f "/boot/grub/grub.cfg" ] || [ -f "/etc/default/grub" ]; then
    echo "GRUB is installed."
else
    echo "GRUB is not installed."
fi

# Check xz version
xz_version=$(xz --version | head -n1 | awk '{print $4}')
echo "xz version: $xz_version"

# Check for CVE-2024-3094 vulnerability
if [[ "$xz_version" == "5.6.0" || "$xz_version" == "5.6.1" ]]; then
    echo "WARNING: Your xz version is vulnerable to CVE-2024-3094. Please downgrade to a safe version."
else
    echo "Your xz version is not directly vulnerable to CVE-2024-3094. Check for distribution-specific advisories."
fi

