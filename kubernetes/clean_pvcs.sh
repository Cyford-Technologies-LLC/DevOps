#!/bin/bash
set -e
##########################################################################
#                          Cyford Technologies LLC                       #
#                        www.cyfordtechnologies.com                      #
#                    Email:  support@ company domain .com                #
##########################################################################
# PVC Cleanup Script
#
# This script is designed to clean up Persistent Volume Claim (PVC) directories
# in a specified directory path. It scans the target path and its subdirectories
# for directories matching the naming convention `pvc-*` and deletes them,
# except those explicitly specified in the ignore list.
#
# Features:
# 1. **Target Path for PVCs**:
#    - Specify the parent directory (TARGET_PATH) where PVC directories are located.
#    - Recursively scans this path for directories matching the `pvc-*` naming pattern.
#
# 2. **Recursive Deletion**:
#    - Deletes all matching PVC directories (and their contents) in the
#      specified path and its subdirectories, ensuring a thorough cleanup.
#
# 3. **Selective Ignoring of PVCs**:
#    - You can specify PVCs to exclude from deletion using the IGNORED_PVCS variable.
#
# 4. **Logging and Safety**:
#    - Logs each step to show which PVCs were found, deleted, or skipped.
#    - Handles invalid paths or cases where no PVCs are found with proper errors.
#
# 5. **Validation**:
#    - Ensures the specified target path exists and is a valid directory.
#
# Use Cases:
# - Cleaning up unused PVC directories in shared storage (e.g., NFS/EFS).
# - Maintaining cleanliness of storage directories while preserving important PVCs.
#
# What It Does:
# 1. Scans the specified directory (TARGET_PATH) and subdirectories for PVC directories.
# 2. Deletes matching PVC directories, except those listed in the IGNORED_PVCS variable.
# 3. Logs all actions for transparency and safety.

#  This script was used with AWS EFS mount..   however  i can not see why it wouldn't wor anywhere else



# Variables
TARGET_PATH="/path/to/pvcs"                      # Replace with the path where your PVCs are located
IGNORED_PVCS=("pvc-to-keep-1" "pvc-to-keep-2")   # PVC directories to ignore

# Function to check if array contains an element
function contains {
  local element
  for element in "${@:2}"; do
    if [[ "$element" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

# Validate the target path
if [[ ! -d "$TARGET_PATH" ]]; then
  echo "[ERROR] Target path '$TARGET_PATH' does not exist or is not a directory."
  exit 1
fi

# List all PVC directories and subdirectories recursively
echo "[INFO] Scanning for PVC directories under $TARGET_PATH..."
PVC_DIRS=($(find "$TARGET_PATH" -type d -name "pvc-*"))

if [ ${#PVC_DIRS[@]} -eq 0 ]; then
  echo "[INFO] No PVC directories found under $TARGET_PATH."
  exit 0
fi

echo "[INFO] Found PVC directories:"
for pvc in "${PVC_DIRS[@]}"; do
  echo "  - $(basename "$pvc")"
done

# Delete PVCs, except for the ignored ones
echo "[INFO] Removing non-ignored PVC directories..."
for pvc in "${PVC_DIRS[@]}"; do
  pvc_name=$(basename "$pvc")
  if contains "$pvc_name" "${IGNORED_PVCS[@]}"; then
    echo "[INFO] Skipping PVC: $pvc_name (Ignored)"
  else
    echo "[INFO] Deleting PVC: $pvc_name (Path: $pvc)"
    rm -rf "$pvc"
    echo "[SUCCESS] Deleted PVC: $pvc_name"
  fi
done

echo "[INFO] PVC cleanup completed successfully."