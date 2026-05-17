MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==//=="

--==//==
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0

#!/bin/bash

# g7e.12xlarge (2x NVIDIA RTX PRO 6000 Blackwell) - basic Lustre over TCP.
# EFA-over-LNet tuning can be added later when the EFA NIC layout is confirmed
# on g7e; until then we mount Lustre plainly. Performance will be lower than
# a fully EFA-tuned mount but it is reliable.

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
