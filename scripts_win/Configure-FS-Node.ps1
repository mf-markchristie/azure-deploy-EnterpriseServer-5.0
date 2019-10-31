param(
    [Parameter(Mandatory = $True)]
    [string]$FSViewPassword,

    [Parameter(Mandatory = $True)]
    [int]$FSPort = 3000,

    [Parameter(Mandatory = $True)]
    [string]$DomainDNSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser
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
$WorkDir = "f:\FSdir"
mkdir -Path $WorkDir
$cmd = "C:\Program Files (x86)\Micro Focus\Enterprise Server\bin\fs.exe"
Start-Process -FilePath $cmd -ArgumentList "-pf $WorkDir\pass.dat -u SYSAD -pw SYSAD" -Wait
Start-Process -FilePath $cmd -ArgumentList "-pf $WorkDir\pass.dat -u FSVIEW -pw $FSViewPassword" -Wait

$Config = "/s FS1,MFPORT:${FSPort}
/pf $WorkDir\pass.dat
/wd $WorkDir
/cm CCITCP"

Add-Content $WorkDir\fs.conf $Config
Start-Process -FilePath "cmd" -ArgumentList "/c `"C:\Program Files (x86)\Micro Focus\Enterprise Server\CreateEnv.bat`" & fsservice -i FS1 /cf $WorkDir\fs.conf"

Start-Process -Wait -FilePath "$PSScriptRoot\Prepare-Demo.exe" -ArgumentList "-DeployFsDemo Y"
Expand-Archive -Path "c:\BankDemo_FS.zip" -DestinationPath "c:\"
Copy-Item -Recurse "C:\BankDemo_FS\System\catalog\data\*" "$WorkDir"

New-SmbShare -Name "FSdir" -Path $WorkDir -FullAccess "$DomainNetBIOSName\$ServiceUser"

Start-Service -Name "Micro Focus Fileshare Service: FS1"