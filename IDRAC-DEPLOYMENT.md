# Deploying RHEL 9.4 via HTTP Boot to Remote Servers with iDRAC

This guide covers deploying RHEL 9.4 to Dell servers in different subnets using iDRAC management and UEFI HTTP Boot.

## Scenario Overview

**Your Setup:**
- Boot Server: `192.168.1.10` (HTTP/DHCP server)
- Target Server: In subnet `10.20.30.0/24`
- Target Server MAC: `AA:BB:CC:DD:EE:FF` (ETH0)
- iDRAC IP: `10.20.31.100` (Management network)

## Prerequisites

- [ ] iDRAC Enterprise or Express license (for remote console)
- [ ] Network routing between boot server and target subnets
- [ ] DHCP relay/IP helper configured on router
- [ ] Firewall allows HTTP, DHCP, and iDRAC traffic
- [ ] iDRAC credentials (username/password)

## Step 1: Configure Network Infrastructure

### 1.1 Configure Router DHCP Relay

Your router/switch needs to forward DHCP requests from the remote subnet to your boot server.

**Cisco IOS:**
```
interface Vlan30
 description Target Server Subnet
 ip address 10.20.30.1 255.255.255.0
 ip helper-address 192.168.1.10
```

**Linux (using dhcp-helper):**
```bash
# Install dhcp-helper
dnf install dhcp-helper

# Configure relay
cat > /etc/sysconfig/dhcp-helper << EOF
DHCPHELPER_OPTS="-s 192.168.1.10"
EOF

systemctl enable dhcp-helper
systemctl start dhcp-helper
```

**Linux (using dhcp-relay):**
```bash
# Install dhcp-relay
dnf install dhcp

# Start relay
dhcrelay -i eth0 192.168.1.10
```

### 1.2 Configure Firewall Rules

On the boot server:

```bash
# Allow DHCP from remote subnets
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.0/24" service name="dhcp" accept'

# Allow HTTP from remote subnets
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.0/24" service name="http" accept'

# Allow iDRAC management subnet (if needed)
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.31.0/24" accept'

# Reload firewall
firewall-cmd --reload
```

### 1.3 Verify Network Connectivity

```bash
# From boot server, test connectivity
ping 10.20.30.1      # Gateway of target subnet
ping 10.20.31.100    # iDRAC IP

# Test routing
traceroute 10.20.30.1

# Verify HTTP server is accessible
curl http://192.168.1.10/boot/efi/shimx64.efi -I
```

## Step 2: Configure DHCP for Remote Subnet

### 2.1 Update DHCP Configuration

```bash
# Use the remote subnet configuration template
cp dhcpd-remote-subnet.conf.example /etc/dhcp/dhcpd.conf

# Edit the configuration
vi /etc/dhcp/dhcpd.conf
```

### 2.2 Add Your Server's MAC Reservation

Add this block to `/etc/dhcp/dhcpd.conf`:

```
# Your specific server
host your-server {
    hardware ethernet AA:BB:CC:DD:EE:FF;  # Your ETH0 MAC address
    fixed-address 10.20.30.50;             # Assign desired IP
    option host-name "your-server.datacenter.local";
    option routers 10.20.30.1;

    # Force UEFI HTTP Boot
    if option architecture-type = 00:0f {
        filename "http://192.168.1.10/boot/efi/shimx64.efi";
    }
    elsif option architecture-type = 00:07 {
        filename "http://192.168.1.10/boot/efi/shimx64.efi";
    }
}

# Define the remote subnet
subnet 10.20.30.0 netmask 255.255.255.0 {
    option routers 10.20.30.1;
    option broadcast-address 10.20.30.255;
    next-server 192.168.1.10;
}
```

### 2.3 Restart DHCP Service

```bash
# Test configuration
dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Restart DHCP
systemctl restart dhcpd

# Monitor DHCP logs
journalctl -u dhcpd -f
```

## Step 3: Configure iDRAC for Network Boot

You have three options to configure iDRAC:

### Option A: Via iDRAC Web Interface (Recommended)

1. **Access iDRAC Web Interface:**
   ```
   Open browser: https://10.20.31.100
   Login with iDRAC credentials
   ```

2. **Enable Network Boot:**
   - Navigate to: **Configuration** → **BIOS Settings** → **Boot Settings**
   - Set **Boot Mode**: `UEFI`
   - Enable **PXE Device 1**: Select your NIC (Embedded NIC 1 or ETH0)
   - Set **Boot Sequence**:
     1. PXE Device (Network boot first)
     2. Hard Drive
   - Click **Apply** and **Reboot**

3. **Configure NIC Settings:**
   - Navigate to: **Configuration** → **Network** → **Network Settings**
   - Ensure NIC is enabled for PXE/HTTP boot
   - Verify UEFI HTTP Boot is enabled (if available)

4. **Launch Virtual Console:**
   - Navigate to: **Dashboard** → **Virtual Console**
   - Launch **HTML5 Console** or **Java Console**
   - Keep this open to monitor boot process

### Option B: Via iDRAC Command Line (RACADM)

```bash
# Install racadm tool (from Dell)
# Or use SSH to iDRAC

# SSH to iDRAC
ssh root@10.20.31.100

# Configure boot settings
racadm set BIOS.BiosBootSettings.BootMode Uefi
racadm set BIOS.BiosBootSettings.UefiBootSeq NIC.Integrated.1-1-1,HardDisk.List.1-1

# Enable network boot
racadm set NIC.Integrated.1-1-1.VirtMacAddr AA:BB:CC:DD:EE:FF
racadm set NIC.Integrated.1-1-1.LegacyBootProto PXE

# Save and reboot
racadm jobqueue create BIOS.Setup.1-1
racadm serveraction powercycle
```

### Option C: Via Remote RACADM (From Boot Server)

```bash
# Install RACADM on your boot server
# Download from Dell support site

# Configure remotely
racadm -r 10.20.31.100 -u root -p password set BIOS.BiosBootSettings.BootMode Uefi
racadm -r 10.20.31.100 -u root -p password set BIOS.BiosBootSettings.UefiBootSeq NIC.Integrated.1-1-1

# Create job and reboot
racadm -r 10.20.31.100 -u root -p password jobqueue create BIOS.Setup.1-1
racadm -r 10.20.31.100 -u root -p password serveraction powercycle
```

## Step 4: Create Host-Specific Kickstart (Optional)

For customized installation per host:

```bash
# Copy base kickstart
cp /var/www/html/kickstart/rhel94-uefi.ks \
   /var/www/html/kickstart/your-server.ks

# Customize for this specific server
vi /var/www/html/kickstart/your-server.ks
```

Example customizations:

```bash
# Set specific hostname
network --hostname=your-server.datacenter.local

# Configure static IP instead of DHCP
network --bootproto=static --ip=10.20.30.50 --netmask=255.255.255.0 --gateway=10.20.30.1 --nameserver=8.8.8.8

# Custom disk layout for this server
clearpart --all --drives=sda,sdb  # If you have multiple disks

# RAID configuration (if needed)
part raid.01 --size=1 --grow --ondisk=sda
part raid.02 --size=1 --grow --ondisk=sdb
raid pv.01 --level=1 --device=md0 raid.01 raid.02
```

Update GRUB to use host-specific kickstart:

```bash
# Edit GRUB config to add host-specific entry
vi /var/www/html/boot/grub2/grub.cfg

# Add entry:
menuentry 'Install your-server (Custom Config)' {
    linuxefi (http,192.168.1.10)/rhel94/images/pxeboot/vmlinuz inst.repo=http://192.168.1.10/rhel94 inst.ks=http://192.168.1.10/kickstart/your-server.ks ip=10.20.30.50::10.20.30.1:255.255.255.0:your-server:eth0:none
    initrdefi (http,192.168.1.10)/rhel94/images/pxeboot/initrd.img
}
```

## Step 5: Boot and Monitor Installation

### 5.1 Power On and Boot

```bash
# Method 1: Via iDRAC Web Interface
# Dashboard → Power → Power On → Boot to Network

# Method 2: Via RACADM SSH
racadm serveraction poweron

# Method 3: Via Remote RACADM
racadm -r 10.20.31.100 -u root -p password serveraction powerup
```

### 5.2 Monitor Boot Process

**Via iDRAC Virtual Console:**
1. Open Virtual Console from iDRAC web interface
2. Watch for network boot attempt
3. Observe DHCP negotiation
4. See GRUB menu appear
5. Monitor installation progress

**Via Boot Server Logs:**

```bash
# Terminal 1: Monitor DHCP
tail -f /var/log/messages | grep dhcpd

# Terminal 2: Monitor HTTP access
tail -f /var/log/httpd/access_log

# Terminal 3: Monitor system logs
journalctl -f
```

### 5.3 Expected Boot Sequence

```
1. POST → iDRAC initializes
2. Network Boot → DHCP request sent
3. DHCP Offer → Receives IP and boot file URL
4. HTTP Download → Fetches shimx64.efi
5. UEFI Boot → Loads GRUB
6. GRUB Menu → Select installation option
7. Kernel Load → Downloads vmlinuz and initrd
8. Anaconda → Installation begins
9. Kickstart → Automated installation
10. Reboot → System boots to installed OS
```

## Step 6: Troubleshooting

### Issue: Server doesn't get DHCP offer

**Check DHCP relay:**
```bash
# On router, verify helper is configured
show ip interface vlan 30

# On boot server, monitor DHCP
tcpdump -i any -n port 67 or port 68
```

**Verify DHCP sees the request:**
```bash
# Should see BOOTREQUEST from 10.20.30.0 subnet
tail -f /var/log/messages | grep DHCP
```

### Issue: Server gets IP but doesn't boot

**Check boot file URL:**
```bash
# Verify in DHCP logs
grep "filename" /var/log/messages

# Test HTTP accessibility from target subnet
# From another server in 10.20.30.0/24:
curl http://192.168.1.10/boot/efi/shimx64.efi -I
```

**Check iDRAC boot settings:**
```bash
racadm -r 10.20.31.100 -u root -p password get BIOS.BiosBootSettings
```

### Issue: HTTP files download but boot fails

**Check GRUB configuration:**
```bash
# Verify server IP in GRUB config
grep -r "192.168.1.10" /var/www/html/boot/grub2/grub.cfg

# Test kernel and initrd are accessible
curl http://192.168.1.10/rhel94/images/pxeboot/vmlinuz -I
curl http://192.168.1.10/rhel94/images/pxeboot/initrd.img -I
```

### Issue: Kickstart not being applied

**Verify kickstart URL:**
```bash
# Check HTTP access log
grep "rhel94-uefi.ks" /var/log/httpd/access_log

# Test kickstart download
curl http://192.168.1.10/kickstart/rhel94-uefi.ks

# Validate syntax
ksvalidator /var/www/html/kickstart/rhel94-uefi.ks
```

## Step 7: Post-Installation Verification

### 7.1 Check Installation Completed

**Via iDRAC Console:**
- System should reboot and boot from hard disk
- Login prompt appears

**Via SSH:**
```bash
# Once installation completes, SSH to new server
ssh root@10.20.30.50

# Verify installation
cat /root/kickstart-complete.txt
cat /root/ks-post.log
```

### 7.2 Verify System Configuration

```bash
# Check hostname
hostnamectl

# Check network configuration
ip addr show
cat /etc/sysconfig/network-scripts/ifcfg-eth0

# Check partitions
lsblk
df -h

# Check SELinux
getenforce

# Check firewall
firewall-cmd --list-all
```

## Complete Example: Your Specific Setup

Based on your scenario, here's the complete configuration:

**Your Details:**
- Boot Server: `192.168.1.10`
- Target Server Subnet: `10.20.30.0/24`
- Target Server MAC: `AA:BB:CC:DD:EE:FF`
- iDRAC IP: `10.20.31.100`
- Desired Server IP: `10.20.30.50`

**DHCP Configuration (`/etc/dhcp/dhcpd.conf`):**

```
subnet 192.168.1.0 netmask 255.255.255.0 {
    # Boot server subnet
}

subnet 10.20.30.0 netmask 255.255.255.0 {
    option routers 10.20.30.1;
    option broadcast-address 10.20.30.255;
    next-server 192.168.1.10;
}

host your-server {
    hardware ethernet AA:BB:CC:DD:EE:FF;
    fixed-address 10.20.30.50;
    option host-name "your-server.datacenter.local";

    if option architecture-type = 00:0f {
        filename "http://192.168.1.10/boot/efi/shimx64.efi";
    }
}
```

**Quick Deployment Commands:**

```bash
# 1. Configure DHCP
sudo vi /etc/dhcp/dhcpd.conf  # Add above configuration
sudo systemctl restart dhcpd

# 2. Configure iDRAC for network boot
racadm -r 10.20.31.100 -u root -p YourPassword set BIOS.BiosBootSettings.BootMode Uefi
racadm -r 10.20.31.100 -u root -p YourPassword jobqueue create BIOS.Setup.1-1

# 3. Power on server
racadm -r 10.20.31.100 -u root -p YourPassword serveraction powercycle

# 4. Monitor installation
tail -f /var/log/httpd/access_log
```

## Automation Script

For deploying multiple servers, see the included `deploy-remote-server.sh` script which automates these steps.

## Security Considerations

1. **Secure iDRAC Access:**
   - Use strong passwords
   - Enable IP filtering
   - Use HTTPS only
   - Consider VPN for iDRAC access

2. **Network Segmentation:**
   - Keep management network (iDRAC) separate
   - Use VLANs for isolation
   - Implement ACLs on routers

3. **Secure Boot Files:**
   - Consider HTTPS for boot files
   - Implement IPsec between subnets
   - Use signed boot images

## Additional Resources

- [Dell iDRAC Documentation](https://www.dell.com/support/home/en-us/product-support/product/idrac9-lifecycle-controller-v3.x-series/docs)
- [RACADM Command Reference](https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v3.x-series/racadm_idrac_pub/)
- [RHEL 9 Network Install Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_a_standard_rhel_9_installation/index)
