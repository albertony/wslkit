#
# Script for creating an Arch Linux WSL distribution.
#
# This script is tailormade for just the simple creation and initial setup of an Arch distribution, and it takes
# advantage of advances in the WSL software, the modern distribution format, etc, compared to the somewhat obsolete
# and general purpose script .\Wsl.ps1.
#
# This installs the official Arch Linux WSL Image. It is based on the modern distribution format, which is basically
# a plain root filesystem archive. It has some extra configuration, sets up pacman automatically on first start, and
# creates Windows Start menu shortcut and Windows Terminal profile. This script skips most of these extras, and instead
# runs the arch-setup shell scripts from the same repository as this script.
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

	# Custom repository mirror to configure in the mirrorlist file for use by pacman, to be used when installing
	# packages. If parameter -UseLatestImageFromMirror is also specified, then this will also be used to download
	# the WSL image itself.
	# Note that this must be the address only to the root of the mirror server and without trailing slash, as
	# "/$repo/os/$arch" will be appended when written to the mirrorlist file. The implicit default in the setup scripts
	# corresponds to "https://fastly.mirror.pkgbuild.com", which is a worldwide CDN mirror from Fastly, a company which
	# is a sponsor of the Arch project providing Hosting/CDN services. This mirror is not a traditional mirror, but a
	# Content Delivery Network service, caching content directly from the authorative source mirror.pkgbuild.com that
	# is running on the Arch Linux Team's own infrastructure. This is a fast and highly recommended worldwide mirror,
	# used a lot recently as the default mirror. The official Arch WSL distro has this preconfigured (but we replace it).
	[string] $Mirror,

	# Optional credentials of regular user to create as default user, instead of the built-in root.
	# If supplying only a username, as a string value, then PowerShell will show Get-Credential prompt
	# automatically to make it into a [pscredential] value, and you will then be able to set
	# a password (and edit the username) in the prompt, before continuing. You may choose to leave
	# the password empty to create user without a password.
	# Parameter -CreateUser is implied.
	[pscredential] $User,

	# Install from an already downloaded distribution image.
	# The argument is assumed to be the path to an official Arch Linux installer file, e.g.
	# "archlinux-2026.03.01.160197.wsl", but it will be imported regardless, so can in theory also be the plain
	# bootstrapper archive.
	# This will perform a simple import, instead of the more standard method of installing the built-in distribution
	# identifier "archlinux" using the WSL install command.
	# This is similar to option -UseLatestImageFromMirror, where the image is first downloaded.
	# Note that the import command in WSL requires the destination to be specified, and since we do not know the
	# default without considering the general.distributionInstallPath parameter in .wslconfig, we require the
	# script parameter -Destination to be specified as well.
	[string] $Source,

	# Download the distribution image manually from the repository mirror and import it. The default is to use the
	# more standard method of installing the built-in distribution identifier "archlinux" using the WSL install command,
	# which takes a predefined image version from a predefined package repository mirror, currently the same Fastly CDN
	# mirror that the image also has preconfigured for pacman to use for installing packages, configured by a
	# distribution registry in the WSL repository itself
	# (https://raw.githubusercontent.com/microsoft/WSL/refs/heads/master/distributions/DistributionInfo.json).
	# Using this method has the advantage of letting you choose the mirror yourself, and also it will use the absolute
	# latest version of the image to be published by the Arch Linux WSL project, which may not yet have been added to
	# the Microsoft's WSL project's distribution registry.
	# Note that the import command in WSL requires the destination to be specified, and since we do not know the
	# default without considering the general.distributionInstallPath parameter in .wslconfig, we require the
	# script parameter -Destination to be specified as well.
	[switch] $UseLatestImageFromMirror,

	# Optionally append distribution name from parameter -Name as a subdirectory of the path given by -Destination.
	[switch] $AppendNameToDestination,

	# Optionally create regular user as default user, instead of the built-in root.
	# This is implied if credentials are supplied in parameter -User.
	# If not credentials are supplied in parameter -User, an interactive prompt will be shown.
	[switch] $CreateUser,

	[switch] $PlainInstall, # Do not run the setup script but leave the distribution in a default, plain, uninitialized state.
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
} elseif ($UseLatestImageFromMirror) {
	throw "Parameter 'Destination' is required when parameter 'UseLatestImageFromMirror' is used"
} elseif ($Source) {
	throw "Parameter 'Destination' is required when parameter 'Source' is used"
}
if ($Source) {
	if ($UseLatestImageFromMirror) {
		throw "Parameters 'Source' and 'UseLatestImageFromMirror' cannot be used together"
	}
	$Source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
	if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
		throw "Source does not exist or is not a file"
	}
}
if (($CreateUser -or $User) -and ($Force -or $PSCmdlet.ShouldProcess("$(if($User){$User.UserName}else{'Prompt for credential'})", "Create user"))) {
	# Repeat while:
	# - Username given but is not valid
	# - Username given, but no password, and user confirms the intention was not passwordless user
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
			if (-not ($Force -or $PSCmdlet.ShouldContinue("No password given. Sudo will then also be configured in passwordless mode.`nDo you want to create user `"$($User.UserName)`" without password?", "Create user"))) {
				$User = $null
			}
		}
	} while (-not $User)
}

if ($Force -or $PSCmdlet.ShouldProcess($(if($Destination){$Destination}else{'(Default destination)'}), "Create Arch Linux WSL distribution '${Name}'")) {
	if ($Source) {
		Write-Host "Installing into custom destination `"${Destination}`"..."
		wsl.exe --import $Name $Destination $Source
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
	}
	elseif ($UseLatestImageFromMirror) {
		# Download the distribution image manually from a package repository mirror and import it.
		$ArchiveName = 'archlinux.wsl'
		$WslMirror = $Mirror # Use the same mirror that we will configure pacman to use when installing packages.
		if (-not $Mirror) {
			# By default we use the worldwide CDN mirror from Fastly, the same as the official WSL repository uses
			# (https://raw.githubusercontent.com/microsoft/WSL/refs/heads/master/distributions/DistributionInfo.json),
			# and the same as the Arch WSL distro has preconfigured for pacman to use when installing packages.
			# Note: Not setting it as $Mirror, because that will be supplied to setup and set as pacman mirror as well,
			# we could do that, but here we don't and instead let that script use its own implicit default (which
			# happens to be the same currently).
			$WslMirror = 'https://fastly.mirror.pkgbuild.com'
		}
		Write-Host "Downloading latest image from mirror `"${WslMirror}`"..."
		$ArchiveUrl = "${WslMirror}/wsl/latest/${ArchiveName}"
		$ArchiveFile = New-TemporaryFile
		try {
			$ExpectedHash = Invoke-WebRequest -Uri "${ArchiveUrl}.SHA256" -UseBasicParsing -DisableKeepAlive | Select-String -Pattern "^(.*?)\s+${ArchiveName}$" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Select-Object -Index 1 | Select-Object -ExpandProperty Value
			if (-not $ExpectedHash) {
				throw "Checksum for image archive '${ArchiveName}' not found"
			}
			Start-BitsTransfer -Source $ArchiveUrl -Destination $ArchiveFile
			$ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchiveFile.FullName).Hash
			if ($ActualHash -ne $ExpectedHash) {
				throw "Checksum mismatch in downloaded image archive ${ArchiveName}: Expected ${ExpectedHash}, but was ${ActualHash}"
			}
			Write-Host "Installing into custom destination `"${Destination}`"..."
			wsl.exe --import $Name $Destination $ArchiveFile.FullName
			if ($LastExitCode -ne 0) {
				throw "WSL command failed (error code ${LastExitCode})"
			}
		}
		finally {
			$ArchiveFile | Remove-Item
		}
	}
	else {
		# Install the official Arch Linux WSL Image identifier "archlinux".
		if ($Destination) {
			Write-Host "Installing into custom destination `"${Destination}`"..."
			wsl.exe --install archlinux --name $Name --location $Destination --no-launch
		}
		else {
			Write-Host "Installing into default destination..."
			wsl.exe --install archlinux --name $Name --no-launch
		}
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
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
	# Disable the distro OOBE (Out of Box Experience) feature, by pretending it has already been run.
	# It would execute script /usr/lib/wsl/first-setup.sh, which does "pacman-key --init && pacman-key --populate",
	# which is not anything that we not already will do in our own arch-setup-pacman script anyway.
	# See:
	#   https://gitlab.archlinux.org/archlinux/archlinux-wsl/-/blob/main/rootfs/etc/wsl-distribution.conf
	#   https://gitlab.archlinux.org/archlinux/archlinux-wsl/-/blob/main/rootfs/usr/lib/wsl/first-setup.sh
	# Note: If we manually downloaded the distribution image .wsl file and imported it with wsl --import, then this
	# is already the case, OOBE will be enabled at all, but it does not harm to make sure.
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
		Write-Host "Creating user `"$($User.UserName)`"..."
		wsl.exe --distribution $Name --exec useradd --create-home --groups wheel $User.UserName # On Arch useradd is a native binary so can use --exec and no need to go through a shell
		if ($LastExitCode -ne 0) {
			throw "WSL command failed (error code ${LastExitCode})"
		}
		if ($User.Password.Length -gt 0) {
			Write-Host "Setting password for user..."
			# Note: Password will be decrypted to plain text in memory and appear on the PowerShell pipeline,
			# but will be piped into the wsl shell process, thus not be visible in process list or shell history.
			# On Arch chpasswd is a native binary, so could have used --exec and avoid going through a shell:
			#   "$($User.UserName):$($User.GetNetworkCredential().Password)" | wsl.exe --distribution $Name --exec chpasswd
			# However, the problem is that PowerShell terminates the pipeline to external command with native line ending,
			# "`r`n", that would then end up including the "`r" as part of the password, and we therefore use the
			# shell to trim that off using the tr command (assuming it is available).
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

	if (-not $PlainInstall -and ($Force -or $PSCmdlet.ShouldProcess('mirrorlist, wsl-distribution.conf, archlinux.ico, first-setup.sh', "Cleanup default wsl configuration from distribution '${Name}'"))) {
		# Deleting the custom mirrorlist that the WSL distribution bundles, as well as WSL specific OOBE-related and shortcut icon files.
		# Leaving behind /etc/wsl.conf (which sets option boot.systemd=true) and /etc/locale.conf (which sets proper default LANG=C.UTF-8).
		wsl.exe --distribution $Name --user root rm /etc/pacman.d/mirrorlist /etc/wsl-distribution.conf /usr/lib/wsl/archlinux.ico /usr/lib/wsl/first-setup.sh
	}

	# Run the complete setup script from this repo, which minimizes filesystem, configures pacman, installs packages,
	# configures locales and sets up sudo.
	# Note: The pacman setup is important since we skipped OOBE (see above).
	# Note: This is an interactive shell script running from within the distro, so you will need to confirm,
	# all should normally be accepted.
	if (-not $PlainInstall -and ($Force -or $PSCmdlet.ShouldProcess('./arch-setup', "Run initial setup of distribution '${Name}'"))) {
		Write-Host
		Write-Host "Running initial setup script (arch-setup with options: $((@('C locale', $(if($Mirror){"pacman mirror ${Mirror}"}), $(if($User.Password.Length -eq 0){"passwordless sudo"})) | Where-Object {$_}) -join ', '))..."
		Write-Host
		wsl.exe --distribution $Name --cd $PSScriptRoot --user root `
			ARCH_SETUP_LANGUAGE=C ARCH_SETUP_MIRROR=${Mirror} ARCH_SETUP_SUDO_NOPASSWD=$(if($User.Password.Length -eq 0){'X'}) `
			./arch-setup $(if($Force -or $PSCmdlet.ShouldProcess('./arch-setup', "Activate non-interactive mode with parameter '--noconfirm'")) { '--noconfirm' })
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
