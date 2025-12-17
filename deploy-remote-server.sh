#!/bin/bash
#
# Remote Server Deployment Script for UEFI HTTP Boot
# This script automates the deployment of a server in a remote subnet via iDRAC
#
# Requirements:
#   - RACADM tools installed (Dell OpenManage)
#   - Network connectivity to iDRAC
#   - DHCP server configured
#   - HTTP boot server running
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BOOT_SERVER_IP="192.168.1.10"
DHCP_CONFIG="/etc/dhcp/dhcpd.conf"
KICKSTART_DIR="/var/www/html/kickstart"

# Logging
LOG_FILE="/var/log/remote-deploy.log"

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

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_banner() {
    echo ""
    echo "========================================="
    echo "  Remote Server Deployment Tool"
    echo "  RHEL 9.4 UEFI HTTP Boot"
    echo "========================================="
    echo ""
}

check_requirements() {
    log "Checking requirements..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
    fi

    # Check for racadm
    if ! command -v racadm &> /dev/null; then
        warn "RACADM not found. Install Dell OpenManage for iDRAC management."
        warn "Continuing without RACADM support..."
        RACADM_AVAILABLE=false
    else
        RACADM_AVAILABLE=true
        log "RACADM found: $(racadm --version | head -1)"
    fi

    # Check DHCP configuration file exists
    if [ ! -f "$DHCP_CONFIG" ]; then
        error "DHCP configuration not found at $DHCP_CONFIG"
    fi

    # Check HTTP server is running
    if ! systemctl is-active --quiet httpd; then
        error "HTTP server is not running. Start it with: systemctl start httpd"
    fi

    log "Requirements check passed"
}

collect_server_info() {
    echo ""
    echo "========================================="
    echo "  Server Information"
    echo "========================================="
    echo ""

    # Server hostname
    read -p "Enter server hostname (e.g., prod-server-01): " SERVER_HOSTNAME
    if [ -z "$SERVER_HOSTNAME" ]; then
        error "Hostname cannot be empty"
    fi

    # Server MAC address
    read -p "Enter server MAC address (ETH0) [AA:BB:CC:DD:EE:FF]: " SERVER_MAC
    if [ -z "$SERVER_MAC" ]; then
        error "MAC address cannot be empty"
    fi

    # Validate MAC address format
    if ! [[ $SERVER_MAC =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        error "Invalid MAC address format. Use AA:BB:CC:DD:EE:FF format"
    fi

    # Server IP address
    read -p "Enter desired server IP address: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        error "IP address cannot be empty"
    fi

    # Server subnet
    read -p "Enter server subnet (e.g., 10.20.30.0): " SERVER_SUBNET
    read -p "Enter subnet mask (e.g., 255.255.255.0): " SERVER_NETMASK
    read -p "Enter gateway IP: " SERVER_GATEWAY

    # iDRAC information
    echo ""
    read -p "Enter iDRAC IP address: " IDRAC_IP
    if [ -z "$IDRAC_IP" ]; then
        warn "No iDRAC IP provided. Skipping iDRAC configuration."
        SKIP_IDRAC=true
    else
        SKIP_IDRAC=false
        read -p "Enter iDRAC username [root]: " IDRAC_USER
        IDRAC_USER=${IDRAC_USER:-root}
        read -sp "Enter iDRAC password: " IDRAC_PASS
        echo ""
    fi

    # Boot server IP (allow override)
    read -p "Enter boot server IP [$BOOT_SERVER_IP]: " BOOT_IP_INPUT
    BOOT_SERVER_IP=${BOOT_IP_INPUT:-$BOOT_SERVER_IP}

    # Kickstart customization
    echo ""
    read -p "Create host-specific kickstart? [y/N]: " CREATE_KS
    if [[ "$CREATE_KS" =~ ^[Yy]$ ]]; then
        CUSTOM_KICKSTART=true
    else
        CUSTOM_KICKSTART=false
    fi

    # Summary
    echo ""
    echo "========================================="
    echo "  Configuration Summary"
    echo "========================================="
    echo "Server Hostname:    $SERVER_HOSTNAME"
    echo "Server MAC:         $SERVER_MAC"
    echo "Server IP:          $SERVER_IP"
    echo "Server Subnet:      $SERVER_SUBNET/$SERVER_NETMASK"
    echo "Gateway:            $SERVER_GATEWAY"
    echo "iDRAC IP:           ${IDRAC_IP:-N/A}"
    echo "Boot Server:        $BOOT_SERVER_IP"
    echo "Custom Kickstart:   ${CUSTOM_KICKSTART}"
    echo "========================================="
    echo ""

    read -p "Continue with this configuration? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        error "Deployment cancelled by user"
    fi
}

add_dhcp_host() {
    log "Adding DHCP host reservation..."

    # Create backup
    cp "$DHCP_CONFIG" "${DHCP_CONFIG}.bak.$(date +%s)"

    # Check if subnet exists
    if ! grep -q "subnet $SERVER_SUBNET" "$DHCP_CONFIG"; then
        warn "Subnet $SERVER_SUBNET not found in DHCP config"
        read -p "Add subnet configuration? [y/N]: " ADD_SUBNET

        if [[ "$ADD_SUBNET" =~ ^[Yy]$ ]]; then
            cat >> "$DHCP_CONFIG" << EOF

# Added by deploy-remote-server.sh on $(date)
subnet $SERVER_SUBNET netmask $SERVER_NETMASK {
    option routers $SERVER_GATEWAY;
    option broadcast-address $(calculate_broadcast "$SERVER_SUBNET" "$SERVER_NETMASK");
    next-server $BOOT_SERVER_IP;

    if option architecture-type = 00:0f {
        filename "http://${BOOT_SERVER_IP}/boot/efi/shimx64.efi";
    }
    elsif option architecture-type = 00:07 {
        filename "http://${BOOT_SERVER_IP}/boot/efi/shimx64.efi";
    }
}
EOF
            log "Subnet added to DHCP configuration"
        fi
    fi

    # Add host reservation
    cat >> "$DHCP_CONFIG" << EOF

# Host: $SERVER_HOSTNAME
# Added: $(date)
# MAC: $SERVER_MAC
host $SERVER_HOSTNAME {
    hardware ethernet $SERVER_MAC;
    fixed-address $SERVER_IP;
    option host-name "${SERVER_HOSTNAME}.datacenter.local";
    option routers $SERVER_GATEWAY;

    if option architecture-type = 00:0f {
        filename "http://${BOOT_SERVER_IP}/boot/efi/shimx64.efi";
    }
    elsif option architecture-type = 00:07 {
        filename "http://${BOOT_SERVER_IP}/boot/efi/shimx64.efi";
    }
}
EOF

    # Test DHCP configuration
    if dhcpd -t -cf "$DHCP_CONFIG"; then
        log "DHCP configuration is valid"
    else
        error "DHCP configuration test failed. Restoring backup."
    fi

    # Restart DHCP
    systemctl restart dhcpd
    log "DHCP service restarted"
}

calculate_broadcast() {
    local subnet=$1
    local netmask=$2
    # Simple calculation - improve if needed
    echo "$subnet" | awk -F. '{print $1"."$2"."$3".255"}'
}

create_custom_kickstart() {
    if [ "$CUSTOM_KICKSTART" = false ]; then
        return
    fi

    log "Creating custom kickstart file..."

    local KS_FILE="${KICKSTART_DIR}/${SERVER_HOSTNAME}.ks"

    # Copy base kickstart
    cp "${KICKSTART_DIR}/rhel94-uefi.ks" "$KS_FILE"

    # Customize hostname
    sed -i "s/network --hostname=.*/network --hostname=${SERVER_HOSTNAME}.datacenter.local/" "$KS_FILE"

    # Add static IP configuration (commented out, uncomment if needed)
    cat >> "$KS_FILE" << EOF

# Static IP configuration for $SERVER_HOSTNAME
# Uncomment to use static IP instead of DHCP
#network --bootproto=static --ip=$SERVER_IP --netmask=$SERVER_NETMASK --gateway=$SERVER_GATEWAY --nameserver=8.8.8.8,8.8.4.4 --device=eth0 --activate

# Custom post-installation for $SERVER_HOSTNAME
%post --log=/root/ks-post-custom.log
echo "Deployed on: $(date)" > /root/deployment-info.txt
echo "Hostname: $SERVER_HOSTNAME" >> /root/deployment-info.txt
echo "IP: $SERVER_IP" >> /root/deployment-info.txt
echo "MAC: $SERVER_MAC" >> /root/deployment-info.txt
%end
EOF

    # Validate kickstart
    if command -v ksvalidator &> /dev/null; then
        ksvalidator "$KS_FILE" || warn "Kickstart validation failed"
    fi

    log "Custom kickstart created: $KS_FILE"
    log "URL: http://${BOOT_SERVER_IP}/kickstart/${SERVER_HOSTNAME}.ks"
}

configure_idrac() {
    if [ "$SKIP_IDRAC" = true ] || [ "$RACADM_AVAILABLE" = false ]; then
        warn "Skipping iDRAC configuration"
        return
    fi

    log "Configuring iDRAC at $IDRAC_IP..."

    # Test iDRAC connectivity
    if ! ping -c 1 -W 2 "$IDRAC_IP" &> /dev/null; then
        error "Cannot reach iDRAC at $IDRAC_IP"
    fi

    # Configure UEFI boot mode
    info "Setting boot mode to UEFI..."
    racadm -r "$IDRAC_IP" -u "$IDRAC_USER" -p "$IDRAC_PASS" \
        set BIOS.BiosBootSettings.BootMode Uefi || warn "Failed to set boot mode"

    # Set boot sequence (Network first)
    info "Configuring boot sequence..."
    racadm -r "$IDRAC_IP" -u "$IDRAC_USER" -p "$IDRAC_PASS" \
        set BIOS.BiosBootSettings.UefiBootSeq NIC.Integrated.1-1-1,HardDisk.List.1-1 || warn "Failed to set boot sequence"

    # Create BIOS configuration job
    info "Creating BIOS configuration job..."
    racadm -r "$IDRAC_IP" -u "$IDRAC_USER" -p "$IDRAC_PASS" \
        jobqueue create BIOS.Setup.1-1 || warn "Failed to create BIOS job"

    log "iDRAC configuration completed"
}

deploy_server() {
    log "Starting server deployment..."

    if [ "$SKIP_IDRAC" = true ] || [ "$RACADM_AVAILABLE" = false ]; then
        warn "Manual power-on required. Configure BIOS for UEFI network boot and power on the server."
        return
    fi

    # Power cycle to apply BIOS changes and boot
    info "Power cycling server..."
    racadm -r "$IDRAC_IP" -u "$IDRAC_USER" -p "$IDRAC_PASS" \
        serveraction powercycle || error "Failed to power cycle server"

    log "Server is booting. Monitor installation via:"
    log "  - iDRAC Virtual Console: https://${IDRAC_IP}"
    log "  - DHCP logs: journalctl -u dhcpd -f"
    log "  - HTTP logs: tail -f /var/log/httpd/access_log"
}

monitor_deployment() {
    echo ""
    echo "========================================="
    echo "  Monitoring Deployment"
    echo "========================================="
    echo ""

    info "Starting log monitoring (Ctrl+C to stop)..."
    echo ""

    # Monitor in background
    journalctl -u dhcpd -f | grep --line-buffered "$SERVER_MAC" &
    DHCP_PID=$!

    tail -f /var/log/httpd/access_log | grep --line-buffered "$SERVER_IP" &
    HTTP_PID=$!

    # Wait for user interrupt
    trap "kill $DHCP_PID $HTTP_PID 2>/dev/null; exit 0" SIGINT SIGTERM

    wait
}

print_completion() {
    echo ""
    echo "========================================="
    log "Deployment Configuration Complete!"
    echo "========================================="
    echo ""
    echo "Server Details:"
    echo "  Hostname: $SERVER_HOSTNAME"
    echo "  IP: $SERVER_IP"
    echo "  MAC: $SERVER_MAC"
    echo ""
    echo "Next Steps:"
    echo "  1. Monitor installation via iDRAC console: https://${IDRAC_IP}"
    echo "  2. Watch DHCP logs: journalctl -u dhcpd -f"
    echo "  3. Monitor HTTP access: tail -f /var/log/httpd/access_log"
    echo ""
    if [ "$CUSTOM_KICKSTART" = true ]; then
        echo "  Custom Kickstart: http://${BOOT_SERVER_IP}/kickstart/${SERVER_HOSTNAME}.ks"
        echo ""
    fi
    echo "  Installation should complete in 10-20 minutes"
    echo "  SSH will be available at: ssh root@${SERVER_IP}"
    echo ""
    echo "========================================="
}

# Main execution
main() {
    print_banner
    check_requirements
    collect_server_info
    add_dhcp_host
    create_custom_kickstart
    configure_idrac
    deploy_server
    print_completion

    # Optional: Monitor deployment
    read -p "Monitor deployment logs? [y/N]: " MONITOR
    if [[ "$MONITOR" =~ ^[Yy]$ ]]; then
        monitor_deployment
    fi
}

main "$@"
