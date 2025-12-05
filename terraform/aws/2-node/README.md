# AWS 2-Node Pacemaker HA Cluster

Production-ready Terraform configuration for deploying a 2-node Pacemaker high availability cluster on AWS with DRBD replication, STONITH fencing, and automatic failover.

## Architecture

- **Nodes**: 2 EC2 instances across 2 AZs
- **HA Stack**: Pacemaker + Corosync + DRBD
- **Fencing**: STONITH with fence_aws
- **Storage**: EBS volumes with DRBD Protocol C replication
- **Networking**: VPC with private subnets, optional NLB
- **OS**: SUSE Linux Enterprise Server 15 SP4 HA or RHEL 8/9 HA

## Prerequisites

1. **Terraform** >= 1.0
2. **AWS CLI** configured with appropriate credentials
3. **EC2 Key Pair** created in target region
4. **SUSE/RHEL HA subscription** (if using marketplace AMIs)

## Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/Manjunathsmurthy/pacemaker-ha-cluster-demo.git
cd pacemaker-ha-cluster-demo/terraform/aws/2-node
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

Minimal required variables:
```hcl
aws_region                  = "us-west-2"
cluster_name                = "prod-pacemaker"
ssh_key_name                = "my-ec2-keypair"
pacemaker_cluster_password  = "SecurePassword123!"
```

### 3. Deploy
```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify Cluster
```bash
# Get node IPs from terraform output
terraform output

# SSH to node1
ssh -i ~/.ssh/my-key.pem ec2-user@<node1-ip>

# Check cluster status
sudo crm status
sudo crm configure show
sudo corosync-cfgtool -s
cat /proc/drbd
```

## Configuration

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region | us-west-2 | No |
| `cluster_name` | Cluster name | pacemaker-ha-cluster | No |
| `instance_type` | EC2 instance type | t3.medium | No |
| `ssh_key_name` | EC2 key pair | - | **Yes** |
| `pacemaker_cluster_password` | hacluster password | - | **Yes** |
| `drbd_volume_size` | DRBD volume size (GB) | 100 | No |
| `drbd_volume_type` | EBS volume type | gp3 | No |
| `enable_stonith` | Enable STONITH fencing | true | No |
| `enable_nlb` | Enable Network Load Balancer | true | No |

See `variables.tf` for complete list.

### Security Groups

Automatically configured ports:
- **SSH**: 22 (from allowed_ssh_cidrs)
- **Corosync**: 5404-5406/UDP
- **Pacemaker**: 2224/TCP
- **DRBD**: 7788-7799/TCP
- **HA Heartbeat**: 694/UDP

### IAM Role

Automatic IAM role creation with permissions for:
- `ec2:DescribeInstances`
- `ec2:StopInstances`
- `ec2:RebootInstances`
- `ec2:DescribeTags`

Required for STONITH fencing operations.

## Post-Deployment

### 1. Configure STONITH

```bash
# STONITH devices are auto-configured via user_data
# Verify configuration:
sudo stonith_admin --list-installed
sudo crm configure show

# Test fencing (careful!):
sudo stonith_admin --fence node2
```

### 2. Configure DRBD

```bash
# DRBD is auto-configured, verify:
cat /proc/drbd
drbdadm status

# Both nodes should show:
# disk:UpToDate
# peer-disk:UpToDate
```

### 3. Create Resources

```bash
# Example: Add virtual IP
sudo crm configure primitive virtual-ip ocf:heartbeat:IPaddr2 \
    params ip=10.0.10.100 cidr_netmask=24 \
    op monitor interval=10s

# Example: Add filesystem
sudo crm configure primitive drbd-fs ocf:heartbeat:Filesystem \
    params device="/dev/drbd0" directory="/mnt/drbd" fstype="ext4" \
    op monitor interval=20s

# Example: Colocation
sudo crm configure colocation fs-with-vip inf: drbd-fs virtual-ip
sudo crm configure order vip-before-fs Mandatory: virtual-ip drbd-fs
```

## Operations

### Cluster Status
```bash
sudo crm status
sudo crm_mon -1
```

### Standby Node
```bash
sudo crm node standby node2
sudo crm node online node2
```

### Migrate Resource
```bash
sudo crm resource migrate virtual-ip node2
sudo crm resource unmigrate virtual-ip
```

### Maintenance Mode
```bash
sudo crm configure property maintenance-mode=true
# Perform maintenance
sudo crm configure property maintenance-mode=false
```

## Troubleshooting

### Cluster Not Starting
```bash
# Check services
sudo systemctl status corosync
sudo systemctl status pacemaker

# Check logs
sudo journalctl -u corosync -f
sudo journalctl -u pacemaker -f
tail -f /var/log/pacemaker/pacemaker.log
```

### STONITH Failures
```bash
# Verify IAM role attached
aws ec2 describe-instances --instance-ids <id>

# Test AWS API access from node
aws ec2 describe-instances --region us-west-2

# Manual fence test
sudo stonith_admin -L
sudo stonith_admin -Q node2
```

### DRBD Split-Brain
```bash
# Detect
cat /proc/drbd | grep -i split

# Resolve (choose secondary node)
sudo drbdadm disconnect r0
sudo drbdadm secondary r0
sudo drbdadm connect --discard-my-data r0

# On primary:
sudo drbdadm connect r0
```

## Monitoring

Outputs include CloudWatch dashboard URL. Key metrics:
- EC2 instance health
- EBS volume metrics
- Network throughput
- Custom Pacemaker health checks

## Backup & Recovery

### Configuration Backup
```bash
sudo crm configure save /tmp/cluster-config.txt
```

### EBS Snapshots
Automated via AWS Backup or custom scripts (see variables).

### Restore
```bash
sudo crm configure load update /tmp/cluster-config.txt
```

## Cost Estimate

**Monthly cost (us-west-2)**:
- 2x t3.medium: ~$60
- 2x 100GB gp3 EBS: ~$16
- 2x 50GB root volumes: ~$10
- NLB (optional): ~$20
- Data transfer: ~$10

**Total**: ~$116/month

For production workloads, use m5.large or larger (~$140/month for compute).

## Use Cases

- SAP HANA System Replication
- Oracle Database HA
- PostgreSQL/MySQL primary-replica
- NFS HA file server
- Custom stateful applications

## Production Checklist

- [ ] Enable encryption (`enable_encryption = true`)
- [ ] Configure allowed_ssh_cidrs
- [ ] Enable termination protection
- [ ] Set up CloudWatch alarms
- [ ] Test STONITH fencing
- [ ] Document runbooks
- [ ] Schedule backup testing
- [ ] Configure monitoring alerts

## Support

13+ years Pacemaker/SLES experience. Available for consulting.

## License

MIT
