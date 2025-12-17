#!/bin/bash
#
# UEFI HTTP Boot Server Setup Script for RHEL 9.4
# This script sets up an HTTP server for UEFI network boot with kickstart
#
# Requirements:
#   - RHEL/CentOS/Rocky Linux server
#   - Root privileges
#   - RHEL 9.4 ISO mounted or extracted
#   - Network connectivity
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
HTTP_ROOT="/var/www/html"
BOOT_DIR="${HTTP_ROOT}/boot"
RHEL_DIR="${HTTP_ROOT}/rhel94"
KICKSTART_DIR="${HTTP_ROOT}/kickstart"
ISO_MOUNT="/mnt/rhel94-iso"

# Server IP (will be detected or set manually)
SERVER_IP=""

# Logging
LOG_FILE="/var/log/httpboot-setup.log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
    fi
}

detect_server_ip() {
    log "Detecting server IP address..."
    SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    if [ -z "$SERVER_IP" ]; then
        warn "Could not auto-detect server IP"
        read -p "Enter server IP address: " SERVER_IP
    fi
    log "Using server IP: $SERVER_IP"
}

install_packages() {
    log "Installing required packages..."
    dnf install -y httpd tftp-server dhcp-server syslinux shim-x64 grub2-efi-x64 || \
        error "Failed to install required packages"
    log "Packages installed successfully"
}

setup_http_server() {
    log "Configuring HTTP server..."

    # Create directory structure
    mkdir -p "$BOOT_DIR"/{grub2,efi}
    mkdir -p "$RHEL_DIR"/{BaseOS,AppStream}
    mkdir -p "$KICKSTART_DIR"

    # Set permissions
    chown -R apache:apache "$HTTP_ROOT"
    chmod -R 755 "$HTTP_ROOT"

    # Configure Apache
    cat > /etc/httpd/conf.d/httpboot.conf << EOF
# UEFI HTTP Boot Configuration
Alias /boot ${BOOT_DIR}
Alias /rhel94 ${RHEL_DIR}
Alias /kickstart ${KICKSTART_DIR}

<Directory ${BOOT_DIR}>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory ${RHEL_DIR}>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory ${KICKSTART_DIR}>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

    # Enable and start httpd
    systemctl enable httpd
    systemctl restart httpd

    # Configure firewall
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=dhcp
    firewall-cmd --reload

    log "HTTP server configured successfully"
}

setup_uefi_boot_files() {
    log "Setting up UEFI boot files..."

    # Copy UEFI boot files
    if [ -f /boot/efi/EFI/redhat/shimx64.efi ]; then
        cp /boot/efi/EFI/redhat/shimx64.efi "${BOOT_DIR}/efi/" || \
            warn "Failed to copy shimx64.efi from /boot/efi"
    elif [ -f /usr/share/shim/shimx64.efi ]; then
        cp /usr/share/shim/shimx64.efi "${BOOT_DIR}/efi/"
    else
        warn "shimx64.efi not found, trying package installation..."
        cp /boot/efi/EFI/*/shimx64.efi "${BOOT_DIR}/efi/" 2>/dev/null || \
            error "Could not find shimx64.efi"
    fi

    if [ -f /boot/efi/EFI/redhat/grubx64.efi ]; then
        cp /boot/efi/EFI/redhat/grubx64.efi "${BOOT_DIR}/efi/" || \
            warn "Failed to copy grubx64.efi from /boot/efi"
    elif [ -f /usr/share/grub2-efi/grubx64.efi ]; then
        cp /usr/share/grub2-efi/grubx64.efi "${BOOT_DIR}/efi/"
    else
        warn "grubx64.efi not found, trying alternative locations..."
        find /boot/efi -name "grubx64.efi" -exec cp {} "${BOOT_DIR}/efi/" \; 2>/dev/null || \
            error "Could not find grubx64.efi"
    fi

    log "UEFI boot files copied successfully"
}

copy_rhel_iso() {
    log "Looking for RHEL 9.4 ISO..."

    # Check if ISO is already mounted
    if mountpoint -q "$ISO_MOUNT"; then
        log "ISO already mounted at $ISO_MOUNT"
    else
        # Look for ISO file
        ISO_FILE=$(find /root /home /tmp -name "*rhel*9.4*.iso" -o -name "*rhel-9.4*.iso" 2>/dev/null | head -n 1)

        if [ -z "$ISO_FILE" ]; then
            warn "RHEL 9.4 ISO not found automatically"
            read -p "Enter path to RHEL 9.4 ISO file (or press Enter to skip): " ISO_FILE

            if [ -z "$ISO_FILE" ]; then
                warn "Skipping ISO copy. You'll need to manually copy files to $RHEL_DIR"
                return
            fi
        fi

        # Mount ISO
        mkdir -p "$ISO_MOUNT"
        mount -o loop "$ISO_FILE" "$ISO_MOUNT" || error "Failed to mount ISO"
        log "ISO mounted at $ISO_MOUNT"
    fi

    # Copy ISO contents
    log "Copying ISO contents (this may take a while)..."
    rsync -av --progress "$ISO_MOUNT/" "$RHEL_DIR/" || error "Failed to copy ISO contents"

    # Unmount ISO
    umount "$ISO_MOUNT" 2>/dev/null || true

    log "ISO contents copied successfully"
}

create_grub_config() {
    log "Creating GRUB configuration..."

    cat > "${BOOT_DIR}/grub2/grub.cfg" << EOF
set timeout=10
set default=0

menuentry 'Install RHEL 9.4 via HTTP Boot (UEFI)' {
    linuxefi (http,${SERVER_IP})/rhel94/images/pxeboot/vmlinuz inst.repo=http://${SERVER_IP}/rhel94 inst.ks=http://${SERVER_IP}/kickstart/rhel94-uefi.ks ip=dhcp
    initrdefi (http,${SERVER_IP})/rhel94/images/pxeboot/initrd.img
}

menuentry 'Install RHEL 9.4 via HTTP Boot (UEFI) - Manual' {
    linuxefi (http,${SERVER_IP})/rhel94/images/pxeboot/vmlinuz inst.repo=http://${SERVER_IP}/rhel94 ip=dhcp
    initrdefi (http,${SERVER_IP})/rhel94/images/pxeboot/initrd.img
}

menuentry 'Boot from local disk' {
    exit
}
EOF

    log "GRUB configuration created"
}

copy_kickstart() {
    log "Copying kickstart file..."

    if [ -f "./rhel94-uefi.ks" ]; then
        cp ./rhel94-uefi.ks "$KICKSTART_DIR/"

        # Update kickstart file with actual server IP
        sed -i "s|YOUR_HTTP_SERVER|${SERVER_IP}|g" "${KICKSTART_DIR}/rhel94-uefi.ks"

        log "Kickstart file copied and configured"
    else
        warn "Kickstart file not found in current directory"
        warn "Please manually copy rhel94-uefi.ks to $KICKSTART_DIR"
    fi
}

setup_dhcp() {
    log "Setting up DHCP configuration example..."

    cat > /etc/dhcp/dhcpd.conf.httpboot-example << EOF
# DHCP configuration for UEFI HTTP Boot
# Copy this to /etc/dhcp/dhcpd.conf and adjust for your network

option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option domain-name "example.local";

    class "pxeclients" {
        match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    }

    # UEFI HTTP Boot
    if option architecture-type = 00:0f {
        filename "http://${SERVER_IP}/boot/efi/shimx64.efi";
    }
    # UEFI PXE
    elsif option architecture-type = 00:07 {
        filename "shimx64.efi";
    }
    # BIOS PXE
    else {
        filename "pxelinux.0";
    }

    next-server ${SERVER_IP};
}
EOF

    log "DHCP example configuration created at /etc/dhcp/dhcpd.conf.httpboot-example"
    warn "Please review and configure DHCP according to your network setup"
}

print_summary() {
    echo ""
    echo "========================================="
    log "UEFI HTTP Boot Server Setup Complete!"
    echo "========================================="
    echo ""
    echo "Server Configuration:"
    echo "  - Server IP: $SERVER_IP"
    echo "  - HTTP Root: $HTTP_ROOT"
    echo "  - Boot Files: $BOOT_DIR"
    echo "  - RHEL Files: $RHEL_DIR"
    echo "  - Kickstart: $KICKSTART_DIR"
    echo ""
    echo "Boot URLs:"
    echo "  - UEFI Boot: http://${SERVER_IP}/boot/efi/shimx64.efi"
    echo "  - Kickstart: http://${SERVER_IP}/kickstart/rhel94-uefi.ks"
    echo ""
    echo "Next Steps:"
    echo "  1. Review and configure DHCP (/etc/dhcp/dhcpd.conf.httpboot-example)"
    echo "  2. Update kickstart file if needed (${KICKSTART_DIR}/rhel94-uefi.ks)"
    echo "  3. Verify HTTP server is accessible: http://${SERVER_IP}"
    echo "  4. Test boot from a UEFI-enabled client"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "========================================="
}

# Main execution
main() {
    log "Starting UEFI HTTP Boot Server setup..."

    check_root
    detect_server_ip
    install_packages
    setup_http_server
    setup_uefi_boot_files
    copy_rhel_iso
    create_grub_config
    copy_kickstart
    setup_dhcp
    print_summary
}

main "$@"
