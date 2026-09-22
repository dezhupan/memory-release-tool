param([string]$WindhawkRoot = '')

$entry = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'TaskbarDiagnostic.ps1'
& $entry -WindhawkRoot $WindhawkRoot
