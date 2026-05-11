$ErrorActionPreference = 'Stop'

$chromePaths = @(
  "$Env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${Env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)
$chromePath = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromePath) {
  Write-Error 'Chrome not found in Program Files'
  exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'Chrome (DevTools MCP).lnk'

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = $chromePath
$lnk.Arguments = '--remote-debugging-port=9222 --user-data-dir="' + $Env:TEMP + '\chrome-devtools-mcp"'
$lnk.IconLocation = "$chromePath,0"
$lnk.Description = 'Chrome with remote debugging on :9222 for chrome-devtools-mcp'
$lnk.Save()
