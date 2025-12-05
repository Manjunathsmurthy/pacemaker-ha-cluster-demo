#!/bin/bash
# Pacemaker HA Cluster Setup Script
# Production-grade automation for 2-node/3-node clusters
# Author: 13+ years Pacemaker/SLES experience
# License: MIT

set -euo pipefail

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-pacemaker-cluster}"
NODE1_IP="${NODE1_IP}"
NODE2_IP="${NODE2_IP}"
NODE3_IP="${NODE3_IP:-}"
CLUSTER_PASSWORD="${CLUSTER_PASSWORD}"
STONITH_ENABLED="${STONITH_ENABLED:-true}"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"  # aws, azure, gcp

LOG_FILE="/var/log/pacemaker-setup.log"
OS_TYPE=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

# Detect node count
if [ -n "$NODE3_IP" ]; then
    NODE_COUNT=3
    TWO_NODE=0
else
    NODE_COUNT=2
    TWO_NODE=1
fi

log "Starting Pacemaker HA cluster setup for $NODE_COUNT nodes"
log "Cloud provider: $CLOUD_PROVIDER"
log "OS: $OS_TYPE"

# Install packages based on OS
install_packages() {
    log "Installing Pacemaker packages..."
    
    case "$OS_TYPE" in
        sles|sle-hpc)
            zypper refresh
            zypper install -y pacemaker corosync crmsh fence-agents resource-agents
            ;;
        rhel|centos)
            yum install -y pacemaker corosync pcs fence-agents-all resource-agents
            systemctl enable --now pcsd
            echo "$CLUSTER_PASSWORD" | passwd --stdin hacluster
            ;;
        ubuntu|debian)
            apt-get update
            apt-get install -y pacemaker corosync crmsh fence-agents resource-agents
            ;;
        *)
            error "Unsupported OS: $OS_TYPE"
            ;;
    esac
}

# Configure corosync
configure_corosync() {
    log "Configuring Corosync..."
    
    cat > /etc/corosync/corosync.conf <<EOF
totem {
    version: 2
    cluster_name: $CLUSTER_NAME
    transport: knet
    crypto_cipher: aes256
    crypto_hash: sha256
    
    interface {
        ringnumber: 0
        bindnetaddr: $(hostname -I | awk '{print $1}')
        broadcast: yes
        mcastport: 5405
    }
}

quorum {
    provider: corosync_votequorum
    expected_votes: $NODE_COUNT
    two_node: $TWO_NODE
}

logging {
    to_logfile: yes
    logfile: /var/log/corosync/corosync.log
    to_syslog: yes
    timestamp: on
}

nodelist {
    node {
        ring0_addr: $NODE1_IP
        name: node1
        nodeid: 1
    }
    
    node {
        ring0_addr: $NODE2_IP
        name: node2
        nodeid: 2
    }
EOF

    if [ "$NODE_COUNT" -eq 3 ]; then
        cat >> /etc/corosync/corosync.conf <<EOF
    node {
        ring0_addr: $NODE3_IP
        name: node3
        nodeid: 3
    }
EOF
    fi

    echo "}" >> /etc/corosync/corosync.conf
}

# Set hacluster password
set_hacluster_password() {
    log "Setting hacluster password..."
    echo "hacluster:$CLUSTER_PASSWORD" | chpasswd
}

# Configure STONITH based on cloud provider
configure_stonith() {
    if [ "$STONITH_ENABLED" != "true" ]; then
        log "STONITH disabled (NOT RECOMMENDED FOR PRODUCTION)"
        crm configure property stonith-enabled=false
        return
    fi
    
    log "Configuring STONITH for $CLOUD_PROVIDER..."
    
    case "$CLOUD_PROVIDER" in
        aws)
            crm configure primitive stonith-node1 stonith:fence_aws \
                params region="$(ec2-metadata --availability-zone | cut -d' ' -f2 | sed 's/.$//')" \
                pcmk_host_map="node1:$(ec2-metadata --instance-id | cut -d' ' -f2)" \
                op monitor interval=60s
            
            crm configure primitive stonith-node2 stonith:fence_aws \
                params region="$(ec2-metadata --availability-zone | cut -d' ' -f2 | sed 's/.$//')" \
                pcmk_host_map="node2:$(ec2-metadata --instance-id | cut -d' ' -f2)" \
                op monitor interval=60s
            
            crm configure location stonith-node1-location stonith-node1 -inf: node1
            crm configure location stonith-node2-location stonith-node2 -inf: node2
            ;;
            
        azure)
            # Azure Managed Identity STONITH
            crm configure primitive stonith-node1 stonith:fence_azure_arm \
                params subscriptionId="$(curl -s -H Metadata:true --noproxy '*' 'http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text')" \
                resourceGroup="$(curl -s -H Metadata:true --noproxy '*' 'http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text')" \
                pcmk_host_map="node1:$(hostname)" \
                op monitor interval=60s
            ;;
            
        gcp)
            # GCP Service Account STONITH
            crm configure primitive stonith-node1 stonith:fence_gce \
                params project="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)" \
                zone="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)" \
                pcmk_host_map="node1:$(hostname)" \
                op monitor interval=60s
            ;;
    esac
    
    crm configure property stonith-enabled=true
    crm configure property stonith-timeout=120s
}

# Start services
start_services() {
    log "Starting Corosync and Pacemaker services..."
    systemctl enable corosync
    systemctl enable pacemaker
    systemctl start corosync
    sleep 5
    systemctl start pacemaker
    sleep 10
}

# Configure cluster properties
configure_cluster_properties() {
    log "Configuring cluster properties..."
    
    crm configure property no-quorum-policy=ignore
    crm configure property startup-fencing=true
    crm configure property cluster-recheck-interval=5min
    crm configure rsc_defaults resource-stickiness=100
    crm configure rsc_defaults migration-threshold=3
}

# Verify cluster status
verify_cluster() {
    log "Verifying cluster status..."
    sleep 5
    
    if crm status > /dev/null 2>&1; then
        log "Cluster is operational"
        crm status
    else
        error "Cluster verification failed"
    fi
}

# Main execution
main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
    fi
    
    if [ -z "$NODE1_IP" ] || [ -z "$NODE2_IP" ] || [ -z "$CLUSTER_PASSWORD" ]; then
        error "Required variables not set: NODE1_IP, NODE2_IP, CLUSTER_PASSWORD"
    fi
    
    install_packages
    set_hacluster_password
    configure_corosync
    start_services
    
    # Run only on node1
    if [ "$(hostname -I | awk '{print $1}')" == "$NODE1_IP" ]; then
        configure_cluster_properties
        configure_stonith
        verify_cluster
    fi
    
    log "Pacemaker HA cluster setup completed successfully"
    log "Check status with: sudo crm status"
}

main "$@"
