#!/bin/bash

################################################################################
# create-encrypted-at-rest-drive.sh
################################################################################
# Author: Aaron `Tripp` N. Josserand Austin
# Version: v0.1.7-alpha - Initial Public Alpha Release
# Date: 14-JAN-2024 T 16:24 Mountain US
################################################################################
# MIT License
################################################################################
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Full License: https://tripp.mit-license.org/
################################################################################
# Description:
# This script facilitates the creation of encrypted storage drives at rest using
# LUKS encryption. It provides a user-friendly interface to select a drive,
# choose a file system type, and performs the necessary steps for formatting,
# encrypting, and mounting the encrypted drive.
#
# Usage:
# ./create-encrypted-at-rest-drive.sh
#
# Requirements:
# - cryptsetup: The script checks for the presence of cryptsetup and prompts the
# user to install it if not found.
# - lsblk: Used to list available drives and their details.
# - numfmt: Used to format drive sizes into human-readable units.
#
# Features:
# 1. Checks for cryptsetup installation and prompts the user to install if not
# found.
# 2. Allows the user to select a drive from a list of available drives.
# 3. Prompts the user to enter a custom name for the encrypted drive (default
# includes drive details).
# 4. Offers a selection of common file system types (ext4, xfs, btrfs, f2fs,
# zfs, vfat).
# 5. Formats, encrypts, and mounts the selected drive using the chosen file
# system.
# 6. Optionally updates user's ~/.bashrc and ~/.bash_logout for automating drive
# unlock/lock.
# 7. Provides error handling and exits gracefully on user cancelation or
# failure.
#
# How to Use:
# - Run the script in the terminal: ./create-encrypted-at-rest-drive.sh
# - Follow the prompts to select a drive, choose a file system, and confirm the
# formatting process.
#
# Notes:
# - ZFS requires additional steps and is currently a placeholder in the script.
#
# Disclaimer:
# This script involves drive formatting and encryption. Use it at your own risk.
# Make sure to back up important data before proceeding. The author is not
# responsible for any data loss or issues caused by the use of this script.
#
# Feedback:
# Your feedback is valuable. Please report any issues or suggest improvements on
# the GitHub repository: https://github.com/anjaustin/encrypted-data-at-rest
################################################################################

### SCRIPT-LEVEL VARIABLES ###
# Enable DEBUG mode (set to 1 to enable)
DEBUG=0

# Log directory
LOG_DIR="/var/log/edar_drive_setup"


### FUNCTIONS ###
# Script logging
log_message() {
    local log_level="$1"
    local message="$2"

    # Define log directory and file path
    local log_dir=$LOG_DIR
    local log_file="$log_dir/$(date +"%Y%m%d")_edar_drive_setup.log"

    # Create log directory if it doesn't exist
    sudo mkdir -p "$log_dir" || { echo "Error: Could not create log directory. Exiting."; exit 1; }

    # Check if log file exists, create if not
    if [ ! -e "$log_file" ]; then
        sudo touch "$log_file" || { echo "Error: Could not create log file. Exiting."; exit 1; }
        sudo chmod 644 "$log_file"
        log_message "INFO" "Log file created: $log_file"
    fi

    # Log the message with timestamp and log level
    local log_entry="$(date +"%Y-%m-%d %H:%M:%S") [$log_level] - $message"
    
    # Check if DEBUG environment variable is set to 1
    if [ "$DEBUG" = "1" ]; then
        # Print log entry to the terminal
        echo "$log_entry"
    fi

    # Append the log entry to the log file
    echo "$log_entry" | sudo tee -a "$log_file" > /dev/null
}

# Check and install external tool dependencies
check_install_dependencies() {
    local dependencies=("cryptsetup" "lsblk" "numfmt")

    # Check if each dependency is installed
    for tool in "${dependencies[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_message "WARNING" "$tool is not installed. Installing..."

            sudo apt-get update
            sudo apt-get install -y "$tool"

            # Check if installation was successful
            if [ $? -eq 0 ]; then
                log_message "INFO" "$tool is now installed."
            else
                log_message "ERROR" "Failed to install $tool. Exiting."
                exit 1
            fi
        else
            log_message "INFO" "$tool is already installed."
        fi
    done
}

# Select the drive to format and encrypt
select_drive() {
    local drives_list
    local total_drives
    local drive_number
    local confirm_choice

    # Get a list of available drives
    drives_list=$(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,RO,MODEL --noheadings | cat -n)

    # Check if no drives are detected
    if [ -z "$drives_list" ]; then
        log_message "ERROR" "No drives detected. Exiting."
        exit 1
    fi

    # Display the list of drives
    log_message "INFO" "Available drives:\n${drives_list}"

    # Prompt the user to select a drive by number
    read -p "Enter the number of the drive you want to use: " drive_number

    # Validate user input for drive selection
    if ! [[ "$drive_number" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid input. Please enter a number. Exiting."
        exit 1
    fi

    # Get the total number of drives
    total_drives=$(echo "$drives_list" | wc -l)

    # Validate user input within the range of available drives
    if ! (( drive_number >= 1 && drive_number <= total_drives )); then
        log_message "ERROR" "Invalid drive number. Please enter a number between 1 and ${total_drives}. Exiting."
        exit 1
    fi

    # Extract information about the selected drive
    selected_drive_info=$(echo "$drives_list" | awk -v num="$drive_number" '$1 == num { print $2, $NF }')

    # Confirm user's drive selection
    read -p "You selected drive ${selected_drive_info}. Is this correct? (y/n): " confirm_choice

    # Exit if user cancels the drive selection
    if ! [[ "$confirm_choice" =~ [yY] ]]; then
        log_message "INFO" "Drive selection canceled. Exiting."
        exit 1
    fi

    log_message "INFO" "Drive ${selected_drive_info} confirmed."
}

# Function to format the selected drive
format_drive() {
    local drive_info
    local drive_name
    local drive_model
    local drive_model_underscored
    local drive_size
    local drive_size_human
    local default_encrypted_drive_name
    local encrypted_drive_name
    local file_system_type
    local confirm_format

    # Extract drive information
    drive_info=$(echo "$selected_drive_info" | awk '{print $1, $2}')
    drive_name=$(echo "$drive_info" | awk '{print $1}')

    # Check if drive name extraction failed
    if [ -z "$drive_name" ]; then
        log_message "ERROR" "Unable to extract drive information. Exiting."
        exit 1
    fi

    # Extract drive model and format it for naming
    drive_model=$(echo "$selected_drive_info" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')
    drive_model_underscored=$(echo "$drive_model" | tr ' ' '_')

    # Get drive size and format it for display
    drive_size=$(lsblk -b -d -n -o SIZE "/dev/${drive_name}")

    # Check if drive size extraction failed
    if [ -z "$drive_size" ]; then
        log_message "ERROR" "Unable to determine drive size. Exiting."
        exit 1
    fi

    drive_size_human=$(numfmt --to=iec-i --suffix=B "$drive_size")

    # Set default name based on drive information
    default_encrypted_drive_name="${drive_name}-EAR-${drive_model_underscored}"
    [ -n "$drive_size" ] && default_encrypted_drive_name="${default_encrypted_drive_name}-${drive_size_human}"

    # Prompt user for custom name or use default
    read -p "Enter a name for the encrypted drive (default: $default_encrypted_drive_name): " encrypted_drive_name
    encrypted_drive_name=${encrypted_drive_name:-$default_encrypted_drive_name}

    # Prompt user to select file system type
    echo -e "Select the file system type:\n"
    PS3="Enter the number corresponding to your choice: "
    options=("ext4" "xfs" "btrfs" "f2fs" "zfs" "vfat")
    select file_system_type in "${options[@]}"; do
        case $file_system_type in
            ext4|xfs|btrfs|f2fs|zfs|vfat)
                break
                ;;
            *)
                echo "Invalid choice. Please enter a valid number."
                ;;
        esac
    done

    # Display selected drive information
    log_message "INFO" "Selected Drive Information:
    Drive Name: ${drive_name}
    Drive Model: ${drive_model}
    Drive Size: ${drive_size_human}
    Encrypted Drive Name: ${encrypted_drive_name}
    Selected File System Type: ${file_system_type}"

    # Prompt user for confirmation to format
    read -p "Do you want to proceed with formatting this drive? (y/n): " confirm_format

    # Exit if user cancels formatting
    if ! [[ "$confirm_format" =~ [yY] ]]; then
        log_message "WARNING" "Formatting canceled. Exiting."
        exit 1
    fi

    # Format the selected drive based on chosen file system type
    log_message "INFO" "Formatting the drive..."
    sudo cryptsetup luksFormat "/dev/${drive_name}"

    # Check if drive formatting failed
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to format the drive. Exiting."
        exit 1
    fi

    # Open the LUKS device
    log_message "INFO" "Opening the LUKS device..."
    sudo cryptsetup luksOpen "/dev/${drive_name}" "${encrypted_drive_name}"

    # Check if opening LUKS device failed
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to open the LUKS device. Exiting."
        exit 1
    fi

    # Create the chosen file system on the LUKS device
    case "$file_system_type" in
        ext4)
            log_message "INFO" "Creating ext4 file system..."
            sudo mkfs.ext4 "/dev/mapper/${encrypted_drive_name}"
            ;;
        xfs)
            log_message "INFO" "Creating XFS file system..."
            sudo mkfs.xfs "/dev/mapper/${encrypted_drive_name}"
            ;;
        btrfs)
            log_message "INFO" "Creating Btrfs file system..."
            sudo mkfs.btrfs "/dev/mapper/${encrypted_drive_name}"
            ;;
        f2fs)
            log_message "INFO" "Creating F2FS file system..."
            sudo mkfs.f2fs "/dev/mapper/${encrypted_drive_name}"
            ;;
        zfs)
            # Note: ZFS requires additional steps; user is informed to refer to documentation
            log_message "INFO" "ZFS requires additional steps. Please refer to ZFS documentation for usage."
            ;;
        vfat)
            log_message "INFO" "Creating VFAT file system..."
            sudo mkfs.vfat "/dev/mapper/${encrypted_drive_name}"
            ;;
    esac

    # Mount the LUKS device
    log_message "INFO" "Mounting the LUKS device..."
    sudo mkdir -vp "/mnt/${encrypted_drive_name}"
    sudo mount "/dev/mapper/${encrypted_drive_name}" "/mnt/${encrypted_drive_name}"

    # Check if mounting the LUKS device failed
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to mount the LUKS device. Exiting."
        exit 1
    fi

    log_message "INFO" "Drive formatting and encryption completed successfully."
}

# Function to update user's '~/.bashrc' and '~/.bash_logout'
update_user_bash() {
    local update_bashrc

    # Prompt user for permission to update bash files
    read -p "Do you want to update your ~/.bashrc and ~/.bash_logout to unlock the drive on login and lock on logout? (y/n): " update_bashrc

    # Update bash files if user agrees
    if [[ "$update_bashrc" =~ [yY] ]]; then
        log_message "INFO" "Updating user's ~/.bashrc and ~/.bash_logout."

        # Append commands to unlock and mount the encrypted drive to ~/.bashrc
        echo -e "\n# Mount encrypted drives\nsudo cryptsetup luksOpen '/dev/${drive_name}' '${encrypted_drive_name}'" >> ~/.bashrc
        echo "sudo mount '/dev/mapper/${encrypted_drive_name}' '/mnt/${encrypted_drive_name}'" >> ~/.bashrc

        # Append commands to unmount and close the encrypted drive to ~/.bash_logout
        echo -e "\n# Unmount encrypted drives\nsudo umount '/mnt/${encrypted_drive_name}' && sudo cryptsetup luksClose '${encrypted_drive_name}'" >> ~/.bash_logout

        log_message "INFO" "Update of ~/.bashrc and ~/.bash_logout completed successfully."
        echo "Updates, complete."
    else
        log_message "INFO" "Skipping update of ~/.bashrc and ~/.bash_logout."
        echo "Skipping update of ~/.bashrc and ~/.bash_logout."
    fi
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [-h|--help]

Create encrypted storage drives at rest using LUKS encryption.

Options:
  -h, --help   Display this help message and exit.

Requirements:
  - This script requires elevated privileges. You may need to run it with 'sudo'.
  - Dependencies: cryptsetup, lsblk, numfmt.

How to Run:
  1. Make the script executable: chmod u+x $0
  2. Run the script with elevated privileges: sudo $0

Feedback:
  Your feedback is valuable. Please report any issues or suggest improvements on
  the GitHub repository: https://github.com/anjaustin/encrypted-data-at-rest
EOF
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Invalid option. Use -h or --help for usage information."
            exit 1
            ;;
    esac
done

### START ###
# Initiate script and create log file before checking dependencies
log_message "INFO" "Script execution started on $(hostname -f):$(pwd)."

# Check for and installing dependencies
log_message "INFO" "Starting checks for dependencies."
check_install_dependencies
log_message "INFO" "Dependency checks complete."

# Select drive to encrypt
log_message "INFO" "Starting drive selection."
select_drive
log_message "INFO" "Drive selection complete."

# Format and encrypt selected drive
log_message "INFO" "Starting drive formatting and encryption."
format_drive
log_message "INFO" "Drive formatting and encryption complete."

# Setup automated locking and unlocking via user .bashrc and .bash_logout
log_message "INFO" "Starting user .bashrc and .bash_logout updates."
update_user_bash
log_message "INFO" "User .bashrc and .bash_logout update function completed."

log_message "INFO" "Script ended without errors."
# EOF >>>
