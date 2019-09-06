param(
    [Parameter(Mandatory = $True)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [string]$ServicePassword
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

Write-Host "Updating ESCWA Service Propertie"
Stop-Service -Name "ESCWA"
$Account="${DomainNetBIOSName}\${ServiceUser}"
$Service=gwmi win32_service -filter "Name='ESCWA'"
$Service.change($null,$null,$null,$null,$null,$false,$Account,$ServicePassword,$null,$null,$null)
Start-Service -Name "ESCWA"

Write-Host "Deleting MFDS Service"
$Service=gwmi win32_service -filter "Name='MF_CCITCP2'"
$Service.delete()

function addDS {

    Param
    (
        [Parameter(Mandatory = $true)]
        [string] $Host,
        [Parameter(Mandatory = $true)]
        [string] $Port,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $JMessage = '
{
    \"MfdsHost\": \"' + $Host + '\",
    \"MfdsIdentifier\": \"' + $Name + '\",
    \"MfdsPort\": ' + $Port + '
}'

    $RequestURL = 'http://localhost:10004/server/v1/config/mfds'
    $Origin = 'Origin: http://localhost:10004'

    curl.exe -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie cookie.txt | Out-Null
}

Write-Host "Configuring ESCWA"
$JMessage = '{ \"mfUser\": \"SYSAD\", \"mfPassword\": \"SYSAD\" }'

$RequestURL = 'http://localhost:10004/logon'
$Origin = 'Origin: http://localhost:10004'

curl.exe -sX POST  $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie-jar cookie.txt | Out-Null
addDS -Host "mfes-es01" -Name "mfes-es01" -Port 86
addDS -Host "mfes-es01" -Name "mfes-es02" -Port 86

Set-NetFirewallProfile -Profile Domain -Enabled False