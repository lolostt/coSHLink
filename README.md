# coSHLink

A live map of the network path from your computer to the internet, drawn in
an 80x24 terminal.

<p align="center">
  <img src="DEMO_IMAGE_URL" alt="coSHLink running with sample data" width="800">
</p>

coSHLink draws your computer, the gateway and the internet as a diagram. Each
link pulses green, amber or red as it goes up, degraded or down, and the link
to the gateway is dashed over Wi-Fi and solid over a cable. A panel lists the
traffic, latency, jitter and loss of each link. Around the map you see the
Wi-Fi network, the local and gateway addresses, the DNS state, the public IP
address with its location and operator, a possible carrier-grade NAT and,
optionally, the download speed.

It is a single bash script. It installs nothing and needs no administrator
rights.

## Three ways to run it

- 🍎 **macOS** and 🐧 **Linux**: use any terminal.
- 🪟 **Windows**: use Git Bash (see [Requirements](#requirements)).

### 1. Run the script

Download it and start it from the same folder:

```sh
curl -fsSL https://raw.githubusercontent.com/lolostt/coSHLink/main/coSHLink.sh -o coSHLink.sh && chmod +x coSHLink.sh
./coSHLink.sh -l
```

Press `q` or `Ctrl+C` to quit. Without `-l` it stops after 60 seconds.

### 2. Install it as a command

From the folder holding `coSHLink.sh`:

```sh
./coSHLink.sh -i
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

Update to the latest version on GitHub:

```sh
coshlink -u
```

Uninstall (removes only what `-i` added):

```sh
coshlink -r
```

### 3. Double-click a launcher

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
| `-v`  | `--version`   | Print the version.                                              |
| `-h`  | `--help`      | Print the help.                                                 |

Short options can be combined: `-ls` is `-l -s`. Thresholds, ping targets and
intervals live in the *User configuration* section at the top of the script.

With `-s`, a speed test runs every 15 seconds and downloads up to 25 MB each
time. Avoid it on a metered connection.

## Wi-Fi name on macOS

🍎 macOS 15 and later hide the Wi-Fi name from scripts, so coSHLink shows
"(name hidden)". To reveal it to every program, across reboots:

```sh
sudo ipconfig setverbose 1
```

To hide it again:

```sh
sudo ipconfig setverbose 0
```

## Requirements

| System        | Minimum                                             | Needs                                                         |
|---------------|-----------------------------------------------------|---------------------------------------------------------------|
| 🍎 macOS      | macOS 12 Monterey                                   | Nothing: every tool it uses ships with macOS.                 |
| 🐧 Linux      | bash 5 (Ubuntu 20.04, Debian 10, Fedora 30, RHEL 9) | `iproute2`, `ping`, `curl`, `nslookup`, `iconv`, `traceroute` |
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
  box shows "no details on Linux".
- 🪟 **Windows.** Git for Windows ships bash 5. Windows Terminal needs
  Windows 10 version 2004 or later; without it, the launcher uses mintty,
  included with Git.

Run `./coSHLink.sh -c` to list the tools missing on your computer.

## How it works

The measurements run in background processes, so drawing never waits for the
network. Their results go to a private temporary directory, readable only by
your user and removed on exit. On Linux it lives in `/dev/shm`, in memory,
unless `TMPDIR` is set.

## Privacy

To show the public IP with its location and operator, coSHLink asks
[ipinfo.io](https://ipinfo.io) every 5 minutes and whenever the network
changes, so this service learns roughly where the computer is.
[api.ipify.org](https://www.ipify.org) is asked only if ipinfo.io fails. With
`-s`, each speed test downloads from `speed.cloudflare.com`. Nothing else
leaves the computer.

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
  <a href="https://github.com/lolostt/coSHLink"><img src="AUTHOR_IMAGE_URL" alt="Sleeping Coconut" width="20" height="20" align="absmiddle"></a>
  · <a href="https://sleepingcoconut.com">www.sleepingcoconut.com</a> · 2026
</p>
