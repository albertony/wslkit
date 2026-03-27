#
# Script for creating an Arch Linux WSL distribution.
#
# This script is tailormade for just the simple creation and initial setup of an Arch distribution, and it takes
# advantage of advances in the WSL software, the modern distribution format, etc, compared to the somewhat obsolete
# and general purpose script .\Wsl.ps1.
#
# This installs the official Arch Linux WSL Image, "archlinux". It is based on the modern distribution format, close
# to a simple root filesystem archive. It has some extra configuration, sets up pacman automatically on first start,
# and creates Windows Start menu shortcut and Windows Terminal profile. This script skips most of these extras, and
# instead runs the arch-setup shell scripts from the same repository as this script.
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
	# The default is "${Env:LocalAppData}\wsl\<DistributionId>", where DistributionId is the unique internal id
	# generated for the distro. An undocumented parameter "general.distributionInstallPath" can be set in the global
	# configuration file, .wslconfig in your Windows user profile directory, to replace the default
	# "${Env:LocalAppData}\wsl".
	[string] $Destination,

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

	[switch] $CleanInstall, # Do not run the setup script but leave the distribution in a clean and uninitialized state.
	[switch] $SetAsDefaultDistribution, # Set this distribution as the default for WSL.
	[switch] $EnableInterop, # Keep the interop process support enabled.
	[switch] $CreateStartMenuShortcut, # Keep the default created Windows Start menu shortcut.
	[switch] $CreateWindowsTerminalProfile, # Keep the default created Windows Terminal profile.

	# Force terminate/shutdown to ensure distribution files can be moved.
	# Default is to ask.
	[switch] $Force
)
if ($Destination) {
	$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
	if ($AppendNameToDestination) {
		$Destination = Join-Path -Path $Destination -ChildPath $Name
	}
	if (Test-Path -LiteralPath $Destination) {
		throw "Destination already exists"
	}
}
if (($CreateUser -or $User) -and ($Force -or $PSCmdlet.ShouldProcess("$(if($User){$User.UserName}else{'Prompt for credential'})", "Create user"))) {
	# Repeat while:
	# - Username given but is not valid (ValidateScript above are still associated with the $User variable)
	# - Username given, but no password, and user confirms the intention was not passwordless user (which is problematic on systems with sudo)
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
if ($Force -or $PSCmdlet.ShouldProcess($(if($Destination){$Destination}else{'(Default destination)'}), "Create Arch Linux WSL distribution '${Name}'")) {
	# Install hard coded distro "archlinux", the official Arch Linux WSL Image, a modern distribution
	# format - close to just a root filesystem archive.
	if ($Destination) {
		Write-Host "Installing into destination `"${Destination}`"..."
		wsl.exe --install archlinux --name $Name --location $Destination --no-launch
	}
	else {
		Write-Host "Installing into default destination..."
		wsl.exe --install archlinux --name $Name --no-launch
	}
	if ($LastExitCode -ne 0) {
		throw "WSL command failed (error code ${LastExitCode})"
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
	# Disable the distro OOBE (Out of Box Experience) script, by pretending it has already been run.
	# It would not do anything that we not already do in the arch-setup-pacman script
	# (pacman-key --init && pacman-key --populate).
	# See:
	#   https://gitlab.archlinux.org/archlinux/archlinux-wsl/-/blob/main/rootfs/etc/wsl-distribution.conf
	#   https://gitlab.archlinux.org/archlinux/archlinux-wsl/-/blob/main/rootfs/usr/lib/wsl/first-setup.sh
	$DistributionRegistryKey | Set-ItemProperty -Name RunOOBE -Value 0
	# Remove auto-generated Windows Start menu shortcut
	if (-not $CreateStartMenuShortcut -and ($ShortcutPath = $DistributionRegistryKey | Get-ItemPropertyValue -Name ShortcutPath)) {
		Remove-Item -LiteralPath $ShortcutPath -ErrorAction Ignore
	}
	# Remove auto-generated Windows Terminal profile.
	if (-not $CreateWindowsTerminalProfile -and ($TerminalProfilePath = $DistributionRegistryKey | Get-ItemPropertyValue -Name TerminalProfilePath)) {
		Write-Host "Suggested Windows Terminal profile definition:"
		Write-Host (Get-Content -LiteralPath $TerminalProfilePath -Raw)
		Remove-Item -LiteralPath $TerminalProfilePath -ErrorAction Ignore
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
		Write-Host "Creating user `"${Name}`"..."
		wsl.exe --distribution $Name --exec sh -c "useradd --create-home --groups wheel $($User.UserName)"
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
		if ($User.GetNetworkCredential().Password) {
			Write-Host "Setting password for user..."
			wsl.exe --distribution $Name --exec sh -c "echo \`"$($User.UserName):$($User.GetNetworkCredential().Password)\`" | chpasswd"
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

	# Run the complete setup script from this repo, which minimizes filesystem, configures pacman, installs packages,
	# configures locales and sets up sudo.
	# Note: The pacman setup is important since we skipped OOBE (see above).
	# Note: This is an interactive shell script running from within the distro, so you will need to confirm,
	# all should normally be accepted.
	if (-not $CleanInstall -and ($Force -or $PSCmdlet.ShouldProcess('./arch-setup', "Run initial setup of distribution '${Name}'"))) {
		Write-Host "`nRunning Initial setup script (./arch-setup)...`n"
		if ($Force -or $PSCmdlet.ShouldProcess('./arch-setup', "Activate non-interactive mode with parameter '--noconfirm'")) {
			wsl.exe --cd $PSScriptRoot --user root ./arch-setup --noconfirm
		}
		else {
			wsl.exe --cd $PSScriptRoot --user root ./arch-setup
		}
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
	# The setup script does have some checks for it and will write a message if needed:
	#   NOTICE: Restarting is required for some of the changes to be applied!
	if ($Force -or $PSCmdlet.ShouldContinue("To ensure all changes have effect WSL should be shut down.`nIf this is really necessary you should see a message just above:`n  NOTICE: Restarting is required for some of the changes to be applied`nThis will terminate all running distributions as well as the shared virtual machine.`nDo you want to continue?", "Shutdown WSL")) {
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
