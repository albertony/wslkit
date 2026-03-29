#
# Script for creating an Alpine Linux WSL distribution.
#
# This script is tailormade for just the simple creation and initial setup of an Arch distribution, and it takes
# advantage of advances in the WSL software, the modern distribution format, etc, compared to the somewhat obsolete
# and general purpose script .\Wsl.ps1.
#
# There is no offisial WSL distro provided by Alpine or included in Microsoft's distribution list, but there
# is an official Alpine Minimal Root Filesystem archive, and it is very simple to download and import. It is ready
# to run as WSL distribution, no need for extra configuration or initial setup.
#
# Runs somewhat interactive by default, asking for confirmation of just a few main decisions. Run with parameter -Force
# to run complete non-interactive. To run fully interactive instead, and be prompted to confirm every relevant steps,
# run with parameter -Confirm.
#
[CmdletBinding(SupportsShouldProcess)]
param (
	# The unique name to register for the distribution.
	[Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9._-]+$', Options = 'None')]
	[string] $Name, # Validation according to https://github.com/microsoft/WSL-DistroLauncher/blob/master/DistroLauncher/DistributionInfo.h

	# The directory path where distribution shall be installed into (mainly the disk image file).
	# If parameter -AppendNameToDestination is also specified, then it will be extended with a subdirectory according
	# to parameter -Name.
	# When using the import command in WSL, this is required parameter. On regular install the default is
	# "${Env:LocalAppData}\wsl\<DistributionId>", where DistributionId is the unique internal id generated for the
	# distro, and an undocumented parameter "general.distributionInstallPath" can be set in the global configuration
	# file, .wslconfig in your Windows user profile directory, to replace the default parent "${Env:LocalAppData}\wsl".
	[Parameter(Mandatory)] [string] $Destination,

	# Optionally append distribution name from parameter -Name as a subdirectory of the path given by -Destination.
	[switch] $AppendNameToDestination,

	# Optionally create regular user as default user, instead of the built-in root.
	# If not credentials are supplied in parameter -User, an interactive prompt will be shown.
	[switch] $CreateUser,

	# Optional credentials of regular user to create as default user, instead of the built-in root.
	# If supplying only a username, as a string value, then PowerShell will show Get-Credential prompt
	# automatically to make it into a [pscredential] value, and you will then be able to set
	# a password (and edit the username) in the prompt, before continuing. You may choose to leave
	# the password empty to create user without a password.
	# Parameter -CreateUser is implied.
	[pscredential] $User,

	[switch] $SetAsDefaultDistribution, # Set this distribution as the default for WSL.
	[switch] $EnableInterop, # Keep the interop process support enabled.

	# Force terminate/shutdown to ensure distribution files can be moved.
	# Default is to ask.
	[switch] $Force
)
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
if ($AppendNameToDestination) {
	$Destination = Join-Path -Path $Destination -ChildPath $Name
}
if (Test-Path -LiteralPath $Destination) {
	throw "Destination already exists"
}
if (($CreateUser -or $User) -and ($Force -or $PSCmdlet.ShouldProcess("$(if($User){$User.UserName}else{'Prompt for credential'})", "Create user"))) {
	# Repeat while:
	# - Username given but is not valid
	# - Username given, but no password, and user confirms the intention was not passwordless user (which is problematic on systems with sudo, but there is no sudo by default in Alpine, and it os only available from a community package)
	# - Credential prompt aborted, and user confirms that the intention is still to create a user
	do {
		if (-not $User -and -not ($User = Get-Credential -Message "Enter credential for user to be created" -UserName $User.UserName)) {
			if ($Force -or $PSCmdlet.ShouldContinue("No credentials given, do you want to skip creation of user?", "Create user")) {
				break
			}
		}
		elseif ($User.UserName -cnotmatch '^[a-z_][a-z0-9_-]*[$]?$') { # Not strict requirement in all distros, but highly recommended to only use usernames that begin with a lower case letter or an underscore, followed by lower case letters, digits, underscores, or dashes. They can end with a dollar sign.
			Write-Warning "The user name `"$($User.UserName)`" is not valid. Must begin with a lower case letter or an underscore, followed by lower case letters, digits, underscores, or dashes. May end with a dollar sign."
			$User = $null
		}
		elseif ($User.Password.Length -eq 0) {
			if (-not ($Force -or $PSCmdlet.ShouldContinue("No password given. Users without password may be problematic to use with sudo.`nDo you want to create user `"$($User.UserName)`" without password?", "Create user"))) {
				$User = $null
			}
		}
	} while (-not $User)
}
if ($Force -or $PSCmdlet.ShouldProcess($(if($Destination){$Destination}else{'(Default destination)'}), "Create Alpine Minimal Root Filesystem distribution '${Name}'")) {
	Write-Host "Fetching release information..."
	$ArchiveName, $Version = Invoke-WebRequest -Uri 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml' -UseBasicParsing -DisableKeepAlive | Select-String -Pattern 'alpine-minirootfs-(.*)-x86_64\.tar\.gz' | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 0,1 | Select-Object -ExpandProperty Value
	if (-not $ArchiveName) {
		throw "Release information (latest-releases.yaml) not found"
	}
	Write-Host "Downloading minimal root filesystem archive version ${Version}..."
	$ArchiveFile = New-TemporaryFile
	try {
		$ExpectedHash = Invoke-WebRequest -Uri "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/${ArchiveName}.sha512" -UseBasicParsing -DisableKeepAlive | Select-String -Pattern "^(.*?)\s+${ArchiveName}$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
		if (-not $ExpectedHash) {
			throw "Checksum for release archive '${ArchiveName}' not found"
		}
		Start-BitsTransfer -Source "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/${ArchiveName}" -Destination $ArchiveFile
		$ActualHash = (Get-FileHash -Algorithm SHA512 -LiteralPath $ArchiveFile.FullName).Hash
		if ($ActualHash -ne $ExpectedHash) {
			throw "Checksum mismatch in downloaded archive ${ArchiveName}: Expected ${ExpectedHash}, but was ${ActualHash}"
		}
		Write-Host "Installing into destination `"${Destination}`"..."
		wsl.exe --import $Name $Destination $ArchiveFile.FullName
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
	}
	finally {
		$ArchiveFile | Remove-Item
	}
	# Look up registry key for the distro, where we set some settings. The key name is unique distribution ID,
	# but we don't know it so must search by name.
	if (-not ($DistributionRegistryKey = Get-ChildItem -LiteralPath HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | Where-Object { (Get-ItemPropertyValue -LiteralPath $_.PSPath -Name DistributionName) -eq $Name })) {
		throw "No distribution with name '${Name}' found in registry"
	}
	if ($DistributionRegistryKey.Count -gt 1) {
		# Should not be possible, trying to create a duplicate should fail with:
		#   A distribution with the supplied name already exists. Use --name to chose a different name.
		#   Error code: Wsl/InstallDistro/ERROR_ALREADY_EXISTS
		throw "More than one distribution with name '${Name}' found in registry"
	}
	# Disable interop processes, for performance and security.
	# Does it with registry option (could have done it in /etc/wsl.conf as well), by unsetting bits
	# from the "Flags" value: Interop (1), and AppendWindowsPath (2) although it has no effect without Interop (1).
	# Default value is 15 (Interop (1) | AppendWindowsPath (2) | AutoMount (4) | Version2 (8)), and
	# after this change the result is therefore 12 (AutoMount (4) og Version2 (8)).
	if (-not $EnableInterop) {
		$DistributionRegistryKey | Set-ItemProperty -Name Flags -Value (($DistributionRegistryKey | Get-ItemPropertyValue -Name Flags) -band -bnot (0x1 -bor 0x2))
	}
	# Create additional (non-root) user and set it as the default user.
	if ($User) {
		Write-Host "Creating user `"$($User.UserName)`"..."
		# Must use adduser command, useradd command is not available before installing package shadow.
		# No sudo by default, so user with empty password will not be a problem.
		wsl.exe --distribution $Name --exec sh -c "adduser --disabled-password --gecos '' $($User.UserName)" # On Alpine adduser must run in a shell, so cannot use --exec adduser like on Arch, but also had to use "--exec sh -c" as a workaround for it to accept arguments!
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
		# Add user as member of customized list of groups.
		# See: https://github.com/agowa338/WSL-DistroLauncher-Alpine/blob/master/DistroLauncher/DistroSpecial.h
		# Add to groups in separate command, since adduser does not support the --groups option,
		# and also there is no usermod command by default so must use adduser or addgroup (which are
		# basically the same) to add one by one.
		Write-Host "Setting as member of wheel and some other standard groups..."
		wsl.exe --distribution $Name for g in adm floppy cdrom tape wheel ping`; do adduser $User.UserName `$g`; done
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
		if ($User.Password.Length -gt 0) {
			Write-Host "Setting password for user..."
			"$($User.UserName):$($User.GetNetworkCredential().Password)" | wsl.exe --distribution $Name --exec sh -c "tr -d '\r' | chpasswd"
			if ($LastExitCode -ne 0) {
				throw "WSL command failed (error code ${LastExitCode})"
			}
		}
		Write-Host "Setting user as the default..."
		wsl.exe --manage $Name --set-default-user $User.UserName
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
	}
	# Set this as the default distro.
	if ($SetAsDefaultDistribution) {
		Write-Host "Setting distribution as the default..."
		wsl.exe --set-default $Name
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
	}
	# Shutdown WSL.
	# Not sure how necessary this is?
	if ($Force -or $PSCmdlet.ShouldContinue("To ensure all changes have effect WSL should be shut down.`nThis will terminate all running distributions as well as the shared virtual machine.`nDo you want to continue?", "Shutdown WSL")) {
		Write-Host "Shutting down WSL..."
		wsl.exe --shutdown
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
	}
	# Done
	Write-Host
	Write-Host "Distribution with name `"${Name}`" and id `"$($DistributionRegistryKey.PSChildName)`" successfully created$(if($SetAsDefaultDistribution){" and set as default"})"
	Write-Host
	Write-Host 'You can launch it with any of the following commands:'
	if ($SetAsDefaultDistribution) {
		Write-Host '  wsl'
	}
	Write-Host "  wsl -d ${Name}"
	Write-Host "  wsl --distribution ${Name}"
	Write-Host "  wsl --distribution-id `"$($DistributionRegistryKey.PSChildName)`""
	Write-Host
	Write-Host 'Should you want to remove it, you can use the following command:'
	Write-Host "  wsl.exe --unregister ${Name}"
	Write-Host
}
