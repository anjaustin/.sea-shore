#!/bin/bash

### Functions ###
## Check if cryptsetup is installed
cryptsetup_installed() {
    # Check if cryptsetup is installed
    if command -v cryptsetup &> /dev/null; then
        # Display version information
        echo "$(cryptsetup -V) is currently installed."
    else
        # Ask user if they want to install cryptsetup
        read -p "cryptsetup is not installed. Do you want to install it? (y/n): " choice

        case "$choice" in
            [yY])
                sudo apt update
                sudo apt install -y cryptsetup
                if ! command -v cryptsetup &> /dev/null; then
                    echo "Something when wrong. I was unable to install crypsetup."
                    exit 1
                else
                    echo "$(cryptsetup -V) was installed successfully."
                fi
                ;;
            [nN])
                echo "cryptsetup will not be installed. Exiting."
                exit 1
                ;;
            *)
                echo "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    fi
}

# Select the drive to format and encrypt
select_drive() {
    # Get a list of drives
    drives_list=$(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,RO,MODEL --noheadings | cat -n)

    # Display the numbered list of drives
    echo -e "Available drives:\n$drives_list"

    # Prompt the user to select a drive by number
    read -p "Enter the number of the drive you want to use: " drive_number

    # Validate user input
    if [[ "$drive_number" =~ ^[0-9]+$ ]]; then
        # Get the total number of drives
        total_drives=$(echo "$drives_list" | wc -l)

        if (( drive_number >= 1 && drive_number <= total_drives )); then
            selected_drive_info=$(echo "$drives_list" | awk -v num="$drive_number" '$1 == num { print $2, $NF }')

            # Confirm user's selection
            read -p "You selected drive $selected_drive_info. Is this correct? (y/n): " confirm_choice

            case "$confirm_choice" in
                [yY])
                    echo "Drive $selected_drive_info confirmed."
                    # You can perform additional actions here with the selected drive
                    ;;
                [nN])
                    echo "Selection canceled. Exiting."
                    exit 1
                    ;;
                *)
                    echo "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        else
            echo "Invalid drive number. Please enter a number between 1 and $total_drives. Exiting."
            exit 1
        fi
    else
        echo "Invalid input. Please enter a number. Exiting."
        exit 1
    fi
}

# Function to format the selected drive
format_drive() {
    # Extract the drive name and model from lsblk output
    drive_info=$(echo "$selected_drive_info" | awk '{print $1, $2}')
    drive_name=$(echo "$drive_info" | awk '{print $1}')
    drive_model=$(echo "$selected_drive_info" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')

    # Replace spaces in the model with underscores for better naming
    drive_model_underscored=$(echo "$drive_model" | tr ' ' '_')

    # Get the drive size directly using lsblk
    drive_size=$(lsblk -b -d -n -o SIZE "/dev/$drive_name")

    # Convert the size to human-readable format
    drive_size_human=$(numfmt --to=iec-i --suffix=B "$drive_size")

    # Create a default name based on the drive information
    default_encrypted_drive_name="${drive_name}-EAR-${drive_model_underscored}"
    [ -n "$drive_size" ] && default_encrypted_drive_name="${default_encrypted_drive_name}-${drive_size_human}"

    # Prompt the user for the desired name for the encrypted drive
    read -p "Enter a name for the encrypted drive (default: $default_encrypted_drive_name): " encrypted_drive_name

    # Use the default name if the user doesn't enter a custom name
    encrypted_drive_name=${encrypted_drive_name:-$default_encrypted_drive_name}

    # Confirm the drive information and the chosen name
    echo -e "Selected Drive Information:\nDrive Name: $drive_name\nDrive Model: $drive_model\nDrive Size: $drive_size_human"
    echo -e "Encrypted Drive Name: $encrypted_drive_name"

    # Prompt the user for confirmation
    read -p "Do you want to proceed with formatting this drive? (y/n): " confirm_format

    case "$confirm_format" in
        [yY])
            # Format the selected drive
            sudo cryptsetup luksFormat "/dev/$drive_name"

            # Open the LUKS device
            sudo cryptsetup luksOpen "/dev/$drive_name" "$encrypted_drive_name"

            # Create ext4 filesystem
            sudo mkfs.ext4 "/dev/mapper/$encrypted_drive_name"

            # Mount the LUKS device
            sudo mkdir -vp "/mnt/$encrypted_drive_name"
            sudo mount "/dev/mapper/$encrypted_drive_name" "/mnt/$encrypted_drive_name"

            echo "Drive formatting and encryption completed successfully."
            ;;
        [nN])
            echo "Formatting canceled. Exiting."
            exit 1
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Function to update user's '~/.bashrc' and '~/.bash_logout'
update_user_bash() {
    # Ask for permission to update ~/.bashrc and ~/.bash_logout
    read -p "Do you want to update your ~/.bashrc and ~/.bash_logout to unlock the drive on login and lock on logout? (y/n): " update_bashrc

    case "$update_bashrc" in
        [yY]|[yY][eE][sS])
            echo "Updating your ~/.bashrc and ~/.bash_logout"
            echo -e "\n# Mount encrypted drives\nsudo cryptsetup luksOpen '/dev/$drive_name' '$encrypted_drive_name'" >> ~/.bashrc
            echo "sudo mount '/dev/mapper/$encrypted_drive_name' '/mnt/$encrypted_drive_name'" >> ~/.bashrc
            echo -e "\n# Unmount encrypted drives\nsudo umount '/mnt/$encrypted_drive_name' && sudo cryptsetup luksClose '$encrypted_drive_name'" >> ~/.bash_logout
            echo "Updates, complete."
            ;;
        *)
            echo "Skipping update of ~/.bashrc and ~/.bash_logout."
            ;;
    esac
}

### Start Script ###
# Are requirements installed?
cryptsetup_installed

# Select the drive to format and encrypt
select_drive

# Format and encrypt selected drive
format_drive

# Update user files to automate unlocking and locking
update_user_bash
# EOF >>>
