# RHEL 9.4 UEFI HTTP Boot with Kickstart

This repository provides a complete solution for deploying RHEL 9.4 systems via UEFI HTTP Boot with automated kickstart installation.

## Overview

UEFI HTTP Boot allows network booting of systems using HTTP/HTTPS protocols instead of traditional TFTP. This provides:

- Faster boot times compared to TFTP
- More reliable file transfers
- Easier firewall configuration (standard HTTP ports)
- Better scalability for large deployments
- Support for modern UEFI firmware

## Components

This repository includes:

### Core Components

- **rhel94-uefi.ks** - Kickstart configuration file for automated RHEL 9.4 installation
- **setup-httpboot-server.sh** - Automated setup script for HTTP boot server
- **grub.cfg.example** - GRUB2 configuration for boot menu
- **dhcpd.conf.example** - DHCP server configuration example

### Remote Deployment Components

- **dhcpd-remote-subnet.conf.example** - DHCP configuration for remote subnets with MAC reservations
- **deploy-remote-server.sh** - Automated deployment script for remote servers
- **IDRAC-DEPLOYMENT.md** - Complete guide for deploying via Dell iDRAC to remote subnets

**See [IDRAC-DEPLOYMENT.md](IDRAC-DEPLOYMENT.md) for deploying to servers in different subnets using iDRAC management.**

## Prerequisites

### Server Requirements

- RHEL/CentOS/Rocky Linux 8 or 9 (for the boot server)
- Root/sudo access
- Minimum 20GB disk space
- Network interface configured
- RHEL 9.4 ISO file

### Client Requirements

- UEFI firmware (not legacy BIOS)
- UEFI HTTP Boot support
- Network interface with PXE/HTTP boot capability
- Minimum 2GB RAM
- Minimum 20GB disk space

## Quick Start

### 1. Setup HTTP Boot Server

```bash
# Clone or download this repository
cd image_builder

# Make the setup script executable
chmod +x setup-httpboot-server.sh

# Run the setup script as root
sudo ./setup-httpboot-server.sh
```

The script will:
- Install required packages (httpd, dhcp-server, etc.)
- Configure Apache HTTP server
- Copy UEFI boot files
- Extract RHEL 9.4 ISO contents
- Create GRUB configuration
- Copy and configure kickstart file
- Generate DHCP configuration example
- Configure firewall rules

### 2. Configure DHCP Server

```bash
# Review the DHCP configuration example
cat /etc/dhcp/dhcpd.conf.httpboot-example

# Update with your network settings
sudo vi /etc/dhcp/dhcpd.conf.httpboot-example

# Replace YOUR_SERVER_IP with your actual server IP address
sudo sed -i 's/YOUR_SERVER_IP/192.168.1.10/g' /etc/dhcp/dhcpd.conf.httpboot-example

# Copy to active DHCP configuration
sudo cp /etc/dhcp/dhcpd.conf.httpboot-example /etc/dhcp/dhcpd.conf

# Enable and start DHCP service
sudo systemctl enable dhcpd
sudo systemctl start dhcpd
```

### 3. Customize Kickstart File (Optional)

The kickstart file is located at `/var/www/html/kickstart/rhel94-uefi.ks` after running the setup script.

```bash
# Edit the kickstart file
sudo vi /var/www/html/kickstart/rhel94-uefi.ks
```

Important customization options:

- **Root password**: Change the default password hash
- **Timezone**: Update timezone setting
- **Partitioning**: Modify disk layout as needed
- **Packages**: Add or remove packages
- **Network**: Configure hostname and network settings
- **Post-installation**: Add custom scripts

#### Generate New Root Password Hash

```bash
python3 -c 'import crypt; print(crypt.crypt("YourNewPassword", crypt.mksalt(crypt.METHOD_SHA512)))'
```

Copy the output and replace the existing hash in the kickstart file.

### 4. Boot Client System

1. Power on the client system
2. Enter BIOS/UEFI firmware settings (usually F2, F12, or DEL)
3. Enable UEFI Network Boot or HTTP Boot
4. Set boot order to prioritize network boot
5. Save and exit
6. System will boot from network and display GRUB menu
7. Select installation option
8. Installation will proceed automatically with kickstart

## Remote Subnet Deployment (iDRAC)

For deploying to servers in different subnets using Dell iDRAC:

### Quick Remote Deployment

```bash
# 1. Run the automated deployment script
sudo ./deploy-remote-server.sh

# The script will prompt you for:
# - Server hostname
# - MAC address (ETH0)
# - Desired IP address
# - Subnet information
# - iDRAC IP and credentials

# 2. Script automatically:
# - Adds DHCP reservation
# - Configures iDRAC for UEFI network boot
# - Creates custom kickstart (optional)
# - Powers on the server
```

### Manual Remote Deployment

If you prefer manual configuration:

1. **Configure DHCP for remote subnet:**
   ```bash
   # Use the remote subnet template
   cp dhcpd-remote-subnet.conf.example /etc/dhcp/dhcpd.conf

   # Add host reservation with your server's MAC address
   # Edit subnet configuration for your network
   vi /etc/dhcp/dhcpd.conf

   systemctl restart dhcpd
   ```

2. **Configure iDRAC for network boot:**
   ```bash
   # Set UEFI boot mode and network boot priority
   racadm -r IDRAC_IP -u root -p password set BIOS.BiosBootSettings.BootMode Uefi
   racadm -r IDRAC_IP -u root -p password jobqueue create BIOS.Setup.1-1
   racadm -r IDRAC_IP -u root -p password serveraction powercycle
   ```

3. **Monitor deployment:**
   ```bash
   # Watch DHCP requests
   journalctl -u dhcpd -f

   # Monitor HTTP access
   tail -f /var/log/httpd/access_log
   ```

**For complete remote deployment documentation, see [IDRAC-DEPLOYMENT.md](IDRAC-DEPLOYMENT.md)**

## Directory Structure

After running the setup script:

```
/var/www/html/
├── boot/
│   ├── efi/
│   │   ├── shimx64.efi       # UEFI boot loader
│   │   └── grubx64.efi       # GRUB2 EFI binary
│   └── grub2/
│       └── grub.cfg          # GRUB configuration
├── rhel94/
│   ├── BaseOS/               # Base OS repository
│   ├── AppStream/            # Application Stream repository
│   └── images/
│       └── pxeboot/
│           ├── vmlinuz       # Kernel
│           └── initrd.img    # Initial RAM disk
└── kickstart/
    └── rhel94-uefi.ks        # Kickstart file
```

## Configuration Details

### GRUB Boot Menu Options

The GRUB configuration provides several boot options:

1. **Automated Installation with Kickstart** - Fully automated installation
2. **Manual Installation** - Manual installation via text interface
3. **Graphical Installation** - Graphical installer with kickstart
4. **VNC Installation** - Remote installation via VNC
5. **Rescue Mode** - System recovery mode
6. **Boot from local disk** - Skip network boot
7. **Reboot** - Restart the system
8. **Firmware Setup** - Enter UEFI settings

### Kickstart Configuration Features

The provided kickstart file includes:

- UEFI boot configuration
- LVM-based partitioning
- SELinux enabled (enforcing mode)
- Firewall enabled with SSH access
- Minimal package installation
- Network configuration via DHCP
- Post-installation scripts
- System hardening settings

### DHCP Architecture Types

The DHCP configuration supports multiple architecture types:

- `00:0f` (15) - UEFI HTTP Boot (x86_64)
- `00:07` (7) - UEFI PXE Boot (x86_64)
- `00:09` (9) - UEFI PXE Boot (x86_64 alternative)
- `00:00` (0) - Legacy BIOS PXE Boot

## Troubleshooting

### Client Cannot Boot from Network

1. Verify UEFI HTTP Boot is enabled in firmware settings
2. Check network cable connection
3. Verify DHCP server is running: `systemctl status dhcpd`
4. Check DHCP logs: `journalctl -u dhcpd -f`

### HTTP Server Issues

```bash
# Check Apache status
systemctl status httpd

# View Apache logs
tail -f /var/log/httpd/access_log
tail -f /var/log/httpd/error_log

# Verify files are accessible
curl http://YOUR_SERVER_IP/boot/efi/shimx64.efi -I
```

### Kickstart Not Loading

1. Verify kickstart file path in GRUB configuration
2. Check kickstart file syntax: `ksvalidator /var/www/html/kickstart/rhel94-uefi.ks`
3. Ensure HTTP server can serve the kickstart file
4. Check firewall allows HTTP traffic: `firewall-cmd --list-all`

### Boot Hangs or Fails

1. Check GRUB configuration syntax
2. Verify kernel and initrd paths are correct
3. Review installation logs on client (Ctrl+Alt+F3 during installation)
4. Check DHCP offers correct boot file

### Network Configuration Issues

```bash
# Verify network interface is configured
ip addr show

# Check routing
ip route

# Test connectivity to HTTP server
ping YOUR_SERVER_IP

# Verify DHCP is listening
netstat -ulnp | grep dhcpd
```

## Advanced Configuration

### Using Custom Partitioning

Edit the kickstart file to customize disk layout:

```bash
# Example: Different LVM layout
part /boot/efi --fstype=efi --size=600
part /boot --fstype=xfs --size=1024
part pv.01 --size=1 --grow

volgroup vg_system pv.01
logvol / --vgname=vg_system --size=20480 --name=lv_root
logvol /var --vgname=vg_system --size=10240 --name=lv_var
logvol /var/log --vgname=vg_system --size=5120 --name=lv_log
logvol /home --vgname=vg_system --size=10240 --name=lv_home
logvol swap --vgname=vg_system --size=8192 --name=lv_swap
```

### Multiple Kickstart Profiles

Create different kickstart files for different server roles:

```bash
# Web server profile
cp rhel94-uefi.ks /var/www/html/kickstart/rhel94-webserver.ks

# Database server profile
cp rhel94-uefi.ks /var/www/html/kickstart/rhel94-database.ks

# Update GRUB menu to offer multiple profiles
```

### HTTPS Boot (Secure)

For secure HTTP boot:

1. Install SSL certificate on Apache
2. Configure HTTPS in Apache
3. Update GRUB configuration to use https:// URLs
4. Update DHCP to provide HTTPS boot file URL

```bash
# Install mod_ssl
dnf install mod_ssl

# Configure SSL certificate
# Update GRUB URLs from http:// to https://
```

### Integration with Satellite/Foreman

This setup can be integrated with Red Hat Satellite or Foreman:

1. Configure Satellite as the repository source
2. Use Satellite-generated kickstart files
3. Point DHCP to Satellite's TFTP/HTTP services
4. Use activation keys in kickstart

## Security Considerations

1. **Change Default Passwords**: Update the root password in kickstart
2. **Secure HTTP Server**: Consider using HTTPS for boot files
3. **Network Segmentation**: Use separate VLAN for provisioning
4. **Firewall Rules**: Restrict access to boot server
5. **SELinux**: Keep SELinux enabled in enforcing mode
6. **Regular Updates**: Keep boot server and repositories updated

## Testing

### Test HTTP Server Accessibility

```bash
# From another machine
curl http://YOUR_SERVER_IP/boot/efi/shimx64.efi -I
curl http://YOUR_SERVER_IP/rhel94/images/pxeboot/vmlinuz -I
curl http://YOUR_SERVER_IP/kickstart/rhel94-uefi.ks
```

### Test DHCP Server

```bash
# Monitor DHCP requests
sudo tcpdump -i eth0 -n port 67 and port 68

# Check DHCP leases
cat /var/lib/dhcpd/dhcpd.leases
```

### Validate Kickstart

```bash
# Install pykickstart if not available
dnf install pykickstart

# Validate kickstart syntax
ksvalidator /var/www/html/kickstart/rhel94-uefi.ks
```

## Resources

- [RHEL 9 Boot Options](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_a_standard_rhel_9_installation/kickstart-installation_installing-rhel)
- [RHEL 9 Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/index)
- [UEFI HTTP Boot](https://github.com/tianocore/tianocore.github.io/wiki/HTTP-Boot)
- [GRUB2 Manual](https://www.gnu.org/software/grub/manual/grub/grub.html)

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review Red Hat documentation
3. Check system logs (`journalctl`, Apache logs, DHCP logs)
4. Verify network connectivity and firewall settings

## License

This configuration is provided as-is for educational and deployment purposes.

## Contributing

Contributions and improvements are welcome. Please test thoroughly before submitting changes.

## Changelog

### Version 1.0 (Initial Release)
- Complete UEFI HTTP Boot setup
- RHEL 9.4 kickstart configuration
- Automated setup script
- GRUB2 and DHCP examples
- Comprehensive documentation
