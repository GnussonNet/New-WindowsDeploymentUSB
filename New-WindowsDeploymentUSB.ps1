Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Create USB Drive for Windows Installation (UEFI only - FAT32 + NTFS)" -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host $Message -ForegroundColor Cyan
}

function Invoke-RobocopyChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter()]
        [string[]]$FileList = @(),

        [Parameter(Mandatory = $true)]
        [string[]]$Options,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & robocopy $Source $Destination @FileList @Options
    if ($LASTEXITCODE -gt 7) {
        throw $FailureMessage
    }
}



function Select-RequiredFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $fileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter = $Filter
        Title = $Title
    }

    [void]$fileBrowser.ShowDialog()

    if ([string]::IsNullOrWhiteSpace($fileBrowser.FileName)) {
        Write-Host "Aborting at user's request."
        exit 1
    }

    if (-not (Test-Path -LiteralPath $fileBrowser.FileName -PathType Leaf)) {
        throw "Selected file does not exist: $($fileBrowser.FileName)"
    }

    return $fileBrowser.FileName
}



function Select-UsbDisk {
    while ($true) {
        $usbDisks = @(Get-Disk | Where-Object { $_.BusType -eq "USB" })

        if ($usbDisks.Count -eq 0) {
            Read-Host "Insert a USB drive and press Enter"
            continue
        }

        if ($usbDisks.Count -eq 1) {
            return $usbDisks
        }

        $usbDisks |
            Format-List Number,
            FriendlyName,
            @{Name = 'Size GB'; Expression = { [math]::Round($_.Size / 1GB, 2) } },
            PartitionStyle

        $driveNumberInput = Read-Host "Enter the USB disk number to overwrite"

        if (-not [int]::TryParse($driveNumberInput, [ref]$null)) {
            Write-Host "Invalid disk number. Please enter a numeric value." -ForegroundColor Yellow
            continue
        }

        $selectedDisk = $usbDisks | Where-Object { $_.Number -eq [int]$driveNumberInput }
        if ($null -eq $selectedDisk) {
            Write-Host "Disk number $driveNumberInput is not a connected USB disk." -ForegroundColor Yellow
            continue
        }

        return $selectedDisk
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$isoMounted = $null
$bootLetter = $null
$installLetter = $null

try {
    # Select Windows ISO
    $ISOFile = Select-RequiredFile `
        -Filter 'Distribution media (*.iso)|*.iso' `
        -Title 'Locate the Windows distribution media image'

    # Select USB drive
    $USBDrive = Select-UsbDisk

    Write-Host ""
    Write-Host "Selected USB drive:" -ForegroundColor Yellow
    $USBDrive |
        Format-List Number,
        FriendlyName,
        @{Name = 'Size GB'; Expression = { [math]::Round($_.Size / 1GB, 2) } }

    $confirm = Read-Host "WARNING: This will erase the USB drive. Type YES to continue"
    if ($confirm -ne 'YES') {
        Write-Host "Cancelled."
        exit 1
    }

    # Mount ISO
    Write-Step "Mounting ISO..."

    $isoMounted = Mount-DiskImage `
        -ImagePath $ISOFile `
        -StorageType ISO `
        -PassThru

    $isoDriveLetter = ($isoMounted | Get-Volume).DriveLetter
    if ([string]::IsNullOrWhiteSpace($isoDriveLetter)) {
        throw 'Mounted ISO has no drive letter.'
    }

    # Prepare USB
    Write-Step "Creating GPT partition layout..."

    $USBDrive | Clear-Disk -RemoveData -Confirm:$false
    $USBDrive | Set-Disk -PartitionStyle GPT

    # FAT32 boot partition
    Write-Step "Creating 1GB FAT32 boot partition..."

    $bootPartition = $USBDrive |
        New-Partition `
            -Size 1GB `
            -AssignDriveLetter

    Format-Volume `
        -Partition $bootPartition `
        -FileSystem FAT32 `
        -NewFileSystemLabel 'UEFI_BOOT' `
        -Confirm:$false | Out-Null

    $bootLetter = ($bootPartition | Get-Volume).DriveLetter

    # NTFS installation partition
    Write-Step "Creating NTFS installation partition..."

    $installPartition = $USBDrive |
        New-Partition `
            -UseMaximumSize `
            -AssignDriveLetter

    Format-Volume `
        -Partition $installPartition `
        -FileSystem NTFS `
        -NewFileSystemLabel 'WindowsInstall' `
        -Confirm:$false | Out-Null

    $installLetter = ($installPartition | Get-Volume).DriveLetter

    # Mark as EFI System Partition (GPT)
    Set-Partition `
        -DiskNumber $USBDrive.Number `
        -PartitionNumber $bootPartition.PartitionNumber `
        -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'

    # Copy all ISO content to NTFS installation partition
    Write-Step "Copying Windows installation files to NTFS..."

    $sourceISO = "$isoDriveLetter`:\"
    $destination = "$installLetter`:\"

    Invoke-RobocopyChecked `
        -Source $sourceISO `
        -Destination $destination `
        -Options @('/E', '/R:1', '/W:1') `
        -FailureMessage 'Failed copying Windows installation files to NTFS.'

    # Copy UEFI boot files to FAT32
    Write-Step "Copying UEFI boot files..."

    Copy-Item `
        -Path "$isoDriveLetter`:\bootmgr*" `
        -Destination "$bootLetter`:" `
        -Force

    Copy-Item `
        -Path "$isoDriveLetter`:\boot" `
        -Destination "$bootLetter`:" `
        -Recurse `
        -Force

    Copy-Item `
        -Path "$isoDriveLetter`:\efi" `
        -Destination "$bootLetter`:" `
        -Recurse `
        -Force

    # Copy boot.wim to FAT32
    Write-Step "Copying WinPE boot image..."

    New-Item `
        -Path "$bootLetter`:\sources" `
        -ItemType Directory `
        -Force | Out-Null

    Copy-Item `
        -Path "$isoDriveLetter`:\sources\boot.wim" `
        -Destination "$bootLetter`:\sources\" `
        -Force

    Write-Host ""
    Write-Host "UEFI Windows installation USB created successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "FAT32 boot partition: $bootLetter`:"
    Write-Host "NTFS installation partition: $installLetter`:"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($null -ne $isoMounted) {
        Write-Step "Unmounting ISO..."
        Dismount-DiskImage -ImagePath $ISOFile -ErrorAction SilentlyContinue
    }
}
