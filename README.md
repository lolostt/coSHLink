# coSHLink

A live map of the network path from this computer to the internet, drawn in
an 80x24 terminal.

![coSHLink running with sample data](docs/coSHLink.png)

*The animation shows sample data: a weak Wi-Fi, a slow internet link and a
cut one, and the recovery.*

coSHLink draws this computer, the gateway and the internet as a diagram. Each
link pulses in green, amber or red while it is up, degraded or down, and the
link to the gateway is dashed over Wi-Fi and solid over a cable. A panel lists
the traffic, latency, jitter and loss of each link. Around the map you see the
Wi-Fi network, the local and gateway addresses, the state of the DNS, the
public IP address with its location and operator, a possible carrier-grade
NAT and the download speed.

It is a single bash script. It installs nothing and needs no administrator
rights.

## Run it

Download `coSHLink.sh` (or clone the repository). The script needs execute
permission; a clone keeps it, but a downloaded file usually loses it. Give it
in a terminal, in the folder that holds the script:

```sh
chmod +x coSHLink.sh
```

On macOS, to double-click the launcher, give it permission too:

```sh
chmod +x coSHLink.sh coSHLink.command
```

Then run it:

```sh
./coSHLink.sh -l
```

Without that permission it also runs as `bash coSHLink.sh -l`.

Press `q` or `Ctrl+C` to quit. Without `-l` it stops after 60 seconds.

You can also double-click a launcher, kept next to `coSHLink.sh`:

| System  | Launcher           |
|---------|--------------------|
| macOS   | `coSHLink.command` |
| Windows | `coSHLink.bat`     |
| Linux   | `coSHLink.desktop` |

### Options

| Short | Long          | What it does                                                    |
|-------|---------------|-----------------------------------------------------------------|
| `-l`  | `--loop`      | Run until `q` or `Ctrl+C`.                                      |
| `-n`  | `--no-speed`  | Do not measure the download speed (see below).                  |
| `-c`  | `--check`     | Read every source once, print the results and exit.             |
| `-L`  | `--log FILE`  | Append the errors of the background measurements to `FILE`.     |
| `-8`  | `--256`       | Use 256 colours.                                                |
| `-t`  | `--truecolor` | Use 24-bit colour.                                              |
| `-i`  | `--install`   | Install it as the command `coshlink`.                           |
| `-u`  | `--update`    | Download the latest version from GitHub and install it.         |
| `-r`  | `--uninstall` | Remove what `--install` added.                                  |
| `-v`  | `--version`   | Print the version.                                              |
| `-h`  | `--help`      | Print the help.                                                 |

Short options can be combined: `-ln` is `-l -n`. The thresholds, ping targets
and intervals are in the *User configuration* section at the top of the
script.

By default the download speed is measured every 10 minutes, and each test
downloads 25 MB: about 150 MB an hour while it runs. On a metered connection,
use `-n`. Without internet the test fails at once, says so, and is tried again
a minute later.

## Install

```sh
./coSHLink.sh -i
```

This copies the script to `~/.local/bin/coshlink` and, if that folder is not
in your `PATH`, adds one marked line to `~/.zshrc`, `~/.bash_profile` or
`~/.bashrc`, depending on your shell. Open a new terminal and run it from any
folder:

```sh
coshlink -l
```

On Windows, run the same command in Git Bash. It also writes `coshlink.cmd` to
`%LOCALAPPDATA%\Microsoft\WindowsApps`, so `coshlink -l` works in PowerShell
and cmd too.

On macOS 15 and later, the installer offers to run `sudo ipconfig setverbose 1`
so that the Wi-Fi name is shown (see [Wi-Fi name on macOS](#wi-fi-name-on-macos)).

Running `-i` again changes nothing unless the script has changed.

## Update

```sh
coshlink -u
```

This downloads the latest `coSHLink.sh` from the `main` branch on GitHub,
checks that it is a complete coSHLink script, and installs it in place of the
current one. While the repository is private, set a GitHub token with read
access first: `GITHUB_TOKEN=... coshlink -u`. The token is passed to curl
through its standard input and is not saved anywhere.

## Uninstall

```sh
coshlink -r
```

This removes `~/.local/bin/coshlink`, the `PATH` line and, on Windows,
`coshlink.cmd`. It only removes what `--install` wrote.

## Wi-Fi name on macOS

macOS 15 and later hide the Wi-Fi name from scripts, and coSHLink then shows
it as "(name hidden)". To show it to every program, across reboots:

```sh
sudo ipconfig setverbose 1
```

To hide it again:

```sh
sudo ipconfig setverbose 0
```

## Requirements

| System  | Minimum                           | Needs                                                    |
|---------|-----------------------------------|----------------------------------------------------------|
| macOS   | macOS 12 Monterey                 | Nothing: everything it uses ships with macOS.            |
| Linux   | bash 5 (Ubuntu 20.04, Debian 10, Fedora 30, RHEL 9) | `iproute2`, `ping`, `curl`, `nslookup`, `iconv`, `traceroute` |
| Windows | Windows 10 with Git for Windows   | Git Bash. Windows Terminal is used when it is installed. |

Notes on these versions:

- **macOS.** The script runs on the bash 3.2 that macOS ships, and then uses
  `perl` (also built in) to pace the frames. Every tool it calls (`curl`,
  `ping`, `nslookup`, `traceroute`, `netstat`, `ipconfig`, `networksetup`,
  `system_profiler`) has been part of macOS for many years. The Wi-Fi details
  come from `system_profiler` and `ipconfig getsummary`, whose output Apple
  changes from time to time. macOS 12 is the oldest version whose output
  format the script expects. Older versions may still run, but with an empty
  Wi-Fi box. Terminal shows 24-bit colour from macOS 26; before that it uses
  256 colours.
- **Linux.** Before it starts, the script checks that every tool is there.
  If one is missing, it names the packages to install (for `apt-get`, `dnf`,
  `yum`, `zypper`, `pacman` or `apk`) and exits.
  With bash 5.0 or later, the frames are paced and timed with
  bash alone. With bash 3.2 or 4, `perl` is needed for smooth animation
  (without it the animation still runs, but less evenly). On minimal
  installations, `nslookup` comes in `dnsutils` (Debian, Ubuntu) or
  `bind-utils` (Fedora, RHEL), and `traceroute` in its own package. Without
  `traceroute` there is no CG-NAT warning. The Wi-Fi box shows "no details on
  Linux".
- **Windows.** Git for Windows ships bash 5. Windows Terminal needs Windows 10
  version 2004 or later; without it the launcher uses mintty, which comes
  with Git.

Run `coshlink -c` to see which tools are missing on your computer.

## Privacy

To show the public IP with its place and operator, coSHLink asks
[ipinfo.io](https://ipinfo.io) every 5 minutes and whenever the network
changes, so that service learns roughly where the computer is.
[api.ipify.org](https://www.ipify.org) is asked only if ipinfo.io fails.
Each speed test downloads from `speed.cloudflare.com`, unless you use `-n`.
Nothing else leaves the computer.

The measurements are written to a private temporary directory that only your
user can open, and that is removed on exit. On Linux it is in `/dev/shm`, in
memory, unless `TMPDIR` is set.

## License

MIT. See [LICENSE](LICENSE).

---

[www.sleepingcoconut.com](https://sleepingcoconut.com) · 2026
