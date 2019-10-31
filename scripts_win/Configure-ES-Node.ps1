param(
    [Parameter(Mandatory = $True)]
    [string]$DomainDNSName,

    [Parameter(Mandatory = $True)]
    [string]$ServiceUser,

    [Parameter(Mandatory = $True)]
    [string]$ServicePassword,

    [Parameter(Mandatory = $True)]
    [string]$ClusterPrefix,

    [Parameter(Mandatory = $True)]
    [Int32]$Index,

    [string]$RedisIp = "",

    [string]$RedisPassword = "",

    [string]$DeployDbDemo = "N",

    [string]$DeployPacDemo = "N",

    [string]$DeployFsDemo = "N"
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

function Add-DirectoryPermissions
{
    param(
        [string]$Directory,
        [string]$Account
    )
    $Inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
    $Propagation = [system.security.accesscontrol.PropagationFlags]"None"
    $Acl = Get-Acl $Directory
    $Accessrule = New-Object system.security.AccessControl.FileSystemAccessRule($Account,"FullControl", $inherit, $propagation, "Allow")
    $Acl.AddAccessRule($Accessrule)
    Set-Acl -aclobject $Acl $Directory
}

function Schedule-Cmd
{
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName,

        [Parameter(Mandatory=$true)]
        [string]$Task,

        [Parameter(Mandatory=$true)]
        [string]$TaskArguments,

        [Parameter(Mandatory=$true)]
        [String]$UserName,

        [Parameter(Mandatory=$true)]
        [string]$Password
    )

    # Schedule the Add-DNS call to run as <domain>\<domainuser> 10s from now and then delete the task 60s later
    $run = Get-Date
    Register-ScheduledTask -TaskName "$TaskName Task"  -User "$UserName" -Password "$Password" -InputObject ( `
            (
                New-ScheduledTask -Action (
                    New-ScheduledTaskAction -Execute $Task -Argument $TaskArguments
                ) `
                -Trigger (
                    New-ScheduledTaskTrigger -Once -At $run.AddSeconds(5)
                ) `
                -Settings (
                    New-ScheduledTaskSettingsSet  -DeleteExpiredTaskAfter 01:00:00 # Delete one hour after trigger expires (leave around for awhile for debugging)
                )
            ) | %{ $_.Triggers[0].EndBoundary = $run.AddSeconds(65).ToString('s') ; $_ } # Run through a pipe to set the end boundary of the trigger
    )
}

$ErrorActionPreference = "Stop"
$DomainNetBIOSName=(Get-NetBIOSName -DomainName $DomainDNSName)

Write-Host "Configuring Service Account Permission"
$cmd = "$PSScriptRoot\Configure-UserLogonPrivileges.ps1"
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

Write-Host "Updating MFDS Service Properties"
Stop-Service -Name "MF_CCITCP2"
$Account="${DomainNetBIOSName}\${ServiceUser}"
$Service=gwmi win32_service -filter "Name='MF_CCITCP2'"
$Service.change($null,$null,$null,$null,$null,$false,$Account,$ServicePassword,$null,$null,$null)
Start-Service -Name "MF_CCITCP2"

Write-Host "Deleting ESCWA Service"
$Service=gwmi win32_service -filter "Name='ESCWA'"
$Service.delete()


Start-Process -Wait -FilePath "$PSScriptRoot\Prepare-Demo.exe" -ArgumentList "-DeployDbDemo $DeployDbDemo -DeployPACDemo $DeployPacDemo -DeployFsDemo $DeployFsDemo"

if ($DeployDbDemo -eq "Y" -or $DeployPacDemo -eq "Y") {
    Write-Host "Setting up ODBC Drivers"
    Start-Process -Wait -FilePath "$PSScriptRoot\Prepare-Demo.exe" -ArgumentList "-DeployODBC Y"
    $env:Path += "c:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn"
}
if ($DeployDbDemo -eq "Y") {
    Add-OdbcDsn -Name DBNASEDB -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=$ClusterPrefix-sqlLB", "Trusted_Connection=Yes", "Database=BANKDEMO")
}
if ($DeployPacDemo -eq "Y") {
    Add-OdbcDsn -Name SS.VSAM -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=$ClusterPrefix-sqlLB", "Trusted_Connection=Yes", 'Database=MicroFocus$SEE$Files$VSAM')
    Add-OdbcDsn -Name SS.MASTER -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=$ClusterPrefix-sqlLB", "Trusted_Connection=Yes", "Database=master")
    Add-OdbcDsn -Name SS.REGION -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=$ClusterPrefix-sqlLB", "Trusted_Connection=Yes", 'Database=MicroFocus$CAS$Region$DEMOPAC')
    Add-OdbcDsn -Name SS.CROSSREGION -DriverName "ODBC Driver 13 for SQL Server" -DsnType "System" -Platform "32-bit" -SetPropertyValue @("Server=$ClusterPrefix-sqlLB", "Trusted_Connection=Yes", 'Database=MicroFocus$CAS$CrossRegion')
}

$Account="${DomainNetBIOSName}\${ServiceUser}"

$installBase = "C:\Program Files (x86)\Micro Focus\Enterprise Server\bin"
$mfdscmd = "$installBase\mfds.exe"
$casstartcmd = "$installBase\casstart.exe"
$deployDbScript = "$pwd\Deploy-Start-ES.bat"
Set-Location -Path "c:\"

if ($DeployFsDemo -eq "Y") {
    Write-Host "Setting up FS Demo"
    Expand-Archive -Path "BankDemo_FS.zip" -DestinationPath "."
    Start-Process -FilePath $mfdscmd -ArgumentList "/g 5 C:\BankDemo_FS\Repo\BNKDMFS.xml D" -Wait
    [System.Environment]::SetEnvironmentVariable("FSHOST", "$ClusterPrefix-fs","Machine")
    Add-DirectoryPermissions -Directory "C:\BankDemo_FS" -Account $Account
    Schedule-Cmd -TaskName "startBNKDMFS" -Task $casstartcmd -TaskArguments "-rBNKDMFS" -UserName $Account -Password $ServicePassword
}

if ($DeployDbDemo -eq "Y") {
    Write-Host "Setting up DB Demo"
    Expand-Archive -Path "BankDemo_SQL.zip" -DestinationPath "."
    Start-Process -FilePath $mfdscmd -ArgumentList "/g 5 C:\BankDemo_SQL\Repo\BNKDMSQL.xml D" -Wait
    Add-DirectoryPermissions -Directory "C:\BankDemo_SQL" -Account $Account
    Schedule-Cmd -TaskName "startBNKDMSQL" -Task $casstartcmd -TaskArguments "-rBNKDMSQL" -UserName $Account -Password $ServicePassword
}

if ($DeployPacDemo -eq "Y") {
    Write-Host "Setting up PAC Demo"
    Expand-Archive -Path "BankDemo_PAC.zip" -DestinationPath "."
    if ($Index -eq 0) {
        $Region = "BNKDM"
    } else {
        $Region = "BNKDM2"
    }
    Start-Process -FilePath $mfdscmd -ArgumentList "/g 5 C:\BankDemo_PAC\Repo\$Region.xml D" -Wait
    Add-DirectoryPermissions -Directory "C:\BankDemo_PAC" -Account $Account

    $JMessage = '{ \"mfUser\": \"\", \"mfPassword\": \"\" }'
    $RequestURL = "http://$clusterPrefix-esadmin:10004/logon"
    $Origin = "Origin: http://$clusterPrefix-esadmin:10004"
    curl.exe -sX POST  $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie-jar cookie.txt | Out-Null
    $JMessage = '
        {
            \"mfCASSOR\": \":ES_SCALE_OUT_REPOS_1=DemoPSOR=redis,' + $RedisIp + ':6379##TMP\",
            \"mfCASPAC\": \"DemoPAC\"
        }'
    $HostName = $ClusterPrefix + '-es0' + [string]($Index + 1)
    $RequestURL = "http://$clusterPrefix-esadmin:10004/native/v1/regions/$HostName/86/$Region"
    curl.exe -sX PUT $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H $Origin -d $Jmessage --cookie-jar cookie.txt | Out-Null

    if ($RedisPassword -ne "") {
        mkdir -path "C:\ProgramData\Micro Focus\Enterprise Developer\mfsecrets"
        Start-Process -FilePath "$installBase\mfsecretsdefaults.exe" -ArgumentList '-location "C:\ProgramData\Micro Focus\Enterprise Developer\mfsecrets"'
        Start-Process -FilePath "$installBase\mfsecretsadmin.exe" -ArgumentList "write microfocus/CAS/SOR-DemoPSOR-Pass $RedisPassword" -Wait
    }

    Schedule-Cmd -TaskName "startBNKDMPAC" -Task $deployDbScript -TaskArguments "$Region" -UserName $Account -Password $ServicePassword
}
