param(
    [Parameter(Mandatory = $True)]
    [string]$escwaHostname
)


function createShortcut{
    param(
        [Parameter(Mandatory = $True)]
        [string]
        $href,

        [Parameter(Mandatory = $True)]
        [string]
        $label
    )
    $wshShell = New-Object -ComObject "WScript.Shell"
    $urlShortcut = $wshShell.CreateShortcut(
      (Join-Path $wshShell.SpecialFolders.Item("AllUsersDesktop") "$label.lnk")
    )
    $urlShortcut.TargetPath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    $urlShortcut.Arguments = $href
    $urlShortcut.Save()
}


Write-Host "Installing Chrome"
$Installer = "chrome_installer.exe";
Start-BitsTransfer -Source "http://dl.google.com/chrome/install/375.126/chrome_installer.exe" -Destination ("./" + $Installer)
Start-Process -FilePath ".\$Installer" -Args "/silent /install" -Verb RunAs -Wait
REG.exe Add HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice /v ProgId /t REG_SZ /d ChromeHTML /f
REG.exe Add HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice /v ProgId /t REG_SZ /d ChromeHTML /f


createShortcut -href 'http://' + $escwaHostname + ':10004' -label "ES Common Web Administration"
createShortcut -href "https://supportline.microfocus.com" -label "Micro Focus Supportline resources"
createShortcut -href "https://www.microfocus.com/support-and-services/supportline/" -label "Logging issues with Supportline"
createShortcut -href "https://community.microfocus.com/t5/Enterprise-Server/ct-p/EnterpriseServer" -label "Enterprise Server Community"
createShortcut -href "https://www.microfocus.com/documentation/enterprise-developer/" -label "Product Documentation"
createShortcut -href "https://www.microfocus.com/ondemand/courses/enterprise-server-basic-diagnostics-training-free/" -label "Enterprise Server Diagnostics Training Course "

