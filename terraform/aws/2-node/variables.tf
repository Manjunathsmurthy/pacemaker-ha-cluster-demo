# AWS 2-Node Pacemaker Cluster - Variables

variable "aws_region" {
  description = "AWS region for cluster deployment"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the Pacemaker cluster"
  type        = string
  default     = "pacemaker-ha-cluster"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for cluster deployment"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  description = "EC2 instance type for cluster nodes"
  type        = string
  default     = "t3.medium"
  validation {
    condition     = can(regex("^t3\\.(medium|large|xlarge|2xlarge)|^m5\\.(large|xlarge|2xlarge|4xlarge)", var.instance_type))
    error_message = "Instance type must be suitable for HA workloads (min t3.medium)."
  }
}

variable "ami_id" {
  description = "AMI ID for SLES or RHEL with HA extensions (leave empty for auto-lookup)"
  type        = string
  default     = ""
}

variable "os_type" {
  description = "Operating system type (sles15, rhel8, rhel9)"
  type        = string
  default     = "sles15"
  validation {
    condition     = contains(["sles15", "rhel8", "rhel9"], var.os_type)
    error_message = "OS type must be sles15, rhel8, or rhel9."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}

variable "drbd_volume_size" {
  description = "DRBD data volume size in GB"
  type        = number
  default     = 100
}

variable "drbd_volume_type" {
  description = "EBS volume type for DRBD (gp3, io2, io1)"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp3", "io2", "io1"], var.drbd_volume_type)
    error_message = "DRBD volume type must be gp3, io2, or io1 for production HA."
  }
}

variable "drbd_volume_iops" {
  description = "Provisioned IOPS for DRBD volume (only for io1/io2/gp3)"
  type        = number
  default     = 3000
}

variable "drbd_volume_throughput" {
  description = "Throughput in MiB/s for gp3 volumes"
  type        = number
  default     = 125
}

variable "enable_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EBS encryption (leave empty for AWS-managed)"
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "EC2 SSH key pair name"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = []
}

variable "cluster_vip" {
  description = "Virtual IP for cluster (within private subnet range)"
  type        = string
  default     = "10.0.10.100"
}

variable "enable_nlb" {
  description = "Enable Network Load Balancer for cluster VIP"
  type        = bool
  default     = true
}

variable "nlb_internal" {
  description = "Create internal NLB (vs public)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection"
  type        = bool
  default     = true
}

variable "pacemaker_cluster_password" {
  description = "Pacemaker hacluster user password"
  type        = string
  sensitive   = true
}

variable "corosync_ring0_port" {
  description = "Corosync ring0 UDP port"
  type        = number
  default     = 5405
}

variable "corosync_ring1_port" {
  description = "Corosync ring1 UDP port (redundant path)"
  type        = number
  default     = 5406
}

variable "enable_stonith" {
  description = "Enable STONITH fencing (should always be true in production)"
  type        = bool
  default     = true
}

variable "stonith_timeout" {
  description = "STONITH operation timeout in seconds"
  type        = number
  default     = 120
}

variable "backup_retention_days" {
  description = "Number of days to retain EBS snapshots"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "drbd_protocol" {
  description = "DRBD protocol (A=async, B=semi-sync, C=sync)"
  type        = string
  default     = "C"
  validation {
    condition     = contains(["A", "B", "C"], var.drbd_protocol)
    error_message = "DRBD protocol must be A, B, or C."
  }
}

variable "resource_stickiness" {
  description = "Pacemaker resource stickiness score"
  type        = number
  default     = 100
}

variable "migration_threshold" {
  description = "Failure count before migration"
  type        = number
  default     = 3
}
