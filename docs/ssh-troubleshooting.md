# SSH troubleshooting notes

Quick reference for diagnosing SSH access to the login node when a fresh apply
doesn't "just work". Based on real failures we hit on this cluster.

## Expected behaviour

After `terraform apply` completes:

- `ssh ec2-user@<login-public-ip>` should work with the SSH key whose public
  half is in `terraform.tfvars` as `ssh_key`.
- `ssh drmahes@<login-public-ip>` should work using the same key (via LDAP).

Login node public IP:

```sh
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=tag:aws:pcs:compute-node-group-id,Values=$(terraform output -raw pcs_cluster_id | xargs -I{} aws pcs list-compute-node-groups --region us-west-2 --cluster-identifier {} --query "computeNodeGroups[?name==\`login\`].id" --output text)" \
  --query 'Reservations[].Instances[?State.Name==`running`].PublicIpAddress' --output text
```

Or just check the EC2 console for the instance tagged with
`aws:pcs:compute-node-group-id` matching your login compute node group.

---

## Failure 1: `Permission denied (publickey)` as `ec2-user`

### Symptom

```
ssh ec2-user@<login-ip>
ec2-user@<ip>: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

With `-v`, you see `Offering public key: ~/.ssh/id_ed25519` but the server
still rejects it.

### Root cause

Cloud-init couldn't write the SSH key into `/home/ec2-user/.ssh/authorized_keys`
at first boot. Console log shows:

```
ci-info: no authorized SSH keys fingerprints found for user ec2-user.
```

`authorized_keys` exists but is empty (0 bytes). This happens because the
baked AMI preserves cloud-init's "instance already initialised" state from the
Image Builder build, so a fresh launch sees the same instance-id and skips the
SSH key injection module.

### Verification

SSH in using SSM (if SSM agent has connectivity):

```sh
aws ssm send-command --region us-west-2 --instance-ids <login-instance-id> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["ls -la /home/ec2-user/.ssh/","cat /home/ec2-user/.ssh/authorized_keys"]'
```

If `authorized_keys` exists but is 0 bytes, this is the issue.

### One-off fix via SSM

```sh
aws ssm send-command --region us-west-2 --instance-ids <login-instance-id> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H X-aws-ec2-metadata-token-ttl-seconds:60)","curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key >> /home/ec2-user/.ssh/authorized_keys","chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys","chmod 600 /home/ec2-user/.ssh/authorized_keys"]'
```

This fetches the public key from IMDS and appends it to `authorized_keys`.
`ssh ec2-user@<ip>` should then work.

### Proper fix (TODO)

Add a cloud-init cleanup step to `modules/ami/pcs-component.yaml` so the baked
AMI doesn't carry forward instance state. Something like:

```yaml
- name: CleanupCloudInit
  action: ExecuteBash
  inputs:
    commands:
      - |
        cloud-init clean --logs --seed
        rm -rf /var/lib/cloud/instances/*
```

Added as the last step before image capture.

---

## Failure 2: `Permission denied (publickey)` as `drmahes` (LDAP user)

### Symptom

`ec2-user` works (once Failure 1 is fixed), but the LDAP user `drmahes` still
gets permission denied.

### Root cause

LDAP server didn't finish its user-data script at first boot. Usually because
when the LDAP EC2 instance started, there was no route to the internet
(NAT Gateway not created yet, or EIP quota blocked it), so `dnf install
openldap-servers openldap-clients nss-pam-ldapd` timed out. LDAP server runs
but without OpenLDAP installed and without the seeded users.

### Verification

On the login node:

```sh
id drmahes
# id: 'drmahes': no such user

sudo systemctl status sssd
# running, but look for: "Backend is offline"

ldapsearch -x -H ldap://<ldap-server-private-dns> -b "ou=people,dc=my-domain,dc=com" "(uid=drmahes)"
# Can't contact LDAP server (-1)
```

On the LDAP server (via SSM if reachable):

```sh
systemctl status slapd
# "Unit slapd.service could not be found"
```

Console log of the LDAP instance shows:

```
Errors during downloading metadata for repository 'amazonlinux':
  - Curl error (28): Timeout was reached ...
Error: Unable to find a match: openldap-servers openldap-clients nss-pam-ldapd
```

### Fix

LDAP's user-data only runs once on first boot. You have to replace the LDAP
instance so user-data runs again, this time with NAT/internet working.

```sh
terraform taint module.ldap.aws_instance.ldap
terraform apply
```

Caveat: tainting the LDAP instance also taints several downstream resources
due to awscc provider drift on PCS node groups (they reference the AMI, which
references the compute profile, etc). This can trigger a full AMI rebake and
node group replacement, adding ~50 minutes.

### Proper fix (TODO)

Move the LDAP EC2 instance to the **public subnet** so it never depends on
NAT. Or: bake OpenLDAP into the LDAP server's AMI so it doesn't need internet
at first boot. Easiest is moving to public subnet with a restrictive SG.

---

## Failure 3: PCS queue delete blocks node group replace

### Symptom

On `terraform apply` after taint:

```
Error: AWS PCS can't delete the compute node group you specified because
the cluster has associated queues.
```

### Root cause

Terraform asks PCS to delete the node group before the queue that references
it. The awscc provider doesn't order these dependencies correctly.

### Fix

Delete the queues manually, then re-apply:

```sh
aws pcs list-queues --region us-west-2 --cluster-identifier <cluster-id>

aws pcs delete-queue --region us-west-2 --cluster-identifier <cluster-id> --queue-identifier <queue-id-1>
aws pcs delete-queue --region us-west-2 --cluster-identifier <cluster-id> --queue-identifier <queue-id-2>

# Remove stale state entries
terraform state rm 'module.pcs.awscc_pcs_queue.gpu["g6e.2xlarge"]'
terraform state rm 'module.pcs.awscc_pcs_queue.gpu["g7e.12xlarge"]'

terraform apply
```

### Proper fix (TODO)

Add explicit `depends_on` or `lifecycle { create_before_destroy = true }` to
queues so they're removed before their node groups during replacement.

---

## Failure 4: Image Builder pipeline blocks recipe delete

### Symptom

After a failed AMI bake and on retry:

```
Error: deleting Image Builder Image Recipe: ResourceDependencyException:
Resource dependency error: The resource ARN has other resources depended on it.
```

### Fix

Terraform rolls back the image on bake failure but leaves the pipeline orphan.
The orphan blocks recipe deletion. Delete the orphan pipeline manually:

```sh
aws imagebuilder list-image-pipelines --region us-west-2 \
  --query 'imagePipelineList[].[arn,imageRecipeArn]' --output table

aws imagebuilder delete-image-pipeline --region us-west-2 \
  --image-pipeline-arn arn:aws:imagebuilder:us-west-2:<account>:image-pipeline/wx-x86

terraform apply
```

### Proper fix (TODO)

Ordering lifecycle on the Image Builder resources.
