#!/bin/bash

################################################################################
# create-encrypted-at-rest-drive.sh
################################################################################
# Author: Aaron `Tripp` N. Josserand Austin
# Version: 0.1.7
# Date: 14-JAN-2024 T 16:24 Mountain US
################################################################################
# MIT License
################################################################################
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
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
################################################################################
#
# Description:
# This script facilitates the creation of encrypted storage drives at rest using LUKS encryption.
# It provides a user-friendly interface to select a drive, choose a file system type, and performs
# the necessary steps for formatting, encrypting, and mounting the encrypted drive.
#
# Usage:
# ./create-encrypted-at-rest-drive.sh
#
# Requirements:
# - cryptsetup: The script checks for the presence of cryptsetup and prompts the user to install it if not found.
# - lsblk: Used to list available drives and their details.
# - numfmt: Used to format drive sizes into human-readable units.
#
# Features:
# 1. Checks for cryptsetup installation and prompts the user to install if not found.
# 2. Allows the user to select a drive from a list of available drives.
# 3. Prompts the user to enter a custom name for the encrypted drive (default includes drive details).
# 4. Offers a selection of common file system types (ext4, xfs, btrfs, f2fs, zfs, vfat).
# 5. Formats, encrypts, and mounts the selected drive using the chosen file system.
# 6. Optionally updates user's ~/.bashrc and ~/.bash_logout for automating drive unlock/lock.
# 7. Provides error handling and exits gracefully on user cancelation or failure.
#
# How to Use:
# - Run the script in the terminal: ./create-encrypted-at-rest-drive.sh
# - Follow the prompts to select a drive, choose a file system, and confirm the formatting process.
#
# Notes:
# - ZFS requires additional steps and is currently a placeholder in the script.
#
# Disclaimer:
# This script involves drive formatting and encryption. Use it at your own risk. Make sure to back up
# important data before proceeding. The author is not responsible for any data loss or issues caused
# by the use of this script.
#
# Feedback:
# Your feedback is valuable. Please report any issues or suggest improvements on the GitHub repository:
# [GitHub Repository URL]
#
################################################################################

### FUNCTIONS ###

# Check if cryptsetup is installed
cryptsetup_installed() {
    local cryptsetup_version

    # Check if cryptsetup is installed
    if ! command -v cryptsetup &> /dev/null; then
        echo "Error: cryptsetup is not installed. Please install it before running this script."
        exit 1
    fi

    # Get and display cryptsetup version information
    cryptsetup_version=$(cryptsetup -V)
    echo "$cryptsetup_version is currently installed."
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
        echo "Error: No drives detected. Exiting."
        exit 1
    fi

    # Display the list of drives
    echo -e "Available drives:\n$drives_list"

    # Prompt the user to select a drive by number
    read -p "Enter the number of the drive you want to use: " drive_number

    # Validate user input for drive selection
    if ! [[ "$drive_number" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input. Please enter a number. Exiting."
        exit 1
    fi

    # Get the total number of drives
    total_drives=$(echo "$drives_list" | wc -l)

    # Validate user input within the range of available drives
    if ! (( drive_number >= 1 && drive_number <= total_drives )); then
        echo "Error: Invalid drive number. Please enter a number between 1 and $total_drives. Exiting."
        exit 1
    fi

    # Extract information about the selected drive
    selected_drive_info=$(echo "$drives_list" | awk -v num="$drive_number" '$1 == num { print $2, $NF }')

    # Confirm user's drive selection
    read -p "You selected drive $selected_drive_info. Is this correct? (y/n): " confirm_choice

    # Exit if user cancels the drive selection
    if ! [[ "$confirm_choice" =~ [yY] ]]; then
        echo "Selection canceled. Exiting."
        exit 1
    fi

    echo "Drive $selected_drive_info confirmed."
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
        echo "Error: Unable to extract drive information. Exiting."
        exit 1
    fi

    # Extract drive model and format it for naming
    drive_model=$(echo "$selected_drive_info" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')
    drive_model_underscored=$(echo "$drive_model" | tr ' ' '_')

    # Get drive size and format it for display
    drive_size=$(lsblk -b -d -n -o SIZE "/dev/$drive_name")

    # Check if drive size extraction failed
    if [ -z "$drive_size" ]; then
        echo "Error: Unable to determine drive size. Exiting."
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
    echo -e "Selected Drive Information:\nDrive Name: $drive_name\nDrive Model: $drive_model\nDrive Size: $drive_size_human"
    echo -e "Encrypted Drive Name: $encrypted_drive_name"
    echo -e "Selected File System Type: $file_system_type"

    # Prompt user for confirmation to format
    read -p "Do you want to proceed with formatting this drive? (y/n): " confirm_format

    # Exit if user cancels formatting
    if ! [[ "$confirm_format" =~ [yY] ]]; then
        echo "Formatting canceled. Exiting."
        exit 1
    fi

    # Format the selected drive based on chosen file system type
    sudo cryptsetup luksFormat "/dev/$drive_name"

    # Check if drive formatting failed
    if [ $? -ne 0 ]; then
        echo "Error: Failed to format the drive. Exiting."
        exit 1
    fi

    # Open the LUKS device
    sudo cryptsetup luksOpen "/dev/$drive_name" "$encrypted_drive_name"

    # Check if opening LUKS device failed
    if [ $? -ne 0 ]; then
        echo "Error: Failed to open the LUKS device. Exiting."
        exit 1
    fi

    # Create the chosen file system on the LUKS device
    case "$file_system_type" in
        ext4)
            sudo mkfs.ext4 "/dev/mapper/$encrypted_drive_name"
            ;;
        xfs)
            sudo mkfs.xfs "/dev/mapper/$encrypted_drive_name"
            ;;
        btrfs)
            sudo mkfs.btrfs "/dev/mapper/$encrypted_drive_name"
            ;;
        f2fs)
            sudo mkfs.f2fs "/dev/mapper/$encrypted_drive_name"
            ;;
        zfs)
            # Note: ZFS requires additional steps; user is informed to refer to documentation
            echo "ZFS requires additional steps. Please refer to ZFS documentation for usage."
            ;;
        vfat)
            sudo mkfs.vfat "/dev/mapper/$encrypted_drive_name"
            ;;
    esac

    # Mount the LUKS device
    sudo mkdir -vp "/mnt/$encrypted_drive_name"
    sudo mount "/dev/mapper/$encrypted_drive_name" "/mnt/$encrypted_drive_name"

    # Check if mounting the LUKS device failed
    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount the LUKS device. Exiting."
        exit 1
    fi

    echo "Drive formatting and encryption completed successfully."
}

# Function to update user's '~/.bashrc' and '~/.bash_logout'
update_user_bash() {
    local update_bashrc

    # Prompt user for permission to update bash files
    read -p "Do you want to update your ~/.bashrc and ~/.bash_logout to unlock the drive on login and lock on logout? (y/n): " update_bashrc

    # Update bash files if user agrees
    if [[ "$update_bashrc" =~ [yY] ]]; then
        echo "Updating your ~/.bashrc and ~/.bash_logout"

        # Append commands to unlock and mount the encrypted drive to ~/.bashrc
        echo -e "\n# Mount encrypted drives\nsudo cryptsetup luksOpen '/dev/$drive_name' '$encrypted_drive_name'" >> ~/.bashrc
        echo "sudo mount '/dev/mapper/$encrypted_drive_name' '/mnt/$encrypted_drive_name'" >> ~/.bashrc

        # Append commands to unmount and close the encrypted drive to ~/.bash_logout
        echo -e "\n# Unmount encrypted drives\nsudo umount '/mnt/$encrypted_drive_name' && sudo cryptsetup luksClose '$encrypted_drive_name'" >> ~/.bash_logout

        echo "Updates, complete."
    else
        echo "Skipping update of ~/.bashrc and ~/.bash_logout."
    fi
}

### START ###
cryptsetup_installed
select_drive
format_drive
update_user_bash
# EOF >>>
