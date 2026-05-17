MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==//=="

--==//==
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0

#!/bin/bash

# Start CloudWatch Agent with the config the AMI already has pre-staged.
# Only runs on compute node groups (not the login node, whose launch
# template does not invoke this start command).
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s || true

modprobe lnet
modprobe kefalnd ipif_name=enp105s0
modprobe ksocklnd credits=2560

lnetctl lnet configure
lnetctl net del --net tcp
lnetctl net add --net tcp --if enp105s0
lnetctl net add --net efa --if rdmap113s0 --peer-credits 128 --cpt "[0]"
lnetctl net add --net efa --if rdmap130s0 --peer-credits 128 --cpt "[0]"
lnetctl net add --net efa --if rdmap147s0 --peer-credits 128 --cpt "[1]"
lnetctl net add --net efa --if rdmap164s0 --peer-credits 128 --cpt "[1]"
lnetctl net add --net efa --if rdmap181s0 --peer-credits 128 --cpt "[2]"
lnetctl net add --net efa --if rdmap198s0 --peer-credits 128 --cpt "[2]"
lnetctl net add --net efa --if rdmap79s0  --peer-credits 128 --cpt "[3]"
lnetctl net add --net efa --if rdmap96s0  --peer-credits 128 --cpt "[3]"

lnetctl set discovery 1
lnetctl udsp add --src efa --priority 0
modprobe lustre

echo "${lustre_dns}@tcp:/${lustre_mnt} /fsx lustre defaults,_netdev,flock,user_xattr,noatime 0 0" >> /etc/fstab
mkdir -p /fsx
chmod a+rwx /fsx
mount /fsx
chmod 777 /fsx
--==//==


