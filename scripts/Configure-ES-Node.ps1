param(
    [Parameter(Mandatory = $True)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [string]$ServicePassword,

    [Parameter(Mandatory = $True)]
    [string]$DemoUser,

    [Parameter(Mandatory = $True)]
    [string]$DemoPassword
)
$ErrorActionPreference = "Stop"

Write-Host "Configuring Service Account Permission"
$cmd = "$PSScriptRoot/Configure-UserLogonPrivileges.ps1"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${ServiceUser}")
$args += ("-PrivilegeName", 'SeServiceLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"

$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${ServiceUser}")
$args += ("-PrivilegeName", 'SeBatchLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"

Write-Host "Updating MFDS Service Propertie"
Stop-Service -Name "MF_CCITCP2"
$Account="${DomainNetBIOSName}\${ServiceUser}"
$Service=gwmi win32_service -filter "Name='MF_CCITCP2'"
$Service.change($null,$null,$null,$null,$null,$false,$Account,$ServicePassword,$null,$null,$null)

Write-Host "Deleting ESCWA Service"
$Service=gwmi win32_service -filter "Name='ESCWA'"
$Service.delete()

Write-Host "Configuring Demo Account"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${DemoUser}")
$args += ("-PrivilegeName", 'SeRemoteInteractiveLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"


Write-Host "Starting Directory Server"
Start-Service -Name "MF_CCITCP2"