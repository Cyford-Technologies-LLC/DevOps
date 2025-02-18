#!/bin/bash
##########################################################################
#                          Cyford Technologies LLC                       #
#                        www.cyfordtechnologies.com                      #
#                    Email:  support@ company domain .com                #
##########################################################################
clear
# This script switches an EC2 instance to a new subnet by:
# 1. Validating VPC compatibility between the target subnet and security group.
# 2. Validating the AMI ID and instance type.
# 3. Checking the current instance state.
# 4. Launching a new instance in the target subnet if the old instance is terminated.
# 5. Ensuring the new instance is ready and running.
# Exit on any error


set -e

# Assign input parameters directly into the script
INSTANCE_ID="i-0bf42ad72753a97b3"   # Old Instance ID
TARGET_SUBNET_ID="subnet-0b2d44ddc1fcc9e99"  # Subnet ID for the new instance
AMI_ID="ami-04b4f1a9cf54c11d0"      # AMI for the instance
INSTANCE_TYPE="t2.micro"            # Instance type
KEY_NAME="allen"                    # Key pair name
SECURITY_GROUP_ID="sg-0425d2c572ecedd0d"  # Security Group ID

# Verify AWS CLI is installed
if ! [ -x "$(command -v aws)" ]; then
  echo "Error: AWS CLI is not installed. Please install it and configure AWS credentials."
  exit 1
fi

# Check Subnet and Security Group Compatibility
echo "[DEBUG] Validating VPC configuration for Subnet and Security Group..."
VPC_ID_FOR_SUBNET=$(aws ec2 describe-subnets --subnet-ids "$TARGET_SUBNET_ID" --query 'Subnets[0].VpcId' --output text)
VPC_ID_FOR_SECURITY_GROUP=$(aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" --query 'SecurityGroups[0].VpcId' --output text)

if [ "$VPC_ID_FOR_SUBNET" != "$VPC_ID_FOR_SECURITY_GROUP" ]; then
  echo "[ERROR] Subnet ($TARGET_SUBNET_ID) and Security Group ($SECURITY_GROUP_ID) belong to different VPCs."
  echo "Please ensure both resources are in the same VPC. Exiting."
  exit 1
fi
echo "[INFO] Subnet and Security Group belong to the same VPC. Proceeding..."

# Validate the AMI ID
echo "[DEBUG] Validating the AMI ID..."
AMI_STATE=$(aws ec2 describe-images --image-ids "$AMI_ID" --query 'Images[0].State' --output text 2> /dev/null)
if [ "$AMI_STATE" != "available" ]; then
  echo "[ERROR] The provided AMI ID ($AMI_ID) is invalid or not available in this region. Exiting."
  exit 1
fi
echo "[INFO] AMI ID is valid and available."

# Validate the Instance Type
echo "[DEBUG] Validating instance type compatibility..."
INSTANCE_TYPE_SUPPORTED=$(aws ec2 describe-instance-types --instance-types "$INSTANCE_TYPE" --query 'InstanceTypes[0].[InstanceType]' --output text 2> /dev/null)
if [ "$INSTANCE_TYPE_SUPPORTED" != "$INSTANCE_TYPE" ]; then
  echo "[ERROR] The instance type ($INSTANCE_TYPE) is not supported in this region. Check the instance type configuration. Exiting."
  exit 1
fi
echo "[INFO] Instance type is valid."

# Check the current state of the instance
echo "[INFO] Checking the current state of Instance ID: $INSTANCE_ID"
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2> /dev/null || echo "terminated")

echo "[INFO] Current state of the instance: $INSTANCE_STATE"
if [ "$INSTANCE_STATE" == "terminated" ]; then
  echo "[WARNING] Instance $INSTANCE_ID is terminated. Creating a new instance..."

  # Launch a new instance
  echo "[INFO] Launching a new instance in Subnet ID: $TARGET_SUBNET_ID"
  NEW_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$TARGET_SUBNET_ID" \
    --query 'Instances[0].InstanceId' \
    --output text)

  if [ -z "$NEW_INSTANCE_ID" ]; then
    echo "[ERROR] Failed to launch a new instance. Exiting."
    exit 1
  fi

  echo "[INFO] New instance created successfully. Instance ID: $NEW_INSTANCE_ID"

  # Wait for the instance to reach the 'running' state
  echo "[INFO] Waiting for the new instance to start..."
  aws ec2 wait instance-running --instance-ids "$NEW_INSTANCE_ID"
  echo "[INFO] New instance is now running with Instance ID: $NEW_INSTANCE_ID"

  # Update INSTANCE_ID to the new instance
  INSTANCE_ID="$NEW_INSTANCE_ID"
fi

echo "[INFO] Instance $INSTANCE_ID is now ready. Proceeding with further actions..."