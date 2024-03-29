# WSLKit

This repository contains a toolkit for Windows Subsystem for Linux (WSL).

*TLDR: Go straight to [usage examples](#usage-examples) for more of a step by step guide.*

The main part of the kit is the PowerShell script [Wsl.ps1](Wsl.ps1), which
is a generic utility script for installing and managing [WSL](https://docs.microsoft.com/en-us/windows/wsl/)
distributions. Two of the [main features](#main-features) this provides,
are custom installation of distros, which I have called [sideloading](#sideloading),
and the setup of a third party networking kit, called [VPNKit](#vpnkit).

WSL2 uses Hyper-V virtualized networking by default, and it has shown to be problematic
in combination with VPN and also various antivirus/firewall software.
This project facilitates use of an alternative, third party, networking kit,
called VPNKit. The core part of the VPNKit comes from the [github.com/moby/vpnkit](https://github.com/moby/vpnkit)
project, and it is adapted to WSL using the method from the [github.com/sakai135/wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit)
project. The way it works is to intercept the ethernet traffic of the WSL2 virtual machine,
and redirect it through a dedicated process pipe connection between the virtual machine
and the host. More details [below](#vpnkit).

In addition to the main features mentioned above, this repository also contains some
convenience shell scripts that can be executed from within a newly created WSL distributions
for quick initial configuration, installation of different predefined sets of software
packages etc.

### Windows version

This project was initially created to work on Windows 10 version 1909 (build 18363),
but I have since upgraded to Windows 10 version 21H2 (build 19044).
Not tested with Windows 11.

If you have a different version of Windows you may want to check 
the [release notes for Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/release-notes)
to see if there are new features that affects this solution.
E.g. in build 20190 the built-in `wsl.exe` command gets the ability
to install WSL distros with `wsl --install` command, and in build 20211
it can also list available images with `wsl --install --list-distributions`.
To some degree this will overlap with the `New-Distro` and `Get-DistroImage` functions
in my PowerShell script, although my variants will still be relevant as they 
only imports the disk images without fully installing distros as Windows "apps".
Also they support not only installation of the official WSL distributions, but
also raw disk images, which some official linux releases provides, e.g. the
Arch Linux bootstrap distribution and the Alpine minimal root filesystem.

### Disclaimers

This project exists primarily to support my own use of WSL.

The source code has not been written with public scrutiny in mind, but has grown
out of the previous rationale.

I take no responsibility if anything bad happens if you decide to try it out.

However, I don't expect any problems, and I assume it could be useful
also for others, so please: Just try it out. If you come across any issues,
or have any suggestions, I would appreciate if you report them in my GitHub
project, and I will do my best to make the necessary improvements!

## Main features

Before showing [example usage](#usage-examples), the main features of this project
will be described. At the end you will find more [details](#details).

### WSL Administration

The main PowerShell script provides general WSL administrative functions. Some of
them are just convenience functions around standard `wsl.exe` functionality, but
with more PowerShell-like syntax, including tab completion of parameters such as
name of installed distribution. Others are accessing registry settings used by the
WSL services, not exposed by the standard tools. Example of such functions are
changing which WSL distribution is default, changing the default user account,
renaming or moving the disk image location of a [sideloaded](#sideloading) WSL
distribution (see next section).
See complete [Wsl.ps1 function list](#wslps1-functions) below.

### Sideloading

The PowerShell script supports creating WSL distribution based on the images
that Microsoft publishes [direct download links](https://docs.microsoft.com/en-us/windows/wsl/install-manual#downloading-distributions)
to, which currently includes: Ubuntu, Debian, Kali and OpenSUSE.
The downloads are appx installers, same as what is used behind the scenes in
a Microsoft Store installation. The PowerShell script does not run these
installers, but instead extracts the root filesystem archives within them,
and imports those using the official `wsl.exe` command line utility. The few
configuration steps that would normally be performed by the appx installer
will (when relevant) be performed by the PowerShell script, mainly the optional
creation of a default user account to use instead of the built-in root account.

This "sideloading" means an installed WSL distribution will not be managed by
Windows as an UWP application, like with the standard Microsoft Store-based
installations. You will not be able to uninstall it from the standard Settings
app, and you do not (automatically) get a start-menu shortcut for it. Also, the
virtual disk file will be stored in a directory of your choosing, instead of
the `%LocalAppData%\Packages` directory used by UWP applications. Still, the
installed WSL distributions will by managed by the regular WSL services, and
the standard `wsl.exe` utility etc will treat them completely like if it was
installed from an appx installer or from Microsoft Store.

You can install as many WSL distributions as you like, even multiple instances
of the same image (e.g. multiple Debian instances), as long as you give them
a unique name and disk file location.

The installation method of importing the root filesystem archive, are also
used to include support for some additional images. For example the official
Alpine "minimal root filesystem" archives are published on
[alpinelinux.org](https://alpinelinux.org/downloads/), and Arch Linux
"bootstrap" distributions on [archlinux.org](https://archive.archlinux.org/iso/).
Both of these are supported by the PowerShell script; it will download the
latest version, import it into WSL, and do the basic configuration like
creation of user etc. like with the officially WSL adapted images.
See complete list of supported Linux distributions [below](#linux-distributions).

Edit: Since the above was written, Microsoft has published a short how-to guide
covering this same approach:
[Import any Linux distribution to use with WSL](https://docs.microsoft.com/en-us/windows/wsl/use-custom-distro).
It mentions importing Alpine "minimal root filesystem", but main example it uses
is CentOS by extracting the disk image from a docker container. So this is now
an "officially approved" method for installing WSL distros! My PowerShell
script automates manual steps described.

### VPNKit

The second main functionality of this project and the main PowerShell script
is the support for [VPNKit](https://github.com/moby/vpnkit). This is a set of
tools providing customized, VPN/antivirus/firewall-friendly, network connectivity
from a network device in the VM used to host WSL2 distros.

The challenge with the Hyper-V based networking that is default in WSL, is that
it can easily be problematic with VPN, and will be entirely blocked by some
antivirus/firewall software etc. Read more [here](https://github.com/moby/vpnkit#why-is-this-needed).

The mechanism used is to route network traffic from the distro into a virtual
network interface in the vm, which is connected to a unix socket. A process
in the vm (`socat`) connects the unix socket via a process pipeline to a process
on the host (`npiperelay`), and this host process connects via a Windows named pipe
to a gateway process (`vpnkit`). This relays the ethernet packages into the actual
host network device.

Docker Desktop with WSL2 backend is using much of the same method, the core components
used here, including the VPNKit executable, are actually taken from the Docker Desktop
toolset. For background information, read the vpnkit documentation
[Plumbing inside Docker for Windows](https://github.com/moby/vpnkit/blob/master/docs/ethernet.md#plumbing-inside-docker-for-windows).
The main difference from Docker's approach, is that instead of using Hyper-V sockets
between the host and VM, we use more "native" approach with a process pipeline and
a Windows named pipe, with help of additional components: The
[socat](https://linux.die.net/man/1/socat) utility in the WSL VM, and
the [npiperelay](https://github.com/albertony/npiperelay) utility on the Windows host.

The administration and execution of VPNKit is handled by a shell script [wsl-vpnkit](wsl-vpnkit/wsl-vpnkit),
which is forked from [github.com/sakai135/wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit).
That project was also the main inspiration for all the VPNKit related functionality in the
current repository. My functionality is based on the original version, where it was
simply this shell script and a set of manual tasks to get it running, see the
[VPNKit manual install](#vpnkit-manual-install) section below for details. My `Wsl.ps1`
script has functions `New-VpnKit` and `Install-VpnKit` that does all the needed steps
for you. On September 20, 2021, the original [sakai135](https://github.com/sakai135/wsl-vpnkit)
repository changed to use a separate Alpine distro, and supply a pre-built version
for download. The original version, which I'm based on, is kept as release [v0.1.0-20210916.4273cb7]
(https://github.com/sakai135/wsl-vpnkit/tree/v0.1.0-20210916.4273cb7).

The `wsl-vpnkit` documentation was initially written with the assumption that you
have network connectivity using the default WSL networking, but needed the customized
networking to be able to use a VPN connection from the host. The shell script assumes
you have installed the `socat` utility in the distribution, but if your case is that
you have no network connectivity at all from within your WSL distributions, then how
do you do that? What you can do is to download the package archive files on your host
computer, and install them from file in the WSL distribution using its package tool
in "offline-mode". The `Install-VpnKit` function of my `Wsl.ps1` does this for you.
See the [VPNKit manual install](#vpnkit-manual-install) section below for details.

#### Docker

If you have Docker Desktop installed, it will include its own copy of the
same vpnkit tool (`com.docker.vpnkit.exe`, previously `vpnkit.exe`) used
by the `wsl-vpnkit` system. Upon start/stop it will terminate any running
processes with same name, which means it would also terminate such a process
started by `wsl-vpnkit`, and it would have to be restarted it to get it to
work again. The workaround for this, as in the original
[github.com/sakai135/wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit),
is to rename the copy used for WSL into `wsl-vpnkit.exe`. This is automatically
done by the installation performed by the `Wsl.ps1`,
functions `New-VpnKit` and `Install-VpnKit`.

### Linux distributions

Currently supported linux distributions (and tested versions):
- Ubuntu (tested version 20.04 LTS "Focal Fossa")
- Debian (tested with version 10 "Buster", originally created when the distro download
  was version 9 "Stretch", and then tested that with upgrade to version 10 "Buster"
  and also version 11 "Bullseye")
- Kali (untested)
- OpenSUSE (untested)
- Alpine (tested version 3.13.1)
- Arch (tested version 2021.02.01)
- Fedora (tested release versions 34, 35, 36 and development versions 37 and 38 (current Rawhide), both standard and minimal base images. Note that Fedora 35 does not mount /mnt/c properly, which also means Install-VpnKit will not work out of the box.
- Rocky Linux (Install-VpnKit not supported yet, does not mount /mnt/c without first installing package util-linux, or util-linux-core)
- Void Linux (tested version 20221001)
- Clear Linux OS (Install-VpnKit not supported yet)

Note that the Alpine, Arch, Fedora, Void, Clear and Rocky distributions listed above
are not regular WSL images. Alpine, Arch and Void are official root filesystem
distributions (Alpine calls it "minimal root filesystem", Arch calls it "bootstrap",
Void calls it "rootfs tarball"). Fedora, Clear and Rocky are similar root filesystem
packages, but taken from the official Docker container images, which may have some
additional customizations. Not all of them have been properly tested in a WSL setup,
and may therefore lack something, typically not automatically mounting the host
drives (e.g. /mnt/c). Alpine and Arch are the most safe choices of them,
in addition to the more official WSL distros in the above list, where
Ubuntu and Debian are the ones I've tested most.

Note also that not all distributions listed above support the full VPNKit
installation, as done by function `Install-VpnKit`, and described above.
This function assumes the distro have no network connection, and must
download any packages required by the VPNKit setup on the host and install
in distro from file. This must be implemented for each specific distro, at
least for specific distro built-in package managers, and this is something
I might not yet have done even though I've added basic support for downloading
and installing the distro. What you can do is to install a base distro known
to work with VPNKit, which includes Alpine, Arch, Ubuntu and Debian, and
install the full VPNKit setup in this. Then, if you want to use a different
distro, such as Rocky Linux, you can just do some simple DNS configuration for
it to be able to have network access through the VPNKit setup running in
the other running distro.
See [Creating additional distribution](#creating-additional-distribution)
for more details.

### Linux configuration

The created Linux installations are intentionally left in a clean state after
creation. If you specified a user name then this user will be created, and added to a
image-specific default set of groups (including the `sudo` group for distributions
that includes the sudo utility by default). When installing the VPNKit, it will install
the software package `socat`, which is required by this utility, and copy in some
wsl-vpnkit scripts into `/usr/local/bin`. The images from Microsoft's WSL downloads
may have some small additional configurations included, such as regional settings,
package repository configurations etc, but usually not much more.

To get a more functional system up and running quickly, this project also includes
some additional shell scripts specialized for some of the supported images. Some
are for initial setup, others are for more specific workflows such as installing a
full development environment with Python and GCC.

~~The Debian Linux image currently published on Microsoft is quite old, currently
still on Debian 9 (stretch), so you will probably want to upgrade it to at least
Debian 10 (buster), which is the currently "stable" version of Debian.~~
The Debian Linux image currently published on Microsoft is Debian 10 (buster),
which is the currently "stable" version of Debian. When Debian 11 moves to stable,
you can use the included shell script `debian-upgrade` to do the upgrade. This script
can be used for regular package updates as well as major release upgrades. Read the
comments in the script header for more details. To upgrade to latest stable version
of Debian, just run the script without arguments: `/mnt/c/Wsl/debian-upgrade`.
See also example [below](#debian).

The Alpine, Arch, Fedora, Void, Clear and Rocky images are not WSL images, but official
plain root filsystem image distributions. These will always be installed from the latest
released version, but will generally have less initial configuration than the WSL images.
This is mostly true for the Arch Linux image, where there are quite a few steps that needs
to be performed before being able to start using `pacman` to install additional software.
The supplied script `arch-setup` will perform the required steps for you (read the comments
for description of what it does), just run the script without arguments:
`/mnt/c/Wsl/arch-setup`. See also example [below](#arch). Other images, such as Alpine,
Void, Clear and Rocky, require little or no initial configuration before being taken into
regular use. 

In addition to the mentioned Arch Linux setup script, there are also some additional
convenience scripts for typical, but not necessarily required, set-up tasks. Such as
for upgrading Debian and Fedora to latest version, or to install bash and some other
relevant core tools. See [below](#setting-up-the-wsl-distribution).

For Arch there are also some even higher level setup scripts, which can be used to
quickly set up a development environment. The script `arch-install-dev-cpp-python-qt`
can be executed after `arch-setup` to install a set of packages relevant for a specific
C++, Python and Qt development environment, including:
Git (with LFS), SSL, SSH, GCC, CMake, Ninja, Qt5, Python (with numpy, pylint,
pytest, pyside2 and ipython). Alternatively, the script `arch-install-dev-go` can be to
install a set of packages relevant for a different development environment, namely
Go (golang), including gcc to be able to compile cgo-based packages. It does not install
additional Go related support tools (such as delve, guru, goimports), since not all are
available as pacman packages, and also they can easily be installed from VSCode when
using WSL remoting, or with "go get" command.

The script `ssh-init` is a script for initializing SSH agent for a shell session.
It starts an ssh-agent process, if not already running, and adds all identities found
for current user that are not already loaded. Its purpose is for use with git
and multiple identities, but it is not only to avoid having to execute ssh-add once
for each identity, but also to be able to re-run it at will for ensuring agent
is running and identities are loaded without having to re-enter password each time
also for keys that were already loaded. Note that this script must be sourced into
your current session: `. /mnt/c/Wsl/ssh-init`.

See example usage [below](#setting-up-the-wsl-distribution).

## Usage examples

### First time install, and creating your first WSL distribution with VPNKit

1. Clone this repo (or download the files manually) into a directory of choice,
e.g. `C:\Wsl`.

2. Start PowerShell and dot source the main PowerShell script into the session:
```
cd C:\Wsl
. \Wsl.ps1
```

3. Initiate a subdirectory with VPNKit utilities (skip if you don't need the optional VPNKit networking):
```
New-VpnKit -Destination .\VPNKit
```

4. Create your primary WSL distribution, e.g. using Debian image, with specified
name ("Primary"), disk image file stored in specified subdirectory, and create
user ("me") to use as default instead of the built-in root:
```
New-Distro -Name Primary -Destination .\Distributions\Primary -Image debian-gnulinux -UserName me
```

5. Install VPNKit utility into the created distribution (skip if you don't need the optional VPNKit networking):
```
Install-VpnKit -Name Primary -ProgramDirectory .\VPNKit
```

### Using a WSL distribution with VPNKit

Assuming you have created a WSL distribution with the optional VPNKit networking as described above.

1. Start VPNKit services previously installed on the primary distribution.
```
Start-VpnKit
```

2. Open a shell session to the primary distribution. The following is the same as
running `wsl.exe`, and it will start a shell session in your current console
window. You can add parameter `NewWindow` to start the session as a new console
Windows instead.

```
Start-Distro
```

#### Alternative:

1. Start VPNKit services and open shell session to same distro with a single command:

```
Start-Distro -WithVpnKit
```

### Setting up the WSL distribution

Depending on the image installed, there are usually some basic steps that you want to
perform after the initial distro install. Some can be quickly done by running shell
scripts included in this project. Run them from within the WSL, but you can easily
just refer to them through the automatic mount back to host.

#### Debian

When distro image was still Debian 9 (stretch), but latest stable version was Debian 10 (buster),
the following script would perform the upgrade.
Note that the script (without arguments) will upgrade to latest stable,
but if this is more than one major version step up then you should upgrade one version
at a time. See script comments for details.

```
/mnt/c/Wsl/debian-upgrade
```

#### Arch

Configure locale, sudo and pacman, perform full upgrade of all installed packages,
install some very basic tools (such as sudo, sed, tar, nano, some of which required
by the script itself), and configure bash.

```
/mnt/c/Wsl/arch-setup
```

#### Fedora

Configure locale, perform full upgrade of all installed packages, and install some very
basic tools (such as wget, nano, unzip, findutils), and configure bash.

```
/mnt/c/Wsl/fedora-setup
```

Perform upgrade to latest version. If no new major release then performs a normal
package upgrade. If there is a new major release it performs a full system upgrade
to the new release. If there is more than one major version step up you should upgrade
one version at a time, by specifying target version as argument.
See script comments for details.

```
/mnt/c/Wsl/fedora-upgrade
```

### Creating additional distribution

You can install as many WSL distributions as you want, just make sure to give them a unique name and a
separate directory for the disk image file.

If you are using the VPNKit networking, you only need the full installation on one distro, since (in WSL2)
all distros run in a single shared virtual machine. Any additional distros can make use of the same
networking by just pointing the nameserver configuration to it.

1. Create additional WSL distribution, this time with the Ubuntu 20.04 image.

```
New-Distro -Name Ubuntu -Destination C:\Dev\VirtualMachines\WSL\Distributions\Ubuntu -Release ubuntu2004 -UserName aon -SevenZip C:\Dev\Tools\7-Zip\7z.exe 
```

2. Alternative 1: Install minimal VPNKit configuration needed to be able to use the VPNKit utility running from the primary distribution
(skip if you don't need the optional VPNKit networking):
```
Install-VpnKit -Name Ubuntu -ProgramDirectory .\VPNKit -ConfigurationOnly
```


2. Alternative 2: You can easily do the same manually by simply configuring the distro to use the VPNKit nameserver address `192.168.67.1` (skip if you don't need the optional VPNKit networking):
   - Add the line `nameserver 192.168.67.1` at the top of file `/etc/resolv.conf` (you can normally just remove existing
     content as the default in WSL is to generates it automatically, see next step).
   - Add the line `generateResolvConf = false` below a line `[network]` in file `/etc/wsl.conf` (to prevent WSL from
     overwriting the `resolv.conf` changes in previous step).
   - Alternatively, if you ran the `New-VpnKit` command you will have ready to use `resolv.conf` and `wsl.conf` in the specified ProgramDirectory,
     which you can copy into `/etc/` of your distro instead (unless you have existing configuration in `wsl.conf` you want to keep).
   - Note that after doing these changes you must shutdown WSL immediately with command `wsl.exe --shutdown`
     to be sure that the changes are picked up, and your `resolv.conf` not overwritten.
   - Read more in the [VPNKit manual configuration](#vpnkit-manual-configuration) section below.

### Uninstalling

Use function `Unintall-VpnKit` to undo the VPNKit related configuration and remove the
program files installed into `/usr/local/bin` of a specified WSL distribution. If you
performed the manal nameserver-configuration for additional distributions as described
above, just change back `generateResolvConf = true` in file `/etc/wsl.conf`.

Use function `Remove-Distro` to unregister a distribution from WSL and delete
its disk image.

To uninstall the VPNKit program files installed on on host with `New-VpnKit`,
just delete the specified destination folder.

## Details

More details. In general, you must look into the different scripts to learn
everything about what they do. Reading the comment headers is a good start,
but you may have to dive into the source code as well.

### Wsl.ps1

The PowerShell script `Wsl.ps1` is a utility script intended to be dot sourced
into a PowerShell session, to expose its functionality for interactive use.

Parts of the functionality is based on GitHub API. It is open for anonymous access,
but will then impose heavy rate limiting. This can be avoided by authenticating
with a Personal Access Token. So if you have a GitHub account, then generate a
token at https://github.com/settings/tokens/new (no special permissions needed),
and supply you username and token (instead of password) when dot sourcing
the `Wsl.ps1` script:

```
. Wsl.ps1 -GitHubCredential (Get-Credential)
```

### Wsl.ps1 functions

- New-Distro
  - Downloads a specified distro image, specified with parameter `-Image` (see `Get-DistroImage`),
    extracts the file system archive from it and imports it into WSL by executing `wsl.exe --import`.
  - Optionally creates a user account within the distro to use as default instead
    of the built-in root account (parameter `-User`). Alternatively you can always
    choose to create a user manually later from within the distro, and
    use `Set-DistroDefaultUserId` to set it as default user for wsl to use.
- Start-Distro
  - Basically just executes `wsl.exe` to enter an interactive shell session,
    but with options such as distro name (with autocompletion),
    starting in new console window instead of current, etc.
  - Parameter `-WithVpnKit` also starts VPNKit service from the same distro in a separate window,
    avoid having to execute Start-VpnKit separately. You can do the same from a regular
    Windows shortcut without having to use the PowerShell script with a command such as this:
    ```
    C:\Windows\System32\cmd.exe /c "start ""VPNKit"" C:\Windows\System32\wsl.exe --user root /usr/local/bin/wsl-vpnkit && start """" C:\Windows\System32\wsl.exe ~"
    ```
- Stop-Distro
  - Basically just executes `wsl.exe --terminate`.
  - Parameter `-All` will call `Stop-Wsl`, which executes `wsl.exe --shutdown`.
- Rename-Distro
  - Renames the distro, by updating the DistributionName value in registry.
  - Checks that the distro is not UWP app installed first.
- Move-Distro
  - Moves the distro disk image, by looking up the current value of BasePath in registry,
    moving the directory pointed to, and then updating the registry entry accordingly.
  - Checks that the distro is not UWP app installed first.
- Remove-Distro
  - Basically just executes `wsl.exe --unregister`.
  - This will permanently delete the distro's disk image.
- New-VpnKit
  - Downloads necessary third party utilities for the VPNKit networking toolkit,
    and generates scripts and configuration files that can later be used with `Install-VpnKit`.
  - Result is a program directory on host.
  - You should keep this around for later use with `Install-VpnKit`, and also after
    that since the `wsl-vpnkit` script contains a reference back to this directory. If
    you want to move it, you should instead delete and recreate it in the new location,
    and then also execute `Install-VpnKit` again on any distros you did this on with
    the old location. You can avoid this by manually updating VPNKIT_PATH variable
    in the `wsl-vpnkit` script, or by overriding VPNKIT_PATH when executing `wsl-vpnkit`
    as described in [VPNKit manual install](#vpnkit-manual-install) section. This does
    not apply to `Install-VpnKit` with `-ConfigurationOnly`, then it will not have
    reference back to the VpnKit directory on host.
- Intall-VpnKit
  - Install VPNKit toolkit into a WSL distro, by using an existing program directory
    on host previously prepared with `New-VpnKit`.
  - Will download necessary packages (`socat`) and install them from host (assuming
    no internet connectivity from distro).
  - Will also modify the DNS configuration in the distro, to make it resolve names
    using host's DNS configuration via the VPNKit services.
  - Parameter `-ConfigurationOnly` will perform the minimal DNS configuration
    necessary for a distro to use a VPNKit service running from another (any) distro.
- Unintall-VpnKit:
  - Revert changes done in a WSL distro by `Install-VpnKit`.
- Start-VpnKit
  - Basically just executes `wsl.exe --user root /usr/local/bin/wsl-vpnkit`, but
    does so in a new console window (unless parameter `-NoNewWindow`).
- Get-Distro
  - Basically just executes `wsl.exe --list --quiet`, or `wsl.exe --list --running --quiet`
    if parameter `-Running`.
- Get-DistroImage
  - Returns the list of supported WSL distro images (Linux distributions), which
    can be used to create WSL distro instances with `New-Distro`, specified in
    its parameter `-Image`.
- Get-DefaultDistroVersion/Set-DefaultDistroVersion
  - Get/set the default WSL version that new WSL distros will be created with:
    Value `1` for WSL1, `2` for WSL2.
- Get-DefaultDistro/Set-DefaultDistro
  - Get/set the name of the installed distro that is currently defined as default in WSL.
- Get-DistroDistributionName/Set-DistroDistributionName
  - Get/set name of installed distro, accessing the registry (`Get-Distro` uses `wsl.exe`).
  - Note: The setter will just update the registry value without any security mechanisms,
    its generally safer to use `Rename-Distro`.
- Get-DistroPackageName
  - Get the name of the Universal Windows Platform (UWP) app, if the distro were installed
    through one (e.g. from Microsoft Store).
- Get-DistroPath/Set-DistroPath
  - Get/set the path to a distro's backing files (virtual disk image) on the host system.
  - Note: The setter will just update the registry value without moving the existing
    disk file, so its generally better to use `Move-Distro`.
- Get-DistroDefaultUserId/Set-DistroDefaultUserId
  - Get/set the user id of the default user for a distro.
  - If a user was specified with `New-Distro`, this will be set as the default.
  - You need to use the internal numeric user identifier from the Linux distro,
    e.g. with command `id -u`.
- Get-DistroFlags/Set-DistroFlags
  - Get/set the flags value of a distro, which is a combination of the options
    for Interop and AutoMount, also exposed as separate convenience functions.
- Get-DistroInterop/Set-DistroInterop
  - Get/set the value of the interop option flag.
  - The main option decides whether WSL will support launching Windows processes,
    with a suboption AppendWindowsPath, which (when main option is enabled) decides
    whether WSL will add Windows path elements to the $PATH environment variable.
  - The same can be done with Get-DistroFlags/Set-DistroFlags.
- Get-DistroAutoMount/Set-DistroAutoMount
  - Get/set the value of automount option flag.
  - This option decides whether WSL will automatically mount fixed drives (i.e C:/ or D:/)
    with DrvFs under /mnt. If not set the drives won't be mounted automatically, but can
    still be mounted manually or via fstab.
  - The same can be done with Get-DistroFlags/Set-DistroFlags.
- Get-DistroVersion
  - Get the WSL version of a distro: `1` for WSL1, `2` for WSL2.
- Get-DistroFileSystemVersion
  - Get the filsystem format version used for a distro.
  - The possible values are `1` for "LxFs" and `2` for "WslFs".
  - This is not the same as the WSL/distro version.
- Stop-Wsl
  - Executes `wsl.exe --shutdown`.
  - This will stop stop all running distributions, as well as the entire virtual
    machine which the distributions run in.

### Wsl.ps1 usage tips

The first created distribution in WSL will be treated as the default. When installing a distro with `New-Distro`
you can specify that it should be the new default distribution from now on by adding parameter `-SetDefault`.

Like with `wsl.exe` most of the PowerShell functions will run against the default distribution,
unless you specify the name of a specific distribution as argument.

To see the complete list of supported distributions use function `Get-DistroImage`.
You will get tab-completion on parameter `-Image` based on the result from this.

If you want to be extra cautious and wants to confirm steps performed by the various functions,
add parameter `-Confirm`, and if you want to see more detailed output about what is going on,
add parameter `-Verbose` to the function, like you normally do in PowerShell.

If you have 7-Zip already but not in your PATH, to avoid it being temporarily
downloaded in the background by the PowerShell script whenever it needs it,
specify its path with parameter `-SevenZip "path\to\your\7z.exe"`.

### VPNKit manual install

One of the main purposes of the PowerShell script [Wsl.ps1](Wsl.ps1) provided by
this project, is to automate the steps necessary to install and run VPNKit.
The required steps are described in the [wsl-vpnkit](wsl-vpnkit) documentation.
The example commands there are for execution from within WSL, which requires you to
already have internet access. Here are the same steps described for running them
on the host, and with some more detail:
- Install `socat` with the WSL distro's package manager. When you do not have internet
  access from the WSL distro yet, you will have to download the packages on host and
  install them from local path, as described below.
- Download the [wsl-vpnkit](https://raw.githubusercontent.com/albertony/wslkit/master/wsl-vpnkit/wsl-vpnkit)
  shell script, and copy it into the WSL file system (e.g. `/usr/local/bin`). From within WSL,
  you can copy it from a host location via the `/mnt/c/` automount, e.g. to copy from `C:\bin`
  on host to `/usr/local/bin` in distro filesystem:
  ```
  cp /mnt/c/bin/wsl-vpnkit /usr/local/bin
  ```
- Download [npiperelay](https://github.com/albertony/npiperelay), extract `npiperelay.exe`
  from the archive download, and copy it to a location reachable to the `wsl-vpnkit` script.
  - The script references it using variable `VPNKIT_NPIPERELAY_PATH`, with default
    value `/mnt/c/bin/npiperelay.exe`, so putting it in `C:\bin` on host will make the
    script work without changes.
  - You can put it in other locations as long as you set the variable before running the
    script, or modify the script source, e.g.
    `VPNKIT_NPIPERELAY_PATH=/mnt/c/VPNKit/npiperelay.exe wsl-vpnkit`.
  - You can choose to keep it within the WSL filesystem instead of the host, if you want
    a more "self-contained" distro installation, not tied to a fixed location on host.
    - The npiperelay readme warns that this is not possible, but that was most probably
      written before [interop](https://docs.microsoft.com/en-us/windows/wsl/filesystems#run-windows-tools-from-linux)
    functionality was added to WSL, because as long as the [interop setting](https://docs.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings)
    is not disabled it does really work!
  - If you put it in a location found from `$PATH` within WSL, e.g. `/usr/local/bin`,
    or create a symbolic link in such a location pointing to the real location, it being
    in WSL or even host's filesystem, you can run the script like this:
    `VPNKIT_NPIPERELAY_PATH=npiperelay.exe wsl-vpnkit`.
- Get the executables `com.docker.vpnkit.exe` (previously just `vpnkit.exe`) and `vpnkit-tap-vsockd` from
  [Docker Desktop](https://hub.docker.com/editions/community/docker-ce-desktop-windows/).
   - If you do not have Docker Desktop already installed, instead of installing it just
     to get a hold on these files, you can download the installer and extract it
     with [7-Zip](https://www.7-zip.org/) - first extract the installer exe, and
     then from the extracted folder extract once more the `resources\services.tar`
     (previously `resources/wsl/docker-for-wsl.iso`) file, and you should find the
     two executables for easy copy-install. For example,
     to install them into C:\bin execute something like this from a PowerShell prompt:
     ```powershell
     Start-BitsTransfer "https://desktop.docker.com/win/stable/Docker Desktop Installer.exe"
     7z e -y -oC:\bin "Docker Desktop Installer.exe" resources\com.docker.vpnkit.exe resources\services.tar
     7z e -y -oC:\bin C:\bin\services.tar containers\services\vpnkit-tap-vsockd\lower\sbin\vpnkit-tap-vsockd
     ```
   - Rename the executable `com.docker.vpnkit.exe` to `wsl-vpnkit.exe`.
     ```powershell
     Rename-Item C:\bin\com.docker.vpnkit.exe wsl-vpnkit.exze
     ```
     The reason for this is that if you are using Docker Desktop on the host computer,
     it will be executing its own `com.docker.vpnkit.exe`, and upon start/stop it will
     terminate any running processes with that name. This means it would also terminate
     such a process started by `wsl-vpnkit`, and it would have to be restarted to get
     it to work again. The workaround for this is to rename the copy of executable
     used for WSL into somethine else. The `wsl-vpnkit` script assumes `wsl-vpnkit.exe`,
     but you can also use a different name if you configure it with `VPNKIT_PATH` (see below).
- Copy the `vpnkit-tap-vsockd` executable into into the WSL filesystem. Note that
  it must be put into `/sbin` and owned by root. For example, from within WSL prompt:
  ```
  sudo cp /mnt/c/bin/vpnkit-tap-vsockd /sbin/vpnkit-tap-vsockd
  chown root:root /sbin/vpnkit-tap-vsockd
  ```
- Make the `wsl-vpnkit.exe` executable accessible from the `wsl-vpnkit` script, just as
  with `npiperelay.exe` described above, but now with script variable `VPNKIT_PATH`.
  If the executable was renamed to something other than `wsl-vpnkit.exe`, then this
  must also be considered.
- Configure DNS as described in the [VPNKit manual configuration](#vpnkit-manual-configuration)
  section, below.
- Finally, run the `wsl-vpnkit` script from the WSL distro to start the network services,
  and you should have connectivity from WSL through the host's network connection as long
  as this script is running!

If you have no internet connectivity in your WSL distro using the default networking,
the remaining challenge from the above steps is: How do you install the `socat` package?
What you can do is download the package archive files on your host computer, and
install them from file in the WSL distribution using its package tool in
"offline-mode", referencing the downloaded package archive files on host through
the automatically `/mnt/c` mount. The package required is called "socat" in
most distributions. In addition you may need some dependent packages that are
also missing.

Debian:
- The official image being on "buster", you need the following package downloads:
    - [packages.debian.org/buster/amd64/libwrap0/download](https://packages.debian.org/buster/amd64/libwrap0/download)
    - [packages.debian.org/buster/amd64/libssl1.1/download](https://packages.debian.org/buster/amd64/libssl1.1/download)
    - [packages.debian.org/buster/amd64/socat/download](https://packages.debian.org/buster/amd64/socat/download)
- Just download the files and then from wsl refer to the files by path.
Example (not the actual file names, don't know if order is important, but I did dependencies first and `socat` last):
`apt-get install libwrap0.deb libssl1.1.deb socat.deb`

Ubuntu 20.04:
- Only missing `socat` package. Download url can be retrieved by the folowing command
  in wsl: `apt-get install socat --print-uris -qq`. Then download this link on host etc,
  and install it just like with Debian.

Alpine:
- Tested the official "minimal root filesystem" distribution from alpinelinux.org, so not
  actually a WSL distribution at all, but works like a charm (except, older versions of
  the wsl-vpnkit script required bash and it is not included by default, but could easily
  be downloaded and installed same way as socat).
- Package downloads from [dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/](https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/)
- Packages needed: `ncurses-terminfo-base`, `ncurses-libs`, `readline`, `socat` (previuosly also bash).
- Install with `apk add --quiet --repositories-file /dev/null <packagefiles>...`.

Arch:
- Tested the official "bootstrap" distribution from archlinux.org, so - same as with
  Alpine: This is a standard image and not a WSL image.
- Package downloads from [archive.archlinux.org/packages](https://archive.archlinux.org/packages)
- Packages needed: `socat`, `iproute2` (optionally also `grep` and `sed`).
    - In contrast to most other distros, the basic utilities `ip` (from `iproute2`), `grep` and `sed`
      are not included by default in Arch. The main run script wsl-vpnkit requires the `ip` and `grep`
      commands, so these are required. The supplementary install/configure scripts used by
      the `Install-VpnKit` and `Uninstall-VpnKit` functions in `Wsl.ps1` also requires `sed`,
      but if just performing a minimal manual install it can be skipped.
    - Install with command `pacman --upgrade --needed <packagefiles>...`

Void:
- Tested the official "rootfs tarball" distribution from voidlinux.org, so
  (similar to Arch) not actually a WSL distribution.
- Package downloads from [repo-default.voidlinux.org/current](https://repo-default.voidlinux.org/current)
- Packages needed: `socat`.
- Install with two commands:
    - First the package must be registered in a local repository: `xbps-rindex --add <full_path_to_package_file>`
    - Next, the package can be installed from the local repository: `xbps-install --repository <full_path_to_package_directory> <package_name>`

### VPNKit manual configuration

To use the VPNKit networking you need to install the complete VPNKit package (`Install-VpnKit`
without parameter `-ConfigurationOnly`) on (at least) one distribution, and run it from there.
Then you can use it from any number of distributions, by simply changing their DNS configuring
to go through the same `vpnkit` service.

In WSL2 all distros run in a single shared virtual machine. This means they all share the same
virtual network adapters. When the `wsl-vpnkit` script is started it will change the ip route
of the `eth1` network adapter to connect through the `vpnkit` gateway. If you check in another
distro you will see that the same ip route is configured for "its" `eth1`.

When the `wsl-vpnkit` script is started from one distro, it sets up the ip route and the
process pipe relay from the shared virtual machine to the host machine. The only thing missing
for a distribution to work through this connection is the DNS configuration, which is a
distribution-specific configuration. By default the VPNKit gateway is bound to IP address
`192.168.67.1`, so to configure the distro to use this as the nameserver you must
add `nameserver 192.168.67.1` into file `/etc/resolv.conf`, and also `generateResolvConf = false`
in section `[network]` of file `/etc/wsl.conf`.

The VPNKit program directory created by `New-VpnKit` contains predefined `resolv.conf` and `wsl.conf`
that you can copy into you distro. Running the `Install-VpnKit` with parameter `-ConfigurationOnly`
will basically do the same, just that it tries to avoid overwriting any existing configuration
you might have in `wsl.conf`, and also it installs a script into `/usr/local/bin` that can be used
to revert the changes. You can choose to install the full VPNKit on more than one distribution, but
only one can be run (`Start-VpnKit`) at the same time.

See also [sample steps](#creating-additional-distribution) described above for creating additional distributions.
