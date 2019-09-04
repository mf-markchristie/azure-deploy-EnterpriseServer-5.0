param(
    [Parameter(Mandatory = $True)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [System.Security.SecureString]$ServicePassword,

    [Parameter(Mandatory = $True)]
    [string]$DemoUser,

    [Parameter(Mandatory = $True)]
    [System.Security.SecureString]$DemoPassword
)

Write-Host "Configuring Service Account"
$cmd = "$PSScriptRoot/Configure-UserLogonPrivileges.ps1"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${ServiceUser}")
$args += ("-PrivilegeName", 'SeServiceLogonRight')
$args += ("-Status", 'Grant')
Write-Host "$cmd $args"
Invoke-Expression "$cmd $args"

$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${ServiceUser}")
$args += ("-PrivilegeName", 'SeBatchLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"
Stop-Service -Name "MF_CCITCP2"
$ServiceCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList "${DomainNetBIOSName}\${ServiceUser}", $ServicePassword
Set-Service -Name "MF_CCITCP2" -Credential $ServiceCredentials
Remove-Service -Name "ESCWA"

Write-Host "Configuring Demo Account"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${DemoUser}")
$args += ("-PrivilegeName", 'SeRemoteInteractiveLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"


Write-Host "Starting Directory Server"
Start-Service -Name "MF_CCITCP2"