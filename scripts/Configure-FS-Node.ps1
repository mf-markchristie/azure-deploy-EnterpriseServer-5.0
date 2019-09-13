param(
    [Parameter(Mandatory = $True)]
    [string]$FSViewPassword,

    [Parameter(Mandatory = $True)]
    [int]$FSPort = 3000
)
$WorkDir = c:\FSWork
mkdir -Path $WorkDir
$cmd = "C:\Program Files (x86)\Micro Focus\Enterprise Server\bin\fs.exe"
Start-Process -FilePath $cmd -ArgumentList "-pf $WorkDir\pass.dat -u SYSAD -pw SYSAD" -Wait
Start-Process -FilePath $cmd -ArgumentList "-pf $WorkDir\pass.dat -u FSVIEW -pw $FSViewPassword" -Wait

$Config = "/s FS1,MFPORT:${FSPort}
/pf $WorkDir\pass.dat
/wd $WorkDir
/cm CCITCP"

Add-Content $WorkDir\fs.conf $Config
Start-Process -FilePath "cmd" -ArgumentList "/c `"C:\Program Files (x86)\Micro Focus\Enterprise Server\CreateEnv.bat`" & fs -cf $WorkDir\fs.conf"

# Set up network share
# Copy catalog and data