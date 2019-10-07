param(
    [boolean]$test=$false
)

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
if ($test -eq $true) {
    .\package\scripts\azcopy copy ".\package" "https://teststoragemarkc.blob.core.windows.net/estest?sv=2018-03-28&ss=bfqt&srt=sco&sp=rwdlacup&se=2019-12-31T20:03:44Z&st=2019-10-07T11:03:44Z&spr=https&sig=X7fw6WNRHs1us%2BcHFG4xFqZMGylyYKZKy%2BL0dXwq%2F3Y%3D" --recursive
}

Remove-Item -Path ".\package" -Recurse -Force

Pop-Location