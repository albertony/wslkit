# WSLKit

This repository contains a toolkit for Windows Subsystem for Linux (WSL).

TLDR: Go straight to [step by step guide](#usage-examples).

The main main part of the kit is the PowerShell script [Wsl.ps1](Wsl.ps1), which
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
and redirect it through a dedicated process pipe connection between the host and the
virtual machine. More details [below](#vpnkit).

In addition to the main features mentioned above, this repository also contains some
convenience shell scripts that can be executed from within a newly created WSL distributions
for quick initial configuration, installation of different predefined sets of software
packages etc.

### Windows version

Currently this project has been created to work with Windows 10 version 1909 (build 18363),
but I am also using the PowerShell script, without the vpnkit feature,
on a Windows 10 version 20H2 (build 19042).

If you have a different version of Windows you may want to check 
the [release notes for Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/release-notes)
to see if there are new features that affects this solution.
E.g. in build 20190 the built-in `wsl.exe` command gets the ability
to install WSL distros with `wsl --install` command, and in build 20211
it can also list available images with `wsl --install --list-distributions`.
To some degree this will overlap with the `New-Distro` and `Get-DistroImage` functions
in my PowerShell script, although my variants will still be relevant as they 
only imports the disk images without fully installing distros as Windows "apps",
and also have additional support for installation of raw disk images,
such as official linux releases, i.e. unofficial WSL distributions,
such as the Arch Linux bootstrap distribution and the Alpine minimal
root filesystem.

### Disclaimers

This project exists primarily to support my own use of WSL.

The source code has not been written with public scrutiny in mind, but has grown
out of the previous rationale.

I take no responsibility if anything bad happens if you decide to try it out.

...however, I don't expect any problems, and I assume it could be usefull
also for others, so please, just try it out, and also just report any issues you
find so that I can make improvements.

## Main features

Before showing [example usage](#usage-examples), the main features of this project
will be described. At the end you will find more [details](#details).

### WSL Administration

The main PowerShell script provides general WSL administrative functions. Some of
them are just convenience functions around standard `wsl.exe` functionality, but
with more PowerShell-like syntax, including tab completion of parameters such as
name of installed distribution. Others are accessing registry settings used by the
WSL services. Example of such functions are changing which WSL distribution is default,
changing the default user account, renaming or moving the disk image location
of a [sideloaded](#sideloading) WSL distribution (see next section).
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
used to include support for some additional images. The official Alpine
"minimal root filesystem" archives are published on
[alpinelinux.org](https://alpinelinux.org/downloads/), and Arch Linux
"bootstrap" distributions on [archlinux.org](https://archive.archlinux.org/iso/).
Both of these are supported by the PowerShell script; it will download the
latest version, import it into WSL, and do the basic configuration like
creation of user etc. like with the officially WSL adapted images.
See complete list of supported Linux distributions [below](#linux-distributions).

Edit: Since this was written, Microsoft has written a short how-to guide covering
this same approach: [Import any Linux distribution to use with WSL](https://docs.microsoft.com/en-us/windows/wsl/use-custom-distro).
It mentions importing Alpine "minimal root filesystem", but main example it uses
is CentOS by extracting the disk image from a docker container. So this is now
an "officially approved" method for installing WSL distros!

### VPNKit

The second main functionality of this project and the main PowerShell script
is the support for [VPNKit](https://github.com/moby/vpnkit). This is a set of
tools providing customized, VPN/antivirus/firewall-friendly, network connectivity
from a network device in the VM used to host WSL2 distros, via a unix socket and
Windows named pipe, to a gateway process running on the host, routing traffic to
the host network device. Docker Desktop with WSL2 backend is using much of the same
system, the core parts used here are actually taken from the Docker Desktop toolset.

The problem with the Hyper-V based networking that is default in WSL, is that
it can easily be problematic with VPN, and will be entirely blocked by some
antivirus/firewall software etc. See also [this](https://github.com/moby/vpnkit#why-is-this-needed).

The main part of this functionality is a shell script `wsl-vpnkit` from repository
[github.com/sakai135/wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit), which was
also the main inspiration for all the VPNKit related functionality in the current repository.
It was initially created with the assumption that you have network connectivity using
the default WSL networking, but needed the customized networking to be able to use
a VPN connection from the host. The shell script assumes you have installed
the `socat` utility in the distribution, but if your case is that you have no network
connectivity at all from within your WSL distributions, then how do you do that? What
you can do is to download the package archive files on your host computer, and install
them from file in the WSL distribution using its package tool in "offline-mode".
The `Install-VpnKit` function of my `Wsl.ps1` does this for you. See the
[VPNKit manual install](#vpnkit-manual-install) section below for details.

If you want to know more, read the vpnkit documentation for background information
about the pipe based networking used by Docker with VPNKit:
[Plumbing inside Docker for Windows](https://github.com/moby/vpnkit/blob/master/docs/ethernet.md#plumbing-inside-docker-for-windows).
The method used by wsl-vpnkit is very similar, although instead of using Hyper-V sockets
between the host and VM, it uses regular Windows named pipes, with help of the
[socat](https://linux.die.net/man/1/socat) utility in the WSL VM and the [npiperelay](https://github.com/jstarks/npiperelay)
utility on the Windows host.

### Linux distributions

Currently supported linux distributions (and tested versions):
- Ubuntu (tested version 20.04 LTS "Focal Fossa")
- Debian (tested version 9 "Stretch", upgraded to versjon 10 "Buster" and version 11 "Bullseye")
- Kali (untested)
- OpenSUSE (untested)
- Alpine (tested version 3.13.1)
- Arch (tested version 2021.02.01)

Note that the Alpine and Arch distributions listed above are not regular WSL images,
but are the official "minimal root filesystem" distribution from alpinelinux.org
and "bootstrap" distribution from archlinux.org.

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

The Debian Linux image currently published on Microsoft is quite old, currently
still on Debian 9 (stretch), so you will probably want to upgrade it to at least
Debian 10 (buster), which is the currently "stable" version of Debian. You can use
the included shell script `debian-upgrade` to do this. This script can be used for
regular package updates as well as major release upgrades. Read the comments in the
script header for more details. To upgrade to latest stable version of Debian, just
run the script without arguments: `/mnt/c/Wsl/debian-upgrade`. See also example
[below](#debian).

The Alpine and Arch images are not WSL images, but official plain root filsystem
image distributions. These will always be installed from the latest released
version, but will generally have less initial configuration than the WSL images. If
using the Arch Linux image there are a few steps that needs to be performed before
being able to start using `pacman` to install additional software. The supplied
script `arch-init` will perform the required steps for you (read the comments for
description of what it does), just run the script without arguments:
`/mnt/c/Wsl/arch-init`.  See also example [below](#arch).

The script `arch-install-dev-cpp-python-qt` can be executed after `arch-init` to install
a set of packages relevant for a specific C++, Python and Qt development environment,
including: Git (with LFS), SSL, SSH, GCC, CMake, Ninja, Qt5, Python (with numpy, pylint,
pytest, pyside2 and ipython).

Alternatively, the script `arch-install-dev-go` can be to install a set of packages
relevant for a different development environment, namely Go (golang), including gcc
to be able to compile cgo-based packages. It does not install additional Go related
support tools (such as delve, guru, goimports), since not all are available as
pacman packages, and also they can easily be installed from VSCode when using WSL remoting,
or with "go get" command.

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

Upgrade from Debian 9 (stretch) to Debian 10 (buster), which is the latest
stable version. Note that the script (without arguments) will upgrade to latest stable,
but if this is more than one major version step up then you should upgrade one version
at a time. See script comments for details.

```
/mnt/c/Wsl/debian-upgrade
```

#### Arch

Configure locale, sudo and pacman, perform full upgrade of all installed packages,
and install some very basic tools (such as sudo, sed, tar, nano, some of which required
by the script itself).

```
/mnt/c/Wsl/arch-init
```


### Creating additional distribution

You can install as many WSL distributions as you want, just make sure to give them a unique name and a separate
directory for the disk image file.

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

### Wsl.ps1 functions

- New-Distro
  - Downloads a specified distro image, specified with parameter `-Image` (see `Get-DistroImage`),
    extracts the file system archive from it and imports it into WSL by executing `wsl.exe --import`.
  - Optionally creates a user account within the distro to use as default instead
    of the built-in root account (parameter `-UserName`).
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
The required steps, as described in the [wsl-vpnkit](https://github.com/sakai135/wsl-vpnkit)
documentation, are:
- Copy the `wsl-vpnkit` shell script into the WSL file system (e.g. `/usr/local/bin`).
- Intall `socat` with the WSL distro's package manager (see below if you do not have
  internet access from within the WSL distro yet).
- Download [npiperelay](https://github.com/jstarks/npiperelay), extract `npiperelay.exe`
  from the archive download and copy it into the WSL file system (e.g. `/usr/local/bin`),
  or create a symlink to the location on host using the `/mnt/c` path.
- Get the executables `vpnkit.exe` and `vpnkit-tap-vsockd` from [Docker Desktop](https://hub.docker.com/editions/community/docker-ce-desktop-windows/).
   - If you do not have Docker Desktop already installed, instead of installing it just
     to get a hold on these files, you can download the installer and extract it
     with [7-Zip](https://www.7-zip.org/) - first extract the installer exe, and
     then from the extracted folder extract once more the `resources/wsl/docker-for-wsl.iso`
     file, and you should find the two executables for easy copy-install.
  - Copy the `vpnkit-tap-vsockd` executable into into the WSL filesystem. Note that
    it must be put into `/sbin` and owned by root (`chown root:root /sbin/vpnkit-tap-vsockd`).
  - Leave the `vpnkit.exe` executable in a "permanent" location on host, and update
    the `wsl-vpnkit` script with the path to it in variable `VPNKIT_PATH` - or you
    can set the variable each time you run the script,
    e.g. `VPNKIT_PATH=C:/VPNKit/vpnkit.exe wsl-vpnkit`.
- Configure DNS as described [below](#vpnkit-manual-configuration).
- Finally, run the `wsl-vpnkit` script from the WSL distro to start the network services,
  and you should have connectivity from WSL through the host's network connection as long
  as this script is running!

If you have no internet connectivity in your WSL distro using the default networking,
the problem with the above steps is: How do you install the `socat` package? What
you can do is download the package archive files on your host computer, and
install them from file in the WSL distribution using its package tool in
"offline-mode", referencing the downloaded package archive files on host through
the automatically `/mnt/c` mount. The package required is called "socat" in
most distributions. In addition you may need some dependent packages that are
also missing.

Debian:
- The official image being on "stretch" still, you needed the following:
    - [packages.debian.org/stretch/amd64/libwrap0/download](https://packages.debian.org/stretch/amd64/libwrap0/download)
    - [packages.debian.org/stretch/amd64/libssl1.1/download](https://packages.debian.org/stretch/amd64/libssl1.1/download)
    - [packages.debian.org/stretch/amd64/socat/download](https://packages.debian.org/stretch/amd64/socat/download)
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
- Downloads from [dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/](https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/)
- Packages needed: `ncurses-terminfo-base`, `ncurses-libs`, `readline`, `socat` (previuosly also bash).
- Install with `apk add --quiet --repositories-file /dev/null <packagefiles>...`.

Arch:
- Tested the official "bootstrap" distribution from archlinux.org, so - same as with
  Alpine: This is a standard image and not a WSL image.
- Downloads from [archive.archlinux.org/packages](https://archive.archlinux.org/packages)
- Packages needed: `socat`, `iproute2` (optionally also `grep` and `sed`).
    - In contrast to most other distros, the basic utilities `ip` (from `iproute2`), `grep` and `sed`
      are not included by default in Arch. The main run script wsl-vpnkit requires the `ip` and `grep`
      commands, so these are required. The supplementary install/configure scripts used by
      the `Install-VpnKit` and `Uninstall-VpnKit` functions in `Wsl.ps1` also requires `sed`,
      but if just performing a minimal manual install it can be skipped.

### VPNKit manual configuration

To use the VPNKit networking you need to install the complete VPNKit package (`Install-VpnKit`
without parameter `-ConfigurationOnly`) on at least one distribution, and run it from there.
You can only run a single instance of it at a time.
Any number of distributions can use the same networking services, simply by configuring them
to use its address `192.168.67.1` as nameserver. To do this you must add `nameserver 192.168.67.1` into
file `/etc/resolv.conf`, and also `generateResolvConf = false` in section `[network]` of file `/etc/wsl.conf`.
The VPNKit program directory created by `New-VpnKit` contains predefined `resolv.conf` and `wsl.conf`
that you can copy into you distro. Running the `Install-VpnKit` with parameter `-ConfigurationOnly`
will basically do the same, just that it tries to avoid overwriting any existing configuration
you might have in `wsl.conf`, and also it installs a script into `/usr/local/bin` that can be used
to revert the changes. You can choose to install the full VPNKit on more than one distribution, but
only one can be run (`Start-VpnKit`) at the same time.

See also [sample steps](#creating-additional-distribution) described above for creating additional distributions.
