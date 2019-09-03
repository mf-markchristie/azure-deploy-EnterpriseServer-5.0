param(
    [Parameter(Mandatory)]
    [string]DomainNetBIOSName

    [Parameter(Mandatory)]
    [string]ServiceUser

    [Parameter(Mandatory)]
    [System.Security.SecureString]ServicePassword

    [Parameter(Mandatory)]
    [string]DemoUser

    [Parameter(Mandatory)]
    [System.Security.SecureString]DemoPassword
)

Write-Host "Creating temporary working directory."
mkdir -path "c:\tmp"
Set-Location "c:\tmp"

Write-Host "Configuring Service Account"
$PSScriptRoot/Configure-UserLogonPrivileges.ps1 -Username "${DomainNetBIOSName}\${ServiceUser}" -PrivilegeName "SeServiceLogonRight" -Status Grant
$PSScriptRoot/Configure-UserLogonPrivileges.ps1 -Username "${DomainNetBIOSName}\${ServiceUser}" -PrivilegeName "SeBatchLogonRight" -Status Grant
Stop-Service -Name "MF_CCITCP2"
$ServiceCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList "${DomainNetBIOSName}\${ServiceUser}", $ServicePassword
Set-Service -Name "MF_CCITCP2" -Credential $ServiceCredentials
Remove-Service -Name "ESCWA"

Write-Host "Configuring Demo Account"
$PSScriptRoot/Configure-UserLogonPrivileges.ps1 -Username "${DomainNetBIOSName}\${DemoUser}" -PrivilegeName "SeRemoteInteractiveLogonRight" -Status Grant


Write-Host "Starting Directory Server"
Start-Service -Name "MF_CCITCP2"