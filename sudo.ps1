using namespace System.Diagnostics

$ErrorActionPreference = "Stop"

if ($Args.Length -lt 1) {
	Write-Host "usage: sudo <cmd...>"
	exit 0
}

$command = Get-Command $Args[0] -ErrorAction SilentlyContinue

if (-not $command) {
	Write-Error "$($Args[0]) not found"
}

$startInfo = [ProcessStartInfo]::new()
$startInfo.Verb = 'RunAs'
$startInfo.UseShellExecute = $true
# $startInfo.WindowStyle = 'Hidden'

if ($command.CommandType -eq 'Application') {
	$startInfo.FileName = $command.Path
	for ($i = 1; $i -lt $Args.Length; $i++) {
		$startInfo.ArgumentList.Add($Args[$i])
	}
} elseif ($command.CommandType -in 'Alias', 'Function', 'ExternalScript', 'Cmdlet') {
	$startInfo.FileName = [Environment]::ProcessPath
	$startInfo.ArgumentList.Add('-NoExit')
	$startInfo.ArgumentList.Add('-c')
	$startInfo.ArgumentList.Add($Args -join ' ')
} else {
	Write-Error "invalid command type: $($command.CommandType)"
}

$process = [Process]::Start($startInfo)
$process.WaitForExit()
exit $process.ExitCode
