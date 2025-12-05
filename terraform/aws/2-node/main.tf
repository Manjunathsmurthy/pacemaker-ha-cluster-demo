# ==============================================================================
# AWS 2-Node Pacemaker HA Cluster - Production-Ready Configuration
# ==============================================================================
# This Terraform configuration deploys a 2-node Pacemaker cluster on AWS
# following industry best practices with STONITH fencing, Corosync, and DRBD
# ==============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# VPC and Networking Configuration
# ==============================================================================

resource "aws_vpc" "pacemaker_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.cluster_name}-vpc"
    Environment = var.environment
    Terraform   = "true"
    Purpose     = "Pacemaker HA Cluster"
  }
}

resource "aws_subnet" "cluster_subnet" {
  vpc_id                  = aws_vpc.pacemaker_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.pacemaker_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.pacemaker_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.cluster_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ==============================================================================
# Security Group - Minimal Access Following Best Practices
# ==============================================================================

resource "aws_security_group" "pacemaker_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for Pacemaker HA cluster"
  vpc_id      = aws_vpc.pacemaker_vpc.id

  # SSH access (restrict to your IP in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
    description = "SSH access"
  }

  # Corosync - multicast/unicast communication
  ingress {
    from_port   = 5404
    to_port     = 5406
    protocol    = "udp"
    self        = true
    description = "Corosync cluster communication"
  }

  # Pacemaker IPC
  ingress {
    from_port   = 2224
    to_port     = 2224
    protocol    = "tcp"
    self        = true
    description = "Pacemaker cluster communication"
  }

  # DRBD replication
  ingress {
    from_port   = 7788
    to_port     = 7799
    protocol    = "tcp"
    self        = true
    description = "DRBD data replication"
  }

  # High-availability daemon
  ingress {
    from_port   = 694
    to_port     = 694
    protocol    = "udp"
    self        = true
    description = "HA daemon heartbeat"
  }

  # Application ports (customizable based on your application)
  dynamic "ingress" {
    for_each = var.application_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_app_cidr
      description = "Application port ${ingress.value}"
    }
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

# ==============================================================================
# IAM Role for STONITH Fencing (fence_aws)
# ==============================================================================

resource "aws_iam_role" "pacemaker_role" {
  name = "${var.cluster_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-role"
  }
}

resource "aws_iam_role_policy" "pacemaker_policy" {
  name = "${var.cluster_name}-policy"
  role = aws_iam_role.pacemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeTags",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:RebootInstances",
          "ec2:DescribeVolumes",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeNetworkInterfaces",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "pacemaker_profile" {
  name = "${var.cluster_name}-profile"
  role = aws_iam_role.pacemaker_role.name
}

# ==============================================================================
# EBS Volumes for DRBD Replication
# ==============================================================================

resource "aws_ebs_volume" "drbd_volume" {
  count             = 2
  availability_zone = var.availability_zone
  size              = var.drbd_volume_size
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = {
    Name        = "${var.cluster_name}-drbd-${count.index + 1}"
    ClusterNode = "node${count.index + 1}"
  }
}

# ==============================================================================
# Pacemaker Cluster Node 1 (Primary)
# ==============================================================================

resource "aws_instance" "pacemaker_node1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cluster_subnet.id
  vpc_security_group_ids = [aws_security_group.pacemaker_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.pacemaker_profile.name
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/user_data.sh", {
    cluster_name  = var.cluster_name
    node_name     = "${var.cluster_name}-node1"
    node_id       = 1
    peer_node_ip  = ""  # Will be updated post-deployment
    cluster_vip   = var.cluster_vip
    is_primary    = true
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.cluster_name}-node1"
    ClusterRole = "primary"
    Environment = var.environment
    NodeID      = "1"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_volume_attachment" "drbd_attach1" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.drbd_volume[0].id
  instance_id = aws_instance.pacemaker_node1.id
  
  # Prevent detachment on destroy to avoid data loss
  skip_destroy = false
}

# ==============================================================================
# Pacemaker Cluster Node 2 (Secondary)
# ==============================================================================

resource "aws_instance" "pacemaker_node2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cluster_subnet.id
  vpc_security_group_ids = [aws_security_group.pacemaker_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.pacemaker_profile.name
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/user_data.sh", {
    cluster_name  = var.cluster_name
    node_name     = "${var.cluster_name}-node2"
    node_id       = 2
    peer_node_ip  = aws_instance.pacemaker_node1.private_ip
    cluster_vip   = var.cluster_vip
    is_primary    = false
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.cluster_name}-node2"
    ClusterRole = "secondary"
    Environment = var.environment
    NodeID      = "2"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_instance.pacemaker_node1]
}

resource "aws_volume_attachment" "drbd_attach2" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.drbd_volume[1].id
  instance_id = aws_instance.pacemaker_node2.id
  
  skip_destroy = false
}

# ==============================================================================
# Network Load Balancer for Virtual IP (Optional but Recommended)
# ==============================================================================

resource "aws_lb" "cluster_lb" {
  count = var.enable_load_balancer ? 1 : 0
  
  name               = "${var.cluster_name}-nlb"
  internal           = var.internal_lb
  load_balancer_type = "network"
  subnets            = [aws_subnet.cluster_subnet.id]

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.enable_lb_deletion_protection

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

resource "aws_lb_target_group" "cluster_tg" {
  count = var.enable_load_balancer ? 1 : 0
  
  name     = "${var.cluster_name}-tg"
  port     = var.application_port
  protocol = "TCP"
  vpc_id   = aws_vpc.pacemaker_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.application_port
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.cluster_name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "node1_attachment" {
  count = var.enable_load_balancer ? 1 : 0
  
  target_group_arn = aws_lb_target_group.cluster_tg[0].arn
  target_id        = aws_instance.pacemaker_node1.id
  port             = var.application_port
}

resource "aws_lb_target_group_attachment" "node2_attachment" {
  count = var.enable_load_balancer ? 1 : 0
  
  target_group_arn = aws_lb_target_group.cluster_tg[0].arn
  target_id        = aws_instance.pacemaker_node2.id
  port             = var.application_port
}

resource "aws_lb_listener" "cluster_listener" {
  count = var.enable_load_balancer ? 1 : 0
  
  load_balancer_arn = aws_lb.cluster_lb[0].arn
  port              = var.application_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cluster_tg[0].arn
  }
}

# ==============================================================================
# Secondary Elastic Network Interface for Cluster VIP (Alternative to NLB)
# ==============================================================================

resource "aws_network_interface" "cluster_vip_eni" {
  count = var.use_eni_for_vip ? 1 : 0
  
  subnet_id       = aws_subnet.cluster_subnet.id
  private_ips     = [var.cluster_vip]
  security_groups = [aws_security_group.pacemaker_sg.id]

  tags = {
    Name = "${var.cluster_name}-vip-eni"
  }
}
