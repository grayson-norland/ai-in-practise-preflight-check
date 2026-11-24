# Pre-flight check

For **Testing the Untestable**. Run this once, a day or two before the session (not weeks before - see "timing" below). It takes 1-3 minutes (a few hundred MB of downloads the first time) and tells you whether your machine will be able to run the session's setup. It is not the session itself: it only starts a few hello-world containers.

It also does real work you'll benefit from on the day: `hello-app` and `hello-py` install the exact same operating-system and Python packages the real session needs (just built into throwaway placeholder programs, not the real thing). Docker caches those downloads-and-installs, so when the real setup runs on the day, it reuses that cache instead of redoing it - which is normally the slowest part of a first-time build, especially on a shared venue network.

## Before you start: is Docker running?

Having Docker installed is not enough - it also has to be **running**. This is the most common reason the check fails, especially on a machine where Docker has never been used before.

- **Windows / macOS:** open **Docker Desktop** from the Start menu or Applications. The first time, accept its terms and skip or close the sign-in screen (an account is not needed). Wait until the bottom-left corner says **Engine running** (green), which can take a minute or two. You can close the window afterwards; Docker keeps running in the background (whale icon in the system tray / menu bar).
- **Linux:** `sudo systemctl start docker`

To double-check, run `docker info` in a terminal. If it prints a long list of details, Docker is running. If it says something like `Cannot connect to the Docker daemon` or `error during connect`, it isn't yet.

## Run it

From this folder:

**macOS, Linux, WSL, Git Bash**

```
bash preflight.sh
```

**Windows (PowerShell)**

```
powershell -ExecutionPolicy Bypass -File .\preflight.ps1
```

## What you should see

```
=============================================================
   YOU ARE READY
   Everything checked out. Nothing more to do until the session.
=============================================================
```

If you see `NOT READY` instead, the lines marked `[FAIL]` say what is wrong and what to try. Fix it and run the script again. If it says **Docker is installed but not running**, start Docker as described in "Before you start" above, wait for it to finish starting, and re-run - nothing else needs fixing. If you are stuck, send the organiser the file `preflight-report.txt` that appears in this folder.

`[WARN]` lines are not blockers, but read them.

## What it checks

- Docker is installed and running, and set to Linux containers
- `docker compose` (or the older `docker-compose`) works
- Docker can download, build and run containers on your machine's architecture, without emulation (Intel, Apple Silicon and so on), using the same base images as the session
- Docker can reach the internet to install packages while building
- Port 8085 is free, and Docker can publish it and get an answer

## Timing

Run it a day or two before the session, not weeks ahead. Docker Desktop periodically clears its build cache under disk pressure, so a warm-up done too early can quietly be gone by the day. If in doubt, just run it again the night before - it's quick, and re-running does no harm.

## What it leaves behind

No containers keep running. The downloaded base images and the packages installed inside them stay in Docker's cache, so the real setup reuses that work and starts (and builds) faster on the day. The two images it built can be removed with `docker rmi preflight-hello-app preflight-hello-py`; keep the base images (and don't run `docker builder prune`, which would throw away the cache this exists to build).
