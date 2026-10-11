#!/usr/bin/env bash
# Pre-flight check for the AI in Practice session.
# Works on macOS, Linux, WSL and Git Bash. Windows PowerShell: use preflight.ps1.
#
#   bash preflight.sh
#
# It runs a few tiny hello-world containers, changes nothing on your machine
# apart from Docker's image cache, and writes preflight-report.txt.
# (Kept compatible with the old bash 3.2 that macOS ships.)

cd "$(dirname "$0")" || exit 1

PORT=8085
PROJECT=preflight-check
REPORT=preflight-report.txt
LOG=$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")
: > "$REPORT"
FAILS=""
WARNS=""
NFAIL=0
NWARN=0
COMPOSE=""

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; N=""
fi

say()  { printf '%s\n' "$1"; printf '%s\n' "$1" >> "$REPORT"; }
plain() { printf '%s\n' "$1" >> "$REPORT"; }
ok()   { printf '  [%s OK %s] %s\n' "$G" "$N" "$1"; plain "  [ OK ] $1"; }
warn() { printf '  [%sWARN%s] %s\n' "$Y" "$N" "$1"; plain "  [WARN] $1"
         NWARN=$((NWARN+1)); WARNS="$WARNS
   - $1"; }
bad()  { printf '  [%sFAIL%s] %s\n' "$R" "$N" "$1"; plain "  [FAIL] $1"
         NFAIL=$((NFAIL+1)); FAILS="$FAILS
   - $1"; }
note() { printf '         %s\n' "$1"; plain "         $1"; }

# Print the tail of a log plus advice that matches what went wrong.
explain() {
  local text; text=$(cat "$LOG")
  tr -d '\r' < "$LOG" | grep -v '^[[:space:]]*$' | tail -n 10 | while IFS= read -r l; do note "| $l"; done
  case "$text" in
    *"Cannot connect to the Docker daemon"*|*"failed to connect to the docker API"*|*"error during connect"*|*"Is the docker daemon running"*|*"docker.sock: connect"*|*"pipe/docker_engine"*)
      note "-> Docker is installed but not running. Start Docker Desktop (or 'sudo systemctl start docker'), wait until it says running, then re-run." ;;
  esac
  case "$text" in
    *"could not be found in this WSL"*)
      note "-> Docker Desktop's WSL integration is off. Docker Desktop > Settings > Resources > WSL integration: switch on this distro, then re-run." ;;
  esac
  case "$text" in
    *"permission denied"*)
      note "-> Permission problem talking to Docker. On Linux: 'sudo usermod -aG docker \$USER', log out and in again." ;;
  esac
  case "$text" in
    *"error getting credentials"*|*"credential helper"*|*"docker-credential"*)
      note "-> Docker's credential helper failed (common in WSL). Remove the \"credsStore\" line from ~/.docker/config.json and re-run." ;;
  esac
  case "$text" in
    *"toomanyrequests"*|*"rate limit"*)
      note "-> Docker Hub rate limit. Run 'docker login' with a free account and re-run." ;;
  esac
  case "$text" in
    *"no matching manifest"*|*"exec format error"*)
      note "-> Architecture mismatch. Tell the organiser exactly what this screen says (and your Mac/PC model)." ;;
  esac
  case "$text" in
    *"x509"*|*"certificate verify failed"*|*"SSL certificate problem"*|*"unable to get local issuer"*)
      note "-> Certificate error: usually a company proxy or VPN that re-signs traffic. Try off-VPN, or ask IT for the proxy CA." ;;
  esac
  case "$text" in
    *"name resolution"*|*"no such host"*|*"i/o timeout"*|*"Could not resolve"*|*"timed out"*|*"Timeout"*|*"TLS handshake"*|*"Failed to fetch"*|*"Temporary failure"*)
      note "-> Network problem reaching the internet from Docker. Check VPN / proxy / Wi-Fi and re-run." ;;
  esac
  case "$text" in
    *"no space left"*)
      note "-> Docker is out of disk space. Try 'docker system prune' (removes unused images/containers) and re-run." ;;
  esac
}

# run <label> <command...>: quiet on success, explains on failure.
run() {
  local label=$1; shift
  local t0; t0=$(date +%s)
  if "$@" > "$LOG" 2>&1; then
    ok "$label ($(( $(date +%s) - t0 ))s)"
    return 0
  fi
  bad "$label"
  explain
  return 1
}

# Is anything answering on localhost:$PORT? (0 = something is listening)
port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }

# --------------------------------------------------------------------------
say ""
say "${B}=============================================================${N}"
say "${B}  PRE-FLIGHT CHECK${N}"
say "${B}=============================================================${N}"
say "  $(date '+%Y-%m-%d %H:%M')   $(uname -s) $(uname -m)"
if grep -qi microsoft /proc/version 2>/dev/null; then say "  (running inside WSL)"; fi
say ""
say "  This will:"
say "    - check that Docker is installed, running, and set up correctly on this machine"
say "    - download a few hundred MB of container images (the same ones the real session uses)"
say "    - build two small placeholder containers, so those downloads and installs are cached"
say "    - briefly start a test web server on port $PORT, then stop everything"
say ""
say "  It does not touch any of your other files, and nothing is left running afterwards."
say ""
if [ -t 0 ]; then
  printf '  Continue? [Y/n] '
  read -r ANSWER
else
  ANSWER=Y
fi
case "$ANSWER" in
  n|N|no|No|NO)
    say ""
    say "  Cancelled - nothing was changed."
    exit 0
    ;;
esac
say ""

# ---- 1. Docker installed ---------------------------------------------------
say "1. Docker"
DOCKER_OK=0
if command -v docker >/dev/null 2>&1; then
  ok "docker command found: $(docker --version 2>/dev/null)"
  DOCKER_OK=1
else
  bad "docker command not found"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    note "-> In WSL: install Docker Desktop for Windows and switch on Settings > Resources > WSL integration for this distro."
  elif [ "$(uname -s)" = "Darwin" ]; then
    note "-> Install Docker Desktop for Mac: https://docs.docker.com/desktop/setup/install/mac-install/"
  else
    note "-> Install Docker Engine + the compose plugin: https://docs.docker.com/engine/install/"
  fi
fi

# ---- 2. Docker running -----------------------------------------------------
if [ $DOCKER_OK -eq 1 ]; then
  if docker info > "$LOG" 2>&1; then
    OSTYPE_D=$(docker info --format '{{.OSType}}' 2>/dev/null)
    DARCH=$(docker info --format '{{.Architecture}}' 2>/dev/null)
    MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
    ok "Docker is running (engine $(docker info --format '{{.ServerVersion}}' 2>/dev/null), $OSTYPE_D/$DARCH)"
    if [ "$OSTYPE_D" != "linux" ]; then
      bad "Docker is set to '$OSTYPE_D' containers; the session needs Linux containers"
      note "-> Docker Desktop tray icon > Switch to Linux containers."
      DOCKER_OK=0
    fi
    case "$MEM" in
      ''|*[!0-9]*) : ;;
      *) if [ "$MEM" -lt 2000000000 ]; then
           warn "Docker has under 2 GB of memory ($((MEM/1000000)) MB); builds may fail. Docker Desktop > Settings > Resources: give it 4 GB."
         fi ;;
    esac
  else
    bad "Docker is installed but not running"
    # docker info prints a page of client details first; keep only the error lines
    grep -i -E 'error|failed|cannot|denied|not found|could not' "$LOG" > "$LOG.err" 2>/dev/null
    if [ -s "$LOG.err" ]; then mv "$LOG.err" "$LOG"; else rm -f "$LOG.err"; fi
    explain
    DOCKER_OK=0
  fi
fi

# ---- 3. docker compose -----------------------------------------------------
say ""
say "2. Docker Compose"
if [ $DOCKER_OK -eq 1 ]; then
  if docker compose version > "$LOG" 2>&1; then
    COMPOSE="docker compose"
    ok "docker compose works ($(docker compose version --short 2>/dev/null || head -n1 "$LOG"))"
  elif command -v docker-compose >/dev/null 2>&1 && docker-compose version > "$LOG" 2>&1; then
    COMPOSE="docker-compose"
    ok "docker-compose (old standalone version) works: $(docker-compose version --short 2>/dev/null)"
    warn "the newer 'docker compose' is not installed; the old one usually works but upgrading Docker is safer"
  else
    bad "neither 'docker compose' nor 'docker-compose' works"
    note "-> Update Docker Desktop, or on Linux install the docker-compose-plugin package."
  fi
else
  note "skipped (Docker not ready)"
fi

# ---- 4. platform -----------------------------------------------------------
say ""
say "3. Your machine's architecture"
if [ $DOCKER_OK -eq 1 ]; then
  ok "Docker reports this machine as $DARCH (confirmed against the containers in step 5)"
  if [ -n "${DOCKER_DEFAULT_PLATFORM:-}" ]; then
    warn "DOCKER_DEFAULT_PLATFORM is set to '$DOCKER_DEFAULT_PLATFORM'; this forces emulation on some machines. Unset it unless you know why it is there."
  fi
else
  note "skipped (Docker not ready)"
fi

# ---- 5. port ---------------------------------------------------------------
say ""
say "4. Port $PORT (the session will need it)"
PORT_FREE=1
PY_BUILT=1
if port_busy; then
  PORT_FREE=0
  bad "something is already listening on port $PORT"
  if [ "$(uname -s)" = "Darwin" ] || command -v lsof >/dev/null 2>&1; then
    note "-> Find it with:  lsof -i :$PORT      (then stop that program)"
  else
    note "-> Find it with:  ss -ltnp | grep $PORT      (then stop that program)"
  fi
  note "-> If it is a Docker project you started earlier, run 'docker compose down' in that project's folder."
else
  ok "port $PORT is free"
fi

# ---- 6. images: pull, build, run ------------------------------------------
say ""
say "5. Pull, build and run the hello-world containers"
if [ -n "$COMPOSE" ]; then
  C="$COMPOSE -p $PROJECT"
  if run "download postgres:16-alpine" $C pull hello-db; then
    APP_BUILT=1; PY_BUILT=1
    run "build hello-app  (installs the same OS packages the session needs)" $C build hello-app || APP_BUILT=0
    run "build hello-py   (installs the same Python packages the session needs)" $C build hello-py || PY_BUILT=0
    for svc in hello-db hello-app hello-py; do
      if [ "$svc" = hello-app ] && [ $APP_BUILT -eq 0 ]; then continue; fi
      if [ "$svc" = hello-py ] && [ $PY_BUILT -eq 0 ]; then continue; fi
      if $C run --rm "$svc" > "$LOG" 2>&1; then
        A=$(sed -n 's/^ARCH=//p' "$LOG" | tail -n 1)
        if [ -n "$A" ] && [ "$A" != "$DARCH" ]; then
          warn "$svc ran as $A but this machine is $DARCH: it is running under emulation (slow, may fail)"
          note "-> Docker Desktop > Settings > General: make sure no platform override is set. Tell the organiser."
        else
          ok "$svc ran ($A)"
        fi
      else
        bad "$svc did not run"
        explain
      fi
    done
  else
    note "skipping builds: the base images could not be downloaded"
    PY_BUILT=0
  fi
else
  note "skipped (Docker Compose not ready)"
fi

# ---- 7. publish the port ---------------------------------------------------
say ""
say "6. Can Docker publish port $PORT and answer on it?"
if [ -n "$COMPOSE" ] && [ $PORT_FREE -eq 1 ] && [ $PY_BUILT -eq 1 ]; then
  C="$COMPOSE -p $PROJECT"
  if $C up -d hello-port > "$LOG" 2>&1; then
    GOT=""
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      GOT=$( (exec 3<>"/dev/tcp/127.0.0.1/$PORT"; printf 'GET / HTTP/1.0\r\n\r\n' >&3; IFS= read -r -t 3 l <&3; printf '%s' "$l") 2>/dev/null )
      case "$GOT" in HTTP/*) break ;; esac
      sleep 1
    done
    case "$GOT" in
      HTTP/*) ok "a test web server answered on http://localhost:$PORT" ;;
      *) bad "the test container started but nothing answered on localhost:$PORT"
         note "-> A firewall or security tool may be blocking local ports. Tell the organiser."
         ;;
    esac
  else
    bad "Docker could not publish port $PORT"
    explain
  fi
elif [ -n "$COMPOSE" ] && [ $PORT_FREE -eq 0 ]; then
  note "skipped (port $PORT is already in use, see step 4)"
elif [ -n "$COMPOSE" ]; then
  note "skipped (the hello-py image could not be built, see step 5)"
else
  note "skipped (Docker Compose not ready)"
fi

# ---- clean up ----------------------------------------------------------
if [ -n "$COMPOSE" ]; then
  $COMPOSE -p $PROJECT down --remove-orphans > /dev/null 2>&1
fi
rm -f "$LOG"

# ---- verdict ---------------------------------------------------------------
say ""
if [ $NFAIL -eq 0 ]; then
  say "${G}${B}=============================================================${N}"
  say "${G}${B}   YOU ARE READY${N}"
  say "${G}${B}   Everything checked out. Nothing more to do until the session.${N}"
  say "${G}${B}=============================================================${N}"
  if [ $NWARN -gt 0 ]; then
    say ""
    say "   Ready, but with $NWARN warning(s) worth a look:$WARNS"
  fi
  say ""
  say "   (This left no containers running. The downloaded images and"
  say "   installed packages stay cached, which makes the real thing"
  say "   start faster on the day. Run this again if it has been more"
  say "   than a couple of days - Docker can quietly clear its cache.)"
  EXIT=0
else
  say "${R}${B}=============================================================${N}"
  say "${R}${B}   NOT READY: $NFAIL problem(s)${N}"
  say "${R}${B}=============================================================${N}"
  say "$FAILS"
  say ""
  say "   Fix what it says above and run this again."
  say "   Stuck? Send the organiser the file  $REPORT"
  say "   (it is in this folder and contains everything shown here)."
  EXIT=1
fi
say ""
exit $EXIT
