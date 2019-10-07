param(
    [Parameter(Mandatory = $True)]
    [string]$DomainDNSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [string]$ServicePassword,

    [Parameter(Mandatory = $True)]
    [int]$ESCount,

    [Parameter(Mandatory = $True)]
    [string]$clusterPrefix,

    [String]$DomainNetBIOSName=(Get-NetBIOSName -DomainName $DomainDNSName)
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


$Directory = "C:\ProgramData\Micro Focus\Enterprise Developer\ESCWA"
$Inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
$Propagation = [system.security.accesscontrol.PropagationFlags]"None"
$Acl = Get-Acl $directory
$Accessrule = New-Object system.security.AccessControl.FileSystemAccessRule($Account,"FullControl", $inherit, $propagation, "Allow")
$Acl.AddAccessRule($Accessrule)
Set-Acl -aclobject $Acl $Directory
Start-Service -Name "ESCWA"

Write-Host "Deleting MFDS Service"
Stop-Service -Name "MF_CCITCP2"
$Service=gwmi win32_service -filter "Name='MF_CCITCP2'"
$Service.delete()

function addDS {

    Param
    (
        [Parameter(Mandatory = $true)]
        [string] $HostName,
        [Parameter(Mandatory = $true)]
        [string] $Port,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $JMessage = '
    {
        \"MfdsHost\": \"' + $HostName + '\",
        \"MfdsIdentifier\": \"' + $Name + '\",
        \"MfdsPort\": \"' + $Port + '\"
    }'

    $RequestURL = 'http://localhost:10004/server/v1/config/mfds'
    $Origin = 'Origin: http://localhost:10004'

    curl.exe -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie cookie.txt | Out-Null
}

Write-Host "Configuring ESCWA"
$JMessage = '{ \"mfUser\": \"\", \"mfPassword\": \"\" }'

$RequestURL = 'http://localhost:10004/logon'
$Origin = 'Origin: http://localhost:10004'

curl.exe -sX POST  $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie-jar cookie.txt | Out-Null

$RequestURL = 'http://localhost:10004/server/v1/config/mfds'
$mfdsObj = curl.exe -sX GET $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin --cookie cookie.txt | ConvertFrom-Json
$Uid=$mfdsObj[0].Uid
$RequestURL = "http://localhost:10004/server/v1/config/mfds/$Uid"
curl.exe -sX DELETE $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin --cookie cookie.txt | Out-Null

addDS -HostName "$clusterPrefix-es01" -Name "$clusterPrefix-es01" -Port "86"
if ($ESCount -eq 2) {
    addDS -HostName "$clusterPrefix-es02" -Name "$clusterPrefix-es02" -Port "86"
}
addDs -HostName "$clusterPrefix-fs" -Name "$clusterPrefix-fs" -Port "86"

Set-NetFirewallProfile -Profile Domain -Enabled False