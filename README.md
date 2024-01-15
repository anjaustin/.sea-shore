# Create drives for encrypted data-at-rest (EDAR)

## Overview
This Bash script facilitates the creation of encrypted storage drives at rest using LUKS encryption. It provides a user-friendly CLI to select a drive, choose a file system type, and performs the necessary steps for formatting, encrypting, and mounting the encrypted drive.

## Compatibility
- Developed on Ubuntu Server 22.04 LTS
- Should be compatible with Debian-based distributions

## Features
- Checks for `cryptsetup` installation and prompts the user to install if not found.
- Allows the user to select a drive from a list of available drives.
- Prompts the user to enter a custom name for the encrypted drive (default includes drive details).
- Offers a selection of common file system types (ext4, xfs, btrfs, f2fs, zfs, vfat).
- Formats, encrypts, and mounts the selected drive using the chosen file system.
- Optionally updates user's `~/.bashrc` and `~/.bash_logout` for automating drive unlock/lock.
- Provides error handling and exits gracefully on user cancellation or failure.

## Requirements
- `cryptsetup`: The script checks for the presence of `cryptsetup` and prompts the user to install it if not found.
- `lsblk`: Used to list available drives and their details.
- `numfmt`: Used to format drive sizes into human-readable units.

## How to Use
1. Make sure the script is executable: `chmod u+x create-edar-drive.sh`
2. Run the script in the terminal: `./create-edar-drive.sh`
3. Follow the prompts to select a drive, choose a file system, and confirm the formatting process.

## Notes
- ZFS requires additional steps and is currently a placeholder in the script.

## Disclaimer
This script involves drive formatting and encryption. Use it at your own risk. Make sure to back up important data before proceeding. The author is not responsible for any data loss or issues caused by the use of this script.

## Feedback
Your feedback is valuable. Please report any issues or suggest improvements on the [GitHub repository](https://github.com/anjaustin/encrypted-data-at-rest).

## License
This script is licensed under the [MIT License](https://tripp.mit-license.org/).

## Author
- Aaron `Tripp` N. Josserand Austin

---
