# RHEL 9.4 Kickstart Configuration for UEFI HTTP Boot
# This kickstart file automates the installation of RHEL 9.4 via HTTP boot

# System language
lang en_US.UTF-8

# Keyboard layout
keyboard us

# System timezone
timezone America/New_York --utc

# Root password (change this!)
rootpw --iscrypted $6$rounds=4096$saltsaltsal$IxDD3ba.WV0H50X.HvY.Uy87QWgU6VN0LbJbFc8c5cR5LfO0CVcPOlcLvVmZo4BNJPq3wd1xPfLn7K9H7X0J0/
# Default password is: changeme
# Generate new hash with: python3 -c 'import crypt; print(crypt.crypt("yourpassword", crypt.mksalt(crypt.METHOD_SHA512)))'

# System authorization
authselect select sssd with-mkhomedir --force

# Use network installation
url --url="http://YOUR_HTTP_SERVER/rhel94/BaseOS/"

# Additional repositories
repo --name="AppStream" --baseurl=http://YOUR_HTTP_SERVER/rhel94/AppStream/

# System bootloader configuration
bootloader --location=mbr --boot-drive=sda --append="crashkernel=auto"

# UEFI boot settings
efi

# Partition clearing information
clearpart --all --initlabel --drives=sda

# Disk partitioning for UEFI
part /boot/efi --fstype=efi --size=600 --ondisk=sda
part /boot --fstype=xfs --size=1024 --ondisk=sda
part pv.01 --size=1 --grow --ondisk=sda

# LVM configuration
volgroup rhel pv.01
logvol / --vgname=rhel --size=10240 --name=root --fstype=xfs
logvol /home --vgname=rhel --size=5120 --name=home --fstype=xfs
logvol /var --vgname=rhel --size=10240 --name=var --fstype=xfs
logvol swap --vgname=rhel --size=4096 --name=swap --fstype=swap

# Network configuration
network --bootproto=dhcp --device=link --ipv6=auto --activate
network --hostname=rhel94-uefi.localdomain

# Firewall configuration
firewall --enabled --ssh

# SELinux configuration
selinux --enforcing

# Do not configure X Window System
skipx

# System services
services --enabled="chronyd,sshd"

# Reboot after installation
reboot

# Package selection
%packages
@^minimal-environment
@standard
chrony
openssh-server
vim-enhanced
wget
curl
net-tools
bind-utils
tar
rsync
tcpdump
nfs-utils
-iwl*firmware
%end

# Post-installation script
%post --log=/root/ks-post.log

# Update system
dnf -y update

# Configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable sshd

# Set up initial network configuration
cat > /etc/sysconfig/network << EOF
NETWORKING=yes
HOSTNAME=rhel94-uefi.localdomain
EOF

# Create a marker file to indicate kickstart completion
echo "Kickstart installation completed on $(date)" > /root/kickstart-complete.txt

# Log installation details
echo "UEFI HTTP Boot installation completed" >> /root/ks-post.log
echo "Installation date: $(date)" >> /root/ks-post.log
echo "Kernel version: $(uname -r)" >> /root/ks-post.log

%end

# Anaconda configuration
%anaconda
pwpolicy root --minlen=8 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=8 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=8 --minquality=1 --notstrict --nochanges --notempty
%end
