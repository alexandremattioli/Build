<#
.SYNOPSIS
    List VMs from a vSphere Resource Pool (default: 'Build') and optionally filter to Windows servers.

.DESCRIPTION
    Uses VMware PowerCLI to connect to a vCenter and enumerate VMs in a given
    Resource Pool. Outputs a table by default or JSON when -OutputJson is specified.

.PARAMETER vCenter
    vCenter server FQDN or IP

.PARAMETER User
    vCenter username (e.g. administrator@vsphere.local)

.PARAMETER Password
    vCenter password (optional; you will be prompted if omitted)

.PARAMETER ResourcePool
    Resource Pool name (default: 'Build')

.PARAMETER OnlyWindows
    If set, returns only VMs with a Windows guest OS

.PARAMETER OutputJson
    Path to write JSON output (optional). If omitted, prints a formatted table.

.EXAMPLE
    .\Get-ResourcePoolVMs.ps1 -vCenter vcsa.example.local -User 'administrator@vsphere.local' -ResourcePool 'Build' -OnlyWindows

.EXAMPLE
    .\Get-ResourcePoolVMs.ps1 -vCenter vcsa -User 'svc-vsphere' -ResourcePool 'Build' -OutputJson C:\Build\coordination\windows_servers.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$vCenter,
    [Parameter(Mandatory=$true)] [string]$User,
    [Parameter(Mandatory=$false)] [string]$Password,
    [Parameter(Mandatory=$false)] [string]$ResourcePool = 'Build',
    [switch]$OnlyWindows,
    [Parameter(Mandatory=$false)] [string]$OutputJson
)

# Ensure PowerCLI is available
$module = Get-Module -ListAvailable -Name VMware.PowerCLI
if (-not $module) {
    Write-Host 'VMware PowerCLI not found. Installing for current user...' -ForegroundColor Yellow
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    try {
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Error "Failed to install VMware.PowerCLI: $_"
        exit 1
    }
}
Import-Module VMware.PowerCLI -ErrorAction Stop

# Disable CEIP prompt and invalid cert warnings for unattended usage
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Build credential
if ([string]::IsNullOrWhiteSpace($Password)) {
    $secure = Read-Host -Prompt 'Enter vCenter password' -AsSecureString
} else {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
}
$cred = [PSCredential]::new($User, $secure)

# Connect to vCenter
try {
    $vi = Connect-VIServer -Server $vCenter -Credential $cred -ErrorAction Stop
} catch {
    Write-Error "Failed to connect to vCenter $vCenter: $_"
    exit 2
}

try {
    $rp = Get-ResourcePool -Name $ResourcePool -ErrorAction Stop
} catch {
    Write-Error "Resource Pool '$ResourcePool' not found."
    Disconnect-VIServer -Server $vCenter -Confirm:$false | Out-Null
    exit 3
}

# Fetch VMs in resource pool
$vms = Get-VM -Location $rp -ErrorAction Stop

# Gather guest details safely
$result = foreach ($vm in $vms) {
    $guestOS = $null
    $ips = @()
    $tools = $null
    try {
        $guestOS = $vm.Guest.OSFullName
        $tools = $vm.ExtensionData.Guest.ToolsStatus
        $ipRaw = $vm.ExtensionData.Guest.IPAddress
        if ($ipRaw) {
            if ($ipRaw -is [string]) { $ips = @($ipRaw) } else { $ips = $ipRaw }
        }
    } catch {
        # Ignore guest info errors
    }

    [PSCustomObject]@{
        Name        = $vm.Name
        PowerState  = $vm.PowerState
        GuestOS     = $guestOS
        IPs         = ($ips | Where-Object { $_ -match '^(\d+\.){3}\d+$' } | Sort-Object -Unique) -join ', '
        Cluster     = ($vm.VMHost | Get-Cluster).Name
        Host        = $vm.VMHost.Name
        ToolsStatus = $tools
        CPU         = $vm.NumCpu
        MemoryGB    = [Math]::Round($vm.MemoryGB, 1)
        ResourcePool= $ResourcePool
    }
}

if ($OnlyWindows) {
    $result = $result | Where-Object { $_.GuestOS -match 'Windows' }
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $result | Sort-Object Name | Format-Table -AutoSize
} else {
    $json = $result | Sort-Object Name | ConvertTo-Json -Depth 6
    $dir = Split-Path -Parent $OutputJson
    if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json | Out-File -FilePath $OutputJson -Encoding UTF8
    Write-Host "Wrote VM inventory to $OutputJson" -ForegroundColor Green
}

# Disconnect
Disconnect-VIServer -Server $vCenter -Confirm:$false | Out-Null
