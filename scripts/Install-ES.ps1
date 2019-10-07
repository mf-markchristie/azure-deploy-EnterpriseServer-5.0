param(
    [string]
    $licenseKey,

    [string]
    $mountDrive="Y"
)

Write-Host "Creating temporary working directory."
mkdir -path "c:\tmp"
Set-Location "c:\tmp"

$installerExeName = "es.exe"
$updateExeName = "es_update.exe"
$installerLocation ="https://mfenterprisestorage.blob.core.windows.net/enterpriseserverdeploy"

Write-Host "Downloading installer $installerExeName"

Copy-Item "$PSScriptRoot/AzCopy.exe" .
.\AzCopy copy "$installerLocation/$installerExeName" .
if(!$?) {
    Write-Error "Failed to download installer"
    exit 500
}

Write-Host "Successfully downloaded installer, starting installation."

Start-Process -FilePath $installerExeName -ArgumentList "/q /log c:\tmp\log.txt" -Wait

Write-Host "Checking installation."

if (!(Select-String -Path ".\log.txt" -Pattern "Exit Code: 0x0")) {
    Write-Error "Install failed - error messages in log.txt"
    Select-String -Path ".\log.txt" -Pattern "Exit Code:"
    exit 500
}

Write-Host "Successfully installed product"

.\AzCopy copy "$installerLocation/$updateExeName" .
if($?) {
    Write-Host "Installing update file."
    Start-Process -FilePath $updateExeName -ArgumentList "/q /log c:\tmp\log.txt" -Wait
    if (!(Select-String -Path ".\log.txt" -Pattern "Exit Code: 0x0")) {
        Write-Error "Install failed - error messages in log.txt"
        Select-String -Path ".\log.txt" -Pattern "Exit Code:"
        exit 500
    }
}

if ($licenseKey -ne "") {
    Write-Host "Installing license."
    Start-Process -FilePath "C:\Program Files (x86)\Common Files\SafeNet Sentinel\Sentinel RMS License Manager\WinNT\cesadmintool" -ArgumentList "-term activate $licenseKey" -Wait
}
else {
    Write-Warning "No license key provided during installation, a license will need to be added before you can use the product."
}

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
