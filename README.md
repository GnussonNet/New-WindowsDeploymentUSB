# Build-GoldenImageMedia

PowerShell tool for creating custom **UEFI Windows deployment USB media** from a Windows ISO and a custom Windows image.

The script creates a GPT-partitioned USB drive with:

- A small **FAT32 EFI boot partition** for UEFI firmware compatibility
- A large **NTFS installation partition** for Windows setup files and custom deployment content

This allows the use of large `install.wim` files without splitting while maintaining compatibility with modern UEFI systems.

## Features

- Creates bootable Windows installation USB media
- Supports UEFI-only systems
- Creates GPT partition layout
- Creates FAT32 + NTFS dual-partition USB layout
- Supports custom `install.wim` files larger than 4GB
- Keeps `install.wim` intact
- Supports automated deployments using:
  - `autounattend.xml`
  - `$OEM$` folders
- Uses `robocopy` for reliable file transfers
- Displays detailed copy progress and transfer statistics
- Designed for custom Windows images and golden image deployments

## USB Layout

The resulting USB drive:

```
USB (GPT)
│
├── FAT32 (UEFI_BOOT)
│   ├── bootmgr
│   ├── boot
│   ├── efi
│   └── sources
│       └── boot.wim
│
└── NTFS (WindowsInstall)
    ├── autounattend.xml
    ├── setup.exe
    ├── sources
    │   ├── install.wim
    │   └── $OEM$
    └── Windows installation files
```

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Administrator privileges
- Windows installation ISO
- Custom `install.wim`
- Optional:
  - `autounattend.xml`
  - `$OEM$` folder

## Usage

Run PowerShell as Administrator:

```
.\New-WindowsDeploymentUSB.ps1
```

The script will ask you to select:

1. Windows ISO
2. Custom `install.wim`
3. Optional `autounattend.xml`
4. Optional `$OEM$` folder
5. Target USB drive

The selected USB drive will be completely erased and recreated.

## Deployment Workflow

A typical golden image deployment workflow:

### 1. Capture a reference installation

Create your custom image:

```
install.wim
```

### 2. Prepare deployment files

Example structure:

```
autounattend.xml
$OEM$
├── $1
│   └── Scripts
│       └── Setup.ps1
└── $$
    └── Setup
        └── Configuration files
```

### 3. Create deployment USB

Run the script and select:

- Windows ISO
- Custom install.wim
- Deployment automation files

### 4. Deploy

Boot the target computer from USB and allow Windows Setup to apply the custom image.

## Why FAT32 + NTFS?

UEFI firmware typically requires a FAT32-readable boot partition.

However, FAT32 has a maximum file size limit of 4GB, which prevents storing many modern `install.wim` files.

This project separates the USB into two partitions:

- FAT32:
  - UEFI boot files
  - Windows PE boot environment

- NTFS:
  - Windows installation files
  - Large `install.wim`
  - Deployment customization files

This avoids the need to split images into `install.swm` files.

## Notes

- This project supports UEFI systems only.
- Legacy BIOS boot is not supported.
- The USB drive will be wiped completely.
- Always verify the selected disk before confirming.
- Administrator privileges are required.

## Troubleshooting

### Windows Setup cannot find the installation image

Verify that:

```
USB:\sources\install.wim
```

exists on the NTFS partition.

### `$OEM$` files are not applied

Verify the folder structure:

```
sources
└── $OEM$
    ├── $1
    └── $$
```
