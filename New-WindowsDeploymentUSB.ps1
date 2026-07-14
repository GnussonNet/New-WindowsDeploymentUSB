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

function Invoke-RobocopyWarning {
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
        [string]$FailureMessage,

        [Parameter(Mandatory = $true)]
        [string]$ItemDescription
    )

    & robocopy $Source $Destination @FileList @Options
    if ($LASTEXITCODE -gt 7) {
        Write-Host ""
        Write-Host "WARNING: Failed to copy $ItemDescription" -ForegroundColor Yellow
        Write-Host $FailureMessage -ForegroundColor Yellow
        Write-Host "This may be due to Data Loss Prevention (DLP) policies blocking the transfer." -ForegroundColor Yellow
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  1. Check if DLP is enabled in your organization" -ForegroundColor Yellow
        Write-Host "  2. Try copying these files manually to the USB drive" -ForegroundColor Yellow
        Write-Host "  3. Temporarily disable DLP policies if you have permission" -ForegroundColor Yellow
        Write-Host "The installation USB is still usable; only $ItemDescription are missing." -ForegroundColor Yellow
        Write-Host ""
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

function Select-OptionalFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$SkippedMessage
    )

    $fileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter = $Filter
        Title = $Title
    }

    [void]$fileBrowser.ShowDialog()

    if ([string]::IsNullOrWhiteSpace($fileBrowser.FileName)) {
        Write-Host $SkippedMessage -ForegroundColor Yellow
        return $null
    }

    if (-not (Test-Path -LiteralPath $fileBrowser.FileName -PathType Leaf)) {
        throw "Selected file does not exist: $($fileBrowser.FileName)"
    }

    return $fileBrowser.FileName
}

function Select-OptionalFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$SkippedMessage
    )

    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = $Description

    if ($folderBrowser.ShowDialog() -eq "OK") {
        if (-not (Test-Path -LiteralPath $folderBrowser.SelectedPath -PathType Container)) {
            throw "Selected folder does not exist: $($folderBrowser.SelectedPath)"
        }

        return $folderBrowser.SelectedPath
    }

    Write-Host $SkippedMessage -ForegroundColor Yellow
    return $null
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

    # Select custom install.wim
    $CustomWIM = Select-RequiredFile `
        -Filter 'Windows image (*.wim)|install.wim;*.wim' `
        -Title 'Locate custom install.wim'

    # Select autounattend.xml
    $AutoUnattend = Select-OptionalFile `
        -Filter 'Autounattend file (autounattend.xml)|autounattend.xml' `
        -Title 'Locate autounattend.xml' `
        -SkippedMessage 'No autounattend.xml selected. Continuing without it.'

    # Select $OEM$ folder
    $OEMFolder = Select-OptionalFolder `
        -Description 'Select the `$OEM$ folder' `
        -SkippedMessage 'No `$OEM$ folder selected. Continuing without it.'

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

    # Copy Windows files to NTFS except install.wim/install.esd
    Write-Step "Copying Windows installation files to NTFS..."

    $sourceISO = "$isoDriveLetter`:\"
    $destination = "$installLetter`:\"

    Invoke-RobocopyChecked `
        -Source $sourceISO `
        -Destination $destination `
        -Options @('/E', '/XF', 'install.wim', 'install.esd', '/R:1', '/W:1') `
        -FailureMessage 'Failed copying Windows installation files to NTFS.'

    # Copy install.wim
    Write-Step "Copying custom install.wim..."

    $sourcesFolder = "$installLetter`:\sources"
    New-Item -Path $sourcesFolder -ItemType Directory -Force | Out-Null

    Invoke-RobocopyChecked `
        -Source (Split-Path -Path $CustomWIM) `
        -Destination $sourcesFolder `
        -FileList @((Split-Path -Path $CustomWIM -Leaf)) `
        -Options @('/COPY:DAT', '/J', '/R:2', '/W:2') `
        -FailureMessage 'Failed copying install.wim.'

    # Copy autounattend.xml
    if ($null -ne $AutoUnattend) {
        Write-Step "Copying autounattend.xml..."

        Invoke-RobocopyWarning `
            -Source (Split-Path -Path $AutoUnattend) `
            -Destination "$installLetter`:" `
            -FileList @((Split-Path -Path $AutoUnattend -Leaf)) `
            -Options @('/COPY:DAT', '/R:2', '/W:2') `
            -FailureMessage 'Failed copying autounattend.xml. Try copying manually to the USB root.' `
            -ItemDescription 'autounattend.xml'
    }

    # Copy $OEM$
    if ($null -ne $OEMFolder) {
        Write-Step 'Copying `$OEM$ folder...'

        Invoke-RobocopyWarning `
            -Source $OEMFolder `
            -Destination "$installLetter`:\$([char]36)OEM$([char]36)" `
            -Options @('/E', '/COPY:DAT', '/R:2', '/W:2') `
            -FailureMessage 'Failed copying `$OEM$ folder. Try copying manually to the USB root.' `
            -ItemDescription '`$OEM$ folder'
    }

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

    # Validate install.wim
    if (Test-Path "$installLetter`:\sources\install.wim") {
        Write-Host "Found install.wim on NTFS partition."
    }
    elseif (Test-Path "$installLetter`:\sources\install.esd") {
        Write-Host "Found install.esd on NTFS partition."
    }
    else {
        Write-Host "WARNING: No install.wim or install.esd found." -ForegroundColor Yellow
    }

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
