# AWS 2-Node Pacemaker Cluster - Outputs

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "cluster_security_group_id" {
  description = "Cluster security group ID"
  value       = aws_security_group.pacemaker_cluster.id
}

output "node1_instance_id" {
  description = "Node 1 EC2 instance ID"
  value       = aws_instance.node1.id
}

output "node2_instance_id" {
  description = "Node 2 EC2 instance ID"
  value       = aws_instance.node2.id
}

output "node1_private_ip" {
  description = "Node 1 private IP address"
  value       = aws_instance.node1.private_ip
}

output "node2_private_ip" {
  description = "Node 2 private IP address"
  value       = aws_instance.node2.private_ip
}

output "node1_public_ip" {
  description = "Node 1 public IP address (if in public subnet)"
  value       = aws_instance.node1.public_ip
}

output "node2_public_ip" {
  description = "Node 2 public IP address (if in public subnet)"
  value       = aws_instance.node2.public_ip
}

output "cluster_vip" {
  description = "Cluster virtual IP address"
  value       = var.cluster_vip
}

output "nlb_dns_name" {
  description = "Network Load Balancer DNS name"
  value       = var.enable_nlb ? aws_lb.nlb[0].dns_name : null
}

output "nlb_zone_id" {
  description = "Network Load Balancer zone ID for Route53"
  value       = var.enable_nlb ? aws_lb.nlb[0].zone_id : null
}

output "drbd_volume_ids" {
  description = "DRBD EBS volume IDs"
  value       = [aws_ebs_volume.drbd_node1.id, aws_ebs_volume.drbd_node2.id]
}

output "iam_role_arn" {
  description = "IAM role ARN for STONITH fencing"
  value       = aws_iam_role.pacemaker_stonith.arn
}

output "cluster_name" {
  description = "Pacemaker cluster name"
  value       = var.cluster_name
}

output "ssh_access" {
  description = "SSH access command for nodes"
  value = {
    node1 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_instance.node1.public_ip}"
    node2 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_instance.node2.public_ip}"
  }
}

output "pacemaker_status_commands" {
  description = "Commands to check Pacemaker cluster status"
  value = {
    cluster_status    = "sudo crm status"
    cluster_config    = "sudo crm configure show"
    corosync_status   = "sudo corosync-cfgtool -s"
    stonith_devices   = "sudo stonith_admin --list-installed"
    drbd_status       = "cat /proc/drbd"
  }
}

output "monitoring_dashboard_url" {
  description = "CloudWatch dashboard URL (construct manually)"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:"
}
