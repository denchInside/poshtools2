using namespace System.IO

function New-PSShim {
    param(
        [String]$FromFile,
        [String]$OutputDirectory,
        [ValidateSet(5, 7)]
        [Int32]$PSVersion = 7
    )
    
    if ([Path]::GetExtension($FromFile) -ne ".ps1") {
        throw "unsupported target file"
    }
    
    if (-not [File]::Exists($FromFile)) {
        throw "source file does not exist"
    }
    
    if (-not [Directory]::Exists($OutputDirectory)) {
        throw "output directory does not exist"
    }
    
    $FromFile = [Path]::GetFullPath($FromFile)
    $OutputDirectory = [Path]::GetFullPath($OutputDirectory)
    
    $outputFile = [Path]::Combine(
        $OutputDirectory,
        [Path]::GetFileNameWithoutExtension($FromFile) + ".cmd"
    )
    
    $psExePath = switch ($PSVersion) {
        7 { "pwsh" }
        5 { "powershell" }
    }
    
    if (-not $psExePath) {
        throw "could not find powershell $PSVersion"
    }
    
    $template = "@echo off`r`n{0} -File `"{1}`" %*"
    
    [String]::Format($template, $psExePath, $FromFile) |
        Out-File -Encoding utf8 -LiteralPath $outputFile
    
    return $outputFile
}

Export-ModuleMember -Function New-PSShim
