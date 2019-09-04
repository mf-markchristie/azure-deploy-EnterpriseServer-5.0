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

Write-Host "Updating Service Propertie"
Stop-Service -Name "MF_CCITCP2"

$Account="${DomainNetBIOSName}\${ServiceUser}"
$Service="name='MF_CCITCP2'"
$svc=gwmi win32_service -filter $Service
$svc.change($null,$null,$null,$null,$null,$null,$Account,$ServicePassword,$null,$null,$null)

Remove-Service -Name "ESCWA"

Write-Host "Configuring Demo Account"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${DemoUser}")
$args += ("-PrivilegeName", 'SeRemoteInteractiveLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"


Write-Host "Starting Directory Server"
Start-Service -Name "MF_CCITCP2"