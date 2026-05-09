MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==//=="

--==//==
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0

#!/bin/bash

modprobe lnet
modprobe kefalnd ipif_name=enp34s0
modprobe ksocklnd

lnetctl lnet configure
lnetctl net del --net tcp
lnetctl net add --net tcp --if enp34s0
lnetctl net add --net efa --if rdmap36s0 --peer-credits 32
lnetctl net add --net efa --if rdmap42s0 --peer-credits 32
lnetctl set discovery 1
lnetctl udsp add --src efa --priority 0
modprobe lustre

echo "${lustre_dns}@tcp:/${lustre_mnt} /fsx lustre defaults,_netdev,flock,user_xattr,noatime 0 0" >> /etc/fstab
mkdir -p /fsx
chmod a+rwx /fsx
mount /fsx
chmod 777 /fsx
--==//==


