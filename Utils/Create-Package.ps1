function createExe{
    param(
        [Parameter(Mandatory=$true)]
        [string]$scriptName
    )

    $cmd = "$PSScriptRoot/ps2exe.ps1"
    $args = @()
    $args += ("-InputFile", '.\package\scripts\$scriptName.ps1')
    $args += ("-outputFile", '.\package\scripts\$scriptName.exe')
    Invoke-Expression "$cmd $args"
    Remove-Item -Path ".\package\scripts\$scriptName.ps1"
    Remove-Item -Path ".\package\scripts\$scriptName.exe.config"
}

Push-Location $PSScriptRoot
mkdir ".\package"
mkdir ".\package\DSC"
mkdir ".\package\scripts"
mkdir ".\package\templates"

Copy-Item -Path "$PSScriptRoot\..\scripts\*" -Destination ".\package\scripts"
Copy-Item -Path "$PSScriptRoot\..\DSC\*" -Destination ".\package\DSC"
Copy-Item -Path "$PSScriptRoot\..\templates\*" -Destination ".\package\templates"
Copy-Item -Path "$PSScriptRoot\..\createUiDefinition.json" -Destination ".\package"
Copy-Item -Path "$PSScriptRoot\..\mainTemplate.json" -Destination ".\package"

createExe -scriptName "Install-ES"
createExe -scriptName "Configure-FS-Node"

Compress-Archive -Path .\package\* -DestinationPath .\package.zip -Force
Remove-Item -Path ".\package" -Recurse -Force

Pop-Location