param(
    [Parameter(Mandatory = $True)]
    [string]$license,

    [string]
    $mountDrive="Y"
)


Write-Host "Creating temporary working directory."
mkdir -path "c:\tmp"
mkdir -path "C:\Utils"
Copy-Item "$PSScriptRoot\AzCopy.exe" "c:\Utils"
Set-Location "c:\tmp"

$installerExeName = "es.exe"
$updateExeName = "es_update.exe"
Start-Process -Wait -FilePath "$PSScriptRoot\Prepare-Installer.exe"

Write-Host "Installing product."
Start-Process -FilePath $installerExeName -ArgumentList "/q /log c:\tmp\log.txt" -Wait
if (!(Select-String -Path ".\log.txt" -Pattern "Exit Code: 0x0")) {
    Write-Error "Install failed - error messages in log.txt"
    Select-String -Path ".\log.txt" -Pattern "Exit Code:"
    exit 500
}
Write-Host "Successfully installed product"

Write-Host "Installing update."
Start-Process -FilePath $updateExeName -ArgumentList "/q /log c:\tmp\log.txt" -Wait
if (!(Select-String -Path ".\log.txt" -Pattern "Exit Code: 0x0")) {
    Write-Error "Install failed - error messages in log.txt"
    Select-String -Path ".\log.txt" -Pattern "Exit Code:"
    exit 500
}
Write-Host "Successfully installed Update"

Write-Host "Installing license."
mkdir ".\licence"
Set-Location ".\licence"
Write-Host "Downloading licence from $license"
C:\Utils\AzCopy copy $license "."
$licenseFileName = (Get-Item -Path .\*).Name
Start-Process -FilePath "C:\Program Files (x86)\Common Files\SafeNet Sentinel\Sentinel RMS License Manager\WinNT\cesadmintool" -ArgumentList "-term install -f $licenseFileName" -Wait
Set-Location ".."

if ($mountDrive -eq "Y") {
    Write-Host "Setting up Data Disk"
    Get-Disk | Where-Object PartitionStyle -Eq "RAW" | Initialize-Disk -PartitionStyle MBR
    New-Partition -DiskNumber 2 -UseMaximumSize -DriveLetter f
    Format-Volume -DriveLetter F -FileSystem NTFS -Confirm:$false
    Get-Volume -DriveLetter F | Set-Volume -NewFileSystemLabel "Data Drive"
}

Write-Host "Cleaning up temporary working directory."
Set-Location "C:\"
Remove-Item "C:\tmp" -Force -Recurse

Write-Host "Configuring Directory Server"
$cmd = "C:\Program Files (x86)\Micro Focus\Enterprise Server\bin\mfds.exe"
Start-Process -FilePath $cmd -ArgumentList "--listen-all" -Wait
Restart-Service -Name "MF_CCITCP2"

Set-NetFirewallProfile -Profile Domain -Enabled False

