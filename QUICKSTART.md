# Quick Start Guide - RHEL 9.4 UEFI HTTP Boot

This guide will get you up and running with UEFI HTTP Boot in 15 minutes.

## Prerequisites Checklist

- [ ] RHEL/CentOS/Rocky Linux server (boot server)
- [ ] Root access to boot server
- [ ] RHEL 9.4 ISO file
- [ ] Client machine with UEFI firmware
- [ ] Network connectivity between server and client

## Step 1: Prepare Boot Server (5 minutes)

```bash
# Download or obtain RHEL 9.4 ISO
# Place it in /root/ or /tmp/

# Clone this repository
cd /opt
git clone <repository-url> image_builder
cd image_builder

# Make setup script executable
chmod +x setup-httpboot-server.sh
```

## Step 2: Run Setup Script (5 minutes)

```bash
# Run as root
sudo ./setup-httpboot-server.sh
```

The script will:
- Auto-detect your server IP
- Install required packages
- Configure HTTP server
- Extract ISO contents
- Setup boot files
- Create configurations

**Note**: When prompted, provide the path to your RHEL 9.4 ISO if not auto-detected.

## Step 3: Configure DHCP (3 minutes)

```bash
# Edit DHCP configuration
sudo vi /etc/dhcp/dhcpd.conf.httpboot-example

# Update these values:
# - subnet 192.168.1.0 netmask 255.255.255.0  (your network)
# - range 192.168.1.100 192.168.1.200         (your DHCP range)
# - option routers 192.168.1.1                (your gateway)
# - YOUR_SERVER_IP                             (your server IP)

# Quick replace server IP (replace 192.168.1.10 with your IP)
sudo sed -i 's/YOUR_SERVER_IP/192.168.1.10/g' /etc/dhcp/dhcpd.conf.httpboot-example

# Activate configuration
sudo cp /etc/dhcp/dhcpd.conf.httpboot-example /etc/dhcp/dhcpd.conf

# Start DHCP server
sudo systemctl enable dhcpd
sudo systemctl start dhcpd
```

## Step 4: Update Kickstart (2 minutes)

```bash
# Change default root password
NEW_HASH=$(python3 -c 'import crypt; print(crypt.crypt("YourPassword123", crypt.mksalt(crypt.METHOD_SHA512)))')

# Update kickstart file
sudo vi /var/www/html/kickstart/rhel94-uefi.ks

# Find the line starting with "rootpw --iscrypted" and replace the hash
# Or run:
sudo sed -i "s|^rootpw --iscrypted.*|rootpw --iscrypted $NEW_HASH|" /var/www/html/kickstart/rhel94-uefi.ks
```

## Step 5: Boot Client (2 minutes)

1. Power on client machine
2. Press F12 (or F2/DEL depending on manufacturer) during boot
3. Select "UEFI Network Boot" or "HTTP Boot"
4. Wait for GRUB menu to appear
5. Select "Install RHEL 9.4 via HTTP Boot with Kickstart (Automated)"
6. Installation proceeds automatically

## Verification Commands

### Verify HTTP Server

```bash
# Check if HTTP server is running
systemctl status httpd

# Test boot file access (replace SERVER_IP)
curl http://SERVER_IP/boot/efi/shimx64.efi -I
curl http://SERVER_IP/kickstart/rhel94-uefi.ks -I
```

### Verify DHCP Server

```bash
# Check DHCP status
systemctl status dhcpd

# Monitor DHCP requests (run this while booting client)
sudo journalctl -u dhcpd -f
```

### Verify Firewall

```bash
# Check firewall rules
sudo firewall-cmd --list-all

# Should show http and dhcp services
```

## Common Issues and Quick Fixes

### Issue: Client doesn't get IP address

```bash
# Check DHCP is running
sudo systemctl restart dhcpd
sudo journalctl -u dhcpd -n 50

# Verify network interface
ip addr show
```

### Issue: Client gets IP but doesn't boot

```bash
# Verify DHCP boot filename
grep "filename" /etc/dhcp/dhcpd.conf

# Should be: filename "http://YOUR_SERVER_IP/boot/efi/shimx64.efi";
```

### Issue: Boot files not found (404 errors)

```bash
# Check files exist
ls -la /var/www/html/boot/efi/
ls -la /var/www/html/rhel94/images/pxeboot/

# Check Apache configuration
sudo httpd -t
sudo systemctl restart httpd
```

### Issue: Kickstart not being applied

```bash
# Validate kickstart syntax
ksvalidator /var/www/html/kickstart/rhel94-uefi.ks

# Check GRUB configuration
cat /var/www/html/boot/grub2/grub.cfg | grep inst.ks

# Test kickstart URL
curl http://YOUR_SERVER_IP/kickstart/rhel94-uefi.ks
```

## Testing Without Physical Hardware

You can test with VirtualBox or KVM:

### VirtualBox

```bash
# Create VM with UEFI firmware
VBoxManage createvm --name "RHEL-HTTPBoot-Test" --ostype RedHat_64 --register
VBoxManage modifyvm "RHEL-HTTPBoot-Test" --firmware efi --memory 2048 --cpus 2
VBoxManage modifyvm "RHEL-HTTPBoot-Test" --nic1 bridged --bridgeadapter1 eth0
VBoxManage modifyvm "RHEL-HTTPBoot-Test" --boot1 net

# Create virtual disk
VBoxManage createhd --filename ~/VMs/rhel-test.vdi --size 20480
VBoxManage storagectl "RHEL-HTTPBoot-Test" --name "SATA Controller" --add sata
VBoxManage storageattach "RHEL-HTTPBoot-Test" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ~/VMs/rhel-test.vdi

# Start VM
VBoxManage startvm "RHEL-HTTPBoot-Test"
```

### KVM/QEMU

```bash
# Create VM with UEFI
virt-install \
  --name rhel94-httpboot-test \
  --memory 2048 \
  --vcpus 2 \
  --disk size=20 \
  --network bridge=br0 \
  --boot uefi,network \
  --graphics vnc \
  --noautoconsole
```

## Next Steps

After successful installation:

1. **Customize Kickstart**: Add your packages, scripts, and configurations
2. **Setup Multiple Profiles**: Create different kickstart files for different server roles
3. **Enable HTTPS**: Secure your boot process with SSL/TLS
4. **Integrate with Satellite**: Connect to Red Hat Satellite for content management
5. **Automate Deployments**: Script mass deployments for your datacenter

## Need More Help?

See the full README.md for:
- Detailed configuration options
- Advanced features
- Security hardening
- Integration guides
- Complete troubleshooting section

## One-Line Server Status Check

```bash
echo "=== HTTP Boot Server Status ===" && \
systemctl is-active httpd && echo "✓ HTTP: Running" || echo "✗ HTTP: Stopped" && \
systemctl is-active dhcpd && echo "✓ DHCP: Running" || echo "✗ DHCP: Stopped" && \
firewall-cmd --query-service=http && echo "✓ Firewall HTTP: Open" || echo "✗ Firewall HTTP: Blocked" && \
firewall-cmd --query-service=dhcp && echo "✓ Firewall DHCP: Open" || echo "✗ Firewall DHCP: Blocked" && \
curl -s -o /dev/null -w "%{http_code}" http://localhost/boot/efi/shimx64.efi | grep -q 200 && echo "✓ Boot files: Accessible" || echo "✗ Boot files: Not accessible"
```

Happy deploying!
