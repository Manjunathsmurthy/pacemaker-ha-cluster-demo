# Pacemaker HA Cluster - Complete Terraform Infrastructure

## Repository Structure

```
pacemaker-ha-cluster-demo/
├── README.md
├── terraform/
│   ├── aws/
│   │   ├── 2-node/
│   │   │   ├── main.tf          ✅ Created
│   │   │   ├── variables.tf     ✅ Created
│   │   │   ├── outputs.tf       ✅ Created
│   │   │   ├── README.md
│   │   │   └── terraform.tfvars.example
│   │   └── 3-node/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── README.md
│   │       └── terraform.tfvars.example
│   ├── azure/
│   │   ├── 2-node/
│   │   └── 3-node/
│   ├── gcp/
│   │   ├── 2-node/
│   │   └── 3-node/
│   └── scripts/
│       ├── user_data.sh
│       ├── pacemaker-setup.sh
│       └── drbd-setup.sh
└── ansible/
    ├── pacemaker-cluster.yml
    ├── drbd-config.yml
    └── stonith-config.yml
```

## Quick Start - AWS 2-Node

### Prerequisites
- Terraform >= 1.0
- AWS CLI configured
- EC2 key pair created
- SUSE/RHEL subscription

### Deploy AWS 2-Node Cluster

```bash
cd terraform/aws/2-node
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
terraform init
terraform plan
terraform apply
```

### Post-Deployment

```bash
# SSH to nodes
ssh -i ~/.ssh/your-key.pem ec2-user@<node1-ip>
ssh -i ~/.ssh/your-key.pem ec2-user@<node2-ip>

# Check cluster status
sudo crm status
sudo crm configure show
sudo corosync-cfgtool -s
cat /proc/drbd
```

## Production Best Practices

### 1. STONITH Fencing (Critical)
- **AWS**: fence_aws with IAM role permissions
- **Azure**: fence_azure_arm with Managed Identity
- **GCP**: fence_gce with service account
- Always enabled in production (`stonith-enabled=true`)
- Test fencing before go-live: `stonith_admin --fence <node>`

### 2. DRBD Replication
- **Protocol C**: Synchronous replication (recommended for prod)
- **Protocol B**: Semi-synchronous (lower latency, slight data risk)
- **Protocol A**: Asynchronous (not recommended for critical data)
- Enable dual-primaries only for specific use cases (OCFS2, GFS2)

### 3. Quorum Settings
- **2-node cluster**: `two_node=1` in corosync.conf
- **3+ node cluster**: Proper quorum calculation, optiona quorum device
- Avoid split-brain with proper fencing

### 4. Security
- Encrypt all EBS/Disk volumes
- Minimal security group rules
- Private subnets for cluster nodes
- Bastion host for SSH access
- IAM roles with least privilege

### 5. Monitoring
- CloudWatch/Azure Monitor/Stackdriver
- Pacemaker resource monitoring
- Corosync ring status
- DRBD sync status
- Custom health checks

### 6. Backup & DR
- EBS snapshots (automated)
- DRBD data replication
- Configuration backups (`crm configure save`)
- Test restore procedures
- Document RPO/RTO

## AWS 3-Node Differences

### Key Changes from 2-Node
- Remove `two_node=1` from corosync.conf
- Three availability zones
- Optional QDevice for improved quorum
- No DRBD (use shared storage or replication resources)
- Different resource constraints

### 3-Node Quorum
```
totem {
    version: 2
    cluster_name: pacemaker-3node
    transport: knet
    crypto_cipher: aes256
    crypto_hash: sha256
}

quorum {
    provider: corosync_votequorum
    expected_votes: 3
    # two_node: 0  (default, omitted)
}
```

## Azure Configuration

### Azure-Specific Components
- **Fencing**: `fence_azure_arm`
- **Networking**: Virtual Network, NSGs
- **Storage**: Managed Disks (Premium_LRS recommended)
- **Identity**: Managed Identity for fencing
- **Load Balancer**: Azure Load Balancer (Standard SKU)

### Azure IAM for STONITH
ManagedIdentity needs **Virtual Machine Contributor** role:
```bash
az role assignment create \
  --role "Virtual Machine Contributor" \
  --assignee <managed-identity-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg-name>
```

## GCP Configuration

### GCP-Specific Components
- **Fencing**: `fence_gce`
- **Networking**: VPC, Firewall Rules
- **Storage**: Persistent Disks (SSD recommended)
- **Identity**: Service Account for fencing
- **Load Balancer**: TCP/UDP Load Balancer

### GCP Service Account Permissions
```json
{
  "roles": [
    "compute.instanceAdmin.v1",
    "compute.viewer"
  ]
}
```

## Use Cases & Workloads

### 1. SAP HANA System Replication
- 2-node: HANA primary/secondary with DRBD
- 3-node: HANA with majority maker
- RTO: <1 minute, RPO: 0
- 99.99% uptime SLA

### 2. Oracle Database HA
- 2-node: Oracle + DRBD block replication
- ASM or file system based
- Automatic failover with VIP
- RTO: <2 minutes

### 3. PostgreSQL/MySQL HA
- Streaming replication + Pacemaker
- pgpool-II or MaxScale integration
- Read replicas with automatic promotion

### 4. Custom Application HA
- Stateless apps with shared storage
- Stateful apps with DRBD
- microservices with Pacemaker orchestration

## Advanced Topics

### Resource Ordering & Colocation
```bash
# Start VIP after service
crm configure order svc-before-vip Mandatory: my-service virtual-ip

# Colocate VIP with service
crm configure colocation vip-with-svc inf: virtual-ip my-service
```

### Resource Stickiness
```bash
# Prefer current node (avoid unnecessary migrations)
crm configure rsc_defaults resource-stickiness=100
```

### Failure Threshold
```bash
# Migrate after 3 failures
crm configure rsc_defaults migration-threshold=3
```

### Location Constraints
```bash
# Prefer node1 for service
crm configure location svc-prefers-node1 my-service 50: node1

# Never run on node3
crm configure location svc-avoids-node3 my-service -inf: node3
```

## Terraform Variables Reference

### Core Variables (All Providers)
```hcl
cluster_name              = "prod-pacemaker-cluster"
environment               = "prod"
instance_type             = "t3.medium"  # or equivalent
enable_stonith            = true
enable_monitoring         = true
backup_retention_days     = 7
pacemaker_cluster_password = "<secure-password>"
```

### AWS-Specific
```hcl
aws_region                = "us-west-2"
availability_zones        = ["us-west-2a", "us-west-2b"]
ami_id                    = ""  # Auto-lookup SLES15-SP4-HA
drbd_volume_type          = "gp3"
drbd_volume_iops          = 3000
enable_nlb                = true
```

### Azure-Specific
```hcl
azure_region              = "West US 2"
vm_size                   = "Standard_D2s_v3"
managed_disk_type         = "Premium_LRS"
enable_accelerated_networking = true
```

### GCP-Specific
```hcl
gcp_project               = "my-project-id"
gcp_region                = "us-west1"
machine_type              = "n1-standard-2"
persistent_disk_type      = "pd-ssd"
```

## Troubleshooting

### Cluster Won't Start
```bash
# Check corosync
sudo corosync-cfgtool -s
sudo journalctl -u corosync

# Check pacemaker
sudo systemctl status pacemaker
sudo journalctl -u pacemaker

# Check logs
tail -f /var/log/pacemaker/pacemaker.log
tail -f /var/log/corosync/corosync.log
```

### STONITH Fencing Fails
```bash
# Test fencing manually
sudo stonith_admin --list-installed
sudo stonith_admin --metadata -a fence_aws
sudo stonith_admin --fence node2

# Check IAM/RBAC permissions
# Verify security group allows instance API calls
```

### DRBD Won't Sync
```bash
# Check DRBD status
cat /proc/drbd
drbdadm status

# Force primary (DANGEROUS)
sudo drbdadm primary --force r0

# Verify network connectivity on port 7788-7799
telnet node2 7788
```

### Split-Brain Detection
```bash
# Check for split-brain
cat /proc/drbd | grep -i split

# Resolve split-brain (manual intervention required)
sudo drbdadm disconnect r0
sudo drbdadm secondary r0
sudo drbdadm connect --discard-my-data r0
# On other node:
sudo drbdadm connect r0
```

## Performance Tuning

### Corosync Token Timeout
```
totem {
    token: 5000     # 5 seconds (default)
    token_retransmits_before_loss_const: 10
    consensus: 6000
}
```

### DRBD Performance
```
resource r0 {
    net {
        max-buffers: 8000
        sndbuf-size: 1024k
    }
    disk {
        c-plan-ahead: 20
        c-fill-target: 10M
    }
}
```

## Multi-Cloud Comparison

| Feature | AWS | Azure | GCP |
|---------|-----|-------|-----|
| **Fencing Agent** | fence_aws | fence_azure_arm | fence_gce |
| **Storage** | EBS (gp3/io2) | Managed Disks | Persistent Disk |
| **Networking** | VPC | VNet | VPC |
| **Load Balancer** | NLB | Azure LB | TCP/UDP LB |
| **IAM** | IAM Roles | Managed Identity | Service Account |
| **Monitoring** | CloudWatch | Azure Monitor | Stackdriver |
| **Cost (2-node)** | ~$150/month | ~$180/month | ~$140/month |
| **Maturity** | ★★★★★ | ★★★★☆ | ★★★★☆ |

## Support & Consulting

13+ years experience with Pacemaker/Corosync on SLES. Available for:
- Architecture design
- Production deployment
- Performance tuning
- 24/7 support
- Training & knowledge transfer

**Achievements**:
- 99.99% uptime for mission-critical SAP HANA systems
- Zero-downtime migrations across data centers
- Custom Pacemaker resource agents for proprietary applications
- Disaster recovery automation with <5 minute RTO

## License

MIT License - Free for commercial and personal use.

## References

- [ClusterLabs Documentation](https://clusterlabs.org/)
- [SUSE Linux Enterprise High Availability Extension](https://documentation.suse.com/sle-ha/)
- [DRBD User's Guide](https://docs.linbit.com/)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [GCP Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
