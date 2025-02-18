#!/bin/bash
set -e
##########################################################################
#                          Cyford Technologies LLC                       #
#                        www.cyfordtechnologies.com                      #
#                    Email:  support@ company domain .com                #
##########################################################################
# This script mounts Amazon EFS to an EC2 instance by:
# 1. Verifying AWS CLI and required tools are installed.
# 2. Fetching and configuring security groups for VM and EFS.
# 3. Adding necessary firewall rules for NFS traffic.
# 4. Mounting the EFS to a specified directory.
# 5. Ensuring EFS is auto-mounted on reboot via /etc/fstab.

# User Variables
EFS_ID="fs-0c67b5751b94e0628"       # Replace with your EFS ID
AWS_REGION="us-east-1"              # Replace with your AWS region
MOUNT_POINT="/mnt/efs"              # Desired mount point
VM_INSTANCE_ID="i-020fd6d8c8c3ade83" # Instance ID of the VM

# Step 1: Ensure AWS CLI is installed
echo "[INFO] Verifying AWS CLI is installed..."
if ! command -v aws &> /dev/null; then
  echo "[ERROR] AWS CLI is not installed or not in PATH."
  exit 1
fi

# Step 2: Fetch VM Security Group
echo "[INFO] Fetching instance security group..."
VM_SG_ID=$(aws ec2 describe-instances --instance-id "$VM_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --region "$AWS_REGION" --output text 2>/dev/null)

if [[ -z "$VM_SG_ID" || "$VM_SG_ID" == "None" ]]; then
  echo "[ERROR] Could not retrieve security group ID of the instance: $VM_INSTANCE_ID."
  exit 1
fi

echo "[INFO] VM Security Group ID: $VM_SG_ID"

# Step 3: Fetch EFS Mount Target and Security Group
echo "[INFO] Fetching EFS mount target's security group..."
EFS_MOUNT_TARGET_ID=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" \
  --query 'MountTargets[0].MountTargetId' --region "$AWS_REGION" --output text)

if [[ -z "$EFS_MOUNT_TARGET_ID" || "$EFS_MOUNT_TARGET_ID" == "None" ]]; then
  echo "[ERROR] Could not retrieve the mount target ID for EFS ID: $EFS_ID."
  exit 1
fi

EFS_SG_ID=$(aws efs describe-mount-target-security-groups --mount-target-id "$EFS_MOUNT_TARGET_ID" \
  --query 'SecurityGroups[0]' --region "$AWS_REGION" --output text)

if [[ -z "$EFS_SG_ID" || "$EFS_SG_ID" == "None" ]]; then
  echo "[ERROR] Could not retrieve security group for the EFS mount target: $EFS_MOUNT_TARGET_ID."
  exit 1
fi

echo "[INFO] EFS Security Group ID: $EFS_SG_ID"

# Step 4: Verify and Update Firewall Rules (Ingress Rule)
echo "[INFO] Verifying firewall rules between VM and EFS..."
EXISTING_RULE=$(aws ec2 describe-security-groups \
  --group-ids "$EFS_SG_ID" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`2049\` && ToPort==\`2049\` && UserIdGroupPairs[?GroupId=='$VM_SG_ID']]" \
  --region "$AWS_REGION" \
  --output text)

if [[ -n "$EXISTING_RULE" && "$EXISTING_RULE" != "None" ]]; then
  echo "[INFO] Ingress rule already exists for NFS traffic. Skipping rule addition."
else
  echo "[INFO] Adding ingress rule to allow NFS traffic from the VM's security group to EFS..."
  aws ec2 authorize-security-group-ingress \
    --group-id "$EFS_SG_ID" \
    --protocol tcp \
    --port 2049 \
    --source-group "$VM_SG_ID" \
    --region "$AWS_REGION" && \
  echo "[SUCCESS] Successfully added ingress rule."
fi
echo "[INFO] Firewall rules are in place."

# Step 5: Mount EFS Locally
echo "[INFO] Preparing to mount EFS locally..."

# Verify that `amazon-efs-utils` or `nfs-common` is installed
if ! command -v mount.efs &> /dev/null; then
  echo "[INFO] 'amazon-efs-utils' not found. Installing..."
  if command -v yum &> /dev/null; then
    sudo yum install -y amazon-efs-utils
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y amazon-efs-utils
  else
    echo "[ERROR] Unable to detect package manager. Install 'amazon-efs-utils' manually."
    exit 1
  fi
  echo "[INFO] Amazon EFS Utils installed."
fi

# Check if the mount point exists
if [ ! -d "$MOUNT_POINT" ]; then
  echo "[INFO] Creating mount point directory: $MOUNT_POINT"
  sudo mkdir -p "$MOUNT_POINT"
fi

# Mount EFS
echo "[INFO] Attempting to mount EFS..."
if mount | grep -q "$MOUNT_POINT"; then
  echo "[INFO] EFS is already mounted at $MOUNT_POINT."
else
  sudo mount -t efs "$EFS_ID:/" "$MOUNT_POINT"
  if mount | grep -q "$MOUNT_POINT"; then
    echo "[SUCCESS] EFS mounted successfully at $MOUNT_POINT."
  else
    echo "[ERROR] Failed to mount EFS."
    exit 1
  fi
fi

# Step 6: Add EFS to /etc/fstab for persistence
echo "[INFO] Adding EFS to /etc/fstab for automatic remount on reboot..."
if ! grep -q "$EFS_ID" /etc/fstab; then
  echo "$EFS_ID:/    $MOUNT_POINT   efs    defaults,_netdev   0   0" | sudo tee -a /etc/fstab
  echo "[SUCCESS] EFS added to /etc/fstab."
else
  echo "[INFO] EFS entry already exists in /etc/fstab."
fi
ls /mnt/efs
echo "[INFO] Script completed successfully."