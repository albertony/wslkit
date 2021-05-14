#
# .SYNOPSIS
#
# Utility script for Windows Subsystem for Linux (WSL).
#
# .DESCRIPTION
#
# Utility script for managing WSL distros, mainly version 2 (WSL2).
# Supports tab completion of distro names.
# Supports setting up VPNKit: A set of services providing customized network
# connectivity from a network device in the VM used to host WSL2 distros,
# via a unix socket and Windows named pipe, to a gateway process running on the
# host, routing traffic to the host network device. Docker Desktop with WSL2
# backend is using much of the same system, the core parts used here are actually
# taken from the Docker Desktop toolset. The problem with the Hyper-V based
# networking that is default in WSL, is that it can easily be problematic with
# VPN, and will be blocked by some firewall software etc.
#
# New-Distro/Remove-Distro:
# New-Distro downloads one of the Linux WSL2 distro images from Microsoft
# Store, performs custom install, which will register them with WSL2 but not add
# them to Windows (no shortcut, no launcher, not uninstall from Settings etc),
# and which will create the virtual disk file into a configurable location.
# Remove-Distro unregisters the WSL distro and deleting its hard disk file.
#
# Start-Distro:
# Start new session, same as executing wsl.exe with only optional distribution
# name as argument. Default is to start it within current PowerShell console,
# use parameter -NewWindow to start as new console window.
#
# Stop-Distro:
# Stops a single distro, executing wsl.exe --terminate <name>, or all distros
# as well as the common virtual machine, executing wsl.exe --shutdown, if
# parameter -All.
#
# New-VpnKit:
# Downloads and prepares a copy-install program directory on host, containing
# tools and configuration files for the VPNKit network setup, deployed into
# the distro by Intall-VpnKit.
# This includes:
# - wsl-vpnkit (Linux/WSL2 shell script) from https://github.com/albertony/wsl-vpnkit (fork of https://github.com/sakai135/wsl-vpnkit)
# - vpnkit.exe (Windows executable) and vpnkit-tap-vsockd (Linux/WSL2 executable)
#   from Docker Desktop for Windows: https://hub.docker.com/editions/community/docker-ce-desktop-windows/
# - npiperelay.exe (Windows executable) from https://github.com/jstarks/npiperelay
# - resolv.conf and wsl.conf (Linux/WSL2 DNS configuration files) generated.
# For updating, just run the command again, it will replace existing files.
# There is no Uninstall command, but to uninstall just delete the program
# directory. Remember, though, that any WSL distros configured with VPNKit
# will have reference to this path!
#
# Intall-VpnKit/Unintall-VpnKit:
# Intall-VpnKit copies executables prepared by a previous New-VpnKit
# from host and into the WSL distribution, and then performs necessary
# configuration. This includes installing the required packages if on
# a distro supported by this script: Primarily the "socat" package (with
# dependencies such as libwrap0 and libssl1.1 if also missing), which is
# missing on most (all) distributions. Also iproute2 (for the ip command),
# sed and grep are needed and will be installed if missing, but these are
# included by default on most distributions - with Arch as a the single
# known exception. Assuming there is no network connectivity in WSL,
# the package file(s) are downloaded on host and installed from file in WSL.
# The socat package is required by the VPNKit tooling.
# Debian 9 and Ubuntu does 20.04 does not include socat, but this script
# supports installing it. Other WSL distro imagess have not been tested.
# For updating, just run the command again, it will replace existing files.
# Unintall-VpnKit reverts everyting that Intall-VpnKit, except
# the package installations (socat).
#
# Start-VpnKit:
# Starts the VPNKit script that enables the network pipe connection.
# Default is to start in a new console window, but can also be started
# within the existing session. The distro must have been configured
# with Intall-VpnKit first!
# Note: If running multiple WSL distros, then the VPNKit script can
# only run in one of them, but since all are effectively sharing a
# single virtual machine they will all be able to use the vpnkit
# networking. The one thing that should be notet is that the script
# will update the DNS server settings in /etc/resolv.conf only on
# the distro in which it is running. For other distros to use the
# Windows host, via the vpnkit gateway, for DNS resolving, the
# nameserver configuration in /etc/resolv.conf must already be set
# correctly (or manually updated). The resolv.conf file generated
# by New-VpnKit and copied into the distros by Intall-VpnKit
# has hard-coded the IP 192.168.67.1 (and just in case, also a free,
# public DNS service IP), which is taken from the current
# version of the wsl-vpnkit, and is the value it sets as the gateway
# address when starting vpnkit. So as long as you make sure to run
# New-VpnKit first, and then Intall-VpnKit for all distros,
# then all should be using the same networking as long as
# Start-VpnKit is executed on one of them. If you need to, you can
# change the resolv.conf manually, but remember that the instance
# you run Start-VpnKit in will temporarily replace it with its own
# version using only the vpnkit gateway, and if you run Intall-VpnKit
# again it will replace the existing /etc/resolv.conf permanently.
#
# Various utilities:
# Additional generic WSL utility functions, that are more or less
# convenience wrappers for specific wsl.exe command line modes
# and stored configuration in registry. There are a lot of options
# that can be set in WSL configuration file /etc/wsl.conf, but these
# are not managed here (except for options that can also be set in registry).
# Note that the when accessing the registry, we are accessing settings
# managed by the LxssManager service, which the wsl.exe command line utility
# interfaces with. Luckily all changes seem to be reflected immediately,
# no need to restart services etc to make wsl.exe in sync with changes we
# do "behind the scenes" in registry.
# Some of the functions are:
#   Get-Distro
#   Get-DistroImage
#   Get-DefaultDistroVersion/Set-DefaultDistroVersion
#   Get-DefaultDistro/Set-DefaultDistro
#   Get-DistroDistributionName/Set-DistroDistributionName
#   Get-DistroPackageName
#   Get-DistroPath/Set-DistroPath
#   Get-DistroDefaultUserId/Set-DistroDefaultUserId
#   Get-DistroFlags/Set-DistroFlags
#   Get-DistroInterop/Set-DistroInterop
#   Get-DistroAutoMount/Set-DistroAutoMount
#   Get-DistroVersion
#   Get-DistroFileSystemVersion
#   Rename-Distro
#   Move-Distro
#
# Main script for the VPNKit part, and the main inspiration for the
# network related functionality, is based on the following repository:
#   https://github.com/sakai135/wsl-vpnkit
#
# Background information on the pipe based networking used by VPNKit
# is available in Docker documentation:
#   https://github.com/moby/vpnkit/blob/master/docs/ethernet.md#plumbing-inside-docker-for-windows
#
# Note:
# - Tested on Debian 9 (stretch) and Ubuntu 20.04 LTS (Focal Fossa)
#   official WSL images from Microsoft Store, Alpine 3.13.1 official
#   "Minimal root filesystem" distribution from alpinelinux.org,
#   and Arch 2021.02.01 official "bootstrap" distribution.
# - If there are problems with process already running, named pipe already
#   existing etc: Check if you have a vpnkit.exe process on the host computer
#   and kill that, terminate the distro (wsl.exe --terminate) or
#   shutdown entire WSL VM (wsl.exe --shutdown), and try again.
# - To be able to run the VPNKit utility, the WSL distro installation must have
#   package 'socat' installed. If WSL does not have network connectivity, the
#   package file (and any missing dependencies) must be donloaded on the host
#   and then installed from file into the WSL distro. This script handles
#   this process automatically, in the Install-VpnKit method.
# - The script installed in WSL will get a reference back to the program
#   directory on host, in the default value of variable VPNKIT_PATH which must
#   contain the path to vpnkit.exe. If this is moved then the script must be
#   updated accordingly, or the VPNKIT_PATH variable must be overridden each
#   time the script is executed.
# - The /etc/resolv.conf created by Intall-VpnKit will contain a hard coded
#   IP that is assumed to be the vpnkit gateway, so if this IP changes in the
#   wsl-vpnkit launcher script then resolv.conf should be updated accordingly.
#   The wsl-vpnkit launcher script will actually temporarily replace resolv.conf
#   with a version containing the real vpnkit gateway IP, but if running other
#   distros they will not get this update and uses the stored /etc/resolv.conf,
#   normally with content from Intall-VpnKit.
# - A previous version of the VPNKit script (wsl-vpnkit) had to be run in bash,
#   so when installing on Alpine distribution, which does not include bash by
#   default, it had to be installed in addition to the required socat package.
#   This was changed 16 Feb 2021, so the script is now plain posix
#   sh, busybox and Alpine compatible.
#
# .EXAMPLE
# mkdir C:\Wsl
# PS C:\Wsl> cd C:\Wsl
# PS C:\Wsl> New-Distro -Name Primary -Destination .\Distributions\Primary -Image debian-gnulinux -UserName me -SetDefault
# PS C:\Wsl> New-VpnKit -Destination .\VPNKit
# PS C:\Wsl> Install-VpnKit -Name Primary -ProgramDirectory .\VPNKit
# PS C:\Wsl> Start-VpnKit
# PS C:\Wsl> Start-Distro
#
[CmdletBinding()]
param
(
	[pscredential] $GitHubCredential # GitHub API imposes heavy rate limiting which can be avoided by authentication with username and a Personal Access Token as password.
)

function Get-GitHubApiAuthenticationHeaders([pscredential]$Credential)
{
	if ($Credential)
	{
		@{
			Authorization = "Basic $([Convert]::ToBase64String([System.Text.Encoding]::Ascii.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)")))"
		}
	}
	else
	{
		@{}
	}
}

# .SYNOPSIS
# Utility function function to pipe output from external commands into the verbose stream.
function Out-Verbose
{
	[CmdletBinding()]
	param([Parameter(ValueFromPipeline=$true)] $Message)
	process { $Message | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } } | Write-Verbose }
}

# .SYNOPSIS
# Utility function to create a new directory with an auto-generated unique name.
function New-TempDirectory
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path
	)
	do { $TempDirectory = Join-Path $Path ([System.IO.Path]::GetRandomFileName()) } while (Test-Path -LiteralPath $TempDirectory)
	New-Item -Path $TempDirectory -ItemType Directory | Select-Object -ExpandProperty FullName
}


# .SYNOPSIS
# Utility function go get valid, absolute path to a directory.
# .DESCRIPTION
# Will either throw if directory does not exist, or create it automatically.
function Get-Directory
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
		[switch] $Create
	)
	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		if (Test-Path -LiteralPath $Path) { throw "Path exists but is not a directory: ${Path}" }
		if (-not $Create) { throw "Path does not exist: ${Path}" }
		(New-Item -Path $Path -ItemType Directory).FullName
	} else {
		(Resolve-Path -LiteralPath $Path).Path
	}
}

# .SYNOPSIS
# Utility function to convert from regular filesystem path, absolute or relative,
# to "extended-length path".
# What it does is simply resolving to absolute path and adding prefix "\\?\",
# if not already present.
# .LINK
# Get-StandardizedPath
function Get-ExtendedLengthPath()
{
	param([Parameter(Mandatory,ValueFromPipeline)][string]$Path)
	if ($Path -and $Path.StartsWith("\\?\")) {
		$Path
	} else {
		"\\?\$($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(${Path}))"
	}
}

# .SYNOPSIS
# Utility function to convert from (possibly) "extended-length path" to back to
# standardized path.
# .DESCRIPTION
# What it does is simply removing the prefix "\\?\", if present.
# Since the extended-length paths are required to be absolute, the resulting path
# should also be an absolute path.
# .LINK
# Get-ExtendedLengthPath
function Get-StandardizedPath
{
	param([Parameter(Mandatory,ValueFromPipeline)][string]$Path)
	if ($Path -and $Path.StartsWith("\\?\")) {
		$Path.Substring(4)
	} else {
		$Path
	}
}

# .SYNOPSIS
# Utility function to download a single file from a specified URL to a specified location.
function Save-File
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Url,
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
		[pscredential] $Credential
	)
	if ($Credential) {
		Write-Verbose "Downloading ${Url} (authenticated as $($Credential.UserName)) -> ${Path}"
		#$GitHubApiHeaders = Get-GitHubApiAuthenticationHeaders -Credential $GitHubCredential
		#Invoke-WebRequest -Uri $Url -UseBasicParsing -DisableKeepAlive -OutFile $Path -Headers $GitHubApiHeaders
		Start-BitsTransfer -Source $Url -Destination $Path -Authentication Basic -Credential $Credential
		#$WebClient = New-Object System.Net.WebClient
		#$WebClient.Headers['Authorization'] = $GitHubApiHeaders['Authorization']
		#$WebClient.Credential = $GitHubCredential
		#$WebClient.DownloadFile($Url, $Path)
		#$WebClient.Dispose()
	} else {
		Write-Verbose "Downloading ${Url} -> ${Path}"
		Start-BitsTransfer -Source $Url -Destination $Path
	}
	# BitsTransfer may have problems with signed url downloads from GitHub, 
	# and also needs TLS 1.1/1.2 to be explicitely enabled on WinHTTP in Windows 7,
	# so then WebClient can be used instead.
	# Note: WebClient needs destination directory to exists, not BitsTransfer does not.
	#$WebClient = New-Object System.Net.WebClient
	#$WebClient.DownloadFile($Url, $Path)
	#$WebClient.Dispose()
}

# .SYNOPSIS
# Utility function to get path to 7-Zip utility, downloading it if necessary.
function Get-SevenZip
{
	[CmdletBinding()]
	param
	(
		# The directory path where 7-Zip (7z.exe and 7z.dll) will be downloaded into, if necessary.
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $DownloadDirectory,

		# Optional working directory where downloads will be temporarily placed. Default is current directory.
		[Parameter(Mandatory=$false)] [ValidateNotNullOrEmpty()] [string] $WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
	)
	$DownloadDirectory = Get-Directory -Path $DownloadDirectory -Create
	$TempDirectory = New-TempDirectory -Path $WorkingDirectory
	try
	{
		# Need the full (x64) edition to be able to extract installers etc.
		$ReleaseInfo = Invoke-RestMethod -Uri "https://sourceforge.net/projects/sevenzip/rss?path=/7-Zip" -DisableKeepAlive | Where-Object { $_.title.'#cdata-section' -match "(?:/7-Zip/)(\d+(\.\d+)*)(?:/7z\d+-x64.exe)" } | Select-Object -First 1
		# Download the basic edition if necessary, either because it is the requested edition or because it is needed to extract a more advanced edition later.
		# The full edition download is itself an archive, but its 7z/LZMA so we just need the simplest single-binary "7-Zip Reduced"
		# which there is a direct download link for, so we download it temporarily if not finding something else.
		# We need some 7-Zip utility to extract the download, see if there is one already, if not we will have to download the basic reduced version later
		$SevenZipUtilPath = Get-Command -CommandType Application "7z.exe", ".\7z.exe", "7za.exe", ".\7za.exe", "7zr.exe", ".\7zr.exe", "7zdec.exe", ".\7zdec.exe" -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
		if ($SevenZipUtilPath) {
			Write-Verbose "Using existing 7-Zip utility for extracting full edition archive download: ${SevenZipUtilPath}"
		} else {
			Write-Verbose "Downloading latest version of 7-Zip Basic edition to be able to extract full edition archive download"
			$DownloadName = "7zr.exe" # Single-binary reduced version, 7zr.exe, which can extract .7z and .lzma files only
			$DownloadUrl = "https://www.7-zip.org/a/${DownloadName}"
			$DownloadFullName = Join-Path $TempDirectory $DownloadName
			Save-File -Url $DownloadUrl -Path $DownloadFullName
			if (-not (Test-Path -PathType Leaf $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
			$SevenZipUtilPath = $DownloadFullName
		}
		# Download the full edition
		Write-Verbose "Downloading latest version of 7-Zip Full edition"
		$DownloadName = $ReleaseInfo.title.'#cdata-section'.Split("/")[-1]
		$DownloadUrl = "https://www.7-zip.org/a/${DownloadName}"
		$DownloadFullName = Join-Path $TempDirectory $DownloadName
		Save-File -Url $DownloadUrl -Path $DownloadFullName
		if (-not (Test-Path -PathType Leaf $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
		# Extract (using the downloaded single-binary reduced version, 7zr.exe, which can extract .7z and .lzma files only)
		&$SevenZipUtilPath x "-o${TempDirectory}" "${DownloadFullName}" | Out-Verbose
		if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
		Remove-Item -LiteralPath $DownloadFullName
		# Copy into destination
		Write-Verbose "Copying extracted binaries to target location ${DownloadDirectory}"
		Move-Item -Path (Join-Path $TempDirectory "7z.exe"), (Join-Path $TempDirectory "7z.dll") -Destination $DownloadDirectory -Force # 7z.exe, 7z.dll
		$SevenZipPath = Join-Path $DownloadDirectory "7z.exe"
		if (-not (Test-Path -PathType Leaf $SevenZipPath)) { throw "Cannot find extracted $SevenZipPath" }
		$SevenZipPath
	}
	finally
	{
		if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
			Remove-Item -LiteralPath $TempDirectory -Recurse
		}
	}
}

# .SYNOPSIS
# Get names of installed distros, possibly filtered on only currently running ones.
# .DESCRIPTION
# This function executes `wsl.exe --list --quiet` in the background.
# See also Get-DistroDistributionNam, which returns names retrieved from the registry
# (should give same results).
# .LINK
# Get-DistroDistributionName
# Test-Distro
function Get-Distro([switch] $Running)
{
	if ($Running) {
		wsl.exe --list --running --quiet | ForEach-Object { $_ -replace '\x00','' } | Where-Object { $_ } # Workaround for character encoding issues!
	} else{
		wsl.exe --list --quiet | ForEach-Object { $_ -replace '\x00','' } | Where-Object { $_ } # Workaround for character encoding issues!
	}
}

# .SYNOPSIS
# Utility function for checking if a distro with specified name exists, and optionally if also currently running.
function Test-Distro([string] $Name, [switch] $Running)
{
	$Name -in @(Get-Distro -Running:$Running)
}

# .SYNOPSIS
# Helper function for optionally specifying the distro options: --distribution and --user.
function GetWslCommandDistroOptions([string] $Name, [string] $UserName)
{
	$Options = @()
	if ($Name) {
		if (-not (Test-Distro $Name)) { throw "There is no WSL distro with name '${Name}'" }
		$Options += '--distribution', $Name
	} # else: No option means let wsl use default
	if ($UserName) {
		$Options += '--user', $UserName
	}
	$Options
}

# .SYNOPSIS
# Helper function to get argument completion.
# .DESCRIPTION
# Enable for a parameter accepting name of distro by prepending with:
# [ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
# .LINK
# ValidateDistroName
function CompleteDistroName
{
	param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
	Get-Distro | Where-Object { -not $WordToComplete -or ($_ -like $WordToComplete.Trim('"''') -or $_.ToLower().StartsWith($WordToComplete.Trim('"''').ToLower())) } | ForEach-Object { if ($_.IndexOfAny(" `"") -ge 0){"`'${_}`'"}else{$_} }
}

# .SYNOPSIS
# Helper function to validate value of parameter accepting name of distro.
# .DESCRIPTION
# Can be used in combination with argument completion with CompleteDistroName.
# Enable by prepending parameter with:
# [ValidateScript({ValidateDistroName $_})]
# .LINK
# CompleteDistroName
function ValidateDistroName
{
	
	param ([string] $Name, [switch] $Physical)
	if ($Name) {
		$ValidSet = Get-Distro
		if ($Name -notin $ValidSet) { throw [System.Management.Automation.PSArgumentException] "The value `"${_}`" is not a known image. Only `"$($ValidSet -join '", "')`" can be specified." }
	}
	$true
}

# .SYNOPSIS
# Helper function to get the primary registry key.
function GetWSLRegistryKey([string] $Name, [switch] $All)
{
	Get-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\
}

# .SYNOPSIS
# Helper function to get registry "item" for a specific distro or all distros.
# .DESCRIPTION
# The returned type is (list of) PSCustomObject, containing properties for all
# registry values, and "context" properties PSPath, PSParentPath and PSChildName
# with reference to the registry location.
function GetDistroRegistryItem([string] $Name, [switch] $All)
{
	if ($All) {
		GetWSLRegistryKey | Get-ChildItem | Get-ItemProperty
	} else {
		$Items = GetWSLRegistryKey | Get-ChildItem | Get-ItemProperty | Where-Object -Property DistributionName -eq (GetDistroNameOrDefault -Name $Name)
		if ($Items.Count -gt 1) { throw "More than one distro with name '${Name}' found in registry" }
		$Items
	}
}

# .SYNOPSIS
# Get default version that new WSL distros will be created with.
# .LINK
# Set-DefaultDistroVersion
function Get-DefaultDistroVersion()
{
	GetWSLRegistryKey | Get-ItemPropertyValue -Name DefaultVersion
}

# .SYNOPSIS
# Set default version that new WSL distros will be created with.
# .DESCRIPTION
# The same can be done with `wsl.exe --set-default-version <Version>`.
# .LINK
# Get-DefaultDistroVersion
function Set-DefaultDistroVersion
{
	[CmdletBinding()] param([ValidateRange(1, 2)][Parameter(Mandatory)] [int] $Version)
	GetWSLRegistryKey | Set-ItemProperty -Name DefaultVersion -Value $Version
}

# .SYNOPSIS
# Get the name of the installed distro that is currently defined as default in WSL.
# .DESCRIPTION
# This is the distro that will be used by other functions when a specific distro is
# not specified, and also by the standard `wsl.exe` command line utility when not
# specifying a distro with argument --distribution or -d.
# .LINK
# Set-DefaultDistro
function Get-DefaultDistro()
{
	$Guid = GetWSLRegistryKey | Get-ItemPropertyValue -Name DefaultDistribution
	if ($Guid) {
		GetDistroRegistryItem -All | Where-Object -Property PSChildName -eq $Guid | Select-Object -ExpandProperty DistributionName
	}
}

# .SYNOPSIS
# Set the distro that should be defined as default in WSL.
# .LINK
# Get-DefaultDistro
function Set-DefaultDistro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Name of distro. Required, cannot assume WSL default in this case!
		[Parameter(Mandatory)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name
	)
	# Note: This method updates registry directly, but can also use 'wsl.exe --set-default' which updates registry through the LxssManager service.
	$Item = GetDistroRegistryItem -Name $Name
	if (-not $Item) {
		throw "Unable to find distro with name ${Name} in registry" # Since the validation uses wsl.exe there can in theory be mismatch with what is in registry?
	} elseif ($Item.PSChildName -eq (GetWSLRegistryKey | Get-ItemPropertyValue -Name DefaultDistribution)) {
		Write-Warning "Specified distro is already the default"
	} else {
		GetWSLRegistryKey | Set-ItemProperty -Name DefaultDistribution -Value $Item.PSChildName
	}
}

# .SYNOPSIS
# Get names of installed distros, from the registry (Get-Distro uses `wsl.exe`).
# .DESCRIPTION
# Returns the DistributionName from registry, which is the same distro name as
# returned by Get-Distro, although it uses wsl.exe to retrieve them instead of
# accessing registry directly.
# Note: This *should* be the same as the input, but can be used to retrieve the name
# of the implicit default, and also assuming the autocompletion/validation of Name
# parameter is result of Get-Distro it can be used to verify that information
# in registry and returned by wsl.exe is matching.
# .LINK
# Get-Distro
# Set-DistroDistributionName
function Get-DistroDistributionName
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty DistributionName
}

# .SYNOPSIS
# Change the name of an installed distro.
# .DESCRIPTION
# This simply updates the DistributionName attribute in registry.
# Note that this will set the DistributionName attribute in registry unconditionally,
# and must be used with care. Consider using Rename-Distro instead, which adds some
# safety checks and supports asking for confirmation if called with parameter -Confirm.
# Note also that this will not change the name of the directory containing the distro's
# backing files (virtual disk image) on the host system - use Set-DistroPath to do that.
# .LINK
# Rename-Distro
# Get-DistroDistributionName
# Get-Distro
# Get-DistroPath
function Set-DistroDistributionName
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()] [ValidatePattern('^[a-zA-Z0-9._-]+$')] # See https://github.com/microsoft/WSL-DistroLauncher/blob/master/DistroLauncher/DistributionInfo.h
		[string] $NewName
	)
	GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name DistributionName -Value $NewName
}

# .SYNOPSIS
# Get the name of the Universal Windows Platform (UWP) app, if the distro were installed
# through one (e.g. from Microsoft Store).
# .DESCRIPTION
# Will be empty when not installed as UWP app, such as by this script's New-Distro function.
function Get-DistroPackageName
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty PackageFamilyName
}

# .SYNOPSIS
# Get the path to a distro's backing files (virtual disk image) on the host system.
# .LINK
# Set-DistroPath
function Get-DistroPath
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty BasePath | ForEach-Object { Get-StandardizedPath $_ }
}

# .SYNOPSIS
# Change the path to the directory containing a distro's backing files (virtual
# disk image) on the host system.
# .DESCRIPTION
# This simply updates the BasePath attribute in registry.
# Note that this will not move the existing directory, and it will set the BasePath
# attribute in registry unconditionally, and therefore must be used with care.
# Consider using Move-Distro instead!
# Note also that this will not change the name of the distribution, use
# Set-DistroDistributionName to do that.
# .LINK
# Get-DistroPath
# Set-DistroDistributionName
function Set-DistroPath
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		[Parameter(Mandatory)]
		[string] $Path
	)
	# Note: This will modify the path property pointing to the directory containing the disk image
	# for the distro! So this is a quite bold move! There is a method Move-Distro that will move the
	# existing disk file along with.
	$Item = GetDistroRegistryItem -Name $Name
	if (-not $Item) { throw "Distro '${Name}' not found in registry" }
	if (IsDistroItemPackageInstalled -Item $Item) {
		# Not tried it, but probably not wise to move these?
		throw "This distro seems to be installed as a standard UWP app, cannot change path"
	}
	$Item | Set-ItemProperty -Name BasePath -Value (Get-ExtendedLengthPath $Path)
}

# .SYNOPSIS
# Get the user id of the default user for a distro.
# .DESCRIPTION
# .LINK
# Set-DistroDefaultUserId
function Get-DistroDefaultUserId
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty DefaultUid
}

# .SYNOPSIS
# Set the default user of a distro
# .DESCRIPTION
# The user must be specified as the internal id integer value, as returned when
# executing `id -u` from within the distro.
# The default user is the one that other functions will run as on this distro,
# also the standard `wsl.exe` command line utility will use this user when not
# a different one is specified with arguments --user or -u.
# .LINK
# Set-DistroDefaultUserId
function Set-DistroDefaultUserId
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		[Parameter(Mandatory)]
		[int] $UserId # Typical values: 0 for root, 1000 for the optional default non-root user created on installation.
	)
	GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name DefaultUid -Value $UserId
}

# .SYNOPSIS
# Get the filsystem format version used for a distro.
# .DESCRIPTION
# The possible values are 1 for "LxFs" and 2 for "WslFs".
# This is not the same as the WSL/distribution version.
function Get-DistroFileSystemVersion
{
	# Get the filesystem format used. Not the same as distro / WSL version!
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	$Value = GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Version
	if ($Value -eq 1) { Write-Host "Filesystem format is LxFs"}
	elseif ($Value -eq 2) { Write-Host "Filesystem format is WslFs"}
	else { Write-Warning "Unknown registry value"}
	$Value
}

# Options that can be stored in registry.
# Default is for distros to have all set, corresponding to int value 15.
# Documented here: https://docs.microsoft.com/en-us/windows/win32/api/wslapi/ne-wslapi-wsl_distribution_flags
# The same options, and many more, can alternatively be set in configuration
# file /etc/wsl.conf within each WSL distro (https://docs.microsoft.com/en-us/windows/wsl/wsl-config).
[Flags()]
enum DistroFlags
{
	None = 0

	# Whether WSL will support launching Windows processes.
	# Equivalent to /etc/wsl.conf option "enabled" in section [interop].
	Interop = 1

	# Whether WSL will add Windows path elements to the $PATH environment variable.
	# Only relevant together with Interop flag.
	# Note: There are some reports that PATH traversal is slow, making command auto-completion
	# in the shell also slow, and unsetting this flag fixes it.
	# Equivalent to /etc/wsl.conf option "appendWindowsPath" in section [interop].
	AppendWindowsPath = 2

	# Whether WSL will automatically mount fixed drives (i.e C:/ or D:/) with DrvFs under /mnt.
	# If not set the drives won't be mounted automatically, but can still be mounted manually or via fstab.
	# Equivalent to /etc/wsl.conf option "enabled" in section [automount].
	AutoMount = 4

	# Undocumented value marking the distro as version 2 (WSL2).
	# Must be included in enum to make it complete, to be able to parse binary int values into enum.
	# There is also a separate registry value "Version" that can be used to
	# find the WSL version of the distro.
	Version2 = 8
}

# .SYNOPSIS
# Get the current flags value of a distro.
# .DESCRIPTION
# The flags value is a bit encoded value representing some options,
# such as whether to enable Windows-Linux Interop, automatically mount
# fixed drives from host etc.
# Default is for distros to have all options set.
# The same options, and many more, can alternatively be set in configuration
# file /etc/wsl.conf within each WSL distro.
# .LINK
# Set-DistroFlags
# Get-DistroInterop
# Get-DistroAutoMount
# Get-DistroVersion
# .LINK
# https://docs.microsoft.com/en-us/windows/win32/api/wslapi/ne-wslapi-wsl_distribution_flags
# https://docs.microsoft.com/en-us/windows/wsl/wsl-config
function Get-DistroFlags
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	[DistroFlags](GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags)
}

# .SYNOPSIS
# Modify the flags value of a distro.
# .DESCRIPTION
# The flags value is a bit encoded value representing some options,
# such as whether to enable Windows-Linux Interop, automatically mount
# fixed drives from host etc.
# Default is for distros to have all options set.
# The same options, and many more, can alternatively be set in configuration
# file /etc/wsl.conf within each WSL distro.
# .LINK
# Get-DistroFlags
# .LINK
# https://docs.microsoft.com/en-us/windows/win32/api/wslapi/ne-wslapi-wsl_distribution_flags
# https://docs.microsoft.com/en-us/windows/wsl/wsl-config
function Set-DistroFlags
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		[DistroFlags] $Flags,

		[switch] $Append # Append specified flags to existing value
	)
	$ExistingFlags = GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags
	if ($Append) {
		$Flags = $Flags -bor $ExistingFlags # Could use '+' but it can easily create invalid values
	}
	if ($ExistingFlags -band [DistroFlags]::Version2) { # Avoid removing the special Version2 flag: If it was set then force it to be included, since conversion between WSL1 and WSL2 is a bigger process and must go via "wsl.exe --set-version"!
		$Flags = $Flags -bor [DistroFlags]::Version2
	}
	GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name Flags -Value ([int]$Flags)
}

# .SYNOPSIS
# Get the current value of interop option flag.
# .DESCRIPTION
# The main option decides whether WSL will support launching Windows processes,
# with a suboption AppendWindowsPath, which (when main option is enabled) decides
# whether WSL will add Windows path elements to the $PATH environment variable.
#
# The same information are also part of the return value from Get-DistroFlags.
#
# This will return the options stored in registry, but it can also be set in
# configuration file /etc/wsl.conf, section [interop].
# .LINK
# Set-DistroInterop
# Get-DistroFlags
# Set-DistroFlags
function Get-DistroInterop
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	[DistroFlags](GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags) | ForEach-Object {
		@{
			Enabled = ($_ -band [DistroFlags]::Interop) -ne 0
			AppendWindowsPath = ($_ -band [DistroFlags]::AppendWindowsPath) -ne 0
		}
	}
}

# .SYNOPSIS
# Set the interop option flag value.
# .DESCRIPTION
# The main option decides whether WSL will support launching Windows processes,
# with a suboption AppendWindowsPath, which (when main option is enabled) decides
# whether WSL will add Windows path elements to the $PATH environment variable.
#
# Default is to enable both options, parameters -Disable or -DontAppendWindowsPath
# can be specified to disable either main option or suboption.
# Default for new WSL distros is both options enabled.
#
# The same can also be done with Set-DistroFlags.
#
# This will modify the options stored in registry, but it can also be set in
# configuration file /etc/wsl.conf, section [interop].
#
# NOTE: There are some reports that PATH traversal is slow with the AppendWindowsPath
# suboption enabled (which it is by default), making command auto-completion
# in the shell also slow.
#
# .LINK
# Get-DistroInterop
# Get-DistroFlags
# Set-DistroFlags
# .LINK
# https://docs.microsoft.com/en-us/windows/win32/api/wslapi/ne-wslapi-wsl_distribution_flags
# https://docs.microsoft.com/en-us/windows/wsl/wsl-config
function Set-DistroInterop
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Disable interop. Default is to enable, and in new WSL distros it is enabled by default.
		[switch] $Disable,

		# Do not add Windows path elements to the $PATH environment variable.
		# Default is to add, which is also the default in new WSL distros.
		# Only relevant when interop is enabled.
		[switch] $DontAppendWindowsPath
	)
	$Flags = GetDistroRegistryItem -Name $Name | Select-Object -ExpandProperty Flags
	if ($Disable) {
		$Flags = $Flags -band -bnot [DistroFlags]::Interop
	} else {
		$Flags = $Flags -bor [DistroFlags]::Interop
	}
	if ($DontAppendWindowsPath) {
		$Flags = $Flags -band -bnot [DistroFlags]::AppendWindowsPath
	} else {
		$Flags = $Flags -bor [DistroFlags]::AppendWindowsPath
	}
	GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name Flags -Value ([int]$Flags)
}

# .SYNOPSIS
# Get the current value of automount option flag.
# .DESCRIPTION
# This option decides whether WSL will automatically mount fixed drives (i.e C:/ or D:/)
# with DrvFs under /mnt. If not set the drives won't be mounted automatically, but can
# still be mounted manually or via fstab.
#
# The same information are also part of the return value from Get-DistroFlags.
#
# This will return the option stored in registry, but it can also be set in
# configuration file /etc/wsl.conf, section [automount].
# .LINK
# Set-DistroAutoMount
# Get-DistroFlags
# Set-DistroFlags
function Get-DistroAutoMount
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	[DistroFlags](GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags) | ForEach-Object { ($_ -band [DistroFlags]::AutoMount) -ne 0 }
}

# .SYNOPSIS
# Set the automunt option flag value.
# .DESCRIPTION
# This option decides whether WSL will automatically mount fixed drives (i.e C:/ or D:/)
# with DrvFs under /mnt. If not set the drives won't be mounted automatically, but can
# still be mounted manually or via fstab.
#
# Default is to enable, parameter -Disable can be specified to disable.
# Default for new WSL distros is enabled.
#
# The same can also be done with Set-DistroFlags.
#
# This will modify the options stored in registry, but it can also be set in
# configuration file /etc/wsl.conf, section [automount].
# .LINK
# Get-DistroAutoMount
# Get-DistroFlags
# Set-DistroFlags
# .LINK
# https://docs.microsoft.com/en-us/windows/win32/api/wslapi/ne-wslapi-wsl_distribution_flags
# https://docs.microsoft.com/en-us/windows/wsl/wsl-config
function Set-DistroAutoMount
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Disable automount. Default is to enable, and in new WSL distros it is enabled by default.
		[switch] $Disable
	)
	$Flags = GetDistroRegistryItem -Name $Name | Select-Object -ExpandProperty Flags
	if ($Disable) {
		$Flags = $Flags -band -bnot [DistroFlags]::AutoMount
	} else {
		$Flags = $Flags -bor [DistroFlags]::AutoMount
	}
	GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name Flags -Value ([int]$Flags)
}

# .SYNOPSIS
# Get the WSL version of a distro: 1 for WSL1, 2 for WSL2.
# .DESCRIPTION
# The same information are also part of the return value from Get-DistroFlags.
# .LINK
# Get-DistroFlags
function Get-DistroVersion
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags | ForEach-Object { if (($_ -band [DistroFlags]::Version2) -eq 0) { 1 } else { 2 } }
}

enum DistroState
{
	Normal = 1
	Installing = 3
	Uninstalling = 4
}

# .SYNOPSIS
# Return the current state of a distro.
# .DESCRIPTION
# The state is one of: Normal, Installing, Uninstalling.
function Get-DistroState
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	[DistroState](GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty State)
}

# .SYNOPSIS
# Helper function to get default distro name when name is not specified.
function GetDistroNameOrDefault([string] $Name)
{
	if (-not $Name) {
		$Name = Get-DefaultDistro
		if (-not $Name) { throw "Distro name must be specified as no default distro could be detected" }
	}
	$Name
}

# .SYNOPSIS
# Helper function (no autocomplete, validation etc) to get version of the distro.
# .DESCRIPTION
# End users should instead use Get-DistroVersion.
# .LINK
# Get-DistroVersion
function IsDistroVersion2([string] $Name)
{
	((GetDistroRegistryItem -Name $Name -All:$All | Select-Object -ExpandProperty Flags) -band [DistroFlags]::Version2) -ne 0
}

# .SYNOPSIS
# Helper function (no autocomplete, validation etc) to check if distro is installed as UWP package,
# e.g. Microsoft Store or appx installed otherwise.
# .DESCRIPTION
# Checks the package name as returned by Get-DistroPackageName and path as returned
# by Get-DistroPath.
# .LINK
# Get-DistroPackageName
# Get-DistroPath
function IsDistroItemPackageInstalled($Item)
{
	$PackageName = $Item | Select-Object -ExpandProperty PackageFamilyName -ErrorAction Ignore
	$Path = $Item | Select-Object -ExpandProperty BasePath | ForEach-Object { Get-StandardizedPath $_ }
	$HasPackagePath = $Path -and $Path.StartsWith((Resolve-Path -LiteralPath (Join-Path $Env:LocalAppData 'Packages')).Path)
	if ($PackageName -and $HasPackagePath) {
		Write-Verbose "Distro have a registered package name and path is in the standard package directory"
		$True
	}
	elseif ($PackageName -and -not $HasPackagePath) {
		Write-Warning "Distro seems package installed but path is not in the standard package directory"
		$True
	}
	elseif (-not $PackageName -and $HasPackagePath) {
		Write-Warning "Distro does not have a registered package name but path is in the standard package directory"
		$True
	}
	else {
		Write-Verbose "Distro does not have a registered package name and path is not in the standard package directory"
		$False
	}
}

# .SYNOPSIS
# Get identifier and download url for supported WSL distro images.
# .DESCRIPTION
# Some are from the "official" list, or at least endorsed by Microsoft, with
# direct download link on the following page: https://docs.microsoft.com/en-us/windows/wsl/install-manual.
# (but there are more distros available in Microsoft Store and also GitHub etc
# which are not supported).
# In addition some non-Microsoft endorsed distros are supported: Currently
# Alpine and Arch, both from official root filesystem images.
function Get-DistroImage
{
	# Get Microsoft direct download links
	$Links = Invoke-WebRequest -Uri 'https://docs.microsoft.com/en-us/windows/wsl/install-manual' -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Where-Object { $_.'data-linktype' -eq 'external' } | Select-Object -ExpandProperty href
	# Get urls with hostname aka.ms.
	# In article updated 09/15/2020 these are:
	#   Ubuntu 20.04
	#   Ubuntu 18.04
	#   Ubuntu 16.04
	#   Debian GNU/Linux
	#   Kali Linux
	#   OpenSUSE Leap 42
	#   SUSE Linux Enterprise Server 12.
	# (not including ARM versions of Ubuntu 20.04 and 18.04).
	$DistroImages = @($Links | Where-Object { $_.StartsWith('https://aka.ms/') -and -not $_.EndsWith('arm') } | ForEach-Object {
		$id = $_ -replace '^.*/(?:wsl-?)?([^/]*)$','$1'
		[PSCustomObject]@{
			Url = $_ # The URL to be used for downloading.
			Id = $Id # A unique id to be used in for selecting distro image in this script.
			FileName = "${Id}.appx" # The filename that will be downloaded. The URL may be redirected and not contain name. Using the extension to know how it can be installed.
		}
	})
	# Get urls with hostname github.com.
	# In article updated 09/15/2020 this is only "Fedora Remix for WSL", but it has only an ARM version which is free.
	#$DistroImages += @($Links | Where-Object { $_ -match 'https://github.com/([^/]*)/(?:wsl-?)?([^/]*)/releases/?' } | ForEach-Object {
	#	[PSCustomObject]@{
	#		Url = $_
	#		Id = $Matches[2]
	#	}
	#})
	# Other "unofficial" versions:
	#   ArchWSL (https://github.com/yuk7/ArchWSL/releases)
	
	# Alpine official "Minimal root filesystem" distribution, latest version.
	# There is also an unofficial Alpine WSL that is officially endorsed by the Alpine project (https://gitlab.alpinelinux.org/alpine/aports/-/issues/9408),
	# but it is only available on Microsoft Store without a direct download link, and anyway it is just a small wrapper around the
	# official "Minimal root filesystem" distribution, so we can easily replicate the necessary steps when installing!
	$ArchiveName = Invoke-WebRequest -Uri 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml' -UseBasicParsing -DisableKeepAlive | Select-String -Pattern 'alpine-minirootfs-(.*)-x86_64.tar.gz' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 0 | Select-Object -ExpandProperty Value
	if ($ArchiveName) {
		$Checksum = Invoke-WebRequest -Uri "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/${ArchiveName}.sha512" -UseBasicParsing -DisableKeepAlive | Select-String -Pattern "^(.*?)\s+${ArchiveName}$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		$DistroImages += @(
			[PSCustomObject]@{
				Url = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/${ArchiveName}"
				Id = 'alpine-minirootfs'
				FileName = $ArchiveName
				Checksum = [PSCustomObject]@{
					Algorithm = "SHA512"
					Value = $Checksum
				}
			}
		)
	}

	# Arch official "bootstrap" distribution, latest version.
	# There is only an unofficial Arch WSL available.
	# Note: The compressed tar file must be fixed before import, the filesystem must be moved from subfolder root.x86_64 to root.
	$ReleaseFolder = Invoke-WebRequest -Uri 'https://archive.archlinux.org/iso/' -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -Last 1 | Select-Object -ExpandProperty href
	$ArchiveName = "archlinux-bootstrap-$($ReleaseFolder.TrimEnd('/'))-x86_64.tar.gz"
	if ($ReleaseFolder) {
		$Checksum = Invoke-WebRequest -Uri "https://archive.archlinux.org/iso/${ReleaseFolder}sha1sums.txt" -UseBasicParsing -DisableKeepAlive | Select-String -Pattern "(?m)^(.*?)\s+${ArchiveName}$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		$DistroImages += @(
			[PSCustomObject]@{
				Url = "https://archive.archlinux.org/iso/${ReleaseFolder}${ArchiveName}"
				Id = 'archlinux-bootstrap'
				FileName = $ArchiveName
				Checksum = [PSCustomObject]@{
					Algorithm = "SHA1"
					Value = $Checksum
				}
			}
		)
	}

	# Fedora root filesystem from official Docker images, last three releases, including the "rawhide" development/daily build.
	# Alternative 1: Downloading from the official GitHub project used for publishing to Docker Hub.
	# These are imports of the so-called "Container Base" published on fedoraproject.org, but with some modifications?
	# Note: The GitHub API imposes heavy rate limiting!
	$GitHubApiHeaders = Get-GitHubApiAuthenticationHeaders -Credential $GitHubCredential
	(Invoke-RestMethod -Uri "https://api.github.com/repos/fedora-cloud/docker-brew-fedora/branches" -DisableKeepAlive -Headers $GitHubApiHeaders) | Where-Object -Property name -NE "master" | Sort-Object -Property name -Descending | Select-Object -First 3 | ForEach-Object {
		(Invoke-RestMethod -Uri "https://api.github.com/repos/fedora-cloud/docker-brew-fedora/contents?ref=$($_.name)" -DisableKeepAlive -Headers $GitHubApiHeaders) | Where-Object { $_.type -eq "dir" -and $_.name -eq "x86_64" } | Select-Object -ExpandProperty url -First 1 | ForEach-Object {
			(Invoke-RestMethod -Uri $_ -DisableKeepAlive -Headers $GitHubApiHeaders) | Where-Object { $_.type -eq "file" -and $_.name -match '(fedora-.*)[.-].*-x86_64.tar.xz' } | ForEach-Object {
				$DistroImages += @(
					[PSCustomObject]@{
						Url = $_.download_url
						Id = $Matches[1].ToLower()
						FileName = $_.name
						#TODO: No checksum available?
					}
				)
			}
		}
	}
	# Alternative 2: Downloading from official download server, which also includes both the full
	# "Fedora Container Base" and also the more minimalistic "Fedora Container Minimal Base".
	# TODO: These can be imported, but are not able to enter the shell, so obviously the Docker images does something extra...
	<#
	$BaseUrl = "https://dl.fedoraproject.org/pub/fedora/linux/"
	$Versions = @(
		@{
			MajorVersion = "Rawhide"
			BaseUrl = "${BaseUrl}development/"
		}
	)
	$Versions += (Invoke-WebRequest -Uri "${BaseUrl}releases/").Links.href | Where-Object { $_ -match '^(\d+)/' } | ForEach-Object { [int] $Matches[1] } | Sort-Object -Descending | Select-Object -First 2 | ForEach-Object {
		@{
			MajorVersion = $_
			BaseUrl = "${BaseUrl}releases/"
		}
	}
	$Versions | ForEach-Object {
		$MajorVersion = $_.MajorVersion
		$BaseUrl = "$($_.BaseUrl)$(`"$($_.MajorVersion)`".ToLower())/"
		$ChecksumFile = (Invoke-WebRequest -Uri "${BaseUrl}Container/x86_64/images/").Links.href | Select-String -Pattern "^Fedora-Container-.*-CHECKSUM$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 0 | Select-Object -ExpandProperty Value
		(Invoke-WebRequest -Uri "${BaseUrl}Container/x86_64/images/").Links.href | Where-Object { $_ -match "^(Fedora-Container-(?:Minimal-)?Base-${MajorVersion})-.*\.x86_64\.tar.xz$" } | ForEach-Object {
			$Checksum = (Invoke-RestMethod -Uri "${BaseUrl}Container/x86_64/images/${ChecksumFile}") | Select-String -Pattern "(?m)^(.*)\s+\($($_.Replace(".","\."))\)\s+=\s+(.*)$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups
			$DistroImages += @(
				[PSCustomObject]@{
					Url = "${BaseUrl}Container/x86_64/images/${_}"
					Id = $Matches[1].ToLower()
					FileName = $_
					Checksum = [PSCustomObject]@{
						Algorithm = $Checksum[1].Value
						Value = $Checksum[2].Value
					}
				}
			)
		}
	}
	#>

	$DistroImages
}

# .SYNOPSIS
# Get system information from an installed linux distribution.
function Get-DistroSystemInfo
{
	param
	(
		[Parameter(Mandatory=$false)] [string] $Name
	)
	$WslOptions = GetWslCommandDistroOptions -Name $Name
	$DistroInfoText = wsl.exe @WslOptions --exec cat /etc/os-release
	if ($LastExitCode -ne 0) { throw "Failed to retrieve info from distro (error code ${LastExitCode})" }
	$DistroInfo = [PSCustomObject]@{
		Id = $DistroInfoText | Select-String -Pattern '^ID=(.*)' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		VersionId = $DistroInfoText | Select-String -Pattern '^(?:VERSION_ID|BUILD_ID)="?(.*?)"?$' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value # Alpine 3.13.1 did not have quotes, Debian 9 did have quotes. Both have VERSION_ID. Arch have instead BUILD_ID=rolling.
		Version = $null
		VersionString = $DistroInfoText | Select-String -Pattern '^VERSION="?(.*?)"?$' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		VersionCodeName = $DistroInfoText | Select-String -Pattern '^VERSION_CODENAME="?(.*?)"?$' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		Name = $DistroInfoText | Select-String -Pattern '^NAME="?(.*?)"?$' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		PrettyName = $DistroInfoText | Select-String -Pattern '^PRETTY_NAME="(.*?)"' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		ShortName = $null
		PackageSourceCodeName = $null
	}
	if ($DistroInfo.Id -eq 'debian') {
		# VersionCodeName is not always present, was present in Debian 10 (buster) but not Debian 9 (stretch),
		# but we know the names of the most relevant ones, so hard coding them based on the major version number for convenience.
		if (-not $DistroInfo.VersionCodeName) {
			if ($DistroInfo.VersionId -eq 8) { $DistroInfo.VersionCodeName = 'jessie' }
			elseif ($DistroInfo.VersionId -eq 9) { $DistroInfo.VersionCodeName = 'stretch' }
			elseif ($DistroInfo.VersionId -eq 10) { $DistroInfo.VersionCodeName = 'buster' } # From this version it seems it is already as VERSION_CODENAME is included in /etc/os-release now
			elseif ($DistroInfo.VersionId -eq 11) { $DistroInfo.VersionCodeName = 'bullseye' }
			elseif ($DistroInfo.VersionId -eq 12) { $DistroInfo.VersionCodeName = 'bookworm' }
			elseif ($DistroInfo.VersionId -eq 13) { $DistroInfo.VersionCodeName = 'trixie' }
			if ($DistroInfo.VersionCodeName) {
				Write-Verbose "Deduced Debian code name '$($DistroInfo.VersionCodeName)' from version number $($DistroInfo.VersionId)"
			} else {
				Write-Verbose "Unable to deduce Debian code name from version number $($DistroInfo.VersionId)"
			}
		}
		# For Debian we can get the more information from an additional file,
		# but it varies what it contains: In stable version it contains the current
		# major.minor version, which is something the /etc/os-release does not inform
		# (just the major version number), but in testing it is the codename - and then
		# may not be specific e.g. "bullseye/sid".
		$Version = wsl.exe @WslOptions --exec cat /etc/debian_version
		if ($LastExitCode -eq 0) {
			$DistroInfo.Version = $Version
		}
		# Channel configured for main binary packages source.
		# Note: In a new install this should match VersionCodeName from /etc/os-release above, but that may not have a value (Debian 9 does not).
		# For previously installed versions we don't know if the package source have been changed without running an upgrade, and then these
		# version code names may differ.
		$PackageSourceCodeName = wsl.exe @WslOptions --exec sh -c "cat /etc/apt/sources.list | sed -rn 's/^deb\s+https?:\/\/deb.debian.org\/debian\s+([a-z]*)\s+main$/\1/p'"
		if ($LastExitCode -eq 0) {
			$DistroInfo.PackageSourceCodeName = $PackageSourceCodeName
		}
	}
	elseif ($DistroInfo.Id -eq 'fedora') {
		# Fedora: We want the "rawhide" identifier for development version, storing it in VersionCodeName. For regular releases it is just the same as the VersionId number.
		if (-not $DistroInfo.VersionCodeName) {
			$DistroInfo.VersionCodeName = $DistroInfoText | Select-String -Pattern '^REDHAT_SUPPORT_PRODUCT_VERSION=(.*)' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		}
	}
	# else:
	#  - Alpine has a file /etc/alpine-release but does only contain the same version number as in VERSION_ID.

	if (-not $DistroInfo.Version) {
		$DistroInfo.Version = $DistroInfo.VersionId
	}

	# TODO:
	#  - Ubuntu also has a file /etc/debian_version, representing the Debian version it is built on. E.g. In Ubuntu 20.04 it contains "bullseye/sid",
	#    which matches the content in latest testing version Debian.
	$DistroInfo.ShortName = "$($DistroInfo.Id) $(if($DistroInfo.VersionString){$DistroInfo.VersionString}else{$DistroInfo.Version})"
	$DistroInfo
}

# .SYNOPSIS
# Create a new WSL distribution.
# .DESCRIPTION
# This will download one of the images returned by Get-DistroImage, and import
# it into WSL using the `wsl.exe --import` command.
#
# It can optionally create a user account, which will be set as default instead
# of the built-in root.
#
# The first created distro, from this function or `wsl.exe`, will be set as default.
# When creating additional distro it can be set as default by adding parameter
# -SetDefault.
# .LINK
# Get-DistroImage
# Install-VpnKit
# Remove-Distro
function New-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# The name to register for the distro.
		[Parameter(Mandatory)]
		[ValidatePattern('^[a-zA-Z0-9._-]+$')] # See https://github.com/microsoft/WSL-DistroLauncher/blob/master/DistroLauncher/DistributionInfo.h
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# The directory path where distro shall be installed into.
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Destination,

		# The distro package to install, from one of the supported values (see Get-DistroImages).
		# Primary source: https://docs.microsoft.com/en-us/windows/wsl/install-manual#downloading-distributions
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			if ($_) {
				$ValidSet = Get-DistroImage | Select-Object -ExpandProperty Id
				if ($_ -notin $ValidSet) { throw [System.Management.Automation.PSArgumentException] "The value `"${_}`" is not a known image. Only `"$($ValidSet -join '", "')`" can be specified." }
			}
			$true
		})]
		[ArgumentCompleter({
			param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
			Get-DistroImage | Select-Object -ExpandProperty Id | Where-Object { -not $WordToComplete -or ($_ -like $WordToComplete.Trim('"''') -or $_.ToLower().StartsWith($WordToComplete.Trim('"''').ToLower())) } | ForEach-Object { if ($_.IndexOfAny(" `"") -ge 0){"`'${_}`'"}else{$_} }
		})]
		[Alias("Source")]
		[string] $Image,

		# Optional name of additional user to create. If not specified then only the default root user will be available from start.
		[Parameter(Mandatory=$false)]
		[ValidatePattern('^[a-z_][a-z0-9_-]*[$]?$')] # Not strict requirement in all distros, but highly recommended to only use usernames that begin with a lower case letter or an underscore, followed by lower case letters, digits, underscores, or dashes. They can end with a dollar sign.
		[ValidateLength(1, 32)] # 32 characters max
		[string] $UserName,

		# Optional working directory where downloads will be temporarily placed. Default is current directory.
		[Parameter(Mandatory=$false)] [ValidateNotNullOrEmpty()] [string] $WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath,

		# Optional search path to 7-Zip utility. It is required for extracting downloads,
		# but will be temporarily downloaded if not found.
		[string[]] $SevenZip = ("7z", ".\7z"),

		[switch] $SetDefault
	)
	$DistroImage = Get-DistroImage | Where-Object { $_.Id -eq $Image }
	if (-not $DistroImage) { throw "Distro image '${Image}' could not be found" }
	if (Test-Distro -Name $Name) { throw "There is already a WSL distro with name '${Name}'" }
	if (Test-Path -LiteralPath $Destination) { throw "Destination already exists" }
	$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
	$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
	$TempDirectory = New-TempDirectory -Path $WorkingDirectory
	try
	{
		if ($PSCmdlet.ShouldProcess($Destination, "Install distro image '$($DistroImage.Id)' into WSL as '${Name}'")) {

			# Download
			Write-Host "Downloading distro image '$($DistroImage.Id)'..."
			$DownloadUrl = $DistroImage.Url
			$DownloadFullName = Join-Path $TempDirectory $DistroImage.FileName
			if (([uri]$DownloadUrl).Host -eq 'api.github.com') {
				Save-File -Url $DownloadUrl -Path $DownloadFullName -Credential $GitHubCredential
			} else {
				Save-File -Url $DownloadUrl -Path $DownloadFullName
			}
			if (-not (Test-Path -LiteralPath $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
			if ($DistroImage.Checksum) {
				# Verify checksum
				$ExpectedHash = $DistroImage.Checksum.Value
				Write-Host "Verifying checksum..."
				Write-Verbose "Expected `"${ExpectedHash}`""
				$ActualHash = Get-FileHash -LiteralPath $DownloadFullName -Algorithm ($DistroImage.Checksum.Algorithm) | Select-Object -ExpandProperty Hash
				Write-Verbose "Actual   `"${ActualHash}`""
				if ($ExpectedHash -ne $ActualHash) {
					throw "Checksum ($($DistroImage.Checksum.Algorithm)) mismatch: Expected ${ExpectedHash} but was ${ActualHash}"
				}
				Write-Verbose "$($DistroImage.Checksum.Algorithm) match: ${ExpectedHash}"
			}
			if ($DownloadFullName.EndsWith(".appx")) {
				# Extract installer archive from appx installer (requires 7-Zip)
				$SevenZipPath = Get-Command -CommandType Application -Name $SevenZip -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
				if (-not $SevenZipPath) {
					Write-Host "Getting required 7-Zip utility (temporary)..."
					$SevenZipPath = Get-SevenZip -DownloadDirectory $TempDirectory -WorkingDirectory $TempDirectory # Will create new tempfolder as subfolder of current $TempDirectory
				}
				&$SevenZipPath x -y "-o${TempDirectory}" "${DownloadFullName}" 'install.tar.gz' | Out-Verbose
				if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
				Remove-Item -LiteralPath $DownloadFullName
				$FileSystemArchiveFullName = Join-Path $TempDirectory 'install.tar.gz'
				if (-not (Test-Path -LiteralPath $FileSystemArchiveFullName)) { throw "Cannot find extracted ${FileSystemArchiveFullName}" }
			} elseif ($DistroImage.Id -eq 'archlinux-bootstrap') {
				# Arch download is archive file that must be modified: The compressed .tar contains
				# filesystem in subfolder but WSL requires it to be at root!
				$SevenZipPath = Get-Command -CommandType Application -Name $SevenZip -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
				if (-not $SevenZipPath) {
					Write-Host "Getting required 7-Zip utility (temporary)..."
					$SevenZipPath = Get-SevenZip -DownloadDirectory $TempDirectory -WorkingDirectory $TempDirectory # Will create new tempfolder as subfolder of current $TempDirectory
				}
				&$SevenZipPath x -y "-o${TempDirectory}" "${DownloadFullName}" | Out-Verbose
				if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
				$FileSystemArchiveFullName = Join-Path $TempDirectory ([System.IO.Path]::GetFileNameWithoutExtension($DownloadFullName))
				if (-not (Test-Path -LiteralPath $FileSystemArchiveFullName)) { throw "Cannot find extracted ${FileSystemArchiveFullName}" }
				&$SevenZipPath rn "$FileSystemArchiveFullName" root.x86_64 . | Out-Verbose
				if ($LastExitCode -ne 0) { throw "Updating of ${FileSystemArchiveFullName} failed with error $LastExitCode" }
			} elseif ($DistroImage.Id -like 'fedora-*') {
				# Fedora download is compressed archive file that must be uncompressed, before the .tar can be imported.
				$SevenZipPath = Get-Command -CommandType Application -Name $SevenZip -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
				if (-not $SevenZipPath) {
					Write-Host "Getting required 7-Zip utility (temporary)..."
					$SevenZipPath = Get-SevenZip -DownloadDirectory $TempDirectory -WorkingDirectory $TempDirectory # Will create new tempfolder as subfolder of current $TempDirectory
				}
				&$SevenZipPath x -y "-o${TempDirectory}" "${DownloadFullName}" | Out-Verbose
				if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
				$FileSystemArchiveFullName = Join-Path $TempDirectory ([System.IO.Path]::GetFileNameWithoutExtension($DownloadFullName))
				if (-not (Test-Path -LiteralPath $FileSystemArchiveFullName)) { throw "Cannot find extracted ${FileSystemArchiveFullName}" }
			} else {
				$FileSystemArchiveFullName = $DownloadFullName
			}
			# Else: Assume its an archive file ready to be imported!

			# Import archive to WSL
			Write-Host "Creating WSL distro '${Name}'..."
			Write-Verbose "Importing from archive ${FileSystemArchiveFullName}"
			#$Destination = Get-Directory -Path $Destination -Create
			wsl.exe --import $Name $Destination $FileSystemArchiveFullName
			if ($LastExitCode -ne 0) {
				# Avoid empty destination being left behind when error, it will prevent a new attempt with same path!
				#if (Test-Path -LiteralPath $Destination) {
				#	Write-Host "Import of image archive failed (error code ${LastExitCode}), deleting destination ${Destination}"
				#	Remove-Item -Path $Destination
				#}
				throw "Import of image archive failed (error code ${LastExitCode})"
			}
			Remove-Item -LiteralPath $FileSystemArchiveFullName

			# Optionally create user
			if ($UserName -and $PSCmdlet.ShouldProcess($UserName, "Add user")) {
				# TODO:
				# - MS reference launcher: Uses 'adduser' with password prompt:
				#     adduser --quiet --gecos '' <username>
				# - Debian: Uses 'adduser' without password prompt, and then sets required password with separate 'passwd' command:
				#     adduser --quiet --disabled-password --gecos '' <username>
				#     passwd <username>
				# - Alpine only have 'adduser' (not useradd) by default.
				# - Arch only have 'useradd', not 'adduser' by default.
				if ($DistroImage.Id -eq 'alpine-minirootfs') {
					# Alpine
					# Add user without password (there is not sudo here by default, so empty password will not be a problem),
					# and add to customized list of groups.
					# See: https://github.com/agowa338/WSL-DistroLauncher-Alpine/blob/master/DistroLauncher/DistroSpecial.h
					Write-Host "Creating user '${UserName}' (without password)..."
					# Must use adduser command, useradd command is not available before installing package 'shadow'
					wsl.exe --distribution $Name sh -c "adduser --disabled-password --gecos '' ${UserName}" # Note: Needed the sh -c workaround for it to accept arguments!
					if ($LastExitCode -eq 0) {
						# Add to groups in separate command, since adduser does not support the --groups option,
						# and also there is no usermod command by default so must use adduser or addgroup (which are
						# basically the same) to add one by one.
						Write-Host "Setting as member of wheel and some other standard groups..."
						wsl.exe --distribution $Name for g in adm floppy cdrom tape wheel ping`; do adduser $UserName `$g`; done
					} else {
						Write-Warning "Failed to create user (error code ${LastExitCode})"
					}
				}
				elseif ($DistroImage.Id -eq 'archlinux-bootstrap') {
					# Arch
					# Add user with required non-empty password. Use low-level command 'useradd',
					# since 'adduser' is not built-in. Make it a member of group "wheel".
					Write-Host "Creating user '${UserName}' as member of wheel group (you will be prompted for password)..."
					wsl.exe --distribution $Name sh -c "useradd --create-home --groups wheel ${UserName}"
					wsl.exe --distribution $Name passwd $UserName
					if ($LastExitCode -ne 0) {
						Write-Warning "Failed to set password (error code ${LastExitCode})"
					}
				}
				elseif ($DistroImage.Id -like 'fedora-*') {
					# Fedora
					# Add user with required non-empty password. Use low-level command 'useradd',
					# since 'adduser' is not built-in. Make it a member of group "wheel".
					# Command 'passwd' is not included by default, so uses 'chpasswd' instead,
					# prompting for the password in PowerShell and pipes it into chpasswd in wsl.
					Write-Host "Creating user '${UserName}' as member of wheel group (you will be prompted for password)..."
					wsl.exe --distribution $Name sh -c "useradd --create-home --groups wheel ${UserName}"
					$Credential = Get-Credential -UserName $UserName -Message "Create password for user ${Name}"
					if ($Credential -and $Credential.GetNetworkCredential().Password) {
						wsl.exe --distribution $Name sh -c "echo `"$($Credential.UserName):$($Credential.GetNetworkCredential().Password)`" | chpasswd"
						if ($LastExitCode -ne 0) {
							Write-Warning "Failed to set password (error code ${LastExitCode})"
						}
					}
					else {
						Write-Warning "No password set"
					}
				}
				else {
					# Debian and related (Ubuntu)
					# Add user with required non-empty password (as Debian does it, perhaps to avoid trouble with sudo later?)
					Write-Host "Creating user '${UserName}' (you will be prompted for password)..."
					# Using 'adduser' command.
					# Could also have used the low-level 'useradd': But must then explicitely specify to create
					# user home, and also possible replace shell /bin/sh with shell /bin/bash if that is wanted,
					# and it does not prompt for password so must explicit call 'passwd' command.
					#   useradd --create-home --shell /bin/bash <username>
					wsl.exe --distribution $Name sh -c "adduser --quiet --disabled-password --gecos '' ${UserName}" # Note: Needed the sh -c workaround for it to accept arguments!
					if ($LastExitCode -eq 0) {
						wsl.exe --distribution $Name passwd $UserName
						if ($LastExitCode -ne 0) {
							Write-Warning "Failed to set password (error code ${LastExitCode})"
						}
						Write-Host "Setting as member of sudo and some other standard groups..."
						# Using the list of default groups from Microsoft's WSL Distro Launcher Reference Implementation
						# (see https://github.com/microsoft/WSL-DistroLauncher/blob/master/DistroLauncher/DistributionInfo.cpp),
						# which is currently: adm,cdrom,sudo,dip,plugdev. Debian's official WSL distro installer uses this
						# list unchanged, Ubuntu adds additional groups: dialout,floppy,audio,video,netdev.
						$UserGroups = "adm,cdrom,sudo,dip,plugdev"
						if ($DistroImage.Id.StartsWith('ubuntu')) { # Ubuntu default installers adds some additional groups
							$UserGroups += ",dialout,floppy,audio,video,netdev"
						}
						# Using low-level usermod. Could also have used adduser (or its alias addgroup), it appends
						# by default but does only support adding one group at a time.
						wsl.exe --distribution $Name usermod --append --groups $UserGroups $UserName
						if ($LastExitCode -ne 0) {
							#wsl.exe --distribution $Name deluser $UserName # Delete the user if the group add command failed (like MS launcher template does)
							Write-Warning "Failed to add user to groups (error code ${LastExitCode})"
						}
					} else {
						Write-Warning "Failed to create user (error code ${LastExitCode})"
					}
				}
				# Register as default WSL user for this distro
				$UserId = wsl.exe --distribution $Name --user $UserName --exec id -u # Note: On Alpine "id --user" does not work, but shortform "id -u" does!
				if ($LastExitCode -eq 0) {
					Write-Host "Setting as default user..."
					GetDistroRegistryItem -Name $Name | Set-ItemProperty -Name DefaultUid -Value $UserId
				} else {
					Write-Warning "Unable to set as default user (could not find uid)"
				}
			}

			# Optionally set as default distro in WSL
			if ($SetDefault -and $PSCmdlet.ShouldProcess($Name, "Set as default WSL distro")) {
				Write-Host "Setting as default WSL distro"
				# Note: Using wsl.exe here, but have also Set-DefaultDistro which access registry.
				wsl.exe --set-default $Name
				if ($LastExitCode -ne 0) {
					Write-Warning "Failed to set as default WSL distro (error code ${LastExitCode})"
				}
			}

			# Fetch some status info about the newly installed distro just to inform user
			$DistroInfo = Get-DistroSystemInfo -Name $Name
			if ($DistroInfo.Id -eq 'debian') {
				# TODO:
				# - Could compare actual version numbers.
				# - Could also compare version code against configured PackageSourceCodeName to see if upgraded according to current source or not.
				# - Could update/update for the user by running necessary commands, but then this requires internet access,
				#   and on systems where VPNKit is required then another distro must have already been installed and running VPNKit,
				#   and also it soon gets a bit complex to handle any state problem free..
				if ($DistroInfo.VersionCodeName) {
					$LatestVersion, $LatestCodeName = Invoke-RestMethod -Uri 'https://deb.debian.org/debian/dists/stable/Release' -DisableKeepAlive | Select-String -Pattern '(?m)^Version:\s*(.*)\n.*Codename:\s*(.*)$' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1,2 | Select-Object -ExpandProperty Value
					if ($LatestCodeName -and $LatestCodeName -ne $DistroInfo.VersionCodeName) {
						Write-Host "Note: There is a newer stable release of Debian that you can upgrade to: $($DistroInfo.Version) ($($DistroInfo.VersionCodeName)) -> ${LatestVersion} (${LatestCodeName})"
					} elseif ($DistroInfo.Version -and $LatestVersion -and $DistroInfo.Version -ne $LatestVersion) {
						Write-Host "Note: There are updates available for the current release of Debian: $($DistroInfo.Version) -> ${LatestVersion}"
					}
				}
			}
			Write-Host "WSL distro '$(if($Name){$Name}else{'(default)'})' has been created with $($DistroInfo.ShortName)"
		}
	}
	finally
	{
		if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
			Remove-Item -LiteralPath $TempDirectory -Recurse
		}
	}
}

# .SYNOPSIS
# Delete a WSL distribution.
# .DESCRIPTION
# This will remove it from WSL by executing `wsl.exe --unregister`, and then delete
# the disk path as returned by Get-DistroPath.
# .LINK
# New-Distro
# Get-DistroPath
function Remove-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Name of distro. Required, do not want to automatically remove default distro without user explicitely specifying it!
		[Parameter(Mandatory)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $Force
	)
	$Name = GetDistroNameOrDefault -Name $Name
	$DistroInfo = Get-DistroSystemInfo -Name $Name # Note: This will start up the distro if not running, but to avoid removing the wrong distro its good to show some info?
	$Item = GetDistroRegistryItem -Name $Name
	if (-not $Item) { throw "Distro '${Name}' not found in registry" }
	if (IsDistroItemPackageInstalled -Item $Item) {
		throw "This distro seems to be installed as a standard UWP app, it should be removed by uninstalling from Settings > Apps & Features"
	}
	$Path = $Item | Select-Object -ExpandProperty BasePath | ForEach-Object { Get-StandardizedPath $_ }
	if (-not $Path) { throw "Base path for distro '${Name}' not found" }
	if ($Force -or $PSCmdlet.ShouldContinue("Are you sure you want to unregister WSL distro '${Name}' [$($DistroInfo.ShortName)] and delete base directory in path '${Path}'?", "Unregister WSL distro")) {
		Write-Host "Removing WSL distro '${Name}' [$($DistroInfo.ShortName)]..."
		wsl.exe --unregister $Name | Out-Null # This prints "Unregistering..." unless redirecting
		if ($LastExitCode -ne 0) { throw "Unregistering distro failed (error code ${LastExitCode})" }
		Remove-Item -LiteralPath $Path -Recurse
	}
}

# .SYNOPSIS
# Change the name of an installed distro.
# .DESCRIPTION
# Note that this will basically just set the DistributionName attribute in registry,
# same as Set-DistroDistributionName, but includes additional safety checks and
# supports asking for confirmation if called with parameter -Confirm.
# Note also that this will not change the name of the directory containing the distro's
# backing files (virtual disk image) on the host system - use Move-Distro to do that.
# .LINK
# Set-DistroDistributionName
# Move-Distro
function Rename-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[string] $Name,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()] [ValidatePattern('^[a-zA-Z0-9._-]+$')] # See https://github.com/microsoft/WSL-DistroLauncher/blob/master/DistroLauncher/DistributionInfo.h
		[string] $NewName
	)
	$Name = GetDistroNameOrDefault -Name $Name
	#$DistroInfo = Get-DistroSystemInfo -Name $Name # NO: Don't want to start the distro up just to print this info!
	$Item = GetDistroRegistryItem -Name $Name
	if (-not $Item) { throw "Distro '${Name}' not found in registry" }
	if (IsDistroItemPackageInstalled -Item $Item) {
		# Not tried it, but probably not wise to move these?
		throw "This distro seems to be installed as a standard UWP app, these cannot be moved"
	}
	$Path = $Item | Select-Object -ExpandProperty BasePath | Get-StandardizedPath
	if (-not $Path) {
		Write-Warning "Distro '${Name}' does not have disk path stored in registry"
	}
	if (Test-Distro -Name $NewName) { throw "Distro with name '${NewName}' already exists" }
	if ($PSCmdlet.ShouldProcess("Rename to '${NewName}' keeping existing path '${Path}'", "Rename WSL distro '${Name}'")) {
		Write-Host "Renaming WSL distro '${Name}' to '${NewName}'..."
		$Item | Set-ItemProperty -Name DistributionName -Value $NewName
		Write-Host "Note: The path to the disk image is not changed, use Move-Distro to do that: ${Path}"
		#Write-Warning "You may have to terminate the distro or shutdown entire WSL for the change to have effect."
	}
}

# .SYNOPSIS
# Move distro, by moving the registered folder containing the disk image,
# and update the reference to it in registry.
# .DESCRIPTION
# Note that this will basically just set the BasePath attribute in registry,
# same as Set-DistroPath, but includes additional safety checks and
# supports asking for confirmation if called with parameter -Confirm.
# Note also that this will not change the name of the distro - use Rename-Distro
# to do that.
# .LINK
# Set-DistroPath
# Rename-Distro
function Move-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		[Parameter(Mandatory=$false)] # Will use registered default distro if not specified
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[string] $Name,

		# Path where to move the distro directory to. Path must not exist.
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string] $Destination,

		# Force terminate/shutdown to ensure distro files can be moved.
		# Default is to ask.
		[switch] $Force
	)
	$Name = GetDistroNameOrDefault -Name $Name
	#$DistroInfo = Get-DistroSystemInfo -Name $Name # NO: Don't want to start the distro up just to print this info!
	$Item = GetDistroRegistryItem -Name $Name
	if (-not $Item) { throw "Distro '${Name}' not found in registry" }
	if (IsDistroItemPackageInstalled -Item $Item) {
		# Not tried it, but probably not wise to move these?
		throw "This distro seems to be installed as a standard UWP app, these cannot be moved"
	}
	$Path = $Item | Select-Object -ExpandProperty BasePath | Get-StandardizedPath
	if (-not $Path) { throw "Base path for distro '${Name}' not found in registry" }
	if (Test-Path -LiteralPath $Destination) { throw "Destination already exists" }
	# Move will easily fail with access denied, and sometimes terminating the distro instance
	# is not enough so seems we have to shutdown WSL to get consistent results.
	if (-not $Force -and -not $PSCmdlet.ShouldContinue("To ensure ensure files are not in use, WSL must be shut down.`nThis will terminate all running distributions as well as the shared virtual machine.`nDo you want to continue?", "Shutdown WSL")) { return }
	wsl.exe --shutdown
	if ($LastExitCode -ne 0) { throw "Shutdown failed (error code ${LastExitCode})" }
	#if (Test-Distro -Name $Name -Running) {
	#	if (-not $Force -and -not $PSCmdlet.ShouldContinue("The distro is currently running. To continue it must be terminated.", "Terminate WSL distro")) { return }
	#	Write-Host "Terminating WSL distro..."
	#	wsl.exe --terminate $Name
	#	if ($LastExitCode -ne 0) { throw "Terminate failed (error code ${LastExitCode})" }
	#}
	if ($PSCmdlet.ShouldProcess("From: ${Path}`nTo: ${Destination}", "Move WSL distro '${Name}'")) {
		Write-Host "Moving WSL distro '${Name}' to '${Destination}'..."
		Move-Item -LiteralPath $Path -Destination $Destination -ErrorAction Stop
		$Item | Set-ItemProperty -Name BasePath -Value (Get-ExtendedLengthPath $Destination)
		#Write-Warning "You may have to terminate the distro or shutdown entire WSL for the change to have effect."
	}
}

# .SYNOPSIS
# Start a distro instance, typically a new shell session.
# .DESCRIPTION
# This is the same as executing `wsl.exe` targeted at a specific distro. Adds argument
# `--distribution` followed by distro name, and optionally `--user` followed by specified
# user name. Default is to enter a new session, and by default within the current shell,
# optionally start it in a new window instead. Can also execute commands directly,
# insted of entering a shell session.
# .LINK
# Start-VpnKit
function Start-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Optional name of distro. If not specified WSL default will be assumed.
		[Parameter(Mandatory=$false)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Optional name of user to log in as. Default is the configured default user.
		[Parameter(Mandatory=$false)]
		[string] $UserName,

		# List of commands/arguments to execute on the distro. E.g. ("ls","-al"). Start with
		# "--exec" or "-e" for it to run without using the default Linux shell like `wsl.exe --execute`.
		# Not compatible with -NewWindow or -StartOnly.
		[string[]] $CommandList,

		# Optional start as new console window, default is within current PowerShell console.
		# Not compatible with -StartOnly.
		[switch] $NewWindow,

		# Optional start it without logging in with a session or executing any commands.
		# Same as calling with `-CommandList exit`. Not usefull for much but testing?
		# Not compatible with -NewWindow or -CommandList.
		[switch] $StartOnly,

		# Optional start VPNKit service from the distro before entering session or executing
		# commands according to other parameters, instead of relying on it being started
		# separately with with Start-VpnKit.
		# Note that this will always be started as root, regardless of -UserName parameter.
		# Note also that you should only run a single instance of the VPNKit service.
		[switch] $WithVpnKit
	)
	$WslOptions = GetWslCommandDistroOptions -Name $Name -UserName $UserName

	if ($WithVpnKit) {
		# Begin by starting VPNKit as root in a new window (copied parts of code from Start-VpnKit)
		if (-not $PSCmdlet.ShouldProcess("/usr/local/bin/wsl-vpnkit", "Run wsl-vpnkit as root")) { return }
		# Check if already running and suggest stopping, but Docker Desktop is also executing its own vpnkit.exe so must not touch those!
		$VpnKitProcesses = Get-Process -Name vpnkit -ErrorAction Ignore | Where-Object -Property CommandLine -like "*\\.\pipe\wsl-vpnkit*" # Note: Assuming named pipe used by wsl-vpnkit script!
		if ($VpnKitProcesses) {
			if ($PSCmdlet.ShouldContinue("There are $($VpnKitProcesses.Count) vpnkit process(es) already running. You can only run one VPNKit service`nat a time, and if you want to start a different one you should manually stop the existing.`nIf you think it is just stray vpnkit processes then terminating them is OK.`nDo you want to terminate existing vpnkit process(es)?`n$($VpnKitProcesses.Path -join '`n')", "Stop vpnkit.exe")) {
				$VpnKitProcesses | Stop-Process -Force:$Force # If -Force then stop without prompting for confirmation (default is to prompt before stopping any process that is not owned by the current user)
			}
		}
		Write-Host "Starting wsl-vpnkit in new window..."
		Start-Process -FilePath wsl.exe -ArgumentList ($WslOptions + '--user', 'root', '--exec', '/usr/local/bin/wsl-vpnkit')
	}
	if ($StartOnly) {
		# Just make sure the distro is running, without entering a session.
		Write-Host "Starting distro..."
		wsl.exe @WslOptions exit
	} elseif ($NewWindow) {
		# Start in a separate session, either a new shell session, or execute specified commands.
		Write-Host "Starting distro shell session in new window..."
		Start-Process -FilePath wsl.exe -ArgumentList ($WslOptions + $CommandList)
	} else {
		# Run in current PowerShell console, either a new shell session, or execute specified commands.
		if ($CommandList.Count -gt 0) {
			Write-Host "Executing distro commands `"${CommandList}`"..."
		} else {
			Write-Host "Starting distro shell session..."
		}
		wsl.exe @WslOptions @CommandList
	}
}

# .SYNOPSIS
# Stop the distro.
# .DESCRIPTION
# This will perform `wsl.exe --terminate` to stop a single distribution,
# or if parameter -All it will execute `wsl.exe --shutdown` which not just
# stops all running distributions, but also shuts down the entire virtual
# machine which the distributions run in (same as calling Stop-Wsl).
# .LINK
# Stop-Wsl
function Stop-Distro
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Optional name of distro. If not specified WSL default will be assumed.
		[Parameter(Mandatory=$false)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,
		[switch] $All
	)
	if ($All)
	{
		Stop-Wsl
	}
	else
	{
		if ($PSCmdlet.ShouldProcess($(if($Name){$Name}else{'(default)'}), "Terminate WSL distro")) {
			Write-Host "Terminating WSL distro '$(if($Name){$Name}else{'(default)'})'..."
			$WslOptions = GetWslCommandDistroOptions -Name $Name
			wsl.exe @WslOptions --terminate $Name
			if ($LastExitCode -ne 0) { throw "Stopping distro failed (error code ${LastExitCode})" }
		}
	}
}

# .SYNOPSIS
# Stop the WSL.
# .DESCRIPTION
# This will perform `wsl.exe --shutdown` to stop stop all running distributions,
# as well as the entire virtual machine which the distributions run in.
# Same as calling `Stop-Distro -All`.
# .LINK
# Stop-Distro
function Stop-Wsl
{
	[CmdletBinding(SupportsShouldProcess)]
	param()
	if ($PSCmdlet.ShouldProcess("WSL", "Shutdown")) {
		Write-Host "Shutting down WSL..."
		wsl.exe --shutdown
		if ($LastExitCode -ne 0) { throw "Stopping WSL failed (error code ${LastExitCode})" }
	}
}

# .SYNOPSIS
# Create a program directory on host with the VPNKit tools.
#
# .DESCRIPTION
# This will download and extract a set of small executables that the VPNKit based
# networking method is based on, and it will generate some related configuration
# files and shell scripts for setting it up. It will not access any WSL distributions,
# but sets up all prerequisites to be able to run Install-VpnKit.
#
# Can be re-run at any time to update an existing directory, e.g. when there is
# a new version of third party executables npiperelay or vpnkit part of
# Docker Desktop.
#
# There is no Remove-VpnKit function, you can just delete the program directory
# for example with standard PowerShell command Remove-Item.
#
# The created directory will contain:
# - wsl-vpnkit (Linux/WSL2 shell script) from https://github.com/albertony/wsl-vpnkit (fork of https://github.com/sakai135/wsl-vpnkit)
# - vpnkit.exe (Windows executable) and vpnkit-tap-vsockd (Linux/WSL2 executable)
#   from Docker Desktop for Windows: https://hub.docker.com/editions/community/docker-ce-desktop-windows/
# - npiperelay.exe (Windows executable) from https://github.com/jstarks/npiperelay
# - wsl-vpnkit-install, wsl-vpnkit-uninstall, wsl-vpnkit-configure,
#   wsl-vpnkit-unconfigure (Linux/WSL2 shell scripts) generated.
# - resolv.conf and wsl.conf (Linux/WSL2 DNS configuration files) generated.
#
# Note that some of the generated scripts will have a reference back to the
# specific path these are generated into, so if this path changes then these must
# be manually updated, or you should re-run this function. It will overwrite existing
# by default, but run with -Confirm to decide for each individual part.
#
# Note also that when installing the VPNKit into a WSL distribution, you must refer to
# a directory containing the files created by New-VpnKit, and the generated script
# files containing a reference to this path on host will be copied into the WSL
# distribution, so if this path changes you must also update the scripts within the
# WSL distribution(s).
# .LINK
# Install-VpnKit
# .LINK
# https://github.com/albertony/wsl-vpnkit/
function New-VpnKit
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# The directory path where programs shall be installed into
		[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Destination,

		# Optional working directory where downloads will be temporarily placed. Default is current directory.
		[Parameter(Mandatory=$false)] [ValidateNotNullOrEmpty()] [string] $WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath,

		# Optional search path to 7-Zip utility. It is required for extracting downloads,
		# but will be temporarily downloaded if not found.
		[string[]] $SevenZip = ("7z", ".\7z"),

		# Force stop processes necessary to update existing executables.
		# Default is to ask.
		[switch] $Force
	)

	$Destination = Get-Directory -Path $Destination -Create
	$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
	$TempDirectory = $null # Lazy-create, when/if first needed!
	try
	{

		#
		# 7-Zip
		# (Just needed in here to extract other downloads)
		#

		$SevenZipPath = Get-Command -CommandType Application -Name $SevenZip -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
		if (-not $SevenZipPath)
		{
			Write-Host "Getting required 7-Zip utility (temporary)..."
			if (-not $TempDirectory) { $TempDirectory = New-TempDirectory -Path $WorkingDirectory }
			$SevenZipPath = Get-SevenZip -DownloadDirectory $TempDirectory -WorkingDirectory $TempDirectory # Will create new tempfolder as subfolder of current $TempDirectory
		}

		#
		# vpnkit.exe and vpnkit-tap-vsockd from Docker Desktop installer
		#

		if ($PSCmdlet.ShouldProcess("VPNKit from Docker Desktop", "Download and extract"))
		{
			Write-Host "Getting VPNKit from Docker Desktop..."
			# Download Docker Desktop installer
			if (-not $TempDirectory) { $TempDirectory = New-TempDirectory -Path $WorkingDirectory }
			$DownloadName = 'Docker Desktop Installer.exe'
			$DownloadFullName = Join-Path $TempDirectory $DownloadName
			$DownloadUrl = "https://desktop.docker.com/win/stable/${DownloadName}"
			Save-File -Url $DownloadUrl -Path $DownloadFullName
			if (-not (Test-Path -LiteralPath $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
			# Extract vpnkit.exe executable and docker-for-wsl.iso from installer
			&$SevenZipPath x -y "-o${TempDirectory}" "${DownloadFullName}" 'resources\vpnkit.exe' 'resources\wsl\docker-for-wsl.iso' | Out-Verbose
			if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
			# Extract vpnkit-tap-vsockd executable from docker-for-wsl.iso
			$IsoPath = (Join-Path $TempDirectory 'resources\wsl\docker-for-wsl.iso')
			&$SevenZipPath x -y "-o${TempDirectory}" $IsoPath 'containers\services\vpnkit-tap-vsockd\lower\sbin\vpnkit-tap-vsockd' | Out-Verbose
			if ($LastExitCode -ne 0) { throw "Extraction of ${IsoPath} failed with error $LastExitCode" }
			# Move executables into destination, replace any existing (due to -Force).
			# But if win executable is currently running the move will fail unless we kill it ifrst
			$DestinationExe = Join-Path $Destination 'vpnkit.exe'
			$DestinationProcesses = Get-Process | Where-Object -Property Path -eq $DestinationExe
			if ($DestinationProcesses) {
				if ($Force -or $PSCmdlet.ShouldContinue("The executable vpnkit.exe in destination is currently running.`nIt must be stopped to be able to overwrite it.`nDo you want to stop it now?", "Stop vpnkit.exe")) {
					$DestinationProcesses | Stop-Process -Force:$Force # If -Force then stop without prompting for confirmation (default is to prompt before stopping any process that is not owned by the current user)
				} # else: Just try anyway, with a probable error being the result?
			}
			Move-Item -Force -LiteralPath (Join-Path $TempDirectory 'resources\vpnkit.exe') -Destination $Destination
			Move-Item -Force -LiteralPath (Join-Path $TempDirectory 'containers\services\vpnkit-tap-vsockd\lower\sbin\vpnkit-tap-vsockd') -Destination $Destination
			# Clean up
			Remove-Item -LiteralPath (Join-Path $TempDirectory 'resources') -Recurse
			Remove-Item -LiteralPath (Join-Path $TempDirectory 'containers') -Recurse
		}

		#
		# npiperelay
		#

		if ($PSCmdlet.ShouldProcess("npiperelay", "Download and extract"))
		{
			Write-Host "Getting npiperelay..."
			# Download zip distribution
			if (-not $TempDirectory) { $TempDirectory = New-TempDirectory -Path $WorkingDirectory }
			$DownloadName = 'npiperelay_windows_amd64.zip'
			$DownloadFullName = Join-Path $TempDirectory $DownloadName
			$GitHubApiHeaders = Get-GitHubApiAuthenticationHeaders -Credential $GitHubCredential
			$DownloadUrl = Invoke-RestMethod -Uri "https://api.github.com/repos/jstarks/npiperelay/releases/latest" -DisableKeepAlive -Headers $GitHubApiHeaders | Select-Object -ExpandProperty assets | Where-Object { $_.name -match $DownloadName } | Select-Object -First 1 | Select-Object -ExpandProperty browser_download_url
			if (-not $DownloadUrl) { throw "Cannot find download URL for ${DownloadName}" }
			Save-File -Url $DownloadUrl -Path $DownloadFullName -Credential $GitHubCredential
			# Extract executable, copy into destination and clean up
			if (-not (Test-Path -LiteralPath $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
			#&$SevenZipPath x -y "-o${TempDirectory}" "${DownloadFullName}" 'npiperelay.exe' | Out-Verbose
			#if ($LastExitCode -ne 0) { throw "Extraction of ${DownloadFullName} failed with error $LastExitCode" }
			Expand-Archive -LiteralPath $DownloadFullName -DestinationPath $TempDirectory
			Remove-Item -LiteralPath $DownloadFullName, (Join-Path $TempDirectory 'LICENSE'), (Join-Path $TempDirectory 'README.md')
			# Move executables into destination, replace any existing (due to -Force).
			# But if win executable is currently running the move will fail unless we kill it ifrst
			$DestinationExe = Join-Path $Destination 'npiperelay.exe'
			$DestinationProcesses = Get-Process | Where-Object -Property Path -eq $DestinationExe
			if ($DestinationProcesses) {
				if ($Force -or $PSCmdlet.ShouldContinue("The executable npiperelay.exe in destination is currently running.`nIt must be stopped to be able to overwrite it.`nDo you want to stop it now?", "Stop npiperelay.exe")) {
					$DestinationProcesses | Stop-Process -Force:$Force # If -Force then stop without prompting for confirmation (default is to prompt before stopping any process that is not owned by the current user)
				} # else: Just try anyway, with a probable error being the result?
			}
			Move-Item -Force -LiteralPath (Join-Path $TempDirectory 'npiperelay.exe') -Destination $Destination
		}

		#
		# wsl-vpnkit
		#

		if ($PSCmdlet.ShouldProcess("wsl-vpnkit", "Download"))
		{
			Write-Host "Getting wsl-vpnkit..."
			# Download script from GitHub repo
			$DownloadName = 'wsl-vpnkit'
			$DownloadFullName = Join-Path $Destination $DownloadName
			$GitHubApiHeaders = Get-GitHubApiAuthenticationHeaders -Credential $GitHubCredential
			$DownloadUrl = Invoke-RestMethod -Uri "https://api.github.com/repos/albertony/wsl-vpnkit/contents/${DownloadName}" -DisableKeepAlive -Headers $GitHubApiHeaders | Select-Object -ExpandProperty download_url
			if (-not $DownloadUrl) { throw "Cannot find download URL for ${DownloadName}" }
			Save-File -Url $DownloadUrl -Path $DownloadFullName -Credential $GitHubCredential
			if (-not (Test-Path -LiteralPath $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
			# Update default values of VPNKIT_PATH and VPNKIT_NPIPERELAY_PATH variables in the script to the destination path via automount.
			# NOTE: This will tie it to the VPNKit program folder on host!
			$DestinationMount = $Destination.Replace('\','/')
			if ($DestinationMount -notmatch '^(\w):(.*?)(?:/*)$') { throw "Destination must be a rooted path reachable from wsl via automount" }
			$DestinationMount = "/mnt/$($Matches[1].ToLower())$($Matches[2])"
			$FileContent = [System.IO.File]::ReadAllText($DownloadFullName, (New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!
			$FileContent = $FileContent -replace "\nVPNKIT_PATH=.*?\n", "`nVPNKIT_PATH=`${VPNKIT_PATH:-${DestinationMount}/vpnkit.exe}`n"
			$FileContent = $FileContent -replace "\nVPNKIT_NPIPERELAY_PATH=.*?\n", "`nVPNKIT_NPIPERELAY_PATH=`${VPNKIT_NPIPERELAY_PATH:-${DestinationMount}/npiperelay.exe}`n"
			[System.IO.File]::WriteAllText($DownloadFullName, $FileContent, (New-Object System.Text.UTF8Encoding $false))
		}

		#
		# DNS-related configuration files
		# NOTE: The configure utility script created below will generate the same configuration,
		# and these are used in normal setup, but just generating complete configuration
		# files as a template for manually configuration - and referencing them with the optional
		# printing of instructions to user for manual setup.
		#
		if ($PSCmdlet.ShouldProcess("wsl.conf and resolv.conf", "Create DNS configuration files"))
		{
			Write-Host "Creating DNS configuration files..."

			# /etc/wsl.conf : Must stop WSL from generating /etc/resolv.conf, since we need to put the vpnkit gateway IP in there.
			# Note: The wsl-vpnkit-install script does only use this wsl.conf file if there not is already one, in other
			# cases it tries to update the existing instead to keep any other configuration.
			[System.IO.File]::WriteAllText((Join-Path $Destination 'wsl.conf'),
				"[network]`n" + `
				"generateResolvConf = false`n",
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!

			# /etc/resolv.conf : Set the hard-coded IP (192.168.67.1) of the VPNKit gateway,
			# as the default nameserver and a free, public DNS service as secondary nameserver
			# (chosing 1.1.1.1, which is Cloudflare's free, pro-privacy, world's fastest, DNS service).
			# Note: When wsl-vpnkit script is running it will replace the contents with the actual IP of the vpnkit.exe gateway process
			# that it uses, which in turn will use the DNS settings on the host computer.
			# Note: If the wsl-vpnkit script is running on another wsl distro, it will configure network, socket and pipe connection
			# to a vpnkit.exe process in host that it has started, and all this can be used by other wsl distros since they are
			# effectively sharing a single virtual machine. But the changes that it does in resolv.conf will only be done within
			# for the distro it is running in! By setting a public nameserver as default the other distros will work through the
			# vpnkit network, but use the public nameserver for DNS resolving instead of the vpnkit which will consider any settings
			# on the host. To make all distros use the vpnkit gateway we hardcode its IP as first nameserver, and then set the public
			# nameserver second. Then as long as vpnkit is running it will be used. If not the public nameserver will be used,
			# it will be slower because it will wait for timeout from the vpnkit ip first, but then there may not be internet
			# connection at all when not vpnkit is running!
			# Note: Hard coding gateway IP for wsl-vpnkit, assuming wsl-vpnkit is using VPNKIT_GATEWAY_IP="192.168.67.1"!
			[System.IO.File]::WriteAllText((Join-Path $Destination 'resolv.conf'),
				"# VPNKit gateway / Windows host DNS resolver`n" + `
				"nameserver 192.168.67.1`n" + `
				"# Public DNS server from Cloudfare`n" + `
				"nameserver 1.1.1.1`n",
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!
		}

		#
		# Utility scripts (install/configure/uninstall/unconfigure)
		#
		if ($PSCmdlet.ShouldProcess("wsl-vpnkit-install, wsl-vpnkit-uninstall, wsl-vpnkit-configure, and wsl-vpnkit-unconfigure", "Create VPNKit utility scripts"))
		{
			Write-Host "Creating VPNKit utility scripts..."

			# Install script
			# NOTE: This is intended only to be executed from host during initial install, and are tied
			# to the VPNKit program folder on host, but this is also the case for the main run script
			# wsl-vpnkit which has path to vpnkit.exe on host!
			# NOTE: The wsl-vpnkit script executes vpnkit.exe on host, and via socat also npiperelay.exe.
			# These can be copied into the wsl together with the other files in /usr/local/bin, even
			# though it is a Windows executable, or can create a symlink there pointing back to the host
			# location, or they can just be left on host and the wsl-vpnkit script can be configured to
			# find them in the host location. By copying into wsl we avoid the reference back to host location.
			# By linking to host location it can easily be upgraded to new version without working with wsl,
			# which could also be a downside if there are breaking changes, different versions in use etc..
			$DestinationRoot = [System.IO.Path]::GetPathRoot($Destination)
			$DestinationWslMount = "/mnt/$($Destination.Replace($DestinationRoot, $DestinationRoot.ToLower().Replace(':','')).Replace('\','/'))"
			[System.IO.File]::WriteAllText((Join-Path $Destination 'wsl-vpnkit-install'),
				"#!/bin/sh`n" + `
				"if [ `${EUID:-`$(id -u)} -ne 0 ]; then echo 'Please run this script as root'; exit 1; fi`n" + `
				# WSL-VPNKit script
				"cp `"${DestinationWslMount}/wsl-vpnkit`" /usr/local/bin/`n" + `
				# WSL-VPNKit Windows utilities (vpnkit.exe and npiperelay.exe)
				# These can be copied into /usr/local/bin as well, or creating a symlink back to host,
				# or the wsl-vpnkit script can be configured to find them in host location
				#"cp `"${DestinationWslMount}/npiperelay.exe`" /usr/local/bin/`n" + ` # npiperelay option 1: Copy into wsl
				#"ln -sf `"${DestinationWslMount}/npiperelay.exe`" /usr/local/bin/npiperelay.exe`n" + ` # npiperelay option 2: Symlink back to host
				"cp `"${DestinationWslMount}/vpnkit-tap-vsockd`" /sbin/`n" + `
				"chown root:root /sbin/vpnkit-tap-vsockd`n"+ `
				# Utility scripts
				# Copies the uninstall-script to be able to uninstall without depending on
				# source on host, and as a convenience also copies the configure and unconfigure
				# scripts that can be executed manually to turn on and off the dns config without
				# uninstalling/reinstalling everything.
				"cp `"${DestinationWslMount}/wsl-vpnkit-configure`" /usr/local/bin/`n" + `
				"cp `"${DestinationWslMount}/wsl-vpnkit-unconfigure`" /usr/local/bin/`n" + `
				"cp `"${DestinationWslMount}/wsl-vpnkit-uninstall`" /usr/local/bin/`n",
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!

			# Configure script
			# This will create DNS configuration files /etc/wsl.conf and /etc/resolv.conf
			# same as the templates create above.
			# If wsl.conf already exists it is updated to include generateResolvConf=true,
			# but without destroying any other configuration that may exist.
			# Assuming any existing resolv.conf does not contain anything that should be kept, so
			# will just replace it.
			# NOTE: Independent of source path on host so that it can be executed standalone within wsl,
			# but then does not copy the unconfigure script (or itself) into the host like the install
			# script does, but instead the Install-VpnKit function does that when executing this.
			# NOTE: By default WSL creates /etc/resolv.conf as a symlink, and even even if we configure
			# it not to in wsl.conf and copies in our own physical resolv.conf, WSL may not detect the
			# changed configuration and will either create a symlink over our physical file or replace
			# it with a autogenerated physical file! Immediately shutting down WSL (wsl.exe --shutdown)
			# seems to be necessary to prevent this!
			[System.IO.File]::WriteAllText((Join-Path $Destination 'wsl-vpnkit-configure'),
				"#!/bin/sh`n" + `
				"if [ `${EUID:-`$(id -u)} -ne 0 ]; then echo 'Please run this script as root'; exit 1; fi`n" + `
				# Generate /etc/wsl.conf
				"if [ -f /etc/wsl.conf ]; then`n" + ` # If exists it must be updated (not replaced)
				"  sed -i '/^[ \t]*generateResolvConf[ \t]*=/d' /etc/wsl.conf`n" + ` # Delete any and all lines with generateResolvConf entries
				"  if grep -q '^[ \t]*\[network\]' /etc/wsl.conf; then`n" + ` # Check if there is an existing [network] section
				"    sed -i '/^[ \t]*\[network\]/a generateResolvConf = false' /etc/wsl.conf`n" + ` # Add "generateResolvConf = false" below the existing [network] header
				"  else`n" + `
				"    echo `"[network]`" >> /etc/wsl.conf`n" + ` # Add new [network] section
				"    echo `"generateResolvConf = false`" >> /etc/wsl.conf`n" + ` # Add "generateResolvConf = false" below the new [network] header
				"  fi`n" + `
				"else`n" + ` # Create new wsl.conf
				"  echo `"[network]`" >> /etc/wsl.conf`n" + ` # Add new [network] section
				"  echo `"generateResolvConf = false`" >> /etc/wsl.conf`n" + ` # Add "generateResolvConf = false" below the new [network] header
				"fi`n" + `
				# Generate /etc/resolv.conf
				"[ -f /etc/resolv.conf ] && rm /etc/resolv.conf`n" + ` # Just delete any existing first, with WSL this is a symlink so best get rid of it first.
				"echo `"# VPNKit gateway / Windows host DNS resolver`" >> /etc/resolv.conf`n" + `
				"echo `"nameserver 192.168.67.1`" >> /etc/resolv.conf`n" + `
				"echo `"# Public DNS server from Cloudfare`" >> /etc/resolv.conf`n" + `
				"echo `"nameserver 1.1.1.1`" >> /etc/resolv.conf`n",
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!

			# Uninstall
			# Remove files and revert configuration added by install and configure scripts. 
			# NOTE: Will not just revert changes from install, but also configure, to avoid
			# inconsistent state. This differs from install process, where install must be
			# followed by configure. There is an unconfigure script to revert only changes
			# from configure, but an uninstall will do everything this does and more.
			# NOTE: Independent of source path on host so that it can be executed standalone
			# within wsl. Install-VpnKit will copy this into the wsl distro so that the VPNKit
			# configuration can be easily reverted from within the distro without dependency
			# to host.
			# NOTE: Does not delete wsl.conf even if it was created, just to avoid risking
			# loss of other configuration that should be kept, so instead uses regex to
			# delete any lines setting generateResolvConf=true.
			# Assuming resolv.conf is not important, so that one is just deleted. WSL should
			# auto generate it anyway, since we remove the generateResolvConf=false setting.
			# NOTE: May have to shut down WSL (wsl.exe --shutdown) to force WSL to consider
			# the config changes and autogenerate the resolv.conf again.
			[System.IO.File]::WriteAllText((Join-Path $Destination 'wsl-vpnkit-uninstall'),
				"#!/bin/sh`n" + `
				"if [ `${EUID:-`$(id -u)} -ne 0 ]; then echo 'Please run this script as root'; exit 1; fi`n" + `
				# Perform same as unconfigure does, reverting changes from configure
				"[ -f /etc/resolv.conf ] && rm /etc/resolv.conf`n" + `
				"[ -f /etc/wsl.conf ] && sed -i '/^[ \t]*generateResolvConf[ \t]*=[ \t]*false/d' /etc/wsl.conf && [ `"`$(cat /etc/wsl.conf)`" = `"[network]`" ] && rm /etc/wsl.conf`n" + ` # Delete any and all lines setting generateResolvConf to false, and if only network section header is left in the file delete entire file
				# Revert additional changes from install
				"[ -f /sbin/vpnkit-tap-vsockd ] && rm /sbin/vpnkit-tap-vsockd`n" + `
				"[ -f /usr/local/bin/wsl-vpnkit ] && rm /usr/local/bin/wsl-vpnkit`n" + `
				#"[ -f /usr/local/bin/npiperelay.exe ] && rm /usr/local/bin/npiperelay.exe`n" + `
				"[ -f /usr/local/bin/wsl-vpnkit-configure ] && rm /usr/local/bin/wsl-vpnkit-configure`n" + `
				"[ -f /usr/local/bin/wsl-vpnkit-unconfigure ] && rm /usr/local/bin/wsl-vpnkit-unconfigure`n" + `
				"[ -f /usr/local/bin/wsl-vpnkit-uninstall ] && rm /usr/local/bin/wsl-vpnkit-uninstall`n", # Note: At the end delete the installed copy of current script, may or may not be the one currently running!
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!

			# Unconfigure
			# Separate script for reverting changes from the configure script.
			# NOTE: The same commands will be performed by the uninstall script, to avoid
			# inconsistent state (this differs from install process, where install must be
			# followed by configure).
			# NOTE: Independent of source path on host so that it can be executed standalone
			# within wsl. Install-VpnKit will copy this into the wsl distro so that the VPNKit
			# configuration can be easily reverted from within the distro without dependency
			# to host.
			[System.IO.File]::WriteAllText((Join-Path $Destination 'wsl-vpnkit-unconfigure'),
				"#!/bin/sh`n" + `
				"if [ `${EUID:-`$(id -u)} -ne 0 ]; then echo 'Please run this script as root'; exit 1; fi`n" + `
				"[ -f /etc/resolv.conf ] && rm /etc/resolv.conf`n" + `
				"[ -f /etc/wsl.conf ] && sed -i '/^[ \t]*generateResolvConf[ \t]*=[ \t]*false/d' /etc/wsl.conf`n", # Delete any and all lines setting generateResolvConf to false
				(New-Object System.Text.UTF8Encoding $false)) # Note: File encoding is UTF-8 without BOM, using System.IO to be able to force this in PowerShell versions older than 7.0!
		}
	}
	finally
	{
		if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
			Remove-Item -LiteralPath $TempDirectory -Recurse
		}
	}
}

# .SYNOPSIS
# Install the VPNKit networking system into a WSL distribution.
#
# .DESCRIPTION
# When done you can start the VPNKit service with function Start-VpnKit.
#
# Installs into /usr/local/bin of the distribution:
# - /usr/local/bin/wsl-vpnkit (third party shell script)
# - /usr/local/bin/wsl-vpnkit-configure (shell script generated by New-VpnKit)
# - /usr/local/bin/wsl-vpnkit-unconfigure (shell script generated by New-VpnKit)
# - /usr/local/bin/wsl-vpnkit-uninstall (shell script generated by New-VpnKit)
# - /sbin/vpnkit-tap-vsockd (third party executable)
#
# Modifies configuration files:
# - /etc/wsl.conf
# - /etc/resolv.conf
#
# On supported distros also installs required packages: Primarily the "socat"
# package (with dependencies such as libwrap0 and libssl1.1 if also missing),
# but also iproute2 (for the ip command), sed and grep if missing. Assuming
# there is no network connectivity in WSL, the package file(s) are downloaded
# on host and installed from file into the WSL distro.
#
# For updating, just run the command again, it will replace existing files.
#
# Can be re-run at any time to update an existing install, it will replace
# existing files, and skip install of packages already present.
# Run Unintall-VpnKit to revert everyting, except the package installations.
#
# By default it will install all tools necessary to run the VPNKit service,
# but you only need to run this from one distribution, and can only run one
# instance at a time, so for additional distributions you can run this function
# with parameter -ConfigurationOnly to set up the DNS configuration required to
# access an already running VPNKit service. It will then only modify the
# configuration files listed above (wsl.conf and resolv.conf).
#
# There is also a parameter -InstructionsOnly, when set this funciton will only
# print instructions for how to install VPNKit into the distro manually.
#
# Note that when installing the VPNKit into a WSL distribution, you must refer to
# a directory containing the files created by New-VpnKit, and the generated script
# files containing a reference to this path on host will be copied into the WSL
# distribution, so if this path changes you must also update the scripts within the
# WSL distribution(s).
# .LINK
# New-VpnKit
# Start-VpnKit
# Uninstall-VpnKit
# .LINK
# https://github.com/albertony/wsl-vpnkit/
function Install-VpnKit
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Optional name of distro. If not specified WSL default will be assumed.
		[Parameter(Mandatory=$false)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Optional directory path where VPNKit program files have been installed into on host. Default is current directory.
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[Alias("Source")]
		[string] $ProgramDirectory = (Get-Location -PSProvider FileSystem).ProviderPath,

		# Optional working directory where downloads will be temporarily placed. Default is current directory.
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string] $WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath,

		# Only install the nameserver configuration (/etc/wsl.conf and /etc/resolv.conf),
		# which is the only necessary part for any additional distro instances other than
		# the one running the wsl-vpnkit script.
		[Alias("DnsOnly", "NameserverOnly")]
		[switch] $ConfigurationOnly,

		# Force terminate/shutdown to ensure DNS configuration changes are applied
		# (let WSL recreate a default /etc/resolv.conf).
		# Default when neither -Terminate nor -DontTerminate is specified is to ask.
		[switch] $Terminate,

		# Don't ask to terminate/shutdown to ensure DNS configuration changes are applied
		# (let WSL should recreate a default /etc/resolv.conf).
		# Default when neither -Terminate nor -DontTerminate is specified is to ask.
		[switch] $DontTerminate,

		# Only print instructions for how to install manually.
		[switch] $InstructionsOnly
	)
	if (-not (IsDistroVersion2 -Name $Name)) {
		throw "The specified distro is not version 2, and VPNKit is only supported (and relevant) on version 2 distros"
	}
	$ProgramDirectory = Get-Directory -Path $ProgramDirectory # Not -Create, report error if not exists!
	if (-not (Test-Path -LiteralPath (Join-Path $ProgramDirectory 'wsl-vpnkit-install') -PathType Leaf)) {
		throw "Parameter -ProgramDirectory must specify path to a directory containing the script 'wsl-vpnkit-install'"
	}
	$ProgramDirectoryRoot = [System.IO.Path]::GetPathRoot($ProgramDirectory)
	$ProgramDirectoryWslMount = "/mnt/$($ProgramDirectory.Replace($ProgramDirectoryRoot, $ProgramDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
	
	if ($InstructionsOnly)
	{
		# Print instructions only
		# Note: Printing Linux shell commands, but could also be prefixed with wsl.exe for execution directly from host shell.
		Write-Host "To install VPNKit you must execute the following (as root) from a WSL2 prompt, or prefixed with wsl.exe in a console on host:"
		Write-Host
		if (-not $ConfigurationOnly)
		{
			Write-Host "cp `"${ProgramDirectoryWslMount}/wsl-vpnkit`" /usr/local/bin/"
			Write-Host "cp `"${ProgramDirectoryWslMount}/vpnkit-tap-vsockd`" /sbin/" # Note: This one goes into the standard directory for root programs
			Write-Host "chown root:root /sbin/vpnkit-tap-vsockd"
			# Note: Could also update VPNKIT_PATH and VPNKIT_NPIPERELAY_PATH in wsl-vpnkit script with destination path to vpnkit.exe on host,
			# but this is currently done in PowerShell above, so the source file is already correct at this point.
			#$DestinationVpnKitExe = (Join-Path $Destination 'vpnkit.exe').Replace('\','\/')
			#Write-Host "sed -i 's/VPNKIT_PATH=.*/VPNKIT_PATH=${DestinationVpnKitExe}/' /usr/local/bin/vpnkit.exe"
			#Write-Host "sed -i 's/VPNKIT_NPIPERELAY_PATH=.*/VPNKIT_NPIPERELAY_PATH=${DestinationVpnKitExe}/' /usr/local/bin/npiperelay.exe"
		}
		else
		{
			Write-Host "cp `"${ProgramDirectoryWslMount}/resolv.conf`" /etc/"
			Write-Host "cp `"${ProgramDirectoryWslMount}/wsl.conf`" /etc/"
		}
		Write-Host
	}
	else
	{
		# Install (not just print instructions)
		# Two variants: Full install (default), and configuration-only install.
		$WslOptions = GetWslCommandDistroOptions -Name $Name
		$DistroInfo = Get-DistroSystemInfo -Name $Name
		if (-not $ConfigurationOnly)
		{
			# Perform full install
			if (-not $PSCmdlet.ShouldProcess($ProgramDirectory, "Install VPNKit to WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]")) { return }
			Write-Host "Installing VPNKit to WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]..."

			# Ensure required package 'socat' is installed
			# Assuming WSL have no network connectivity yet, temporarily download the package file (and any missing dependencies)
			# on host and install them from file.
			if ($DistroInfo.Id -eq 'debian') {
				# Debian (at least version 9/stretch) does not include socat, and neither its dependencies libssl1.1 and libwrap0.
				# Note: The packages are not in the built-in package list, so we can not get download url
				# just from apt-get install option --print-uris.
				# Note: The dependencies are missing on Debian 9, but if any of them are already installed
				# they will be kept if newer, apt will just report:
				#   "Note, selecting 'socat' instead of '<path>'"
				#   "socat is already the newest version (<version>)."
				$SocatStatus = wsl.exe @WslOptions dpkg -l `| grep -E '^ii[ \t]+socat' # Alternative to "apt list --installed" to avoid WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
				if ($LastExitCode -eq 0) {
					Write-Verbose "Skipping installation of package 'socat' because it is already present: ${SocatStatus}"
				} else {
					$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
					$TempDirectory = New-TempDirectory -Path $WorkingDirectory
					try
					{
						$Packages = 'libwrap0', 'libssl1.1', 'socat' # In order: Dependencies first!
						# Downloading all first, then installing in a single command
						Write-Host "Downloading packages '$($Packages -join `"', '`")'..."
						$PackageDownloadNames = @()
						foreach ($Package in $Packages) {
							if (-not $DistroInfo.PackageSourceCodeName) {
								$DownloadUrl = $null
							} else {
								$DownloadUrl = Invoke-WebRequest -Uri "https://packages.debian.org/$($DistroInfo.PackageSourceCodeName)/amd64/${Package}/download" -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -ExpandProperty href | Where-Object { $_ -match "https?://ftp.no.debian.org/debian" } | Select-Object -First 1
								if (-not $DownloadUrl) {
									# Try once more from the security repo, in case it is there (libssl1.1 will be there)!
									$DownloadUrl = Invoke-WebRequest -Uri "https://packages.debian.org/$($DistroInfo.PackageSourceCodeName)/amd64/${Package}/download" -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -ExpandProperty href | Where-Object { $_ -match "https?://security.debian.org/debian-security" } | Select-Object -First 1
								}
							}
							if (-not $DownloadUrl) {
								Write-Warning "Unable find download url for package '${Package}', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed later"
								break
							} else {
								$DownloadName = ([uri]$DownloadUrl).Segments[-1]
								$DownloadFullName = Join-Path $TempDirectory $DownloadName
								Save-File -Url $DownloadUrl -Path $DownloadFullName
								if (-not (Test-Path -LiteralPath $DownloadFullName)) {
									Write-Warning "Failed to download package '${Package}', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed later"
									break
								}
								$PackageDownloadNames += $DownloadName
							}
						}
						if ($Packages.Count -eq $PackageDownloadNames.Count) { # If some of them failed to be downloaded, don't even try!
							$TempDirectoryRoot = [System.IO.Path]::GetPathRoot($TempDirectory)
							$TempDirectoryWslMount = "/mnt/$($TempDirectory.Replace($TempDirectoryRoot, $TempDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
							Write-Host "Installing packages '$($Packages -join `"', '`")'..."
							$Commands = 'apt-get', 'install'
							foreach($PackageDownloadName in $PackageDownloadNames) {
								$Commands += "${TempDirectoryWslMount}/${PackageDownloadName}"
							}
							wsl.exe @WslOptions --user root --exec @Commands | Out-Verbose
							if ($LastExitCode -ne 0) {
								Write-Warning "Failed to install packages (error code ${LastExitCode}), you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
								break
							}
						}
					}
					finally
					{
						if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
							Remove-Item -LiteralPath $TempDirectory -Recurse
						}
					}
				}
			} elseif ($DistroInfo.Id -eq 'ubuntu') {
				# Ubuntu, at least 20.04, does not include socat, but does include libssl1.1 and libwrap0.
				$SocatStatus = wsl.exe @WslOptions dpkg -l `| grep -E '^ii[ \t]+socat' # Alternative to "apt list --installed" to avoid WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
				if ($LastExitCode -eq 0) {
					Write-Verbose "Skipping installation of package 'socat' because it is already present: ${SocatStatus}"
				} else {
					# The missing socat package is already in the package list, so we can get download url from apt-get install option --print-uris.
					$DownloadUrl = wsl.exe @WslOptions --exec apt-get install socat --print-uris -qq | Select-String -Pattern "\'(.*)\'" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
					if (-not $DownloadUrl) {
						Write-Warning "Unable to download package 'socat', you must manually ensure this required package gets installed"
					} else {
						$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
						$TempDirectory = New-TempDirectory -Path $WorkingDirectory
						try
						{
							$DownloadName = ([uri]$DownloadUrl).Segments[-1]
							$DownloadFullName = Join-Path $TempDirectory $DownloadName
							Save-File -Url $DownloadUrl -Path $DownloadFullName
							if (-not (Test-Path -LiteralPath $DownloadFullName)) { throw "Cannot find download ${DownloadFullName}" }
							$TempDirectoryRoot = [System.IO.Path]::GetPathRoot($TempDirectory)
							$TempDirectoryWslMount = "/mnt/$($TempDirectory.Replace($TempDirectoryRoot, $TempDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
							Write-Host "Installing package 'socat'"
							wsl.exe @WslOptions --user root --exec apt-get install "${TempDirectoryWslMount}/${DownloadName}" | Out-Verbose
							Remove-Item -LiteralPath $DownloadFullName
							if ($LastExitCode -ne 0) {
								Write-Warning "Failed to install package 'socat' (error code ${LastExitCode}), you must manually ensure this required package gets installed"
								break
							}
						}
						finally
						{
							if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
								Remove-Item -LiteralPath $TempDirectory -Recurse
							}
						}
					}
				}
			} elseif ($DistroInfo.Id -eq 'alpine') {
				# Alpine is missing socat, with dependencies ncurses-terminfo-base, ncurses-libs and readline.
				# OLD: Also bash is required to run the original wsl-vpnkit script
				$SocatStatus = wsl.exe @WslOptions apk list --installed --repositories-file /dev/null `| grep '^socat-'
				if ($LastExitCode -eq 0) {
					Write-Verbose "Skipping installation of package 'socat' because it is already present: ${SocatStatus}"
				} else {
					$DownloadBaseUrl = 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/'
					$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
					$TempDirectory = New-TempDirectory -Path $WorkingDirectory
					try
					{
						$Packages = 'ncurses-terminfo-base', 'ncurses-libs', 'readline', 'socat' # OLD: , 'bash'
						# Downloading all first, then installing in a single command
						Write-Host "Downloading packages '$($Packages -join `"', '`")'..."
						$PackageDownloadNames = @()
						foreach ($Package in $Packages) {
							$DownloadName = Invoke-WebRequest -Uri $DownloadBaseUrl -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -ExpandProperty href | select-String -Pattern "^${Package}-\d.*$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 0 | Select-Object -ExpandProperty Value
							if (-not $DownloadName) {
								Write-Warning "Unable to download package '${Package}', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
							} else {
								$DownloadFullName = Join-Path $TempDirectory $DownloadName
								Save-File -Url "${DownloadBaseUrl}${DownloadName}" -Path $DownloadFullName
								if (-not (Test-Path -LiteralPath $DownloadFullName)) {
									Write-Warning "Failed to download package '${Package}', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed later"
									break
								}
								$PackageDownloadNames += $DownloadName
							}
						}
						if ($Packages.Count -eq $PackageDownloadNames.Count) { # If some of them failed to be downloaded, don't even try!
							$TempDirectoryRoot = [System.IO.Path]::GetPathRoot($TempDirectory)
							$TempDirectoryWslMount = "/mnt/$($TempDirectory.Replace($TempDirectoryRoot, $TempDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
							Write-Host "Installing packages '$($Packages -join `"', '`")'..."
							$Commands = 'apk', 'add', '--quiet', '--repositories-file', '/dev/null'
							foreach($PackageDownloadName in $PackageDownloadNames) {
								$Commands += "${TempDirectoryWslMount}/${PackageDownloadName}"
							}
							wsl.exe @WslOptions --user root @Commands | Out-Verbose
							if ($LastExitCode -ne 0) {
								Write-Warning "Failed to install packages (error code ${LastExitCode}), you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
								break
							}
							if ($InstalledPackages -contains 'bash') {
								Write-Host "Note: The bash shell has been installed to be able to run the VPNKit script, you may consider switching the default from the Alpine default ash shell."
							}
						}
					}
					finally
					{
						if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
							Remove-Item -LiteralPath $TempDirectory -Recurse
						}
					}
				}
			} elseif ($DistroInfo.Id -eq 'arch') {
				# Arch is missing socat, and also iproute2, as well as sed and grep required by the shell scripts.
				$SocatStatus = wsl.exe @WslOptions pacman --query socat
				if ($LastExitCode -eq 0) {
					Write-Verbose "Skipping installation of package 'socat' because it is already present: ${SocatStatus}"
				} else {
					$DownloadMirror = 'http://mirror.terrahost.no/linux/archlinux' # Note: Hard coded mirror url!
					$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
					$TempDirectory = New-TempDirectory -Path $WorkingDirectory
					try
					{
						$Packages = @(
							@{ Name = 'socat'; Repository = 'extra'}, # Required by main run script wsl-vpnkit
							@{ Name = 'iproute2'; Repository = 'core' }, # The ip command required by main run script wsl-vpnkit
							@{ Name = 'sed'; Repository = 'core' }, # Required by install/configure scripts
							@{ Name = 'grep'; Repository = 'core' } # Required by install/configure scripts
						)
						# Downloading all first, then installing in a single command
						Write-Host "Downloading packages '$($Packages.Name -join `"', '`")'..."
						$PackageDownloadNames = @()
						foreach ($Package in $Packages) {
							$DownloadBaseUrl = "${DownloadMirror}/$($Package.Repository)/os/x86_64/"
							$DownloadName = Invoke-WebRequest -Uri $DownloadBaseUrl -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -ExpandProperty href | select-String -Pattern "^$($Package.Name)-\d.*\.tar\.zst$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 0 | Select-Object -ExpandProperty Value
							if (-not $DownloadName) {
								Write-Warning "Unable to download package '$($Package.Name)', you must manually ensure required packages '$($Packages.Name -join `"', '`")' gets installed"
							} else {
								$DownloadFullName = Join-Path $TempDirectory $DownloadName
								Save-File -Url "${DownloadBaseUrl}${DownloadName}" -Path $DownloadFullName
								if (-not (Test-Path -LiteralPath $DownloadFullName)) {
									Write-Warning "Failed to download package '$($Package.Name)', you must manually ensure required packages '$($Packages.Name -join `"', '`")' gets installed later"
									break
								}
								$PackageDownloadNames += $DownloadName
							}
						}
						if ($Packages.Count -eq $PackageDownloadNames.Count) { # If some of them failed to be downloaded, don't even try!
							$TempDirectoryRoot = [System.IO.Path]::GetPathRoot($TempDirectory)
							$TempDirectoryWslMount = "/mnt/$($TempDirectory.Replace($TempDirectoryRoot, $TempDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
							Write-Host "Installing packages '$($Packages.Name -join `"', '`")'..."
							$Commands = 'pacman', '--upgrade', '--noconfirm'
							foreach($PackageDownloadName in $PackageDownloadNames) {
								$Commands += "${TempDirectoryWslMount}/${PackageDownloadName}"
							}
							wsl.exe @WslOptions --user root @Commands | Out-Verbose
							if ($LastExitCode -ne 0) {
								Write-Warning "Failed to install packages (error code ${LastExitCode}), you must manually ensure required packages '$($Packages.Name -join `"', '`")' gets installed"
								break
							}
						}
					}
					finally
					{
						if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
							Remove-Item -LiteralPath $TempDirectory -Recurse
						}
					}
				}
			} elseif ($DistroInfo.Id -eq 'fedora') {
				# Fedora is missing socat, and also iproute with dependencies psmisc og libmnl, required by the shell scripts.
				$SocatStatus = wsl.exe @WslOptions rpm --query socat
				if ($LastExitCode -eq 0) {
					Write-Verbose "Skipping installation of package 'socat' because it is already present: ${SocatStatus}"
				} else {
					# TODO: Only packages for stable versions are available, so if distro image is based on Rawhide there is not a match - but should be use highest version number?
					if ($DistroInfo.VersionCodeName -eq 'rawhide') {
						$DownloadBaseUrl = 'https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/x86_64/os/Packages/'
					} else {
						$DownloadBaseUrl = "https://dl.fedoraproject.org/pub/fedora/linux/releases/$($DistroInfo.VersionCodeName)/Everything/x86_64/os/Packages/"
					}
					$WorkingDirectory = Get-Directory -Path $WorkingDirectory -Create
					$TempDirectory = New-TempDirectory -Path $WorkingDirectory
					try
					{
						$Packages = 'socat', 'psmisc', 'libmnl', 'iproute'
						# Downloading all first, then installing in a single command
						Write-Host "Downloading packages '$($Packages -join `"', '`")'..."
						$PackageDownloadNames = @()
						foreach ($Package in $Packages) {
							$DownloadUrl = "${DownloadBaseUrl}$($Package[0])/"
							$DownloadName = Invoke-WebRequest -Uri $DownloadUrl -UseBasicParsing -DisableKeepAlive | Select-Object -ExpandProperty Links | Select-Object -ExpandProperty href | Where-Object { $_ -match "^${Package}-\d.*\.x86_64\.rpm$" } | Select-Object -First 1 # Pick first with a version number, skip "-devel", "-static" or other variants
							$DownloadUrl += $DownloadName
							if (-not $DownloadName) {
								Write-Warning "Unable to download package '$($Package.Name)', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
							} else {
								$DownloadFullName = Join-Path $TempDirectory $DownloadName
								Save-File -Url "${DownloadUrl}" -Path $DownloadFullName
								if (-not (Test-Path -LiteralPath $DownloadFullName)) {
									Write-Warning "Failed to download package '$($Package.Name)', you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
									break
								}
								$PackageDownloadNames += $DownloadName
							}
						}
						if ($Packages.Count -eq $PackageDownloadNames.Count) { # If some of them failed to be downloaded, don't even try!
							$TempDirectoryRoot = [System.IO.Path]::GetPathRoot($TempDirectory)
							$TempDirectoryWslMount = "/mnt/$($TempDirectory.Replace($TempDirectoryRoot, $TempDirectoryRoot.ToLower().Replace(':','')).Replace('\','/'))"
							Write-Host "Installing packages '$($Packages -join `"', '`")'..."
							$Commands = 'rpm', '--install'
							foreach($PackageDownloadName in $PackageDownloadNames) {
								$Commands += "${TempDirectoryWslMount}/${PackageDownloadName}"
							}
							wsl.exe @WslOptions --user root @Commands | Out-Verbose
							if ($LastExitCode -ne 0) {
								Write-Warning "Failed to install packages (error code ${LastExitCode}), you must manually ensure required packages '$($Packages -join `"', '`")' gets installed"
								break
							}
						}
					}
					finally
					{
						if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
							Remove-Item -LiteralPath $TempDirectory -Recurse
						}
					}
				}
			}
			else {
				Write-Warning "Automatic install of package 'socat' is not implemented for this distro, you must manually ensure this required package gets installed"
			}
			
			# Execute the install and configure scripts from within WSL with wsl.exe.
			# The install script will also copy the uninstall-script into wsl to be able
			# to uninstall without depending on source on host, and as a convenience also
			# copies the configure and unconfigure scripts that can be executed manually to
			# turn on and off the dns config without uninstalling/reinstalling everything.
			# Note: Running as root (not all systems have sudo, e.g. Alpine)
			Write-Host "Running VPNKit install and configure scripts..."
			wsl.exe @WslOptions --user root "${ProgramDirectoryWslMount}/wsl-vpnkit-install" `&`& "${ProgramDirectoryWslMount}/wsl-vpnkit-configure"
			if ($LastExitCode -ne 0) { throw "VPNKit install/configure scripts failed (error code ${LastExitCode})" }
		}
		else
		{
			# Perform configuration-only install
			if (-not $PSCmdlet.ShouldProcess($ProgramDirectory, "Configure VPNKit (nameserver) for WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]")) { return }
			Write-Host "Configuring VPNKit (nameserver) for WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]..."
			# Execute the configure script from within WSL with wsl.exe.
			# The configure script does not copy itself or the unconfigure script into WSL,
			# because they are created to also be a stand-alone part of the full install where
			# they can be executed manually, so therefore we copy them in here. Unconfigure is
			# most important, to be able to roll back, but for conenience also includes the
			# configure script to be able to reconfigure manually.
			# Note: Running as root (not all systems have sudo, e.g. Alpine)
			Write-Host "Running VPNKit configure script..."
			wsl.exe @WslOptions --user root "${ProgramDirectoryWslMount}/wsl-vpnkit-configure" `&`& cp "${ProgramDirectoryWslMount}/wsl-vpnkit-configure" "${ProgramDirectoryWslMount}/wsl-vpnkit-unconfigure" /usr/local/bin/
			if ($LastExitCode -ne 0) { throw "VPNKit configure scripts failed (error code ${LastExitCode})" }
		}

		# Shutdown WSL seems to be the only way to consistently get it to not clobber with our copied /etc/resolv.conf!
		# If starting a new session without shutting down, the changes may be lost!
		# TODO: Terminating the single instance may be enough, but seems it not always is!
		# Alt 1: Default shutdown, ask only if -Confirm.
		#if ($PSCmdlet.ShouldProcess("This will terminate all running distributions as well as the virtual machine", "Shut down WSL to apply configuration changes")) {
		# Alt 2: Default ask, shutdown without asking if -Shutdown, and don't shutdown and don't ask if -DontShutdown
		if (-not $DontTerminate -and ($Terminate -or $PSCmdlet.ShouldContinue("Do you want to shutdown WSL to apply DNS configuration changes?`nThis will terminate all running distributions as well as the shared virtual machine.`nIf you chose 'No' there is a chance that the changes will be lost!", "Shut down WSL"))) {
			Write-Host "Shutting down WSL to make sure DNS configuration changes are applied..."
			wsl.exe --shutdown
			if ($LastExitCode -eq 0) {
				return
			} else {
				Write-Warning "Shutdown failed (error code ${LastExitCode})"
			}
		}
		Write-Warning "To be sure that the DNS configuration changes are not lost, due to WSL overwriting the configuration file '/etc/resolv.conf' with a default version, you should shutdown WSL immediately with 'wsl.exe --shutdown'."
	}
}

# .SYNOPSIS
# Uninstall the VPNKit from a WSL distribution.
# .DESCRIPTION
# This will execute unintall/unconfigure scripts that were installed into the
# /usr/local/bin directory of the distribution by Install-VpnKit, so you can also
# perform the uninstallation by executing these directly.
# .LINK
# Install-VpnKit
function Uninstall-VpnKit
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Optional name of distro. If not specified WSL default will be assumed.
		[Parameter(Mandatory=$false)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Force terminate/shutdown to ensure DNS configuration changes are applied
		# (let WSL recreate a default /etc/resolv.conf).
		# Default when neither -Terminate nor -DontTerminate is specified is to ask.
		[switch] $Terminate,

		# Don't ask to terminate/shutdown to ensure DNS configuration changes are applied
		# (let WSL should recreate a default /etc/resolv.conf).
		# Default when neither -Terminate nor -DontTerminate is specified is to ask.
		[switch] $DontTerminate

		# The directory path where VPNKit program files have been installed into.
		#[Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ProgramDirectory
	)

	$WslOptions = GetWslCommandDistroOptions -Name $Name
	$DistroInfo = Get-DistroSystemInfo -Name $Name
	if (-not $PSCmdlet.ShouldProcess("", "Uninstall VPNKit from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]")) { return }
	#Write-Host "Uninstalling VPNKit from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)] (you will be prompted for root password)..." # Print what we are doing, because there will be a prompt for sudo password!
	Write-Host "Uninstalling VPNKit from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]..."

	# Execute the unintall/unconfigure script from within WSL with wsl.exe
	# If there has been a complete install, then the uninstall script should be present,
	# and executing it should uninstall everything, including what the unconfigure script
	# would do, including deleting all scripts.
	# If there has been a configuration-only install, there should not be uninstall script
	# but an unconfigure script, as well as the configure script since Install-VpnKit copies both.
	# We execute the unconfigure script and deletes the two scripts, so that the distro is
	# completely reverted to original state.
	# NOTE: Executes the scripts that are installed into distro. Could also have executed the
	# source versions on host. These may be different if changes have been made, and also
	# by using the script in WSL the uninstallation is not depedent of the script still being
	# present on host.
	# Note: Running as root (not all systems have sudo, e.g. Alpine)
	wsl.exe @WslOptions --user root if [ -f /usr/local/bin/wsl-vpnkit-uninstall ]`; then /usr/local/bin/wsl-vpnkit-uninstall`; fi
	if ($LastExitCode -ne 0) { throw "Uninstall failed (error code ${LastExitCode})" }
	wsl.exe @WslOptions --user root if [ -f /usr/local/bin/wsl-vpnkit-unconfigure ]`; then /usr/local/bin/wsl-vpnkit-unconfigure `&`& rm /usr/local/bin/wsl-vpnkit-unconfigure /usr/local/bin/wsl-vpnkit-configure`; fi
	if ($LastExitCode -ne 0) { throw "Unconfigure failed (error code ${LastExitCode})" }
	# Shutdown WSL to ensure WSL recreates default /etc/resolv.conf?
	# TODO: Seems terminating the instance is enough in this case? But it seems not when doing the install!
	# For terminate we need the name of the distro, so if not given and default is implied we
	# would have to find it to be able to terminate (parse output from wsl --list?)
	# Alt 1: Default shutdown, ask only if -Confirm.
	#if ($PSCmdlet.ShouldProcess("This will terminate all running distributions as well as the virtual machine", "Shut down WSL to apply DNS configuration changes")) {
	# Alt 2: Default ask, shutdown without asking if -Shutdown, and don't shutdown and don't ask if -DontShutdown
	#        Also choosing to just terminate instance if -Name was given.
	if ($Name) {
		# If we have the name we can terminate just this one (seems that is enough)
		if (-not $DontTerminate -and ($Terminate -or $PSCmdlet.ShouldContinue("Do you want to terminate the WSL distro to apply DNS configuration changes?`nYou can chose 'No' and do it yourself any time later later.", "Terminate WSL distro"))) {
			Write-Host "Terminating WSL distro to make sure DNS configuration changes are applied..."
			wsl.exe --terminate $Name
			if ($LastExitCode -eq 0) {
				return
			} else {
				Write-Warning "Terminate failed (error code ${LastExitCode})"
			}
		}
	} else {
		# Don't know the name, implied default but to terminate we must have the name. So offer full shutdown instead.
		if (-not $DontTerminate -and ($Terminate -or $PSCmdlet.ShouldContinue("Do you want to shutdown WSL to apply DNS configuration changes?`nThis will terminate all running distributions as well as the shared virtual machine.`nIf you had specified the distro name instead of relying on default, this single`ninstance could have been terminated instead.`nYou can always chose 'No' and do it yourself any time later.", "Shut down WSL"))) {
			Write-Host "Shutting down WSL to make sure DNS configuration changes are applied..."
			wsl.exe --shutdown
			if ($LastExitCode -eq 0) {
				return
			} else {
				Write-Warning "Shutdown failed (error code ${LastExitCode})"
			}
		}
	}
	Write-Warning "The default DNS configuration file '/etc/resolv.conf' may not be recreated until the distro has been terminated."
}

# .SYNOPSIS
# Start the VPNKit service from a distro where it has been installed with Install-VpnKit.
# .DESCRIPTION
# This will simply execute the script `/usr/local/bin/wsl-vpnkit` from within the distribution,
# so you can do this directly also.
#
# By default it will start the script in a new console window, so that you can continue using
# you current console Windows to e.g. log in to the distro and start using it, but can also
# start in the current console with parameter -NoNewWindow.
#
# Can only run a single instance at the time.
#
# .LINK
# Install-VpnKit
# Start-Distro
function Start-VpnKit
{
	[CmdletBinding(SupportsShouldProcess)]
	param
	(
		# Optional name of distro. If not specified WSL default will be assumed.
		[Parameter(Mandatory=$false)]
		[ArgumentCompleter({param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams) CompleteDistroName -WordToComplete $WordToComplete})]
		[ValidateNotNullOrEmpty()] [ValidateScript({ValidateDistroName $_})]
		[Alias("Distribution", "Distro")]
		[string] $Name,

		# Start in the current console windows. Default is to start as a new console window.
		[switch] $NoNewWindow,

		# Force stop any existing vpnkit processes.
		# Default when neither -StopExisting nor -DontStopExisting is specified is to ask.
		[switch] $StopExisting,
		
		# Don't ask to stop existing vpnkit processes.
		# Default when neither -StopExisting nor -DontStopExisting is specified is to ask.
		[switch] $DontStopExisting
	)
	$WslOptions = GetWslCommandDistroOptions -Name $Name
	$DistroInfo = Get-DistroSystemInfo -Name $Name
	if (-not $PSCmdlet.ShouldProcess("/usr/local/bin/wsl-vpnkit", "Run wsl-vpnkit as root from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]")) { return }
	# Check if already running and suggest stopping, but Docker Desktop is also executing its own vpnkit.exe so must not touch those!
	# Note that even if killing vpnkit.exe on host, if the existing vpnkit process was started from a wsl-vpnkit
	# script in the same distro, then it will still fail with socat socket already exists etc! But sometimes it
	# is just a stray vpnkit process, and then killing it automatically is convenient.
	$VpnKitProcesses = Get-Process -Name vpnkit -ErrorAction Ignore | Where-Object -Property CommandLine -like "*\\.\pipe\wsl-vpnkit*" # Note: Assuming named pipe used by wsl-vpnkit script!
	if ($VpnKitProcesses) {
		if (-not $DontStopExisting -and ($StopExisting -or $PSCmdlet.ShouldContinue("There are $($VpnKitProcesses.Count) vpnkit process(es) already running. You can only run one VPNKit service`nat a time, and if you want to start a different one you should manually stop the existing.`nIf you think it is just stray vpnkit processes then terminating them may is OK.`nDo you want to terminate existing vpnkit process(es)?`n$($VpnKitProcesses.Path -join '`n')", "Stop vpnkit.exe"))) {
			$VpnKitProcesses | Stop-Process -Force:$Force # If -Force then stop without prompting for confirmation (default is to prompt before stopping any process that is not owned by the current user)
		}
		# TODO: If deciding not to stop, just try anyway, with a probable error being the result, or should we abort?
	}
	if ($NoNewWindow) {
		# Run in current PowerShell console
		# Note: Running as root (not all systems have sudo, e.g. Alpine)
		Write-Host "Starting wsl-vpnkit from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)] in new window..."
		wsl.exe @WslOptions --user root --exec /usr/local/bin/wsl-vpnkit
		# Will run until Ctrl+C exit, so will typically report non-zero exit code!?
	} else {
		# Start as new window
		# Note: Running as root (not all systems have sudo, e.g. Alpine)
		Write-Host "Starting wsl-vpnkit from WSL distro '$(if($Name){$Name}else{'(default)'})' [$($DistroInfo.ShortName)]..."
		Start-Process -FilePath wsl.exe -ArgumentList ($WslOptions + '--user', 'root', '--exec', '/usr/local/bin/wsl-vpnkit')
	}
}
