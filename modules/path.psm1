function Register-Path {
    <#
    .SYNOPSIS
        Adds a directory to the PATH environment variable.
    
    .DESCRIPTION
        Adds a directory to the PATH environment variable for the specified scope.
        Automatically handles trailing slashes and prevents duplicate entries.
    
    .PARAMETER Path
        The directory path to add to PATH.
    
    .PARAMETER Scope
        The scope for the PATH modification. Valid values: 'System', 'CurrentUser'.
        Default is 'CurrentUser'.
    
    .PARAMETER Permanent
        When enabled (default), saves the PATH permanently. When disabled, only modifies
        the current session's PATH.
    
    .EXAMPLE
        Register-Path -Path "C:\Tools\bin" -Scope CurrentUser
        
    .EXAMPLE
        Register-Path -Path "C:\Tools\bin" -Scope System -Permanent:$false
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('System', 'CurrentUser')]
        [string]$Scope = 'CurrentUser',
        
        [Parameter(Mandatory = $false)]
        [switch]$Permanent = $true
    )
    
    begin {
        # Validate path exists
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Warning "Path does not exist: $Path"
            return
        }
        
        # Resolve to full path
        $ResolvedPath = (Resolve-Path -LiteralPath $Path).Path
        
        # Normalize path (remove trailing slashes)
        $NormalizedPath = $ResolvedPath.TrimEnd('\', '/')
        
        # Check for admin rights if System scope
        if ($Scope -eq 'System') {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "Administrator privileges required to modify System PATH. Run PowerShell as Administrator."
            }
        }
    }
    
    process {
        # Determine environment variable target
        $Target = if ($Scope -eq 'System') { 
            [System.EnvironmentVariableTarget]::Machine 
        } else { 
            [System.EnvironmentVariableTarget]::User 
        }
        
        # Get current PATH
        $CurrentPath = if ($Permanent) {
            [System.Environment]::GetEnvironmentVariable('Path', $Target)
        } else {
            $env:Path
        }
        
        # Split PATH into array and normalize each entry
        $PathEntries = $CurrentPath -split ';' | Where-Object { $_ -ne '' } | ForEach-Object {
            $_.TrimEnd('\', '/')
        }
        
        # Check if path already exists (case-insensitive)
        $PathExists = $PathEntries | Where-Object { 
            $_ -eq $NormalizedPath -or $_.TrimEnd('\', '/') -eq $NormalizedPath 
        }
        
        if ($PathExists) {
            Write-Verbose "Path already exists in $Scope PATH: $NormalizedPath"
            return
        }
        
        # Add new path
        $NewPathEntries = @($PathEntries) + @($NormalizedPath)
        $NewPath = $NewPathEntries -join ';'
        
        # Apply changes
        if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add $NormalizedPath")) {
            if ($Permanent) {
                [System.Environment]::SetEnvironmentVariable('Path', $NewPath, $Target)
                Write-Host "Successfully added to $Scope PATH (permanent): $NormalizedPath" -ForegroundColor Green
                
                # Update current session
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine) + ';' + 
                            [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
            } else {
                $env:Path = $NewPath
                Write-Host "Successfully added to session PATH (temporary): $NormalizedPath" -ForegroundColor Green
            }
        }
    }
}

function Unregister-Path {
    <#
    .SYNOPSIS
        Removes a directory from the PATH environment variable.
    
    .DESCRIPTION
        Removes a directory from the PATH environment variable for the specified scope.
        Automatically handles trailing slashes when searching for the path to remove.
    
    .PARAMETER Path
        The directory path to remove from PATH.
    
    .PARAMETER Scope
        The scope for the PATH modification. Valid values: 'System', 'CurrentUser'.
        Default is 'CurrentUser'.
    
    .PARAMETER Permanent
        When enabled (default), removes the PATH permanently. When disabled, only modifies
        the current session's PATH.
    
    .EXAMPLE
        Unregister-Path -Path "C:\Tools\bin" -Scope CurrentUser
        
    .EXAMPLE
        Unregister-Path -Path "C:\Tools\bin\" -Scope System
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('System', 'CurrentUser')]
        [string]$Scope = 'CurrentUser',
        
        [Parameter(Mandatory = $false)]
        [switch]$Permanent = $true
    )
    
    begin {
        # Normalize path (remove trailing slashes)
        $NormalizedPath = $Path.TrimEnd('\', '/')
        
        # Try to resolve to full path if it exists
        if (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) {
            $NormalizedPath = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
        }
        
        # Check for admin rights if System scope
        if ($Scope -eq 'System') {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "Administrator privileges required to modify System PATH. Run PowerShell as Administrator."
            }
        }
    }
    
    process {
        # Determine environment variable target
        $Target = if ($Scope -eq 'System') { 
            [System.EnvironmentVariableTarget]::Machine 
        } else { 
            [System.EnvironmentVariableTarget]::User 
        }
        
        # Get current PATH
        $CurrentPath = if ($Permanent) {
            [System.Environment]::GetEnvironmentVariable('Path', $Target)
        } else {
            $env:Path
        }
        
        # Split PATH into array
        $PathEntries = $CurrentPath -split ';' | Where-Object { $_ -ne '' }
        
        # Find and remove matching entries (case-insensitive, handles trailing slashes)
        $OriginalCount = $PathEntries.Count
        $NewPathEntries = $PathEntries | Where-Object {
            $CurrentEntry = $_.TrimEnd('\', '/')
            $CurrentEntry -ne $NormalizedPath
        }
        
        # Check if anything was removed
        if ($NewPathEntries.Count -eq $OriginalCount) {
            Write-Warning "Path not found in $Scope PATH: $NormalizedPath"
            return
        }
        
        $RemovedCount = $OriginalCount - $NewPathEntries.Count
        $NewPath = $NewPathEntries -join ';'
        
        # Apply changes
        if ($PSCmdlet.ShouldProcess("$Scope PATH", "Remove $NormalizedPath")) {
            if ($Permanent) {
                [System.Environment]::SetEnvironmentVariable('Path', $NewPath, $Target)
                Write-Host "Successfully removed from $Scope PATH (permanent): $NormalizedPath ($RemovedCount occurrence(s))" -ForegroundColor Green
                
                # Update current session
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine) + ';' + 
                            [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
            } else {
                $env:Path = $NewPath
                Write-Host "Successfully removed from session PATH (temporary): $NormalizedPath ($RemovedCount occurrence(s))" -ForegroundColor Green
            }
        }
    }
}

# Export module members
Export-ModuleMember -Function Register-Path, Unregister-Path
