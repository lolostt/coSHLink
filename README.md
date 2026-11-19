# coSHLink

A live map of the network path from your computer to the internet, drawn in an 80×24 terminal.

<p align="center">
  <img src="https://github.com/user-attachments/assets/ceb8d2d5-6fa1-4b0f-95f9-9e23c96d77de" alt="coSHLink running with sample data" width="800">
</p>

Monitor network links, latency, jitter, packet loss, DNS, Wi-Fi, public IP
and more — all in a single Bash script.

## Contents

- [Three ways to run it](#three-ways-to-run-it)
  - [Method 1: Run the script](#method-1-run-the-script)
  - [Method 2: Double-click a launcher](#method-2-double-click-a-launcher)
  - [Method 3: Install it as a command](#method-3-install-it-as-a-command)
- [What it shows](#what-it-shows)
- [Options](#options)
- [Requirements](#requirements)
- [Wi-Fi details](#wi-fi-details)
- [Update](#update)
- [Uninstall](#uninstall)
- [Privacy](#privacy)
- [License](#license)

## Three ways to run it

- 🍎 **macOS** and 🐧 **Linux**: use any terminal.
- 🪟 **Windows**: use Git Bash (see [Requirements](#requirements)).

### Method 1: Run the script

Download it and start it from the same folder:

```sh
curl -fsSL https://raw.githubusercontent.com/lolostt/coSHLink/main/coSHLink.sh -o coSHLink.sh && chmod +x coSHLink.sh
./coSHLink.sh -l
```

Press `q` or `Ctrl+C` to quit. Without `-l` it stops after 60 seconds.

### Method 2: Double-click a launcher

Download the script and the launcher for your system into the same folder,
and double-click the launcher. It opens an 80x24 window running
`coSHLink.sh -l`. If `coSHLink.sh` is already there, the command replaces it
with the latest version.

- 🍎 **macOS**:

  ```sh
  for f in coSHLink.sh coSHLink.command; do curl -fsSL "https://raw.githubusercontent.com/lolostt/coSHLink/main/$f" -o "$f" && chmod +x "$f"; done
  ```

- 🪟 **Windows** (in Git Bash):

  ```sh
  for f in coSHLink.sh coSHLink.bat; do curl -fsSL "https://raw.githubusercontent.com/lolostt/coSHLink/main/$f" -o "$f"; done; chmod +x coSHLink.sh
  ```

- 🐧 **Linux**:

  ```sh
  for f in coSHLink.sh coSHLink.desktop; do curl -fsSL "https://raw.githubusercontent.com/lolostt/coSHLink/main/$f" -o "$f" && chmod +x "$f"; done
  ```

### Method 3: Install it as a command

Download the script and install it:

```sh
curl -fsSL https://raw.githubusercontent.com/lolostt/coSHLink/main/coSHLink.sh -o coSHLink.sh && chmod +x coSHLink.sh && ./coSHLink.sh -i
```

Open a new terminal and run it from any folder:

```sh
coshlink -l
```

The installer copies the script to `~/.local/bin/coshlink`. If this folder is
missing from your `PATH`, it adds one marked line to `~/.zshrc`,
`~/.bash_profile` or `~/.bashrc`, depending on your shell.

> [!NOTE]
> 🪟 On Windows the installer also writes `coshlink.cmd` to
> `%LOCALAPPDATA%\Microsoft\WindowsApps`, so `coshlink -l` works in
> PowerShell and cmd as well as in Git Bash.

## What it shows

| What | Where | Details |
|------|-------|---------|
| Links | Map | This computer, the gateway and the internet. Each link pulses green, amber or red as it goes up, degraded or down |
| Connection type | Map | The link to the gateway is dashed over Wi-Fi and solid over a cable |
| Local IP | Under the computer | The address of this computer |
| Gateway IP | Under the gateway | The address of the router |
| DNS | Right of the globe | ok, partial or fail, after resolving two names every 5 seconds, and the server in use: the gateway, Cloudflare, Google, Quad9, OpenDNS or its address |
| Public IP | Right of the globe | The address, with its country, city and operator |
| Carrier-grade NAT | Right of the globe | "Possible CG-NAT" when a hop after the router is in 100.64.0.0/10 |
| Download speed | Right of the globe | With `-s`, in Mb/s, measured every 30 seconds |
| Wi-Fi network | Wi-Fi box, right | The name, or "(name hidden)" (see [Wi-Fi details](#wi-fi-details)). Hidden over a cable |
| Wi-Fi signal | Wi-Fi box | 4 bars, the signal in dBm and the signal to noise ratio |
| Wi-Fi rate and mode | Wi-Fi box | The transmit rate in Mb/s and the mode, such as 802.11ax |
| Wi-Fi security and band | Wi-Fi box | WPA2, WPA3 or OWE; amber if weak (WPA, WEP), blinking red if open. Then the band in GHz and the channel |
| Traffic | TRAFFIC box, bottom left | A meter and the speed of the network interface, in or out, whichever is higher |
| Link state | Panel, one row per link | UP, DEGRADED, DOWN, or NO PING for a gateway that ignores pings while the internet answers |
| Ping history | Panel | A sparkline of the latest latencies, newest on the right |
| Latency, jitter and loss | Panel | In ms, ms and %, for the gateway and for the internet (1.1.1.1 or 8.8.8.8, whichever answers better) |
| Updates | Footer, left | **ⓘ Update available** when GitHub has a newer build (see [Update](#update)) |

## Options

| Short | Long          | What it does                                                    |
|-------|---------------|-----------------------------------------------------------------|
| `-l`  | `--loop`      | Run until `q` or `Ctrl+C`.                                      |
| `-s`  | `--speed`     | Measure the download speed (see below).                         |
| `-c`  | `--check`     | Read every source once, print the results and exit.             |
| `-L`  | `--log FILE`  | Append the errors of the background measurements to `FILE`.     |
| `-8`  | `--256`       | Use 256 colours.                                                |
| `-t`  | `--truecolor` | Use 24-bit colour.                                              |
| `-i`  | `--install`   | Install it as the command `coshlink`.                           |
| `-u`  | `--update`    | Download the latest version from GitHub and install it.         |
| `-r`  | `--uninstall` | Remove what `--install` added.                                  |
| `-v`  | `--version`   | Print the version and its date.                                 |
| `-h`  | `--help`      | Print the help.                                                 |

Short options can be combined: `-ls` is `-l -s`. Thresholds, ping targets,
intervals and the drawing of your computer (`COMPUTER`: a laptop or a tower)
live in the *User configuration* section at the top of the script.

With `-s`, a speed test runs every 30 seconds and downloads up to 20 MB each
time. Avoid it on a metered connection.

## Requirements

| System        | Minimum                                             | Needs                                                         |
|---------------|-----------------------------------------------------|---------------------------------------------------------------|
| 🍎 macOS      | macOS 12 Monterey                                   | Nothing: every tool it uses ships with macOS.                 |
| 🐧 Linux      | bash 3.2                                            | `iproute2`, `ping`, `curl`, `nslookup`, `iconv`, `traceroute`, and `perl` before bash 5 |
| 🪟 Windows    | Windows 10                                          | [Git for Windows](https://gitforwindows.org/), which brings Git Bash. [Windows Terminal](https://learn.microsoft.com/windows/terminal/) is used if installed. |

- 🍎 **macOS.** The script runs on the bash 3.2 shipped with macOS and uses
  the built-in `perl` to pace the frames. Every tool it calls (`curl`,
  `ping`, `nslookup`, `traceroute`, `netstat`, `ipconfig`, `networksetup`,
  `system_profiler`) has been part of macOS for years. The Wi-Fi details come
  from `system_profiler` and `ipconfig getsummary`, whose output Apple changes
  from time to time; macOS 12 is the oldest version with the format the
  script expects. Older versions may still run, with an empty Wi-Fi box.
  Terminal shows 24-bit colour from macOS 26 and 256 colours before it.
- 🐧 **Linux.** Before starting, the script checks for every tool. If one is
  missing, it names the packages to install (for `apt-get`, `dnf`, `yum`,
  `zypper`, `pacman` or `apk`) and exits. Bash 5.0 or later paces the frames
  on its own; with bash 3.2 or 4, `perl` keeps the animation smooth. On
  minimal installs, `nslookup` comes in `dnsutils` (Debian, Ubuntu) or
  `bind-utils` (Fedora, RHEL), and `traceroute` in its own package. The Wi-Fi
  box shows no details (see [Wi-Fi details](#wi-fi-details)).
- 🪟 **Windows.** Git for Windows ships bash 5. Windows Terminal needs
  Windows 10 version 2004 or later; without it, the launcher uses mintty,
  included with Git.

Run `./coSHLink.sh -c` to list the tools missing on your computer and, on
Linux, the packages that provide them.

## Wi-Fi details

🍎 **macOS.** macOS 15 and later hide the Wi-Fi name from scripts, so
coSHLink shows "(name hidden)". To reveal it to every program, across
reboots:

```sh
sudo ipconfig setverbose 1
```

To hide it again:

```sh
sudo ipconfig setverbose 0
```

🐧 **Linux.** The Wi-Fi box shows "no details on Linux". coSHLink only uses
tools that every distribution ships, and none of those reports the Wi-Fi
network. That information comes from `iw`, `nmcli` (NetworkManager) or
`iwctl` (iwd), and which one is present depends on the distribution and the
desktop. Rather than require one of them, coSHLink leaves the box empty. The
rest of the map works the same: the gateway, the addresses and the traffic
come from `ip route` and `/sys`, and the link to the gateway is still drawn
dashed over Wi-Fi.

## Update

If you run the script or a launcher from a folder, download it again with
the same command you used the first time.

If you installed it as a command, download the latest version from GitHub
and install it over the old one:

```sh
coshlink -u
```

## Uninstall

If you run the script or a launcher from a folder, you can safely delete the
files.

If you installed it as a command:

```sh
coshlink -r
```

This removes `~/.local/bin/coshlink`, the `PATH` line added to your shell
startup file and, on Windows, `coshlink.cmd`. It removes only what `-i`
added, and leaves anything else in those files as it was.

🍎 If you ran `sudo ipconfig setverbose 1`, undo it with
`sudo ipconfig setverbose 0`.

## Privacy

To show the public IP with its location and operator, coSHLink asks
[ipinfo.io](https://ipinfo.io) every 5 minutes and whenever the network
changes, so this service learns roughly where the computer is.
[api.ipify.org](https://www.ipify.org) is asked only if ipinfo.io fails. With
`-s`, each speed test downloads from `speed.cloudflare.com`. To know
whether there is a newer build, it reads the first lines of `coSHLink.sh`
on GitHub at start and every 6 hours. Nothing else leaves the computer.

## License

MIT. See [LICENSE](LICENSE).

---

<p>
  <a href="https://github.com/lolostt"><img src="https://github.com/user-attachments/assets/85619289-29ae-406d-badb-23e38b30bebe" alt="Sleeping Coconut" width="32" height="32" align="absmiddle"></a>
  · <a href="https://sleepingcoconut.com">www.sleepingcoconut.com</a> · 2026
</p>
