#!/usr/bin/env bash
# coSHLink
# Build: 3
#
# https://github.com/lolostt/coSHLink
# Copyright (C) 2026 Sleeping Coconut https://sleepingcoconut.com
# Licensed under the MIT License.
#
# A live map, in an 80x24 terminal, of the way from this computer to the
# internet on whatever network it has joined. The computer is wired to the
# gateway and the gateway to the internet; a pulse runs along each wire in
# the colour of its state, dashed over Wi-Fi and solid over a cable. A panel
# shows the traffic, latency, jitter and loss of each link. Around the map:
# the Wi-Fi network, the local and gateway addresses, the DNS, the public IP
# with its place and operator, a possible CG-NAT and, with --speed, the
# download speed. Background processes take the measures and write them to
# files, so the drawing never waits for the network.
#
# Requirements:
#   macOS: nothing to install.
#   Windows: Git Bash (Git for Windows).
#   Linux: bash, iproute2, ping, curl, nslookup, iconv and traceroute. The
#   Wi-Fi details are not shown.
#   Run with --check to list the tools that are missing.
#
# Usage:
#   coSHLink.sh [--loop] [--speed] [--check] [--log FILE] [--256 | --truecolor]
#   coSHLink.sh --install | --uninstall
#     --loop       run until Ctrl+C (otherwise RUN_S seconds)
#     --speed      measure the download speed every SPEED_S seconds; each
#                  test downloads SPEED_MB MB
#     --check      read every source once, print the results and exit
#     --log FILE   append the errors of the background measures to FILE
#     --256        force 256 colours
#     --truecolor  force 24-bit colour
#     --install    install it for this user as the command "coshlink"
#     --uninstall  remove what --install added
#     -h, --help   show the options
#
#   --install copies the script to ~/.local/bin/coshlink (INSTALL_DIR) and,
#   if that folder is not in the PATH, adds it in ~/.zshrc, ~/.bash_profile
#   or ~/.bashrc, after the login shell. On Windows it also writes
#   coshlink.cmd to %LOCALAPPDATA%\Microsoft\WindowsApps, so that
#   "coshlink" works from PowerShell and cmd too. No administrator rights
#   are needed. Run --install again to update the installed copy.
#
#   macOS 15 and later hide the Wi-Fi name from scripts. To show it to every
#   program, across reboots:
#     sudo ipconfig setverbose 1
#   To hide it again:
#     sudo ipconfig setverbose 0
#
#   Privacy: the public IP is asked to ipinfo.io (IP_URL) every IP_S seconds
#   and whenever the network changes, so that service learns where the
#   computer is. api.ipify.org is asked only when ipinfo.io fails. With
#   --speed, each test downloads from speed.cloudflare.com.
#
# shellcheck disable=SC2086  # unquoted on purpose: numbers and lists of PIDs
#
# ============================================================================
# User configuration
# ============================================================================
#

# Label under the computer drawing (ASCII, up to 15 characters)
LOCAL="THIS COMPUTER"
# Link names in the panel, internet first (ASCII, up to 9 characters)
LINK_NAMES=(INTERNET GATEWAY)

# Where --install puts the script, and the name of the command
INSTALL_DIR=$HOME/.local/bin
INSTALL_NAME=coshlink

# Latency in ms per link (internet, gateway): amber from WARN, red from CRIT
LAT_WARN=(100 30)
LAT_CRIT=(200 80)
# Loss in % above which a wired link is degraded
LOSS_WARN=5

# Wi-Fi signal in dBm for 4, 3 (green), 2 (amber) and 1 bar (red)
SIG_DBM=(-55 -65 -75 -85)

# Over Wi-Fi a link is degraded only if the median latency stays at or above
# LAT_WARN for WIFI_SLOW_ROUNDS rounds in a row, or loss exceeds WIFI_LOSS_WARN %
WIFI_SLOW_ROUNDS=3
WIFI_LOSS_WARN=10
LOSS_ROUNDS=5                      # rounds over which loss is counted
DOWN_ROUNDS=2                      # rounds with every ping lost before "down"
CHECK_S=5                          # seconds between check rounds
PINGS=4                            # pings per target and round
RUN_S=60                           # seconds to run without --loop
LINK_MBPS=(100 300)                # full scale of the traffic meters, Mbit/s
WIFI_S=15                          # seconds between reads of the Wi-Fi state

# Ping targets of the internet link: each round shows the one that answers better
INET_TARGET=1.1.1.1
INET_ALT=8.8.8.8

# Names resolved each round to check the DNS
DNS_NAMES=(www.google.com www.wikipedia.org)

# Public IP with place and operator, and a fallback that gives the address only
IP_URL=https://ipinfo.io/json
IP_URL2=https://api.ipify.org
IP_S=300                           # seconds between public IP queries

# Download speed (--speed): one download of SPEED_MB MB, at most SPEED_MAX_S
# seconds long, every SPEED_S seconds
SPEED_URL="https://speed.cloudflare.com/__down?bytes="
SPEED_MB=25
SPEED_MAX_S=15
SPEED_S=600

# Status box title (ASCII, up to 11 characters)
APP=coSHLink
# Footer, bottom right: "MAKER · YEAR · BUILD" (ASCII)
MAKER="www.sleepingcoconut.com"
YEAR=2026
BUILD="build 3"

#
# ============================================================================
# Helper functions
# ============================================================================
#

# Read the command-line options into LOOP, CHECK, SPEED_ON, COLOR_MODE, LOG
# and ACTION.
parse_args() {
  ACTION=""
  LOOP=0
  CHECK=0
  SPEED_ON=0
  COLOR_MODE=auto
  LOG=/dev/null
  while (( $# )); do
    case $1 in
      --loop)      LOOP=1 ;;
      --check)     CHECK=1 ;;
      --speed)     SPEED_ON=1 ;;
      --log)       [[ -n $2 ]] || { echo "${0##*/}: --log needs a file" >&2; exit 2; }
                   LOG=$2; shift ;;
      --256)       COLOR_MODE=256 ;;
      --truecolor) COLOR_MODE=24 ;;
      --install)   ACTION=install ;;
      --uninstall) ACTION=uninstall ;;
      -h|--help)   echo "$USAGE"; exit 0 ;;
      *) echo "${0##*/}: unknown option '$1'" >&2
         echo "$USAGE" >&2
         exit 2 ;;
    esac
    shift
  done
  if (( ! CHECK )) && [[ -z $ACTION && ! -t 1 ]]; then
    echo "${0##*/}: the output is not a terminal (try --check)" >&2; exit 2
  fi
  if [[ $LOG != /dev/null ]]; then
    { : >> "$LOG"; } 2>/dev/null || { echo "${0##*/}: cannot write to $LOG" >&2; exit 2; }
  fi
}

# Set RC to the startup file of the user's login shell ("" if unknown).
shell_rc() {
  case ${SHELL##*/} in
    zsh)  RC=$HOME/.zshrc ;;
    bash) if [[ $OS == mac ]]; then RC=$HOME/.bash_profile; else RC=$HOME/.bashrc; fi ;;
    *)    RC="" ;;
  esac
  [[ $OS == win ]] && RC=$HOME/.bashrc
}

# Set CMD_FILE to the Windows command that runs the installed copy ("" if
# there is no WindowsApps folder).
win_cmd_file() {
  CMD_FILE=""
  [[ -n $LOCALAPPDATA ]] || return
  CMD_FILE="$(cygpath -u "$LOCALAPPDATA")/Microsoft/WindowsApps/$INSTALL_NAME.cmd"
  [[ -d ${CMD_FILE%/*} ]] || CMD_FILE=""
}

# --install: copy the script to INSTALL_DIR as INSTALL_NAME, put that folder
# in the PATH if needed and, on Windows, add a .cmd for PowerShell and cmd.
install_app() {
  local dest=$INSTALL_DIR/$INSTALL_NAME src=${BASH_SOURCE[0]}
  mkdir -p "$INSTALL_DIR" || { echo "${0##*/}: cannot create $INSTALL_DIR" >&2; exit 1; }
  if [[ ! $src -ef $dest ]]; then
    cp -f "$src" "$dest.tmp" && chmod 755 "$dest.tmp" && mv -f "$dest.tmp" "$dest" ||
      { rm -f "$dest.tmp"; echo "${0##*/}: cannot write $dest" >&2; exit 1; }
  fi
  echo "Installed $dest"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      shell_rc
      if [[ -z $RC ]]; then
        echo "Add $INSTALL_DIR to your PATH to run it as $INSTALL_NAME."
      elif ! grep -qF "$PATH_MARK" "$RC" 2>/dev/null; then
        printf '\nexport PATH="%s:$PATH"  %s\n' "${INSTALL_DIR/#$HOME/\$HOME}" "$PATH_MARK" >> "$RC" ||
          { echo "${0##*/}: cannot write $RC" >&2; exit 1; }
        echo "Added $INSTALL_DIR to the PATH in $RC"
      fi ;;
  esac
  if [[ $OS == win ]]; then
    win_cmd_file
    if [[ -n $CMD_FILE ]]; then
      printf '@echo off\r\nrem %s\r\nset CHERE_INVOKING=1\r\n"%s" -l "%s" %%*\r\n' \
        "$CMD_MARK" "$(cygpath -w /)\bin\bash.exe" "$(cygpath -w "$dest")" > "$CMD_FILE" ||
        { echo "${0##*/}: cannot write $CMD_FILE" >&2; exit 1; }
      echo "Installed $CMD_FILE"
    fi
  fi
  echo "Open a new terminal and run: $INSTALL_NAME --loop"
}

# --uninstall: remove the installed copy, the PATH line and the .cmd, only
# if --install wrote them.
uninstall_app() {
  local dest=$INSTALL_DIR/$INSTALL_NAME f tmp
  if [[ -f $dest ]] && grep -q '^# coSHLink$' "$dest" 2>/dev/null; then
    rm -f "$dest" && echo "Removed $dest"
  fi
  for f in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    grep -qF "$PATH_MARK" "$f" 2>/dev/null || continue
    tmp=$(grep -vF "$PATH_MARK" "$f")
    if [[ -z ${tmp//[[:space:]]/} ]]; then rm -f "$f"   # --install created it
    else printf '%s\n' "$tmp" > "$f"
    fi && echo "Removed the PATH line from $f"
  done
  if [[ $OS == win ]]; then
    win_cmd_file
    if [[ -n $CMD_FILE ]] && grep -qF "$CMD_MARK" "$CMD_FILE" 2>/dev/null; then
      rm -f "$CMD_FILE" && echo "Removed $CMD_FILE"
    fi
  fi
  rmdir "$INSTALL_DIR" "${INSTALL_DIR%/*}" 2>/dev/null   # only if empty
  echo "coSHLink is uninstalled."
}

# Map a colour level 0-255 to an index 0-5 of the 256-colour cube, in CUBE.
cube() {
  if (( $1 < 48 )); then CUBE=0
  elif (( $1 < 115 )); then CUBE=1
  else CUBE=$(( ($1 - 35) / 40 ))
  fi
}

# rgb R G B: set FG to the SGR parameters of that text colour, as close as
# the colour mode allows (the nearest of the cube and the grey ramp in 256).
rgb() {
  if [[ $COLOR_MODE == 24 ]]; then FG="38;2;$1;$2;$3"; return; fi
  local lv=(0 95 135 175 215 255) ri gi bi cr cg cb k gv dc dg
  cube "$1"; ri=$CUBE; cube "$2"; gi=$CUBE; cube "$3"; bi=$CUBE
  cr=${lv[ri]}; cg=${lv[gi]}; cb=${lv[bi]}
  k=$(( (($1 + $2 + $3) / 3 - 3) / 10 ))
  (( k < 0 )) && k=0; (( k > 23 )) && k=23
  gv=$(( 8 + k * 10 ))
  dc=$(( ($1 - cr) * ($1 - cr) + ($2 - cg) * ($2 - cg) + ($3 - cb) * ($3 - cb) ))
  dg=$(( ($1 - gv) * ($1 - gv) + ($2 - gv) * ($2 - gv) + ($3 - gv) * ($3 - gv) ))
  if (( dg < dc )); then FG="38;5;$(( 232 + k ))"
  else FG="38;5;$(( 16 + 36 * ri + 6 * gi + bi ))"
  fi
}

# setc INDEX CHAR COLOR: set a map cell and record it in CHG if it changed.
setc() {
  [[ ${GCH[$1]} == "$2" && ${GCO[$1]} == "$3" ]] && return
  GCH[$1]=$2; GCO[$1]=$3; CHG+=("$1")
}

# put ROW COL CHAR COLOR: set the map cell at ROW, COL.
put() {
  setc $(( $1 * COLS + $2 )) "$3" "$4"
}

# text ROW COL STRING COLOR: write ASCII text on the map.
text() {
  local i
  for (( i = 0; i < ${#3}; i++ )); do put $1 $(( $2 + i )) "${3:i:1}" "$4"; done
}

# center ROW COL WIDTH STRING COLOR: write ASCII text centred in a span.
center() {
  text $1 $(( $2 + ($3 - ${#4}) / 2 )) "$4" "$5"
}

# clear_cells ROW COL WIDTH: blank a span of the map.
clear_cells() {
  local k
  for (( k = 0; k < $3; k++ )); do put $1 $(( $2 + k )) " " "$RESET"; done
}

# draw ROW COL ROWS...: paint a drawing with its top-left corner at ROW, COL.
# Each row is "MASK|CHARS": one colour letter (C_x) and one character per
# cell, "_" for a cell left as it is.
draw() {
  local r=$1 c=$2 row mask i co
  local -a chars
  shift 2
  for row in "$@"; do
    mask=${row%%|*}
    read -r -a chars <<< "${row#*|}"
    for (( i = 0; i < ${#chars[@]}; i++ )); do
      [[ ${chars[i]} == _ ]] && continue
      eval "co=\$C_${mask:i:1}"
      put $r $(( c + i )) "${chars[i]}" "$co"
    done
    (( r++ ))
  done
}

# cell ROW COL h|v: add a cell to the current wire, horizontal or vertical.
cell() {
  local n=${#P_IDX[@]}
  P_IDX[n]=$(( $1 * COLS + $2 ))
  # A lower half block is about as thick as a full block is wide, so both
  # directions look equally heavy.
  if [[ $3 == h ]]; then
    P_HV[n]="▄"; P_LT[n]="▄"
  else
    P_HV[n]="█"; P_LT[n]="█"
  fi
}

# On every exit: stop the background processes and restore the terminal.
cleanup() {
  trap - EXIT INT TERM HUP TSTP CONT WINCH
  kill $CHECK_PID 2>/dev/null
  # Waiting for the clock keeps bash 3.2 from printing "Terminated".
  [[ -n $CLOCK_PID ]] && { kill $CLOCK_PID; wait $CLOCK_PID; } 2>/dev/null
  [[ -n $TMPD ]] && rm -rf "$TMPD"
  (( HIDDEN )) && { term_restore; echo; }
}

# Hide the cursor and the keys typed.
term_hide() {
  HIDDEN=1
  printf '%s' "${ESC}[?25l"
  [[ -t 0 ]] && stty -echo 2>/dev/null
}

# Show the cursor and put the terminal settings back.
term_restore() {
  printf '%s' "${ESC}[?25h${RESET}"
  [[ -t 0 && -n $STTY ]] || return
  # Drop the keys pressed while running, or the shell would get them on
  # exit (an Enter among them runs a command). cat gets EAGAIN on MSYS.
  stty -icanon min 0 time 0 2>/dev/null && cat > /dev/null 2>&1
  stty "$STTY" 2>/dev/null
}

# Ctrl+Z: restore the terminal, then stop.
suspend() {
  term_restore; trap - TSTP; kill -TSTP $$; trap suspend TSTP
}

# Back in the foreground: hide the terminal again and redraw everything.
resume() {
  term_hide; RESUMED=1
}

# Set the traps for every exit and for Ctrl+Z, and hide the terminal.
setup_term() {
  RESUMED=0
  [[ -t 0 ]] && STTY=$(stty -g 2>/dev/null)
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  trap suspend TSTP
  trap resume CONT
  trap '' PIPE                       # a dead helper gives a write error, not death
  (( CHECK )) || term_hide
}

# Update NOW, in ms: from the perl clock, EPOCHREALTIME or a fixed step.
clock_tick() {
  local last=$NOW
  if (( CLOCK )); then              # if the perl clock dies, carry on without it
    { printf x >&4 && read -r NOW <&5 && [[ $NOW =~ ^[0-9]+$ ]]; } 2>/dev/null ||
      { CLOCK=0; NOW=$last; pause() { sleep 0.04; }; clock_tick; }
  elif [[ -n $EPOCHREALTIME ]]; then
    local t=${EPOCHREALTIME/[.,]/}
    NOW=$(( t / 1000 ))
  else
    NOW=$(( NOW + TICK_MS ))
  fi
}

# rnd N: set H to a pseudo-random 0-255, always the same for each N.
# draw_screen, traffic_meter and render_map inline copies of it for speed:
# keep them the same.
rnd() {
  H=$(( ((($1 * 2654435761) ^ ($1 * 40503 >> 3)) >> 11) & 255 ))
}

# blink A B: set BL to A or B, alternating every 400 ms.
blink() {
  if (( T / 400 % 2 )); then BL=$1; else BL=$2; fi
}

# tail_level DIST TAIL: set TL to the brightness of a comet cell DIST cells
# behind the head.
tail_level() {
  if (( $1 == 0 )); then TL=8
  elif (( $1 > 0 && $1 <= $2 )); then TL=$(( 7 - ($1 - 1) * 5 / $2 ))
  else TL=0
  fi
}

# still_wire LINK: draw a grey wire with no pulse, before the first data.
still_wire() {
  local i k
  for (( i = 0; i < LINK_LEN[$1]; i++ )); do
    k=$(( LINK_START[$1] + i ))
    if (( DASH[$1] && i % 2 )); then setc ${P_IDX[k]} " " "$RESET"
    else setc ${P_IDX[k]} "${P_LT[k]}" "$BOX_COLOR"
    fi
  done
}

# draw_wire LINK STATE: draw a wire with its comet, a pulse with a fading
# tail that runs to the far end and back. A cut wire shows a ✕ in the middle
# and a retry pulse that dies at the cut.
draw_wire() {
  local j=$1 s=$2 o=${LINK_START[$1]} n=${LINK_LEN[$1]} tail=${LTAIL[$1]}
  local mid i k l d step cyc ph head fwd pl
  mid=$(( n / 2 ))
  if (( s == 2 )); then
    cyc=$(( (T + j * 700) / 2500 ))  # the retry leaves from each end in turn
    ph=$(( ((T + j * 700) % 2500) / (45 * LSLOW[j]) ))
    pl=$(( tail < 4 ? tail : 4 ))
    for (( i = 0; i < n; i++ )); do
      k=$(( o + i ))
      if (( cyc % 2 )); then l=$(( ph - (n - 1 - i) )); (( i < mid )) && l=-1
      else l=$(( ph - i )); (( i > mid )) && l=-1
      fi
      if (( i == mid )); then
        blink $(( RED + 8 )) $(( RED + 3 )); setc ${P_IDX[k]} "✕" "${RAMP[BL]}"
      elif (( i == mid - 1 || i == mid + 1 )); then
        setc ${P_IDX[k]} " " "$RESET"    # a gap on each side of the ✕
      elif (( l >= 0 && l < pl && ph < mid + pl )); then
        setc ${P_IDX[k]} "${P_HV[k]}" "${RAMP[RED+7-l]}"
      else
        # dashes counted from the cut, so they fall evenly around it
        if (( (i - mid) % 2 )); then setc ${P_IDX[k]} " " "$RESET"
        else setc ${P_IDX[k]} "${P_LT[k]}" "${RAMP[RED+1]}"
        fi
      fi
    done
    return
  fi
  if (( s == 0 )); then step=${LUP[j]}; else step=$(( 90 * LSLOW[j] )); fi
  cyc=$(( 2 * (n - 1) ))             # there and back
  ph=$(( ((T + j * 1000) / step) % cyc ))
  if (( ph < n )); then head=$ph; fwd=1; else head=$(( cyc - ph )); fwd=0; fi
  for (( i = 0; i < n; i++ )); do
    k=$(( o + i ))
    if (( fwd )); then d=$(( head - i )); else d=$(( i - head )); fi
    tail_level $d $tail; l=$TL
    if (( DASH[j] && i % 2 )); then setc ${P_IDX[k]} " " "$RESET"
    elif (( l > 1 )); then setc ${P_IDX[k]} "${P_HV[k]}" "${RAMP[s*9+l]}"
    else setc ${P_IDX[k]} "${P_LT[k]}" "${RAMP[s*9+1]}"
    fi
  done
}

# Draw the computer screen: faint lines of "text" scroll up, the last one
# being typed with a blinking cursor.
draw_screen() {
  local r c n k len ind typed ch co cur key H
  n=$(( T / SCR_MS ))               # the line being typed
  rnd $(( n * 7 + 3 )); len=$(( 3 + H % 5 ))
  typed=$(( len * (T % SCR_MS) / (SCR_MS * 3 / 4) )); (( typed > len )) && typed=$len
  cur=$(( T / 500 % 2 == 0 ))
  key="$n $typed $cur"
  [[ $key == "$SCR_KEY" ]] && return
  for (( r = 0; r < 2; r++ )); do
    k=$(( n - 1 + r ))
    (( r < 1 )) && [[ ${SCR_KEY%% *} == "$n" ]] && continue   # only the last line moved
    rnd $(( k * 7 + 3 )); len=$(( 3 + H % 5 )); ind=$(( H / 8 % 3 * 2 ))
    (( k % 5 == 4 )) && len=0       # now and then a blank line
    typed=$len; co=$SCR_COLOR
    (( r == 1 )) && { typed=$(( len * (T % SCR_MS) / (SCR_MS * 3 / 4) )); co=$SCR_HOT; }
    (( typed > len )) && typed=$len
    for (( c = 0; c < 9; c++ )); do
      ch=" "
      if (( c >= ind && c < ind + typed )); then
        H=$(( k * 31 + c )); H=$(( (((H * 2654435761) ^ (H * 40503 >> 3)) >> 11) & 255 ))
        if (( H % 4 )); then ch=⠶; else ch=⠒; fi
      fi
      put $(( SCR_R + r )) $(( SCR_C + c )) "$ch" "$co"
    done
    if (( r == 1 && cur )); then
      c=$(( ind + typed )); (( c > 8 )) && c=8
      put $(( SCR_R + 1 )) $(( SCR_C + c )) "▁" "$SCR_CUR"
    fi
  done
  SCR_KEY=$key
}

# Create the private directory of the results files (only this user can
# open it; there is no fixed-name fallback another user could create first).
make_tmp() {
  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/coSHLink.XXXXXX" 2>/dev/null) || {
    TMPD=""; echo "${0##*/}: cannot create a temporary directory" >&2; exit 1; }
  RES=$TMPD/results
  : > "$RES"; : > "$RES.dns"; : > "$RES.ip"; : > "$RES.wifi"; : > "$RES.speed"
  MAIN_PID=$$
}

# Choose how frames are paced and timed. With bash 5: read -t on a FIFO
# nobody writes to, and EPOCHREALTIME. Otherwise a small perl process that
# answers with the time at most every FRAME_MS ms, or else sleep and a fixed
# step.
start_clock() {
  CLOCK=0
  if [[ -n $EPOCHREALTIME ]] && mkfifo "$TMPD/tick" 2>/dev/null &&
     exec 3<> "$TMPD/tick"; then
    pause() { read -r -t 0.04 -u 3 _; }
  elif command -v perl > /dev/null 2>&1 && mkfifo "$TMPD/ask" "$TMPD/ms" 2>/dev/null; then
    perl -MTime::HiRes=time,sleep -e '$| = 1; my $next = 0;
      while (sysread(STDIN, my $b, 1)) {
        my $t = time; if ($t < $next) { sleep($next - $t); $t = $next }
        $next = $t + $ARGV[0] / 1000; printf "%d\n", $t * 1000 }' $FRAME_MS \
      < "$TMPD/ask" > "$TMPD/ms" 2>/dev/null &
    CLOCK_PID=$!
    exec 4> "$TMPD/ask" 5< "$TMPD/ms"
    CLOCK=1
    pause() { :; }                    # the clock waits instead
  else
    pause() { sleep 0.04; }
  fi
}

# Find the Wi-Fi interface, in WIFI_IF ("" if none).
find_wifi_if() {
  case $OS in
    win) WIFI_IF=$(netsh wlan show interfaces 2>/dev/null | tr -d '\r' |
           awk -F' : ' '/^ +(Nombre|Name) +:/ { print $2; exit }') ;;
    mac) WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null |
           awk '/^Hardware Port: (Wi-Fi|AirPort)/ { getline; print $2; exit }') ;;
    linux)
      WIFI_IF=""
      for f in /sys/class/net/*/wireless; do
        [[ -d $f ]] && { WIFI_IF=${f%/wireless}; WIFI_IF=${WIFI_IF##*/}; break; }
      done ;;
  esac
}

# ping_host HOST: send PINGS pings, waiting 1 s for each reply and at most
# PINGS + 1 s in all (the wait is in ms on macOS and Windows, s on Linux).
ping_host() {
  case $OS in
    win)   command ping -n $PINGS -w 1000 "$1" ;;
    mac)   command ping -c $PINGS -W 1000 -t $(( PINGS + 1 )) "$1" ;;
    linux) command ping -c $PINGS -W 1 -w $(( PINGS + 1 )) "$1" ;;
  esac
}

# ping_parse FILE: read the output of ping_host into P_RTT (PINGS times in
# ms, -1 for a lost ping), P_OK (replies), P_SUM (their sum) and P_JIT (mean
# change between consecutive replies, -1 unknown).
ping_parse() {
  # Each reply goes to the place of its icmp_seq (from 0 on macOS, 1 on
  # Linux), so a lost ping shows where it was lost. Windows has no seq:
  # replies go in order. Decimals are dropped.
  local line n=0 i prev=-1 d base=0 re='[=<]([0-9]+)([.,][0-9]+)? ?m' sq='icmp_seq=([0-9]+)'
  local jsum=0 jn=0
  local -a sqn=() rtt=()
  P_RTT=(); P_OK=0; P_SUM=0; P_JIT=-1
  [[ $OS == linux ]] && base=1
  while IFS= read -r line && (( n < PINGS )); do
    [[ $line == *[Tt][Tt][Ll]=* && $line =~ $re ]] || continue  # a reply
    rtt[n]=$(( 10#${BASH_REMATCH[1]} )); sqn[n]=-1
    [[ $line =~ $sq ]] && sqn[n]=$(( 10#${BASH_REMATCH[1]} ))
    (( sqn[n] == 0 )) && base=0       # BusyBox counts from 0 on Linux too
    (( n++ ))
  done < "$1"
  for (( i = 0; i < n; i++ )); do
    d=$(( sqn[i] - base ))
    (( sqn[i] < 0 || d < 0 || d >= PINGS )) && d=$i   # no usable seq: in order
    [[ -n ${P_RTT[d]} ]] && d=$i
    P_RTT[d]=${rtt[i]}; (( P_SUM += rtt[i], P_OK++ ))
  done
  for (( i = 0; i < PINGS; i++ )); do
    [[ -n ${P_RTT[i]} ]] || { P_RTT[i]=-1; continue; }
    if (( prev >= 0 )); then
      d=$(( P_RTT[i] - prev )); (( d < 0 )) && d=$(( -d )); (( jsum += d, jn++ ))
    fi
    prev=${P_RTT[i]}
  done
  (( jn )) && P_JIT=$(( (jsum + jn / 2) / jn ))
}

# Set MS to the current time in ms (whole seconds without EPOCHREALTIME).
now_ms() {
  if [[ -n $EPOCHREALTIME ]]; then MS=${EPOCHREALTIME/[.,]/}; MS=$(( MS / 1000 ))
  else MS=$(( SECONDS * 1000 )); fi
}

# Find the gateway: GW its address ("" if none), GW_IF its interface, and
# TUN 1 if a default route goes through a VPN tunnel (not on Windows).
# The *_mac, *_win and *_linux functions below hold what differs between
# systems; each returns the same variables in the same form.
gateway() {
  local re='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  GW=""; GW_IF=""; TUN=0
  gateway_$OS
  [[ $GW =~ $re ]] || { GW=""; GW_IF=""; }
}

# Gateway from ipconfig (in Spanish or English). Also sets IF_IP, the
# address of the gateway's adapter, and WIFI_IP, the Wi-Fi one.
gateway_win() {
  local line ad="" ip="" ingw=0 v re='([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
  GW=""; GW_IF=""; IF_IP=""; WIFI_IP=""
  while IFS= read -r line; do
    line=${line//$'\r'/}
    if [[ $line == [![:space:]]*: ]]; then   # "Adaptador de LAN inalambrica Wi-Fi:"
      ad=${line%:}; ip=""; ingw=0
      [[ -n $WIFI_IF && $ad == *" $WIFI_IF" ]] && ad=$WIFI_IF
      continue
    fi
    if [[ $line == *IPv4*:* && ${line##*:} =~ $re ]]; then
      ip=${BASH_REMATCH[1]}; [[ $ad == "$WIFI_IF" ]] && WIFI_IP=$ip
    fi
    if [[ $line == *"Puerta de enlace"*:* || $line == *"Default Gateway"*:* ]]; then
      ingw=1; v=${line##*: }
    elif (( ingw )) && [[ $line != *": "* ]]; then v=$line   # more gateways, one per line
    else ingw=0; v=""
    fi
    if [[ -z $GW && $v =~ ^[[:space:]]*$re ]]; then
      GW=${BASH_REMATCH[1]}; GW_IF=$ad; IF_IP=$ip
    fi
  done < <(ipconfig 2>/dev/null)
}

# Gateway from the default route that is not a VPN, else from the router
# that DHCP gave (when a VPN takes every route).
gateway_mac() {
  local dst gw netif re='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  while read -r dst gw _ netif _; do
    [[ $dst == default ]] || continue
    [[ $netif == utun* || $netif == ipsec* ]] && { TUN=1; continue; }
    [[ -z $GW && $gw =~ $re ]] && { GW=$gw; GW_IF=$netif; }
  done < <(netstat -rn -f inet 2>/dev/null)
  if [[ -z $GW && -n $WIFI_IF ]]; then
    GW=$(ipconfig getoption "$WIFI_IF" router 2>/dev/null); GW_IF=$WIFI_IF
  fi
  for netif in $(ipconfig getiflist 2>/dev/null); do
    [[ -n $GW ]] && break
    GW=$(ipconfig getoption "$netif" router 2>/dev/null); GW_IF=$netif
  done
}

# Gateway from /proc/net/route: the default route with a router, not
# through a tunnel.
gateway_linux() {
  local netif dst gw x a b c d
  while read -r netif dst gw x; do
    [[ $dst == 00000000 ]] || continue
    [[ $netif == tun* || $netif == wg* || $netif == tap* ]] && { TUN=1; continue; }
    [[ -z $GW && $gw =~ ^[0-9A-Fa-f]{8}$ && $gw != 00000000 ]] || continue
    # hex, lowest byte first: 0101A8C0 -> 192.168.1.1
    a=$(( 16#${gw:6:2} )); b=$(( 16#${gw:4:2} )); c=$(( 16#${gw:2:2} )); d=$(( 16#${gw:0:2} ))
    GW="$a.$b.$c.$d"; GW_IF=$netif
  done 2>/dev/null < /proc/net/route
}

# if_addr INTERFACE: set IFA to its IPv4 address ("" if none).
if_addr() {
  IFA=""
  [[ -n $1 ]] && if_addr_$OS "$1"
  [[ $IFA =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || IFA=""
}

# Interface address on macOS.
if_addr_mac() {
  IFA=$(ipconfig getifaddr "$1" 2>/dev/null)
}

# Interface address on Linux.
if_addr_linux() {
  local line re='inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
  while IFS= read -r line; do
    [[ $line =~ $re ]] && { IFA=${BASH_REMATCH[1]}; break; }
  done < <(ip -4 -o addr show dev "$1" 2>/dev/null)
}

# Interface address on Windows, from what gateway_win read before.
if_addr_win() {
  [[ $1 == "$GW_IF" ]] && IFA=$IF_IP
  [[ $1 == "$WIFI_IF" && -n $WIFI_IP ]] && IFA=$WIFI_IP
}

# Byte counters of GW_IF into RX and TX, on macOS.
if_bytes_mac() {
  local -a f
  while read -r -a f; do
    [[ ${f[2]} == "<Link"* ]] || continue
    RX=${f[6]}; TX=${f[9]}; break
  done < <(netstat -ib -I "$GW_IF" 2>/dev/null)
}

# Byte counters of GW_IF on Windows ("MTU state in out name" per interface).
if_bytes_win() {
  local -a f
  local line
  while read -r -a f; do
    line="${f[*]:4}"; line=${line//$'\r'/}
    [[ -n $line && ( $GW_IF == "$line" || $GW_IF == *" $line" ) ]] || continue
    RX=${f[2]}; TX=${f[3]}; break
  done < <(netsh interface ipv4 show subinterfaces 2>/dev/null)
}

# Byte counters of GW_IF on Linux, from /sys.
if_bytes_linux() {
  read -r RX 2>/dev/null < "/sys/class/net/$GW_IF/statistics/rx_bytes"
  read -r TX 2>/dev/null < "/sys/class/net/$GW_IF/statistics/tx_bytes"
}

# Set RATE to the bit/s through GW_IF since the last call, the busier of
# the two directions (-1 unknown).
if_rate() {
  local rx tx dt b
  RATE=-1
  [[ $GW_IF == "$PREV_IF" ]] || { PREV_RX=-1; PREV_IF=$GW_IF; }  # another interface
  [[ -n $GW_IF ]] || return
  RX=-1; TX=-1; if_bytes_$OS; rx=$RX; tx=$TX
  [[ $rx =~ ^[0-9]+$ && $tx =~ ^[0-9]+$ ]] || return
  now_ms; dt=$(( MS - PREV_MS ))
  if (( PREV_RX >= 0 && dt > 0 && rx >= PREV_RX && tx >= PREV_TX )); then
    b=$(( rx - PREV_RX )); (( tx - PREV_TX > b )) && b=$(( tx - PREV_TX ))
    RATE=$(( b * 8000 / dt ))
  fi
  PREV_RX=$rx; PREV_TX=$tx; PREV_MS=$MS
}

# traffic_level BIT/S MBPS: set L to the level 0-4 of a traffic meter whose
# full scale is MBPS (-1 unknown).
traffic_level() {
  local pm=$(( $1 / ($2 * 1000) ))  # per mille of the full scale
  if (( $1 < 0 )); then L=-1
  elif (( $1 < 8000 )); then L=0
  elif (( pm < 10 )); then L=1
  elif (( pm < 50 )); then L=2
  elif (( pm < 250 )); then L=3
  else L=4
  fi
}

# printable STRING: set PR to it without control characters or "|". Text
# from outside (a Wi-Fi name, a web answer) goes through it before it is
# written to a results file, so no escape can reach the terminal.
printable() {
  PR=${1//[[:cntrl:]]/}; PR=${PR//|//}
}

# fit_name NAME: set FIT to "NAME|PAD", the name cleaned and cut to 18
# characters and PAD the spaces that fill it to 18 (characters, not bytes).
fit_name() {
  # shellcheck disable=SC2016  # the script for the inner bash, as it is
  FIT=$(LC_ALL=$UTF8 "$BASH" -c 's=${1//[[:cntrl:]]/}; s=${s//|//}; s=${s:0:18}
    printf "%s|%d" "$s" $(( 18 - ${#s} ))' _ "$1")
}

# ascii STRING: set A to it in ASCII, accents dropped ("Córdoba" -> "Cordoba").
ascii() {
  A=$(printf '%s' "$1" | LC_ALL=$UTF8 iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null |
    tr -d "'\`^~\"")
  printable "$A"; A=$PR
}

# sec_short SECURITY: set SEC to a short name of a Wi-Fi security and SECLV
# to its level: 0 fine (WPA2, WPA3, OWE), 1 weak or unknown, 2 open.
sec_short() {
  SEC=$1; SECLV=1
  case $SEC in
    "")                     SECLV=0; return ;;   # not known yet
    *"Enhanced Open"*|*OWE*) SEC=OWE; SECLV=0; return ;;
    *None*|Open|Abierta)    SEC=OPEN; SECLV=2; return ;;
    *WEP*)                  SEC=WEP; return ;;
  esac
  # "WPA2 Personal" (macOS), "WPA2-Personal" (Windows, English or Spanish)
  SEC=${SEC//[ -]Personal/}; SEC=${SEC//[ -]Enterprise/-Ent}; SEC=${SEC//-Empresa/-Ent}
  SEC=${SEC// Transition/}; SEC=${SEC//\/WPA3/\/3}
  printable "$SEC"; SEC=${PR:0:10}
  case $SEC in
    WPA|WPA-Ent|WPA/*) ;;                    # WPA1: weak
    *WPA2*|*WPA3*)     SECLV=0 ;;
  esac
}

# Read the Wi-Fi state into WIFI:
# "state|name|pad|security|level|band|channel|signal|noise|rate|mode".
# state: 0 joined, 1 on but not joined, 2 off, 3 no Wi-Fi interface,
# 4 no details on this system.
wifi_poll() {
  if [[ -z $WIFI_IF ]]; then WIFI="3|||||||||"; return; fi
  wifi_poll_$OS
}

# Wi-Fi state on Linux: no details.
wifi_poll_linux() {
  WIFI="4|||||||||"
}

# Wi-Fi state on macOS: the name from ipconfig, the rest from the system
# profiler.
wifi_poll_mac() {
  local line cur=0 sec="" seclv=0 band="" ch="" sig="" noise="" rate="" phy=""
  local ssid="" name="" st re
  st=1
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]+SSID[[:space:]]:[[:space:]](.*)$ ]] && { ssid=${BASH_REMATCH[1]}; break; }
  done < <(ipconfig getsummary "$WIFI_IF" 2>/dev/null)
  # only the first "Current Network Information" block
  while IFS= read -r line; do
    if [[ $line == *"Current Network Information:"* ]]; then
      (( cur )) && break; cur=1; st=0; continue
    fi
    (( cur )) || continue
    [[ $line == *"Other Local"* ]] && break
    line=${line#"${line%%[![:space:]]*}"}
    case $line in
      "PHY Mode: "*)       phy=${line#*: } ;;
      "Channel: "*)        re='^Channel: ([0-9]+) \(([0-9.]+)GHz'
                           [[ $line =~ $re ]] && { ch=${BASH_REMATCH[1]}; band=${BASH_REMATCH[2]}; } ;;
      "Security: "*)       sec=${line#*: } ;;
      "Signal / Noise: "*) re='(-?[0-9]+) dBm / (-?[0-9]+) dBm'
                           [[ $line =~ $re ]] && { sig=${BASH_REMATCH[1]}; noise=${BASH_REMATCH[2]}; } ;;
      "Transmit Rate: "*)  rate=${line#*: } ;;
      *:)                  [[ -z $name ]] && name=${line%:} ;;   # the network name
    esac
  done < <(system_profiler SPAirPortDataType 2>/dev/null)
  if (( st == 1 )); then
    networksetup -getairportpower "$WIFI_IF" 2>/dev/null | grep -q ': Off' && st=2
  fi
  [[ -z $ssid || $ssid == *redacted* ]] && ssid=$name
  [[ $ssid == *redacted* ]] && ssid=""
  sec_short "$sec"; sec=$SEC; seclv=$SECLV
  fit_name "$ssid"; ssid=$FIT
  printable "$rate"; rate=${PR:0:9}; printable "$phy"; phy=${PR:0:10}
  WIFI="$st|$ssid|$sec|$seclv|$band|$ch|$sig|$noise|$rate|$phy"
}

# Wi-Fi state on Windows, from netsh (in Spanish or English). Signal comes
# as a percentage and is turned into rough dBm; there is no noise.
wifi_poll_win() {
  local line k v st=1 ssid="" sec="" seclv=0 band="" ch="" sig="" rate="" phy=""
  while IFS= read -r line; do
    line=${line//$'\r'/}
    [[ $line == *"Software Desactivado"* || $line == *"Software Off"* ]] && st=2
    [[ $line == *" : "* ]] || continue
    k=${line%%" : "*}; k=${k#"${k%%[![:space:]]*}"}; k=${k%"${k##*[![:space:]]}"}
    v=${line#*" : "}; v=${v%"${v##*[![:space:]]}"}
    case $k in
      Estado|State)        [[ $v == conectado || $v == connected ]] && st=0 ;;
      SSID)                ssid=$v ;;
      Autentica*|Authentication) sec=$v ;;
      Banda|Band)          band=${v%% *}; band=${band/,/.}
                           [[ $band =~ ^[0-9.]+$ ]] || band="" ;;
      Canal|Channel)       [[ $v =~ ^[0-9]+$ ]] && ch=$v ;;
      Se*al|Signal)        v=${v%'%'}; [[ $v =~ ^[0-9]+$ ]] && sig=$(( v / 2 - 100 )) ;;
      "Velocidad de transmisi"*|"Transmit rate"*) rate=${v%%[.,]*} ;;
      "Tipo de radio"|"Radio type") phy=$v ;;
    esac
  done < <(netsh wlan show interfaces 2>/dev/null)
  (( st )) && { WIFI="$st|||||||||"; return; }
  sec_short "$sec"; sec=$SEC; seclv=$SECLV
  fit_name "$ssid"; ssid=$FIT
  printable "$rate"; rate=${PR:0:9}; printable "$phy"; phy=${PR:0:10}
  WIFI="0|$ssid|$sec|$seclv|$band|$ch|$sig||$rate|$phy"
}

# write_file FILE LINE: replace FILE at once, so a reader never sees half.
write_file() {
  printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"
}

# Start a background loop: on TERM it stops its children too, so no ping,
# sleep or download outlives the script. The tools answer in English.
bg_init() {
  trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM
  export LC_ALL=C
}

# nap SECONDS: sleep as a child, so a signal is handled at once.
nap() {
  sleep "$1" & wait $!
}

# round_sleep PERIOD START: sleep what is left of a round that began when
# SECONDS was START.
round_sleep() {
  local left=$(( $1 - (SECONDS - $2) ))
  (( left > 0 )) && nap $left
}

# Background loop: write "round|$WIFI" to $RES.wifi every WIFI_S seconds.
wifi_checker() {
  local seq=0 t0
  bg_init
  while kill -0 "$MAIN_PID" 2>/dev/null; do
    t0=$SECONDS
    wifi_poll; (( seq++ ))
    write_file "$RES.wifi" "$seq|$WIFI"
    round_sleep $WIFI_S $t0
  done
}

# dns_parse FILE: true if nslookup got an address. Sets DNS_SRV to the
# server that answered.
dns_parse() {
  local line body=0 ok=0 bad=0 ip='[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
  local srv='Address:[[:space:]]+([0-9a-fA-F.:]+)'
  while IFS= read -r line; do
    line=${line//$'\r'/}
    if (( ! body )); then           # server block, up to the first blank line
      [[ -z $line ]] && { body=1; continue; }
      [[ $line =~ $srv ]] && DNS_SRV=${BASH_REMATCH[1]}
    elif [[ $line == *'**'* || $line == *'timed out'* ]]; then bad=1
    elif [[ $line =~ $ip ]]; then ok=1
    fi
  done < "$1"
  (( ok && ! bad ))
}

# Background loop: write "round state server" to $RES.dns every CHECK_S
# seconds. State: 0 every name resolves, 1 only some do, 2 none for
# DOWN_ROUNDS rounds, -1 no nslookup.
dns_checker() {
  local i k t0 st seq=0 zero=0
  bg_init
  while kill -0 "$MAIN_PID" 2>/dev/null; do
    t0=$SECONDS
    st=-1; DNS_SRV=-
    if (( HAVE_NSLOOKUP )); then
      for (( i = 0; i < ${#DNS_NAMES[@]}; i++ )); do
        nslookup -timeout=2 "${DNS_NAMES[i]}" > "$TMPD/d$i" 2>&1 &
      done
      wait
      k=0
      for (( i = 0; i < ${#DNS_NAMES[@]}; i++ )); do dns_parse "$TMPD/d$i" && (( k++ )); done
      if (( k == ${#DNS_NAMES[@]} )); then st=0; zero=0
      elif (( k )); then st=1; zero=0
      else zero=$(( zero + 1 )); st=1; (( zero >= DOWN_ROUNDS )) && st=2
      fi
    fi
    (( seq++ ))
    write_file "$RES.dns" "$seq $st $DNS_SRV"
    round_sleep $CHECK_S $t0
  done
}

# Ask the web for the public IP: PUB_IP the address ("" unknown), PUB_LOC
# its country, city and operator ("ES Madrid, EXAMPLE TELECOM").
public_ip() {
  local body re='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  local cc="" city="" org="" sfx
  PUB_IP=""; PUB_LOC=""
  curl -fsS -m 5 --max-filesize 100000 "$IP_URL" > "$TMPD/ipinfo" 2>/dev/null < /dev/null & wait $!
  body=$(< "$TMPD/ipinfo")
  [[ $body =~ \"ip\":\ *\"([^\"]*)\" ]] && PUB_IP=${BASH_REMATCH[1]}
  [[ $body =~ \"country\":\ *\"([^\"]*)\" ]] && cc=${BASH_REMATCH[1]}
  [[ $body =~ \"city\":\ *\"([^\"]*)\" ]] && city=${BASH_REMATCH[1]}
  [[ $body =~ \"org\":\ *\"([^\"]*)\" ]] && org=${BASH_REMATCH[1]}
  if [[ ! $PUB_IP =~ $re ]]; then
    curl -fsS -m 5 --max-filesize 1000 "$IP_URL2" > "$TMPD/ipinfo" 2>/dev/null < /dev/null & wait $!
    PUB_IP=$(< "$TMPD/ipinfo")
    [[ $PUB_IP =~ $re ]] || PUB_IP=""
    return
  fi
  org=${org#AS[0-9]* }                          # "AS64500 EXAMPLE TEL..." -> "EXAMPLE TEL..."
  org=${org%.}
  for sfx in " S.A.U" " S.A" " S.L" " SAU" " SA" " SL" ", Inc" " Inc" " LLC" " Ltd" \
             " GmbH" " AG" " B.V"; do
    [[ $org == *"$sfx" ]] && { org=${org%"$sfx"}; break; }
  done
  ascii "$cc${city:+ $city}${org:+, $org}"; PUB_LOC=${A:0:33}
}

# The first 5 hops to the internet target, on Windows.
trace_win() {
  tracert -d -h 5 -w 1000 "$INET_TARGET"
}

# The first 5 hops to the internet target, on macOS.
trace_mac() {
  traceroute -n -m 5 -q 1 -w 1 "$INET_TARGET"
}

# The first 5 hops to the internet target, on Linux.
trace_linux() {
  traceroute -n -m 5 -q 1 -w 1 "$INET_TARGET"
}

# Set CGN to 1 if a hop after the local router is in 100.64.0.0/10, the
# shared space of carrier-grade NAT. Skipped through a VPN, whose hops may
# use the same space (Tailscale does).
cgnat_check() {
  local line n=0 re='^[0-9]+[[:space:]][^.]*[^0-9.]([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+'
  CGN=0
  (( TUN )) && return
  trace_$OS > "$TMPD/trace" 2>&1 < /dev/null & wait $!
  while read -r line; do           # "2  10.20.30.40  2.5 ms" or, on Windows,
    line=" ${line//$'\r'/}"        # "2  2 ms  2 ms  2 ms  10.20.30.40"
    [[ ${line# } =~ ^[0-9]+[[:space:]] ]] || continue
    (( n++ )); (( n == 1 )) && continue          # hop 1 is the local router
    [[ ${line# } =~ $re ]] || continue
    (( 10#${BASH_REMATCH[1]} == 100 && 10#${BASH_REMATCH[2]} >= 64 &&
       10#${BASH_REMATCH[2]} < 128 )) && CGN=1
  done < "$TMPD/trace"
}

# Background loop: write "address|cgnat|place" to $RES.ip every IP_S
# seconds and at once when the network or a VPN changes. Address "-" is
# unknown and "~" means it is asking again.
ip_checker() {
  local ip=- loc="" key old="" next=0 ok=0
  bg_init
  while kill -0 "$MAIN_PID" 2>/dev/null; do
    gateway
    if_addr "$WIFI_IF"; key="$IFA $GW $GW_IF $TUN"
    if [[ $key != "$old" ]] || (( SECONDS >= next )); then
      [[ -n $old && $key != "$old" ]] && { ip=-; loc=""; write_file "$RES.ip" "~|0|"; }
      old=$key
      public_ip
      if [[ -n $PUB_IP ]]; then ip=$PUB_IP; loc=$PUB_LOC; ok=$SECONDS
      elif (( SECONDS - ok > 2 * IP_S )); then ip=-; loc=""   # too old to show
      fi
      # show the address before the slower CG-NAT check
      [[ $(< "$RES.ip") == "~|0|" || ! -s $RES.ip ]] && write_file "$RES.ip" "$ip|0|$loc"
      cgnat_check
      write_file "$RES.ip" "$ip|$CGN|$loc"
      if [[ -n $PUB_IP ]]; then next=$(( SECONDS + IP_S )); else next=$(( SECONDS + 30 )); fi
    fi
    nap 10
  done
}

# Set DL_KBPS to the download speed in kbit/s (-1 failed).
speed_test() {
  local b=""
  curl -fsS -o /dev/null -m $SPEED_MAX_S -w '%{speed_download}' \
    "${SPEED_URL}$(( SPEED_MB * 1000000 ))" > "$TMPD/speed" 2>/dev/null < /dev/null & wait $!
  read -r b < "$TMPD/speed"
  b=${b%%[.,]*}
  if [[ $b =~ ^[0-9]+$ ]] && (( b > 0 )); then DL_KBPS=$(( b * 8 / 1000 )); else DL_KBPS=-1; fi
}

# Background loop: write "round kbit/s" to $RES.speed every SPEED_S seconds
# (0 kbit/s while measuring). $TMPD/busy exists during the download.
speed_checker() {
  local seq=0
  bg_init
  nap 3                          # after the first pings
  while kill -0 "$MAIN_PID" 2>/dev/null; do
    write_file "$RES.speed" "$seq 0"
    : > "$TMPD/busy"
    speed_test; (( seq++ ))
    rm -f "$TMPD/busy"
    write_file "$RES.speed" "$seq $DL_KBPS"
    nap $SPEED_S
  done
}

# median N...: set MED to the median of the values that are not negative
# (-1 if none).
median() {
  local -a ok=()
  local r i
  for r; do                          # insertion sort: at most PINGS values
    (( r < 0 )) && continue
    for (( i = ${#ok[@]}; i > 0 && ok[i-1] > r; i-- )); do ok[i]=${ok[i-1]}; done
    ok[i]=$r
  done
  i=${#ok[@]}; MED=-1
  (( i )) && MED=$(( (ok[(i-1)/2] + ok[i/2]) / 2 ))
}

# classify_link ZERO SLOW LOSS NEED LOSS_WARN IS_GATEWAY INET_UP: set ST to
# the state of a link: 0 up, 1 degraded, 2 down, 3 a gateway that ignores
# pings while the internet answers. ZERO: rounds in a row with no reply;
# SLOW: rounds in a row at or above the latency warning, NEED of which make
# it degraded; LOSS and LOSS_WARN in %.
classify_link() {
  if (( $1 >= DOWN_ROUNDS )); then
    ST=2; (( $6 && $7 )) && ST=3
  elif (( $2 >= $4 || $3 > $5 )); then ST=1
  else ST=0
  fi
}

# checker [ROUNDS]: background loop that pings every CHECK_S seconds and
# writes one line to $RES: round, gateway (- if none), 1 if wired, local
# address (- if none), then per link state, latency, loss %, jitter,
# traffic level, traffic kbit/s (-1 unknown) and the PINGS round trips
# (-1 lost). With ROUNDS it stops after that many.
checker() {
  local i j r t0 st lat loss lost sent L seq=0 out lip wifi med need lw busy
  LOSTH=(); ZERO=(); PLAT=(); SLOW=()
  bg_init
  while kill -0 "$MAIN_PID" 2>/dev/null && (( seq < ${1:-0} || ${1:-0} == 0 )); do
    t0=$SECONDS; busy=0
    # during a speed test the delay and loss are not the link's
    [[ -e $TMPD/busy ]] && busy=1
    gateway; if_rate
    HOSTS=("$INET_TARGET" "$GW" "$INET_ALT")
    for (( i = 0; i < ${#HOSTS[@]}; i++ )); do
      if [[ -n ${HOSTS[i]} ]]; then ping_host "${HOSTS[i]}" > "$TMPD/p$i" 2>&1 &
      else : > "$TMPD/p$i"
      fi
    done
    wait
    [[ -e $TMPD/busy ]] && busy=1
    (( seq++ ))
    if_addr "$GW_IF"; lip=$IFA
    out="$seq ${GW:--} 0 ${lip:--}"; wifi=1
    [[ -n $GW_IF && $GW_IF != "$WIFI_IF" ]] && { out="$seq $GW 1 ${lip:--}"; wifi=0; }
    if (( wifi )); then need=$WIFI_SLOW_ROUNDS; lw=$WIFI_LOSS_WARN; else need=1; lw=$LOSS_WARN; fi
    for (( j = 0; j < NL; j++ )); do
      ping_parse "$TMPD/p$j"
      if (( j == 0 )); then          # the internet: the better of its two
        r=$P_OK; ping_parse "$TMPD/p$NL"   # targets, the first on a tie
        (( P_OK > r )) || ping_parse "$TMPD/p0"
      fi
      if (( ! busy )); then
        for (( r = LOSS_ROUNDS - 1; r > 0; r-- )); do
          LOSTH[j*LOSS_ROUNDS+r]=${LOSTH[j*LOSS_ROUNDS+r-1]}
        done
        LOSTH[j*LOSS_ROUNDS]=$(( PINGS - P_OK ))
      fi
      lost=0; sent=0
      for (( r = 0; r < LOSS_ROUNDS; r++ )); do
        [[ -n ${LOSTH[j*LOSS_ROUNDS+r]} ]] || continue
        (( lost += LOSTH[j*LOSS_ROUNDS+r], sent += PINGS ))
      done
      loss=0; (( sent )) && loss=$(( (lost * 100 + sent / 2) / sent ))
      if (( P_OK )); then
        ZERO[j]=0; PLAT[j]=$(( P_SUM / P_OK ))
        med=${PLAT[j]}
        (( wifi )) && { median "${P_RTT[@]}"; med=$MED; }
        if (( busy )); then :
        elif (( med >= LAT_WARN[j] )); then SLOW[j]=$(( ${SLOW[j]:-0} + 1 ))
        else SLOW[j]=0
        fi
      else ZERO[j]=$(( ${ZERO[j]:-0} + 1 ))
      fi
      lat=-1; (( P_OK )) && lat=${PLAT[j]}
      classify_link ${ZERO[j]} ${SLOW[j]:-0} $loss $need $lw \
        $(( j == 1 && ${#GW} > 0 )) $(( ZERO[0] == 0 )); st=$ST
      (( st == 3 )) && lat=-1
      traffic_level $RATE ${LINK_MBPS[j]}
      out+=" $st $lat $loss $P_JIT $L $(( RATE < 0 ? -1 : RATE / 1000 )) ${P_RTT[*]}"
    done
    write_file "$RES" "$out"
    round_sleep $CHECK_S $t0
  done
}

# Print the tools this system needs and those that are missing.
needs() {
  local t miss="" all="ping curl nslookup iconv"
  case $OS in
    mac)   all+=" netstat ipconfig networksetup system_profiler traceroute" ;;
    linux) all+=" ip traceroute" ;;
    win)   all+=" netsh ipconfig tracert" ;;
  esac
  [[ -z $EPOCHREALTIME ]] && all+=" perl"
  for t in $all; do command -v "$t" > /dev/null 2>&1 || miss+=" $t"; done
  echo "tools needed: $all"
  echo "missing:${miss:- none}"
}

# --check: read every source once, print it as text and exit.
run_check() {
  export LC_ALL=C
  echo "bash $BASH_VERSION on $OS, Wi-Fi interface: ${WIFI_IF:-none}"
  needs
  wifi_poll; echo "Wi-Fi (state|name|pad|security|level|GHz|channel|signal|noise|Mb/s|mode):"
  echo "  $WIFI"
  gateway; echo "gateway: ${GW:-none}"
  echo "  through $GW_IF ($( [[ $GW_IF == "$WIFI_IF" ]] && echo Wi-Fi || echo cable))"
  if_rate; sleep 2; if_rate; echo "traffic: $RATE bit/s"
  public_ip; cgnat_check
  echo "public IP: ${PUB_IP:-unknown}, ${PUB_LOC:-place unknown}, possible CG-NAT: $CGN"
  for h in "$INET_TARGET" "$GW" "$INET_ALT"; do
    [[ -n $h ]] || continue
    ping_host "$h" > "$TMPD/p" 2>&1
    ping_parse "$TMPD/p"; echo "ping $h: ${P_RTT[*]} ms, jitter $P_JIT ms"
  done
  if (( SPEED_ON )); then speed_test; echo "download speed: $DL_KBPS kbit/s"; fi
  echo "Background process, 2 rounds of $CHECK_S s:"
  ( checker 2 ) < /dev/null > /dev/null 2>> "$LOG" &
  wait $!
  echo "  result: $(cat "$RES")"
  CHECK_PID=
  exit 0
}

# Start the background loops, without the clock's file descriptors.
start_checkers() {
  checker < /dev/null > /dev/null 2>> "$LOG" 3<&- 4>&- 5<&- &
  CHECK_PID=$!
  dns_checker < /dev/null > /dev/null 2>> "$LOG" 3<&- 4>&- 5<&- &
  CHECK_PID="$CHECK_PID $!"
  ip_checker < /dev/null > /dev/null 2>> "$LOG" 3<&- 4>&- 5<&- &
  CHECK_PID="$CHECK_PID $!"
  wifi_checker < /dev/null > /dev/null 2>> "$LOG" 3<&- 4>&- 5<&- &
  CHECK_PID="$CHECK_PID $!"
  if (( SPEED_ON )); then
    speed_checker < /dev/null > /dev/null 2>> "$LOG" 3<&- 4>&- 5<&- &
    CHECK_PID="$CHECK_PID $!"
  fi
}

# push_samples ROW FIRST_FIELD: append the PINGS samples of R from
# FIRST_FIELD to the latency history of link ROW.
push_samples() {
  local b=$(( $1 * HW )) x
  for (( x = 0; x < HW - PINGS; x++ )); do SH[b+x]=${SH[b+x+PINGS]}; done
  for (( x = 0; x < PINGS; x++ )); do SH[b+HW-PINGS+x]=${R[$2+x]}; done
}

# ints "N N ...": true if every word is an integer.
ints() {
  [[ " $1 " =~ $INTS_RE ]]
}

# Read the results files twice a second and take in what is new. Every
# field used in arithmetic is checked to be a number first: bash evaluates
# a variable's text there, and a[$(cmd)] would run cmd.
results() {
  local slot=$(( T / 500 )) j o ln
  local -a a
  (( slot == RES_SLOT )) && return
  RES_SLOT=$slot
  RD=()
  read -r -a RD 2>/dev/null < "$RES.dns"
  (( ${#RD[@]} == 3 )) && ints "${RD[0]} ${RD[1]}" && (( RD[0] != DSEQ )) &&
    { DSEQ=${RD[0]}; DNS_ST=${RD[1]}; DNS_SERVER=${RD[2]}; }
  ln=""; read -r ln 2>/dev/null < "$RES.ip"
  if [[ -n $ln ]]; then
    IFS='|' read -r PUB CGNAT PLACE <<< "$ln"; [[ $CGNAT == 1 ]] || CGNAT=0
  fi
  ln=""; read -r ln 2>/dev/null < "$RES.wifi"
  if [[ -n $ln ]]; then
    IFS='|' read -r -a a <<< "$ln"
    (( ${#a[@]} >= 2 )) && ints "${a[W_SEQ]} ${a[W_STATE]} ${a[W_PAD]:-0} ${a[W_SECLV]:-0} ${a[W_SIG]:-0} ${a[W_NOISE]:-0}" &&
      W=("${a[@]}")
  fi
  RD=()
  read -r -a RD 2>/dev/null < "$RES.speed"
  (( ${#RD[@]} == 2 )) && ints "${RD[*]}" && { SPD_SEQ=${RD[0]}; SPD=${RD[1]}; }
  R=()
  read -r -a R 2>/dev/null < "$RES"
  (( ${#R[@]} == NFIELDS )) && ints "${R[0]} ${R[2]} ${R[*]:4}" && (( R[0] != SEQ )) || return
  SEQ=${R[0]}; GWIP=${R[1]}; WIRED=${R[2]}; LIP=${R[3]}; DASH[1]=$(( ! WIRED )); o=4
  for (( j = 0; j < NL; j++ )); do
    STATE[j]=${R[o]}; LAT[j]=${R[o+1]}; LOSS[j]=${R[o+2]}; JIT[j]=${R[o+3]}
    TLV[j]=${R[o+4]}; KBPS[j]=${R[o+5]}
    push_samples $j $(( o + 6 )); (( o += 6 + PINGS ))
  done
}

# fmt_speed KBIT/S: set SPEED to it in at most 4 characters ("940k", "8.2M").
fmt_speed() {
  local k=$1
  if (( k < 0 )); then SPEED="--"
  elif (( k < 1000 )); then SPEED="${k}k"
  elif (( k < 10000 )); then SPEED="$(( k / 1000 )).$(( k / 100 % 10 ))M"
  elif (( k < 1000000 )); then SPEED="$(( k / 1000 ))M"
  else SPEED="$(( k / 1000000 )).$(( k / 100000 % 10 ))G"
  fi
}

# traffic_meter LINK STATE WIDTH: set CELL to a Braille traffic meter that
# flows left to right, as high as the measured traffic level.
traffic_meter() {
  local j=$1 s=$2 TW=$3 x ph v L=${TLV[$1]}
  CELL=""
  if (( s == 2 )); then
    for (( x = 0; x < TW; x++ )); do CELL+="${RAMP[RED+2]}⣀"; done
    return
  fi
  if (( L < 0 )); then               # no data yet: a still, faint line
    for (( x = 0; x < TW; x++ )); do CELL+="${RAMP[s*9+1]}⣀"; done
    return
  fi
  if (( s == 0 )); then ph=$(( T / 60 )); else ph=$(( T / 130 )); fi
  for (( x = 0; x < TW; x++ )); do
    H=$(( ph - x + 1000 + j * 977 )); H=$(( (((H * 2654435761) ^ (H * 40503 >> 3)) >> 11) & 255 ))
    # always moving: each level flickers with the one above it
    if (( L == 0 )); then v=$(( H % 3 != 0 ))
    elif (( L == 4 )); then v=$(( 4 - (H % 3 == 0) ))
    else v=$(( L + H % 2 ))
    fi
    CELL+="${RAMP[s*9+3+v]}${BRAILLE[v]}"
  done
}

# ping_meter LINK STATE WIDTH: set CELL to a latency sparkline of the last
# WIDTH samples, newest on the right.
ping_meter() {
  local j=$1 s=$2 TW=$3 x v r b w=${LAT_WARN[$1]} c=${LAT_CRIT[$1]}
  CELL=""
  if (( s == 2 )); then
    blink $(( RED + 8 )) $(( RED + 3 ))
    for (( x = 0; x < TW; x++ )); do
      if (( x == TW / 2 )); then CELL+="${RAMP[BL]}✕"; else CELL+="${RAMP[RED+1]}·"; fi
    done
    return
  fi
  b=$(( j * HW + HW - TW ))
  for (( x = 0; x < TW; x++ )); do
    r=${SH[b+x]}
    if (( r == -2 )); then CELL+="${RAMP[s*9+1]}${SPARK[0]}"   # no sample yet
    elif (( r == -1 )); then CELL+="${RAMP[RED+6]}✕"           # lost ping
    else
      v=$(( r * 6 / c )); (( v > 7 )) && v=7  # the red threshold is ▇
      if (( r >= c )); then CELL+="${RAMP[RED+6]}${SPARK[v]}"
      elif (( r >= w )); then CELL+="${RAMP[AMBER+6]}${SPARK[v]}"
      else CELL+="${RAMP[GREEN+6]}${SPARK[v]}"
      fi
    fi
  done
}

# wline ASCII_LENGTH STRING: set WL to a Wi-Fi box row padded to the box.
# STRING holds colours, so the callers cut it to 22 characters.
wline() {
  local p
  printf -v p '%*s' $(( 22 - $1 < 0 ? 0 : 22 - $1 )) ''
  WL="${BOX_COLOR}│ $2${RESET}${p} ${BOX_COLOR}│"
}

# Set TROWS and TCOLS to the terminal size (0 0 if unknown).
term_size() {
  local sz
  sz=$(stty size 2>/dev/null) || sz=""
  TROWS=${sz% *}; TCOLS=${sz#* }
  [[ $TROWS =~ ^[0-9]+$ && $TCOLS =~ ^[0-9]+$ ]] || { TROWS=0; TCOLS=0; }
}

# True if the screen fits the terminal, or its size is unknown.
fits() {
  term_size
  (( TROWS == 0 || (TROWS >= LINES_N && TCOLS >= NEED_COLS) ))
}

# Say on a cleared screen that the window is too small.
too_small() {
  printf '%s' "${ESC}[H${ESC}[2J${RESET}coSHLink needs ${NEED_COLS}x${LINES_N}; this window is ${TCOLS}x${TROWS}."
}

# Make room for the screen without scrolling: the last line gets no newline.
reserve_lines() {
  local i
  for (( i = 1; i < LINES_N; i++ )); do echo; done
}

# spin OFFSET: set SP to the current spinner frame, shifted by OFFSET.
spin() {
  SP=${SPIN[$(( (T / SPIN_MS + $1) % ${#SPIN[@]} ))]}
}

# to_line LINE: add to out the cursor move from line CUR to LINE.
to_line() {
  if (( $1 > CUR )); then out+="${ESC}[$(( $1 - CUR ))B"
  elif (( $1 < CUR )); then out+="${ESC}[$(( CUR - $1 ))A"
  fi
  CUR=$1
}

# map_seg ROW COL: set SEG to the map cells of ROW from COL to the end.
map_seg() {
  local k last="" c
  SEG=""
  for (( c = $2, k = $1 * COLS + $2; c < COLS; c++, k++ )); do
    [[ ${GCO[k]} != "$last" ]] && { last=${GCO[k]}; SEG+=$last; }
    SEG+=${GCH[k]}
  done
}

# Build the status box rows, top left, with the overall state.
render_status() {
  inet_down=$(( SEQ && STATE[0] == 2 ))
  if (( SEQ == 0 )); then             # first round still running
    spin 0; icon="${SPIN_COLOR}${SP}"; msg="checking"
  elif (( inet_down )); then
    icon="${RAMP[RED+7]}${BOLD}○"
    if (( WIRED )); then
      if (( STATE[1] == 2 )); then msg="gateway down"; else msg="no internet"; fi
    elif (( wst == 2 )); then msg="Wi-Fi off"
    elif (( wst == 1 || wst == 3 )); then msg="no Wi-Fi"
    elif (( STATE[1] == 2 )); then msg="gateway down"
    else msg="no internet"
    fi
  elif (( STATE[0] == 1 )); then icon="${RAMP[AMBER+7]}${BOLD}◐"; msg="internet degraded"
  elif (( STATE[1] == 1 )); then
    icon="${RAMP[AMBER+7]}${BOLD}◐"; if (( WIRED )); then msg="LAN degraded"; else msg="Wi-Fi degraded"; fi
  else icon="${RAMP[GREEN+7]}${BOLD}●"; msg="online"
  fi
  printf -v pad '%*s' $(( SBOX_IN - 4 - ${#msg} )) ''
  OV=(); OVC=()                      # box rows over the map: text and map column
  OV[0]="${BOX_COLOR}${SBOX_TOP}"
  OV[1]="${BOX_COLOR}│ ${icon} ${msg}${RESET}${pad} ${BOX_COLOR}│"
  OV[2]="${BOX_COLOR}${SBOX_BOT}"
  OVC[0]=0; OVC[1]=0; OVC[2]=0
}

# Draw the wires, the globe, the computer screen and the gateway lights.
render_map() {
  for (( j = 0; j < NL; j++ )); do
    s=${STATE[j]}; (( s == 3 )) && s=1
    if (( SEQ )); then draw_wire $j $s; else still_wire $j; fi
  done
  if (( inet_down )); then           # red, blinking globe
    blink $(( RED + 6 )) $(( RED + 2 )); gc=${RAMP[BL]}; tc="${RAMP[RED+7]}${BOLD}"
  else gc=$C_o; tc=$NAME_COLOR
  fi
  if [[ "$gc$tc" != "$GLOBE_KEY" ]]; then
    GLOBE_KEY="$gc$tc"
    for k in "${GLOBE_CELLS[@]}"; do setc $k "${GCH[k]}" "$gc"; done
    for k in "${INET_CELLS[@]}"; do setc $k "${GCH[k]}" "$tc"; done
  fi
  draw_screen
  # gateway lights: a soft yellow flicker while it answers, red when down
  s=${STATE[1]}; (( s == 3 )) && s=1
  key="$SEQ $s $(( T / 250 )) $(( T / 400 % 2 ))"
  if [[ $key != "$LIGHT_KEY" ]]; then
    LIGHT_KEY=$key
    for (( k = 0; k < 3; k++ )); do
      c=$(( AP_C + 2 + k * 2 ))
      if (( SEQ == 0 )); then put $(( AP_R + 3 )) $c "▪" "$DIM_COLOR"
      elif (( s == 2 )); then blink $(( RED + 7 )) $(( RED + 2 )); put $(( AP_R + 3 )) $c "▪" "${RAMP[BL]}"
      else
        H=$(( T / 250 + k * 13 )); H=$(( (((H * 2654435761) ^ (H * 40503 >> 3)) >> 11) & 255 ))
        put $(( AP_R + 3 )) $c "▪" "${LED_YEL[H%5]}"
      fi
    done
    if (( WIN )); then               # the tower's power light
      rnd $(( T / 250 + 3 * 13 ))
      put $(( MAC_R + 3 )) $(( MAC_C - 2 )) "▪" "${LED_RED[H%5]}"
    fi
  fi
}

# Draw the texts around the map (addresses, DNS, public IP, CG-NAT and
# speed), only when what they show changes.
render_info() {
  key="$GWIP|$LIP|$DSEQ $DNS_ST $DNS_SERVER|$PUB|$PLACE|$CGNAT|$SPD_SEQ $SPD"
  (( DSEQ == 0 || DNS_ST == 2 || CGNAT )) && key+=" $(( T / 400 ))"
  [[ -z $PUB || $PUB == "~" || ( SPEED_ON -eq 1 && ( SPD_SEQ -lt 0 || SPD -eq 0 ) ) ]] && key+=" $(( T / SPIN_MS ))"
  (( DSEQ == 0 )) && key+=" $(( T / SPIN_MS ))"
  if [[ $key != "$INFO_KEY" ]]; then
    INFO_KEY=$key
    # gateway and computer addresses, under their drawings
    clear_cells $(( TOP + 6 )) $(( MID_C - 8 )) 17
    [[ -n $GWIP && $GWIP != - ]] && center $(( TOP + 6 )) $(( MID_C - 7 )) 15 "$GWIP" "$LABEL_COLOR"
    clear_cells $(( TOP + 6 )) $MAC_C 15
    [[ -n $LIP && $LIP != - ]] && center $(( TOP + 6 )) $MAC_C 15 "$LIP" "$LABEL_COLOR"
    # DNS state, under the INTERNET label
    if (( DSEQ == 0 )); then
      spin 5; ic=$SP; co=$SPIN_COLOR; msg="DNS"; mc=$LABEL_COLOR
    else
      case $DNS_ST in
        0) ic=●; co=${RAMP[GREEN+7]}; msg="DNS ok" ;;
        1) ic=◐; co=${RAMP[AMBER+7]}; msg="DNS partial" ;;
        2) blink $(( RED + 8 )) $(( RED + 3 )); ic=○; co=${RAMP[BL]}; msg="DNS fail" ;;
        *) ic=·; co=$LABEL_COLOR; msg="DNS ?" ;;
      esac
      mc=$co
    fi
    clear_cells 1 $INFO_C 33
    put 1 $INFO_C "$ic" "$co"
    text 1 $(( INFO_C + 2 )) "$msg" "$mc"
    # the DNS server: the gateway, a well-known public one, or its address
    if (( DSEQ )) && [[ $DNS_SERVER != - ]]; then
      case $DNS_SERVER in
        "$GWIP")                 t="gateway" ;;
        1.1.1.1|1.0.0.1)         t="Cloudflare" ;;
        8.8.8.8|8.8.4.4)         t="Google" ;;
        9.9.9.9|149.112.112.112) t="Quad9" ;;
        208.67.222.222|208.67.220.220) t="OpenDNS" ;;
        *)                       t=$DNS_SERVER ;;
      esac
      [[ $t != "$DNS_SERVER" ]] && t+=" $DNS_SERVER"
      put 1 $(( INFO_C + 3 + ${#msg} )) "·" "$LABEL_COLOR"   # not ASCII: one cell
      text 1 $(( INFO_C + 5 + ${#msg} )) "${t:0:$(( 26 - ${#msg} ))}" "$LABEL_COLOR"
    fi
    # public IP, then its place and operator
    clear_cells 2 $(( INFO_C + 13 )) 20
    clear_cells 3 $(( INFO_C + 2 )) 31
    if [[ -z $PUB || $PUB == "~" ]]; then
      spin 7; put 2 $(( INFO_C + 13 )) "$SP" "$SPIN_COLOR"
    elif [[ $PUB == - ]]; then text 2 $(( INFO_C + 13 )) "?" "$LABEL_COLOR"
    else
      text 2 $(( INFO_C + 13 )) "$PUB" "$LABEL_COLOR"
      text 3 $(( INFO_C + 2 )) "${PLACE:0:31}" "$LABEL_COLOR"
    fi
    clear_cells 4 $(( INFO_C + 2 )) 15
    if (( CGNAT )); then
      blink $(( AMBER + 8 )) $(( AMBER + 3 )); text 4 $(( INFO_C + 2 )) "Possible CG-NAT" "${RAMP[BL]}"
    fi
    # download speed (--speed)
    if (( SPEED_ON )); then
      clear_cells 5 $INFO_C 33
      put 5 $INFO_C "↓" "$LABEL_COLOR"
      if (( SPD_SEQ < 0 || SPD == 0 )); then
        spin 3; put 5 $(( INFO_C + 2 )) "$SP" "$SPIN_COLOR"
        text 5 $(( INFO_C + 4 )) "measuring speed" "$LABEL_COLOR"
      elif (( SPD < 0 )); then text 5 $(( INFO_C + 2 )) "speed test failed" "$LABEL_COLOR"
      else
        t="$(( SPD / 1000 )).$(( SPD / 100 % 10 )) Mb/s"
        text 5 $(( INFO_C + 2 )) "$t" "$NAME_COLOR"
        text 5 $(( INFO_C + 3 + ${#t} )) "download" "$LABEL_COLOR"
      fi
    fi
  fi
}

# Build the Wi-Fi box rows, over the right of the map: name, signal, rate
# and mode, security and band. On a cable, and until the first round tells
# cable from Wi-Fi, the map under it is shown instead.
render_wifi_box() {
  nobox=$(( WIRED || SEQ == 0 ))
  key="${W[*]}"
  (( wst < 0 )) && key+=" $(( T / SPIN_MS ))"
  (( (wst > 0 && wst < 4) || W[W_SECLV] == 2 )) && key+=" $(( T / 400 % 2 ))"
  (( nobox )) && key=hidden
  if [[ $key != "$WBOX_KEY" ]]; then
    WBOX_KEY=$key
    WBOXL=("${BOX_COLOR}${WBOX_TOP}")
    if (( nobox )); then
      WBOXL=()
      for k in 0 1 2 3 4 5; do map_seg $(( WBOX_R + k )) $WBOX_C; WBOXL+=("$SEG"); done
    elif (( wst < 0 )); then
      spin 2; wline 9 "${SPIN_COLOR}${SP} ${LABEL_COLOR}reading"; WBOXL+=("$WL")
      for k in 1 2 3; do wline 0 ""; WBOXL+=("$WL"); done
    elif (( wst == 4 )); then
      wline 19 "${LABEL_COLOR}· no details on Linux"; WBOXL+=("$WL")
      for k in 1 2 3; do wline 0 ""; WBOXL+=("$WL"); done
    elif (( wst != 0 )); then
      case $wst in 2) msg="Wi-Fi off" ;; 3) msg="no Wi-Fi interface" ;; *) msg="not connected" ;; esac
      blink $(( RED + 8 )) $(( RED + 3 ))
      wline $(( 2 + ${#msg} )) "${RAMP[BL]}○ ${RAMP[RED+7]}${msg}"; WBOXL+=("$WL")
      for k in 1 2 3; do wline 0 ""; WBOXL+=("$WL"); done
    else
      # signal: 4 bars lit by its strength, green, amber or red
      sig=${W[W_SIG]}; noise=${W[W_NOISE]}; nb=0; bc=2
      if [[ -n $sig ]]; then
        if (( sig >= SIG_DBM[0] )); then nb=4; bc=0
        elif (( sig >= SIG_DBM[1] )); then nb=3; bc=0
        elif (( sig >= SIG_DBM[2] )); then nb=2; bc=1
        elif (( sig >= SIG_DBM[3] )); then nb=1
        fi
      fi
      if [[ -n ${W[W_NAME]} ]]; then
        printf -v p '%*s' "${W[W_PAD]:-0}" ''
        wline 20 "${RAMP[bc*9+7]}● ${NAME_COLOR}${W[W_NAME]}${p}"
      else
        wline 15 "${RAMP[bc*9+7]}● ${LABEL_COLOR}(name hidden)"
      fi
      WBOXL+=("$WL")
      # bars, dBm and the signal to noise ratio
      bars=""
      for (( k = 0; k < 4; k++ )); do
        if (( k < nb )); then bars+="${RAMP[bc*9+7]}${BARS[k]}"; else bars+="${DIM_COLOR}${BARS[k]}"; fi
      done
      if [[ -n $sig ]]; then
        t2="$sig dBm"; [[ -n $noise ]] && t2+="  SNR $(( sig - noise ))"
      else t2="--"
      fi
      wline $(( 5 + ${#t2} )) "${bars} ${LABEL_COLOR}${t2}"; WBOXL+=("$WL")
      t3=""; [[ -n ${W[W_RATE]} ]] && t3="${W[W_RATE]} Mb/s"
      [[ -n ${W[W_MODE]} ]] && t3+="${t3:+  }${W[W_MODE]}"
      t3=${t3:0:22}; wline ${#t3} "${LABEL_COLOR}${t3}"; WBOXL+=("$WL")
      # security, amber if weak, blinking red if open; then band and channel
      if (( W[W_SECLV] == 2 )); then blink $(( RED + 8 )) $(( RED + 3 )); scol=${RAMP[BL]}
      elif (( W[W_SECLV] == 1 )); then scol=${RAMP[AMBER+7]}
      else scol=$LABEL_COLOR
      fi
      sec=${W[W_SEC]:-?}; band=""
      if [[ -n ${W[W_CH]} ]]; then
        if [[ ${W[W_BAND]} == 2.4 ]]; then band="2.4GHz  ch ${W[W_CH]}"; else band="${W[W_BAND]} GHz  ch ${W[W_CH]}"; fi
        (( ${#sec} + 2 + ${#band} > 22 )) && band="${W[W_BAND]}GHz ch${W[W_CH]}"   # tighter
      fi
      sec=${sec:0:$(( 20 - ${#band} ))}  # nothing may push the box edge
      wline $(( ${#sec} + 2 + ${#band} )) "${scol}${sec}  ${LABEL_COLOR}${band}"; WBOXL+=("$WL")
    fi
    (( nobox )) || WBOXL+=("${BOX_COLOR}${WBOX_BOT}")
  fi
  for (( k = 0; k < ${#WBOXL[@]}; k++ )); do
    OV[WBOX_R+k]=${WBOXL[k]}; OVC[WBOX_R+k]=$WBOX_C
  done
}

# Build the traffic box and the panel rows, one per link.
render_panel() {
  # traffic box: the meter, then the speed, in the internet link's colour
  vs=${STATE[0]}; (( vs == 3 )) && vs=1
  traffic_meter 0 $vs 14
  TBOX=("${BOX_COLOR}│ ${CELL}${BOX_COLOR} │")
  if (( KBPS[0] < 0 )); then spin 3; v="${SPIN_COLOR}${SP}"; k=1
  else fmt_speed ${KBPS[0]}; v="${RAMP[vs*9+7]}${SPEED}b/s"; k=$(( ${#SPEED} + 3 ))
  fi
  printf -v p '%*s' $(( 9 - k )) ''
  TBOX+=("${BOX_COLOR}│ ${LABEL_COLOR}speed${p}${v}${BOX_COLOR} │")

  # panel rows: the gateway first, then the internet
  PANEL=()
  for j in 1 0; do
    s=${STATE[j]}; vs=$s; (( vs == 3 )) && vs=1
    name=${LINK_NAME[j]}; st=${STATE_NAME[s]}
    (( SEQ )) || { spin $(( j + 6 )); st="  ${SPIN_COLOR}${SP}       "; }
    if (( SEQ == 0 )); then
      # spinners in the units place of latency, jitter and loss
      spin $j; info="   ${SPIN_COLOR}${SP}      "
      spin $(( j + 2 )); info+="${SP}     "
      spin $(( j + 4 )); info+="${SP}"
    elif (( s == 2 )); then
      spin $j; info="${SPIN_COLOR}${SP} ${RAMP[RED+7]}reconnecting…"
    elif (( s == 3 )); then
      info="${RAMP[AMBER+7]}  no ping reply"
    else
      lat=${LAT[j]}; (( lat > 9999 )) && lat=9999; (( lat < 0 )) && lat=--
      jit=${JIT[j]}; (( jit > 999 )) && jit=999; (( jit < 0 )) && jit=--
      # latency coloured by its own thresholds, jitter and loss by the
      # state (a Wi-Fi link up through a lone spike stays green)
      if (( s == 0 )); then lc=$(( GREEN + 7 ))
      elif (( LAT[j] >= LAT_CRIT[j] )); then lc=$(( RED + 7 ))
      elif (( LAT[j] >= LAT_WARN[j] )); then lc=$(( AMBER + 7 ))
      else lc=$(( GREEN + 7 ))
      fi
      printf -v lat '%4s ms' "$lat"; printf -v jit ' %3s ms' "$jit"
      printf -v info ' %3s%%' "${LOSS[j]}"
      info="${RAMP[lc]}${lat}${RAMP[vs*9+7]}${jit}${info}"
    fi
    ping_meter $j $vs 13               # odd width: the ✕ of a cut link centred
    PANEL+=("${SP2}${TBOX[1-j]} ${LABEL_COLOR}⇄ ${NAME_COLOR}${name} ${RAMP[vs*9+7]}${BOLD}${st} ${CELL} ${info}${RESET}${ESC}[K")
  done
}

# Send the frame to the terminal: every line the first time, then only the
# map cells, box rows and panel rows that changed. Lines start with ESC[G
# (column 1) rather than \r, which Git Bash can drop.
flush_frame() {
  if (( FIRST )); then
    FIRST=0
    out="${ESC}[$(( LINES_N - 1 ))A${ESC}[G${ESC}[K"$'\n'
    for (( r = 0; r < ROWS; r++ )); do
      line="${ESC}[G$SP2"; last=""; c=0; end=$COLS
      if [[ -n ${OV[r]} ]]; then
        if (( OVC[r] == 0 )); then line+=${OV[r]}; c=$SBOX_W; else end=${OVC[r]}; fi
      fi
      for (( k = r * COLS + c; c < end; c++, k++ )); do
        [[ ${GCO[k]} != "$last" ]] && { last=${GCO[k]}; line+=$last; }
        line+=${GCH[k]}
      done
      [[ -n ${OV[r]} ]] && (( OVC[r] )) && line+=${OV[r]}
      out+="${line}${RESET}${ESC}[K"$'\n'
      OV_PREV[r]=${OV[r]}
    done
    out+="${ESC}[K"$'\n'
    out+="${ESC}[G${SP2}${PANEL_HEAD}${RESET}${ESC}[K"$'\n'
    for (( j = 0; j < NL; j++ )); do out+="${ESC}[G${PANEL[j]}"$'\n'; PANEL_PREV[j]=${PANEL[j]}; done
    out+="${ESC}[G${SP2}${BOX_COLOR}${TBOX_BOT}${RESET}${ESC}[K"$'\n'
    out+="${ESC}[G${BUILD_COLOR}${BUILD_LINE}${RESET}${ESC}[K"
  else
    # line 0 is the blank line on top, map row r is line r + 1
    out="${ESC}[G${ESC}[$(( LINES_N - 1 ))A"; CUR=0; last=""
    for k in "${CHG[@]}"; do
      # cells under a box stay hidden: the box is sent only when it changes
      r=$(( k / COLS )); c=$(( k % COLS ))
      (( r < 3 && c < SBOX_W )) && continue
      (( ! nobox && r >= WBOX_R && r < WBOX_R + 6 && c >= WBOX_C )) && continue
      to_line $(( r + 1 ))
      out+="${ESC}[$(( k % COLS + 3 ))G"
      [[ ${GCO[k]} != "$last" ]] && { last=${GCO[k]}; out+=$last; }
      out+=${GCH[k]}
    done
    for r in "${!OV[@]}"; do
      [[ ${OV[r]} == "${OV_PREV[r]}" ]] && continue
      OV_PREV[r]=${OV[r]}
      to_line $(( r + 1 ))
      out+="${ESC}[$(( OVC[r] + 3 ))G${OV[r]}${RESET}"; last=""
    done
    for (( j = 0; j < NL; j++ )); do
      [[ ${PANEL[j]} == "${PANEL_PREV[j]}" ]] && continue
      PANEL_PREV[j]=${PANEL[j]}
      to_line $(( ROWS + 3 + j ))    # after the header line
      out+="${ESC}[G${PANEL[j]}"
    done
    to_line $(( LINES_N - 1 ))
  fi
  CHG=()
  printf '%s' "$out"
}

# The animation: one frame per turn, until RUN_S seconds or Ctrl+C.
main_loop() {
  while :; do
    if (( RESUMED )); then RESUMED=0; reserve_lines; FIRST=1; fi
    if (( RESIZED )); then            # the window changed: clear it and
      RESIZED=0                       # redraw everything from the top
      if fits; then printf '%s' "${ESC}[H${ESC}[2J"; reserve_lines; FIRST=1
      else too_small; RESIZED=2
      fi
    fi
    if (( RESIZED == 2 )); then sleep 0.2; continue; fi   # until it fits again
    clock_tick
    (( START < 0 )) && START=$NOW
    T=$(( NOW - START ))
    (( LOOP == 0 && T >= RUN_S * 1000 )) && break
    results
    wst=${W[W_STATE]:--1}             # Wi-Fi state, -1 not read yet

    render_status
    render_map
    render_info
    render_wifi_box
    render_panel
    flush_frame
    pause
  done
}

#
# ============================================================================
# Script
# ============================================================================
#

USAGE="Usage: ${0##*/} [--loop] [--speed] [--check] [--log FILE] [--256 | --truecolor]
  --loop       run forever (Ctrl+C to quit); default is RUN_S seconds
  --speed      measure the download speed every SPEED_S seconds (it
               downloads SPEED_MB MB each time: mind a metered connection)
  --check      read every source once, print what it returns and exit
               (no animation)
  --log FILE   append the errors of the background measures to FILE
               (they are discarded otherwise)
  --256        force 256 colors
  --truecolor  force 24-bit color
  --install    install it for this user as the command \"coshlink\"
  --uninstall  remove what --install added
  -h, --help   show this help"

# When sourced (". coSHLink.sh"), the script only defines its functions and
# settings; the options are read and the animation starts only when run.
LOOP=0; CHECK=0; SPEED_ON=0; COLOR_MODE=auto; LOG=/dev/null; ACTION=""
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then parse_args "$@"; fi

case $OSTYPE in
  darwin*)       OS=mac ;;
  msys*|cygwin*) OS=win ;;           # Git Bash
  *)             OS=linux ;;
esac
WIN=0; [[ $OS == win ]] && WIN=1
NL=2                                 # links: 0 internet, 1 gateway

# Marks of what --install writes, so --uninstall removes only that
PATH_MARK="# added by coSHLink --install"
CMD_MARK="coSHLink, added by coSHLink.sh --install"
if [[ -n $ACTION ]]; then ${ACTION}_app; exit 0; fi

ESC=$'\e'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"

# Colour mode: 24-bit where the terminal says so (COLORTERM) or is known to
# support it, 256 colours otherwise (Terminal of macOS 15 and earlier, tmux).
if [[ $COLOR_MODE == auto ]]; then
  COLOR_MODE=256
  case $COLORTERM in truecolor|24bit) COLOR_MODE=24 ;; esac
  case $TERM_PROGRAM in
    iTerm.app|WezTerm|ghostty|vscode|mintty) COLOR_MODE=24 ;;
    Apple_Terminal)
      macos=$(sw_vers -productVersion 2>/dev/null)
      [[ $macos =~ ^[0-9]+ ]] && (( ${macos%%.*} >= 26 )) && COLOR_MODE=24 ;;
  esac
  [[ $OS == win ]] && COLOR_MODE=24  # Windows Terminal and mintty
fi

# State colours: RAMP[s*9 + l] is state s (GREEN, AMBER, RED = 0, 9, 18: up,
# degraded, down) at brightness l (0-1 faint, 7 plain, 8 hot head). Every
# escape starts with 0, which also clears the bold of the text before.
BASE=(40 210 90   245 175 30   225 45 45)
RAMP=()
for (( s = 0; s < 3; s++ )); do
  r0=${BASE[s*3]}; g0=${BASE[s*3+1]}; b0=${BASE[s*3+2]}
  for (( l = 0; l < 8; l++ )); do
    rgb $(( 35 + (r0 - 35) * (l + 1) / 8 )) $(( 35 + (g0 - 35) * (l + 1) / 8 )) \
       $(( 35 + (b0 - 35) * (l + 1) / 8 ))
    RAMP[s*9+l]="${ESC}[0;${FG}m"
  done
  rgb $(( (r0 + 255) / 2 )) $(( (g0 + 255) / 2 )) $(( (b0 + 255) / 2 ))
  RAMP[s*9+8]="${ESC}[0;${FG}m"
done
GREEN=0; AMBER=9; RED=18
# Pilot lights, flickering between brightness 3 and 7: yellow for the
# gateway, red for the power light of the PC tower
LED_YEL=(); LED_RED=()
for (( l = 3; l < 8; l++ )); do
  rgb $(( 35 + 215 * (l + 1) / 8 )) $(( 35 + 180 * (l + 1) / 8 )) $(( 35 + 5 * (l + 1) / 8 ))
  LED_YEL+=("${ESC}[0;${FG}m")
  rgb $(( 35 + 200 * (l + 1) / 8 )) $(( 35 + 5 * (l + 1) / 8 )) $(( 35 + 5 * (l + 1) / 8 ))
  LED_RED+=("${ESC}[0;${FG}m")
done

SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
rgb 80 160 255; SPIN_COLOR="${ESC}[0;${FG}m"
SPIN_MS=60
rgb 120 124 135; BOX_COLOR="${ESC}[0;${FG}m"
rgb 235 238 245; NAME_COLOR="${ESC}[0;1;${FG}m"
rgb 140 140 150; LABEL_COLOR="${ESC}[0;${FG}m"
rgb 85 88 98; BUILD_COLOR="${ESC}[0;${FG}m"
rgb 60 62 70; DIM_COLOR="${ESC}[0;${FG}m"
# Computer screen: faint lines of text, the one being typed a little
# brighter, and the cursor
rgb 55 75 105; SCR_COLOR="${ESC}[0;${FG}m"
rgb 85 115 160; SCR_HOT="${ESC}[0;${FG}m"
rgb 150 190 255; SCR_CUR="${ESC}[0;${FG}m"

BRAILLE=(" " ⣀ ⣤ ⣶ ⣿)
SPARK=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
BARS=(▂ ▄ ▆ █)
# Padded by hand: without a UTF-8 locale ${#str} counts bytes. 3 is a
# gateway that does not answer pings while the internet works.
STATE_NAME=("● UP      " "◐ DEGRADED" "○ DOWN    " "◐ NO PING ")

# The map grid: the globe on top, the gateway under it in the middle, the
# computer on the left and the Wi-Fi box on the right, in 80x24.
ROWS=16
COLS=77
GCH=(); GCO=()
for (( k = 0; k < ROWS * COLS; k++ )); do GCH[k]=" "; GCO[k]=$RESET; done
CHG=()                               # cells changed since the last frame

# Drawing colours, by mask letter: m computer, k keyboard, a access point,
# n antenna, o globe.
# shellcheck disable=SC2034  # C_m ... C_n are read by draw, through eval
{
  rgb 165 170 182; C_m="${ESC}[0;${FG}m"
  rgb 120 124 135; C_k="${ESC}[0;${FG}m"
  rgb 150 155 168; C_a="${ESC}[0;${FG}m"
  rgb 110 114 125; C_n="${ESC}[0;${FG}m"
  rgb 80 160 255;  C_o="${ESC}[0;${FG}m"
}
MAC=(
  "..mmmmmmmmmmm|_ _ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐"
  "..m.........m|_ _ │ _ _ _ _ _ _ _ _ _ │"
  "..m.........m|_ _ │ _ _ _ _ _ _ _ _ _ │"
  "..mmmmmmmmmmm|_ _ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘"
  "kkkkkkkkkkkkkkk|▝ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▘"
)
# On Windows a desktop, with the tower on the left (MAC_C moves right for it)
DESK=(
  "mmmmm.mmmmmmmmmmm|┌ ─ ─ ─ ┐ _ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐"
  "mkkkm.m.........m|│ ─ ─ ─ │ _ │ _ _ _ _ _ _ _ _ _ │"
  "mkkkm.m.........m|│ ─ ─ ─ │ _ │ _ _ _ _ _ _ _ _ _ │"
  "mmmmm.mmmmmmmmmmm|│ _ ▪ _ │ _ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘"
  "mmmmm....kkkkk...|└ ─ ─ ─ ┘ _ _ _ _ ▝ ▀ ▀ ▀ ▘ _ _ _"
)
AP=(
  ".n.....n.|_ ┃ _ _ _ _ _ ┃ _"
  ".n.....n.|_ ┃ _ _ _ _ _ ┃ _"
  "aaaaaaaaa|▄ █ ▄ ▄ ▄ ▄ ▄ █ ▄"
  "a.......a|█ _ _ _ _ _ _ _ █"
  "aaaaaaaaa|▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀ ▀"
)
GLOBE=(                              # a circle of 16 x 16 Braille dots
  "ooooooooo|_ ⣠ ⠖ ⡟ ⠉ ⢻ ⠲ ⣄ _"
  "ooooooooo|⢰ ⠃ ⢸ ⠁ _ ⠈ ⡇ ⠘ ⡆"
  "ooooooooo|⠸ ⡍ ⢹ ⡉ ⠉ ⢉ ⡏ ⢩ ⠇"
  "ooooooooo|_ ⠙ ⠦ ⣧ ⣀ ⣼ ⠴ ⠋ _"
)

TOP=8                                # first row of the map drawings
LINK_R=$(( TOP + 3 ))                # row of the computer wire
MID_C=38                             # gateway centre column, under the globe
MAC_C=1                              # computer drawing column (15 wide)
(( WIN )) && MAC_C=4                 # room for the tower on its left
MAC_R=$(( TOP + 1 ))                 # computer drawing row (5 tall)
SCR_C=$(( MAC_C + 3 ))               # first column inside the screen (9 wide)
SCR_R=$(( MAC_R + 1 ))               # first row inside the screen (2 tall)
AP_C=$(( MID_C - 4 ))                # gateway drawing column (9 wide)
AP_R=$(( TOP + 1 ))                  # gateway drawing row (5 tall)
INFO_C=$(( MID_C + 6 ))              # internet details, right of the globe
if (( WIN )); then draw $MAC_R $(( MAC_C - 4 )) "${DESK[@]}"
else draw $MAC_R $MAC_C "${MAC[@]}"
fi
draw $AP_R $AP_C "${AP[@]}"
draw 0 $(( MID_C - 4 )) "${GLOBE[@]}"
text 0 $INFO_C "INTERNET" "$NAME_COLOR"
put 2 $INFO_C "○" "$LABEL_COLOR"
text 2 $(( INFO_C + 2 )) "Public IP:" "$LABEL_COLOR"
center $(( TOP + 7 )) $MAC_C 15 "$LOCAL" "$NAME_COLOR"
center $(( TOP + 7 )) $AP_C 9 "GATEWAY" "$NAME_COLOR"

# Wires: ordered lists of cells from the computer outwards, each with its
# grid index and its heavy and light characters. Rows are about twice as
# tall as columns are wide, so vertical wires move their pulse at half
# speed (LSLOW) with a shorter tail (LTAIL).
P_IDX=(); P_HV=(); P_LT=()
LINK_START=(); LINK_LEN=(); LSLOW=(); LTAIL=()
# ms per cell of an up pulse; the short internet wire goes slower so both
# pulses take about as long per trip
LUP=(60 20)
# link 0: gateway -> internet, up between the antennas
LINK_START[0]=${#P_IDX[@]}; LSLOW[0]=2; LTAIL[0]=3
for (( r = AP_R + 1; r >= 4; r-- )); do cell $r $MID_C v; done
# link 1: computer -> gateway, to the right
LINK_START[1]=${#P_IDX[@]}; LSLOW[1]=1; LTAIL[1]=6
for (( c = MAC_C + 13; c < AP_C; c++ )); do cell $LINK_R $c h; done
DASH=(0 1)                           # 1 dashed (Wi-Fi), 0 solid (cable)
LINK_START[NL]=${#P_IDX[@]}
for (( j = 0; j < NL; j++ )); do
  LINK_LEN[j]=$(( LINK_START[j+1] - LINK_START[j] ))
  printf -v tmp '%-9s' "${LINK_NAMES[j]}"; LINK_NAME[j]=$tmp
done

# Cells of the globe and of its label, recoloured when the internet is down
GLOBE_CELLS=(); INET_CELLS=()
for (( k = 0; k < 4 * COLS; k++ )); do
  [[ ${GCO[k]} == "$C_o" ]] && GLOBE_CELLS+=("$k")
  [[ ${GCO[k]} == "$NAME_COLOR" ]] && INET_CELLS+=("$k")
done

# Set before the traps, so cleanup never acts on values from the environment
TMPD=""; CHECK_PID=""; CLOCK_PID=""; STTY=""
HIDDEN=0

TICK_MS=60                           # clock step without a real clock
NOW=0
SCR_MS=1400                          # ms per line on the computer screen
FRAME_MS=40                          # frame time paced by the perl clock

# A UTF-8 locale to count the characters of names and for iconv: the
# user's if it is one, else one this system has
UTF8=${LC_ALL:-${LC_CTYPE:-$LANG}}
if [[ $UTF8 != *[Uu][Tt][Ff]*8* ]]; then
  UTF8=$(locale -a 2>/dev/null | grep -i -m 1 -E '^(C|en_US)\.utf-?8$')
  UTF8=${UTF8:-en_US.UTF-8}
fi

PREV_RX=-1; PREV_TX=-1; PREV_MS=0; PREV_IF=""
# Fields of the Wi-Fi file, "round|" + WIFI, as read into W
W_SEQ=0; W_STATE=1; W_NAME=2; W_PAD=3; W_SEC=4; W_SECLV=5; W_BAND=6; W_CH=7
W_SIG=8; W_NOISE=9; W_RATE=10; W_MODE=11
HAVE_NSLOOKUP=0; command -v nslookup > /dev/null 2>&1 && HAVE_NSLOOKUP=1

# Measured values, as last read from the results files. SH holds HW latency
# samples per link (-2 = none yet), newest last.
STATE=(); LAT=(); LOSS=(); JIT=(); TLV=(); KBPS=(); SH=()
HW=15
for (( k = 0; k < NL * HW; k++ )); do SH[k]=-2; done
for (( j = 0; j < NL; j++ )); do STATE[j]=0; TLV[j]=-1; KBPS[j]=-1; done
NFIELDS=$(( 4 + NL * (6 + PINGS) ))
DNS_ST=-1; DNS_SERVER=-; WIRED=0; LIP=""; PUB=""; PLACE=""; CGNAT=0; GWIP=""
W=(); SPD_SEQ=-1; SPD=-1
SEQ=0; RES_SLOT=-1
DSEQ=0
INTS_RE='^( -?[0-9]+)+ $'

printf -v SP2 '%*s' 2 ''
# Status box, top left of the map, with the overall state
SBOX_IN=22                           # fits "◐ internet degraded"
SBOX_W=$(( SBOX_IN + 2 ))
SBOX_TOP="┌─ ${NAME_COLOR}${APP}${BOX_COLOR} "
for (( i = 3 + ${#APP}; i < SBOX_IN; i++ )); do SBOX_TOP+="─"; done
SBOX_TOP+="┐"
SBOX_BOT="└"
for (( i = 0; i < SBOX_IN; i++ )); do SBOX_BOT+="─"; done
SBOX_BOT+="┘"
# Wi-Fi box, over the right side of the map from row TOP - 1
WBOX_IN=24                           # " " + 22 characters + " "
WBOX_W=$(( WBOX_IN + 2 ))
WBOX_C=$(( COLS - WBOX_W ))
WBOX_R=$(( TOP - 1 ))
WBOX_TOP="┌─ ${NAME_COLOR}Wi-Fi${BOX_COLOR} "
for (( i = 8; i < WBOX_IN; i++ )); do WBOX_TOP+="─"; done
WBOX_TOP+="┐"
WBOX_BOT="└"
for (( i = 0; i < WBOX_IN; i++ )); do WBOX_BOT+="─"; done
WBOX_BOT+="┘"
# Screen lines: a blank one on top, the map, a blank one, the panel header
# and rows, and the footer
LINES_N=$(( ROWS + 5 + NL ))
printf -v BUILD_LINE "%*s · %s · %s" $(( COLS - 4 - ${#YEAR} - ${#BUILD} )) "$MAKER" "$YEAR" "$BUILD"
# Traffic box, left of the panel rows, from the header line to the blank
# line under the rows. Both links read the same counters.
TBOX_TOP="┌─ ${NAME_COLOR}TRAFFIC${BOX_COLOR} ──────┐"
TBOX_BOT="└────────────────┘"
PANEL_HEAD="${BOX_COLOR}${TBOX_TOP} ${LABEL_COLOR}  LINK      STATE      PING          LATENCY JITTER LOSS"
NEED_COLS=$(( COLS + 3 ))            # 2 margin columns, and the last one free
RESIZED=0
START=-1
OV_PREV=()                           # box rows last sent, by map row
PANEL_PREV=()                        # panel rows last sent
INFO_KEY=""; SCR_KEY=""; LIGHT_KEY=""; GLOBE_KEY=""; WBOX_KEY=""
FIRST=1

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

setup_term
make_tmp
start_clock
find_wifi_if
if (( CHECK )); then run_check; fi   # it exits
if ! fits; then
  echo "${0##*/}: the window must be at least ${NEED_COLS}x${LINES_N} (it is ${TCOLS}x${TROWS})" >&2
  exit 2
fi
start_checkers
trap 'RESIZED=1' WINCH
reserve_lines
main_loop
exit 0
