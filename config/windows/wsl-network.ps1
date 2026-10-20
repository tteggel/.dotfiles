# Run from Windows PowerShell. The default only collects diagnostics.
# -Recover also shuts down ALL WSL distros and restarts the host WSL service.
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Distro = 'thixos',
    [switch]$Recover,
    [string]$OutputDirectory = "$env:LOCALAPPDATA\wsl-network\reports"
)

$ErrorActionPreference = 'Stop'

if ($Recover) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '-Recover requires an elevated Windows PowerShell window.'
    }
}

# A stuck WSL client must not prevent host diagnostics or service recovery.
function Invoke-BoundedCommand {
    param([string]$FilePath, [string]$Arguments, [int]$TimeoutSeconds = 20)
    $stdout = [IO.Path]::GetTempFileName()
    $stderr = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
            -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Cache the native handle before waiting so Windows PowerShell 5.1
        # retains the exit code even for very short-lived commands.
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Output "Timed out after ${TimeoutSeconds}s: $FilePath $Arguments"
        } else {
            Write-Output "Exit code: $($process.ExitCode)"
        }
        # wsl --version emits UTF-16 on some versions, including without a BOM.
        Get-Content $stdout, $stderr -ErrorAction SilentlyContinue | ForEach-Object { $_ -replace "`0", '' }
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Write-Section {
    param([string]$Name, [scriptblock]$Action)
    Write-Output "`n=== $Name ==="
    try { & $Action | Out-String -Width 200 | Write-Output }
    catch { Write-Output $_.Exception.Message }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$report = Join-Path $OutputDirectory ("wsl-network-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
Start-Transcript -Path $report | Out-Null
try {
    Write-Section 'Time and WSL version' {
        Get-Date -Format o
        Invoke-BoundedCommand wsl.exe '--version'
        Invoke-BoundedCommand wsl.exe '--list --verbose'
        Get-Content "$env:USERPROFILE\.wslconfig"
    }
    Write-Section 'Host services and WSL processes' {
        Get-Service WslService, LxssManager, hns, vmcompute, MpsSvc, WinNat -ErrorAction SilentlyContinue |
            Format-Table Name, Status, StartType
        Get-Process wslservice, wslhost, wslrelay, dllhost, vmcompute -ErrorAction SilentlyContinue |
            Format-Table Name, Id, StartTime, Handles
    }
    Write-Section 'Host adapters, routes and DNS' {
        Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed
        Get-NetRoute -DestinationPrefix '0.0.0.0/0', '::/0' -ErrorAction SilentlyContinue |
            Format-Table InterfaceAlias, DestinationPrefix, NextHop, RouteMetric
        Get-DnsClientServerAddress | Format-Table InterfaceAlias, AddressFamily, ServerAddresses
    }
    Write-Section 'Host HTTPS by name' {
        Invoke-BoundedCommand curl.exe '--noproxy "*" --connect-timeout 5 --max-time 8 --head --silent --show-error https://example.com'
    }
    Write-Section 'Host TCP/TLS without DNS' {
        Invoke-BoundedCommand curl.exe '--noproxy "*" --connect-timeout 5 --max-time 8 --head --silent --show-error https://1.1.1.1'
    }
    Write-Section 'Guest addresses, routes and DNS ownership' {
        Invoke-BoundedCommand wsl.exe "--distribution $Distro --exec sh -c `"ip -brief address; ip route; ip -6 route; ls -l /etc/resolv.conf; cat /etc/resolv.conf; tailscale status`""
    }
    Write-Section 'Guest HTTPS by name' {
        Invoke-BoundedCommand wsl.exe "--distribution $Distro --exec sh -lc `"curl --noproxy '*' --connect-timeout 5 --max-time 8 --head --silent --show-error https://example.com`""
    }
    Write-Section 'Guest TCP/TLS without DNS' {
        Invoke-BoundedCommand wsl.exe "--distribution $Distro --exec sh -lc `"curl --noproxy '*' --connect-timeout 5 --max-time 8 --head --silent --show-error https://1.1.1.1`""
    }
    Write-Section 'Active host firewall profiles and explicit block rules' {
        Get-NetFirewallProfile -PolicyStore ActiveStore |
            Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction, AllowLocalFirewallRules
        Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Action Block -ErrorAction SilentlyContinue |
            Format-Table DisplayName, Direction, Profile, PolicyStoreSourceType
    }
    Write-Section 'Active WSL Hyper-V firewall policy' {
        $wslId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
        Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name $wslId |
            Format-List Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LoopbackEnabled, AllowHostPolicyMerge
        Get-NetFirewallHyperVRule -PolicyStore ActiveStore -VMCreatorId $wslId -ErrorAction SilentlyContinue |
            Format-Table Name, Direction, Action, Protocol, LocalPorts, RemotePorts
    }
    Write-Section 'Recent host network and service warnings/errors' {
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-24); Level=1,2,3} -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'Tcpip|DNS|HNS|Host-Network|Hyper-V|Netwtw|NDIS|WLAN|Service Control' } |
            Select-Object -First 50 TimeCreated, ProviderName, Id, Message | Format-List
    }
    if ($Recover) {
        Write-Output 'Stopping all WSL distros, then restarting the Windows WSL service.'
        Invoke-BoundedCommand wsl.exe '--shutdown'
        $service = Get-Service WslService -ErrorAction SilentlyContinue
        if (-not $service) { $service = Get-Service LxssManager }
        Restart-Service -InputObject $service -Force
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
        Write-Output 'WSL service restarted. Reopen the distro, then run this report again to verify connectivity.'
    }
} finally {
    Stop-Transcript | Out-Null
}
Write-Output "Report saved to $report"
