MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==//=="

--==//==
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0

#!/bin/bash

# g6e.2xlarge (1x NVIDIA L40S) - basic Lustre over TCP.
# This size has a single EFA-capable NIC; if/when you need EFA-over-LNet
# tuning, see modules/pcs/templates/g6.xlarge.userdata.tpl for the pattern.

# Start CloudWatch Agent using the config pre-staged on the AMI.
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s || true

echo "${lustre_dns}@tcp:/${lustre_mnt} /fsx lustre defaults,_netdev,flock,user_xattr,noatime,noauto,x-systemd.automount 0 0" >> /etc/fstab
mkdir -p /fsx
chmod a+rwx /fsx
mount /fsx
chmod 777 /fsx
--==//==
