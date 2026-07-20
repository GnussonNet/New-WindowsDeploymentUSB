# Windows Deployment USB

PowerShell tool for creating a bootable **UEFI Windows deployment USB** from a Windows ISO.

The script creates a GPT-partitioned USB drive with:

- A small **FAT32 EFI boot partition** for UEFI firmware compatibility
- A large **NTFS installation partition** for Windows setup files and easy customization

This layout keeps the media bootable while giving full read/write access to the NTFS partition so you can manually add or replace deployment files like `install.wim`, `autounattend.xml`, and `$OEM$` at any time.

## What This Tool Does

- Creates bootable Windows installation USB media
- Supports UEFI-only systems
- Creates GPT partition layout
- Creates FAT32 + NTFS dual-partition USB layout
- Copies original content from the selected Windows ISO
- Uses `robocopy` for reliable file transfer

## What This Tool Does Not Do

- Does not inject or replace `install.wim` automatically
- Does not copy `autounattend.xml` automatically
- Does not copy `$OEM$` automatically

## Why This Design

The USB is intentionally split into FAT32 + NTFS:

- **FAT32** keeps UEFI boot compatibility
- **NTFS** gives writable space for large files and easy updates

After creation, you can manually maintain deployment content on the NTFS partition:

- Replace `sources\install.wim` with a newer custom image
- Add or update `autounattend.xml` in the USB root
- Add or update `$OEM$` content

This allows fast iteration without recreating the USB every time.

## USB Layout

```text
USB (GPT)
|
|-- FAT32 (UEFI_BOOT)
|   |-- bootmgr
|   |-- boot
|   |-- efi
|   '-- sources
|       '-- boot.wim
|
'-- NTFS (WindowsInstall)
    |-- setup.exe
    |-- sources
    |   |-- install.wim (from ISO by default)
    |   '-- ...
    '-- Windows installation files
```

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Administrator privileges
- Windows installation ISO
- USB drive (will be fully erased)

## Usage

Run PowerShell as Administrator:

```powershell
.\New-WindowsDeploymentUSB.ps1
```

The script will prompt for:

1. Windows ISO
2. Target USB drive

The selected USB drive will be completely erased and recreated.

## Manual Customization Workflow (Optional)

After USB creation, open the NTFS partition and copy your deployment assets manually:

1. Custom image:

```text
<NTFS>:\sources\install.wim
```

2. Unattended setup file:

```text
<NTFS>:\autounattend.xml
```

3. OEM provisioning content:

```text
<NTFS>:\$OEM$
```

To update later, just replace files with new versions.

## Notes

- UEFI-only. Legacy BIOS is not supported.
- The USB drive is wiped completely.
- Always verify the selected disk before confirming.
- Administrator privileges are required.
