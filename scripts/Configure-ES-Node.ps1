param(
    [Parameter(Mandatory = $True)]
    [string]$DomainDNSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [string]$ServicePassword,

    [Parameter(Mandatory = $True)]
    [string]$DemoUser,

    [Parameter(Mandatory = $True)]
    [string]$DemoPassword
)

function Get-NetBIOSName
{
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}

$ErrorActionPreference = "Stop"
$DomainNetBIOSName=(Get-NetBIOSName -DomainName $DomainDNSName)

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
Start-Service -Name "MF_CCITCP2"

Write-Host "Deleting ESCWA Service"
$Service=gwmi win32_service -filter "Name='ESCWA'"
$Service.delete()

Write-Host "Configuring Demo Account"
$args = @()
$args += ("-Username", "${DomainNetBIOSName}\${DemoUser}")
$args += ("-PrivilegeName", 'SeRemoteInteractiveLogonRight')
$args += ("-Status", 'Grant')
Invoke-Expression "$cmd $args"


Write-Host "Configuring Directory Server"
$cmd = "C:\Program Files (x86)\Micro Focus\Enterprise Server\bin\mfds.exe"
Start-Process -FilePath $cmd -ArgumentList "--listen-all" -Wait
Restart-Service -Name "MF_CCITCP2"

#Download & Import Region Definitions
#Configure ODBC drivers
#Setup region files

Set-NetFirewallProfile -Profile Domain -Enabled False