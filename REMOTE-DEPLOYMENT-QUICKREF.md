# Remote Subnet Deployment - Quick Reference

## Your Scenario

You have:
- **Boot Server**: HTTP/DHCP server at `192.168.1.10`
- **Target Server**: In different subnet `10.20.30.0/24`
- **Server MAC Address**: Known ETH0 MAC `AA:BB:CC:DD:EE:FF`
- **iDRAC IP**: `10.20.31.100`

## 3-Step Quick Deploy

### Step 1: Configure DHCP (5 minutes)

```bash
# Edit DHCP configuration
sudo vi /etc/dhcp/dhcpd.conf

# Add these blocks:

# Remote subnet configuration
subnet 10.20.30.0 netmask 255.255.255.0 {
    option routers 10.20.30.1;
    option broadcast-address 10.20.30.255;
    next-server 192.168.1.10;  # Your boot server

    if option architecture-type = 00:0f {
        filename "http://192.168.1.10/boot/efi/shimx64.efi";
    }
}

# Host reservation for your server
host your-server {
    hardware ethernet AA:BB:CC:DD:EE:FF;  # Your server's MAC
    fixed-address 10.20.30.50;             # Desired IP
    option host-name "your-server.local";

    if option architecture-type = 00:0f {
        filename "http://192.168.1.10/boot/efi/shimx64.efi";
    }
}

# Restart DHCP
sudo systemctl restart dhcpd
```

### Step 2: Configure Router DHCP Relay

Your router must forward DHCP requests from `10.20.30.0/24` to `192.168.1.10`:

**Cisco:**
```
interface Vlan30
 ip helper-address 192.168.1.10
```

**Linux Router:**
```bash
dhcrelay -i eth0 192.168.1.10
```

### Step 3: Configure iDRAC and Boot

```bash
# Set UEFI boot mode
racadm -r 10.20.31.100 -u root -p PASSWORD \
  set BIOS.BiosBootSettings.BootMode Uefi

# Create configuration job
racadm -r 10.20.31.100 -u root -p PASSWORD \
  jobqueue create BIOS.Setup.1-1

# Power cycle to boot
racadm -r 10.20.31.100 -u root -p PASSWORD \
  serveraction powercycle
```

## OR: Use Automated Script

```bash
sudo ./deploy-remote-server.sh
# Just answer the prompts!
```

## Monitoring

```bash
# Terminal 1: Watch DHCP
journalctl -u dhcpd -f | grep AA:BB:CC:DD:EE:FF

# Terminal 2: Watch HTTP
tail -f /var/log/httpd/access_log | grep 10.20.30

# Terminal 3: iDRAC Console
# Open: https://10.20.31.100
# Virtual Console → Watch boot process
```

## Expected Timeline

1. **0:00** - Power on server
2. **0:30** - POST complete, network boot starts
3. **1:00** - DHCP request/offer
4. **1:30** - Download shimx64.efi via HTTP
5. **2:00** - GRUB menu appears
6. **2:30** - Kernel/initrd download starts
7. **3:00** - Anaconda installer starts
8. **3:30** - Kickstart begins automated install
9. **15:00** - Installation complete, first reboot
10. **20:00** - System ready, SSH available

## Troubleshooting Quick Checks

### Server doesn't get IP
```bash
# Check DHCP relay on router
show ip interface vlan 30

# Verify DHCP sees request
tcpdump -i any -n port 67 or port 68
```

### Gets IP but doesn't boot
```bash
# Test boot file accessible
curl http://192.168.1.10/boot/efi/shimx64.efi -I

# Check iDRAC boot mode
racadm -r 10.20.31.100 -u root -p PASSWORD get BIOS.BiosBootSettings.BootMode
```

### Boot fails after GRUB
```bash
# Check kernel files exist
ls -lh /var/www/html/rhel94/images/pxeboot/vmlinuz
ls -lh /var/www/html/rhel94/images/pxeboot/initrd.img

# Verify HTTP logs show download
grep "vmlinuz\|initrd.img" /var/log/httpd/access_log
```

## Firewall Quick Fix

```bash
# Allow from remote subnet
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.0/24" accept'
firewall-cmd --reload
```

## Network Requirements

Must allow:
- **DHCP**: UDP 67/68 (from `10.20.30.0/24` to `192.168.1.10`)
- **HTTP**: TCP 80 (from `10.20.30.0/24` to `192.168.1.10`)
- **Routing**: Between subnets (via gateway/router)

## Post-Install Verification

```bash
# SSH to new server (after ~20 minutes)
ssh root@10.20.30.50

# Check deployment info
cat /root/kickstart-complete.txt
cat /root/ks-post.log

# Verify network
ip addr show
cat /etc/sysconfig/network-scripts/ifcfg-eth0

# Check storage
lsblk
df -h
```

## Complete Documentation

- **Full Guide**: See [IDRAC-DEPLOYMENT.md](IDRAC-DEPLOYMENT.md)
- **DHCP Examples**: See [dhcpd-remote-subnet.conf.example](dhcpd-remote-subnet.conf.example)
- **Automated Tool**: Run `./deploy-remote-server.sh`

## Common Mistakes to Avoid

1. ❌ Forgetting to configure DHCP relay on router
2. ❌ Using wrong boot server IP in DHCP config
3. ❌ Not setting UEFI boot mode in iDRAC
4. ❌ Firewall blocking HTTP from remote subnet
5. ❌ MAC address typo in DHCP host reservation
6. ❌ Wrong subnet mask or gateway in DHCP
7. ❌ Forgetting to restart DHCP after config changes

## Need Help?

1. Check logs: `journalctl -u dhcpd -xe`
2. Test connectivity: `ping`, `curl`, `traceroute`
3. Verify configs: `dhcpd -t`, `httpd -t`
4. See [IDRAC-DEPLOYMENT.md](IDRAC-DEPLOYMENT.md) for detailed troubleshooting
