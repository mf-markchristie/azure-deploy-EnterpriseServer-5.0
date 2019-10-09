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
    [string]$DemoPassword,

    [string]$DeployDbDemo = "N",

    [string]$DeployPacDemo = "N"
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

if ($DeployDbDemo -eq "Y" -or $DeployPacDemo -eq "Y") {
    Import-Module BitsTransfer
    Start-BitsTransfer -Source "https://download.microsoft.com/download/D/5/E/D5EEF288-A277-45C8-855B-8E2CB7E25B96/x64/msodbcsql.msi" -Destination "."
    Start-Process -Wait -FilePath "msiexec" -ArgumentList "/quiet /passive /qn /i msodbcsql.msi IACCEPTMSODBCSQLLICENSETERMS=YES ADDLOCAL=ALL"

    Start-BitsTransfer -Source "https://download.microsoft.com/download/C/8/8/C88C2E51-8D23-4301-9F4B-64C8E2F163C5/x64/MsSqlCmdLnUtils.msi" -Destination "."
    Start-Process -Wait -FilePath "msiexec" -ArgumentList "/quiet /passive /qn /i MsSqlCmdLnUtils.msi IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES"

    $env:Path += "c:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn"
}
if ($DeployDbDemo -eq "Y") {
    Add-OdbcDsn -Name DBNASEDB -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=sqlLoadBalancer", "Trusted_Connection=Yes", "Database=BANKDEMO")
}
if ($DeployPacDemo -eq "Y") {
    Add-OdbcDsn -Name SS.VSAM -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=sqlLoadBalancer", 'Database=MicroFocus$SEE$Files$VSAM')
    Add-OdbcDsn -Name SS.MASTER -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=sqlLoadBalancer", "Database=master")
    Add-OdbcDsn -Name SS.REGION -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=sqlLoadBalancer", 'Database=MicroFocus$CAS$Region$DEMOPAC')
    Add-OdbcDsn -Name SS.CROSSREGION -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=sqlLoadBalancer", 'Database=MicroFocus$CAS$CrossRegion')
}

#Download & Import Region Definitions
#Setup region files

Set-NetFirewallProfile -Profile Domain -Enabled False