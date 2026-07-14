Write-Host "Create USB Drive for Windows Installation (UEFI only - FAT32 + NTFS)" -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms

# Select Windows ISO
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
}

$FileBrowser.Filter = 'Distribution media (*.iso)|*.iso'
$FileBrowser.Title = "Locate the Windows distribution media image"

[void]$FileBrowser.ShowDialog()

if ($FileBrowser.FileName -eq "") {
    Write-Host "Aborting at user's request."
    exit 1
}

$ISOFile = $FileBrowser.FileName

# Select custom install.wim
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
}

$FileBrowser.Filter = 'Windows image (*.wim)|install.wim;*.wim'
$FileBrowser.Title = "Locate custom install.wim"

[void]$FileBrowser.ShowDialog()

if ($FileBrowser.FileName -eq "") {
    Write-Host "Aborting at user's request."
    exit 1
}

$CustomWIM = $FileBrowser.FileName



# Select autounattend.xml
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
}

$FileBrowser.Filter = 'Autounattend file (autounattend.xml)|autounattend.xml'
$FileBrowser.Title = "Locate autounattend.xml"

[void]$FileBrowser.ShowDialog()

if ($FileBrowser.FileName -eq "") {
    Write-Host "No autounattend.xml selected. Continuing without it." -ForegroundColor Yellow
    $AutoUnattend = $null
}
else {
    $AutoUnattend = $FileBrowser.FileName
}

# Select $OEM$ folder
$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$FolderBrowser.Description = "Select the `$OEM$ folder"
if ($FolderBrowser.ShowDialog() -eq "OK") {
    $OEMFolder = $FolderBrowser.SelectedPath
}
else {
    Write-Host "No `$OEM$ folder selected. Continuing without it." -ForegroundColor Yellow
    $OEMFolder = $null
}


# Select USB drive
do {
    $USBDrives = Get-Disk | Where-Object BusType -EQ "USB"

    if ($null -eq $USBDrives) {
        Read-Host "Insert a USB drive and press Enter"
    }
    else {
        if ($USBDrives.Count -gt 1) {
            $USBDrives |
            Format-List Number,
            FriendlyName,
            @{Name = 'Size GB'; Expression = { [math]::Round($_.Size / 1GB, 2) } },
            PartitionStyle

            $DriveNumber = Read-Host "Enter the USB disk number to overwrite"
            $USBDrive = Get-Disk -Number $DriveNumber
        }
        else {
            $USBDrive = $USBDrives
        }
    }

}
while ($null -eq $USBDrive)

Write-Host ""
Write-Host "Selected USB drive:" -ForegroundColor Yellow

$USBDrive |
Format-List Number,
FriendlyName,
@{Name = 'Size GB'; Expression = { [math]::Round($_.Size / 1GB, 2) } }

$Confirm = Read-Host "WARNING: This will erase the USB drive. Type YES to continue"

if ($Confirm -ne "YES") {
    Write-Host "Cancelled."
    exit 1
}

# Mount ISO
Write-Host "Mounting ISO..."

$ISOMounted = Mount-DiskImage `
    -ImagePath $ISOFile `
    -StorageType ISO `
    -PassThru

$ISODriveLetter = ($ISOMounted | Get-Volume).DriveLetter

# Prepare USB
Write-Host "Creating GPT partition layout..."

$USBDrive | Clear-Disk -RemoveData -Confirm:$false

$USBDrive | Set-Disk -PartitionStyle GPT

#
# FAT32 boot partition
#
Write-Host "Creating 1GB FAT32 boot partition..."

$BootPartition = $USBDrive |
New-Partition `
    -Size 1GB `
    -AssignDriveLetter

Format-Volume `
    -Partition $BootPartition `
    -FileSystem FAT32 `
    -NewFileSystemLabel "UEFI_BOOT" `
    -Confirm:$false

$BootLetter = ($BootPartition | Get-Volume).DriveLetter

#
# NTFS installation partition
#
Write-Host "Creating NTFS installation partition..."

$InstallPartition = $USBDrive |
New-Partition `
    -UseMaximumSize `
    -AssignDriveLetter

Format-Volume `
    -Partition $InstallPartition `
    -FileSystem NTFS `
    -NewFileSystemLabel "WindowsInstall" `
    -Confirm:$false

$InstallLetter = ($InstallPartition | Get-Volume).DriveLetter

# Mark as EFI System Partition (GPT)
Set-Partition `
    -DiskNumber $USBDrive.Number `
    -PartitionNumber $BootPartition.PartitionNumber `
    -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

#
# Copy Windows files to NTFS except install.wim/install.esd
#
Write-Host "Copying Windows installation files to NTFS..."

$SourceISO = "$ISODriveLetter`:\"
$Destination = "$InstallLetter`:\"

# Copy everything except install image
robocopy `
    $SourceISO `
    $Destination `
    /E `
    /XF install.wim install.esd `
    /R:1 `
    /W:1


#
# Copy install.wim
#
Write-Host "Copying custom install.wim..."

$SourcesFolder = "$InstallLetter`:\sources"

robocopy `
(Split-Path $CustomWIM) `
    $SourcesFolder `
(Split-Path $CustomWIM -Leaf) `
    /COPY:DAT `
    /J `
    /R:2 `
    /W:2

if ($LASTEXITCODE -gt 7) {
    Write-Host "Failed copying install.wim." -ForegroundColor Red
    exit 1
}

#
# Copy autounattend.xml
#
if ($null -ne $AutoUnattend) {
    Write-Host "Copying autounattend.xml..."

    robocopy `
    (Split-Path $AutoUnattend) `
        "$InstallLetter`:\" `
    (Split-Path $AutoUnattend -Leaf) `
        /COPY:DAT `
        /R:2 `
        /W:2

    if ($LASTEXITCODE -gt 7) {
        Write-Host "Failed copying autounattend.xml." -ForegroundColor Red
    }
}

#
# Copy $OEM$
#
if ($null -ne $OEMFolder) {
    Write-Host "Copying `$OEM$ folder..."

    robocopy `
        $OEMFolder `
        "$InstallLetter`:\$([char]36)OEM$([char]36)" `
        /E `
        /COPY:DAT `
        /R:2 `
        /W:2

    if ($LASTEXITCODE -gt 7) {
        Write-Host "Failed copying `$OEM$ folder." -ForegroundColor Red
    }
}

#
# Copy UEFI boot files to FAT32
#
Write-Host "Copying UEFI boot files..."

Copy-Item `
    -Path "$ISODriveLetter`:\bootmgr*" `
    -Destination "$BootLetter`:\" `
    -Force

Copy-Item `
    -Path "$ISODriveLetter`:\boot" `
    -Destination "$BootLetter`:\" `
    -Recurse `
    -Force

Copy-Item `
    -Path "$ISODriveLetter`:\efi" `
    -Destination "$BootLetter`:\" `
    -Recurse `
    -Force

#
# Copy boot.wim to FAT32
#
Write-Host "Copying WinPE boot image..."

New-Item `
    -Path "$BootLetter`:\sources" `
    -ItemType Directory `
    -Force | Out-Null

Copy-Item `
    -Path "$ISODriveLetter`:\sources\boot.wim" `
    -Destination "$BootLetter`:\sources\" `
    -Force

#
# Validate install.wim
#
if (Test-Path "$InstallLetter`:\sources\install.wim") {
    Write-Host "Found install.wim on NTFS partition."
}
elseif (Test-Path "$InstallLetter`:\sources\install.esd") {
    Write-Host "Found install.esd on NTFS partition."
}
else {
    Write-Host "WARNING: No install.wim or install.esd found." -ForegroundColor Yellow
}

# Cleanup
Write-Host "Unmounting ISO..."

Dismount-DiskImage -ImagePath $ISOFile

Write-Host ""
Write-Host "UEFI Windows installation USB created successfully." -ForegroundColor Green
Write-Host ""
Write-Host "FAT32 boot partition: $BootLetter`:"
Write-Host "NTFS installation partition: $InstallLetter`:"
