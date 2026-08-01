# plex-updater

A lightweight HTTP server written in Go that manages Plex Media Server on a FreeBSD system. It exposes a simple JSON API to check service status, start/stop/restart Plex, and trigger version upgrades.

## Prerequisites

- FreeBSD system with Plex Media Server installed
- The following files must be present on the target system with the correct permissions:

  | File | Permissions | Description |
  |---|---|---|
  | `/usr/local/etc/rc.d/plexmediaserver` | `755` (executable) | Plex rc.d service script |
  | `/usr/local/bin/plex-start` | `755` (executable) | Plex startup environment wrapper |
  | `/usr/local/sbin/update-plex` | `755` (executable) | Upgrade shell script |

  Verify with:
  ```sh
  ls -la /usr/local/etc/rc.d/plexmediaserver /usr/local/bin/plex-start /usr/local/sbin/update-plex
  ```

  Fix permissions if needed:
  ```sh
  chmod 755 /usr/local/etc/rc.d/plexmediaserver /usr/local/bin/plex-start /usr/local/sbin/update-plex
  ```

- The `plex-updater` binary must run as **root** (required to invoke `service` and the upgrade script)

## Quick Install (FreeBSD)

Run this as root on your FreeBSD system or jail:

```sh
fetch --no-verify-peer -o - https://raw.githubusercontent.com/rdattilo/plex-updater/main/scripts/install.sh | sh
```

> **Note:** `--no-verify-peer` is needed on older FreeBSD versions with outdated CA certificates. The install script will automatically install `ca_root_nss` (Mozilla CA bundle) so that all subsequent HTTPS fetches work correctly without bypassing verification.

This will:
1. Install `ca_root_nss` if missing (fixes SSL on older FreeBSD)
2. Download the pre-built FreeBSD binary (or build from source if no release exists)
3. Install it to `/usr/local/sbin/plex-updater`
4. Install the rc.d service script to `/usr/local/etc/rc.d/plexupdater`
5. Enable and start the service automatically

## Building from Source

```sh
make build
```

This produces a `plex-updater` binary in the current directory.

To cross-compile a FreeBSD binary from macOS or Linux:

```sh
GOOS=freebsd GOARCH=amd64 go build -o plex-updater ./cmd/plex-updater/
```

## Manual Install

```sh
make install        # installs FreeBSD binary to /usr/local/sbin/plex-updater
make install-rcd    # installs rc.d script to /usr/local/etc/rc.d/plexupdater
```

## Running

```sh
/usr/local/sbin/plex-updater
```

The server listens on port **8080** by default.

## API

All responses are JSON.

### Health check

```
GET /healthz
```

Returns `200 OK` if the server is running.

```json
{"status":"ok"}
```

---

### Plex service status

```
GET /status
```

Returns the output of `service plexmediaserver status`.

```json
{"status":"ok","output":"plexmediaserver is running as pid 1234."}
```

---

### Start Plex

```
GET /start
```

Runs `service plexmediaserver start`.

---

### Stop Plex

```
GET /stop
```

Runs `service plexmediaserver stop`.

---

### Restart Plex

```
GET /restart
```

Runs `service plexmediaserver restart`.

---

### Upgrade Plex

```
GET /upgrade/{version}
```

Triggers the `/usr/local/sbin/update-plex` script with the given version string. The upgrade process:

1. Stops the Plex service
2. Downloads the FreeBSD tarball from Plex's CDN
3. Backs up the current installation to `/usr/local/share/plexmediaserver.bak`
4. Installs the new version
5. Restarts the Plex service

**Example:**

```sh
curl http://localhost:8080/upgrade/1.43.3.10828-00f62d37d
```

**Success response:**

```json
{
  "status": "ok",
  "output": "Upgrade complete:\n  Version: 1.43.3.10828-00f62d37d\n  Backup:  /usr/local/share/plexmediaserver.bak"
}
```

**Error response:**

```json
{
  "status": "error",
  "output": "...",
  "error": "exit status 1"
}
```

## Running as a FreeBSD Service

A FreeBSD rc.d script is included at `rc.d/plexupdater`. The service runs `plex-updater` as root (required to invoke `service` and the upgrade script) and logs to `/var/log/plexupdater.log`.

### Install the service

```sh
make install        # installs binary to /usr/local/sbin/plex-updater
make install-rcd    # installs rc.d script to /usr/local/etc/rc.d/plexupdater
```

### Enable and start

Add to `/etc/rc.conf`:

```sh
plexupdater_enable="YES"
```

Then start the service:

```sh
service plexupdater start
```

### Optional rc.conf variables

| Variable | Default | Description |
|---|---|---|
| `plexupdater_enable` | `NO` | Set to `YES` to enable at boot |
| `plexupdater_user` | `root` | User to run the daemon as |
| `plexupdater_logfile` | `/var/log/plexupdater.log` | Log file path |

### Service commands

```sh
service plexupdater start
service plexupdater stop
service plexupdater status
service plexupdater restart
```

---

## plexctl — Local CLI

`scripts/plexctl` is a bash script for controlling `plex-updater` from your local machine (macOS or Linux).

### Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| `curl` | **Required** | Makes HTTP requests to plex-updater |
| `jq` | Optional | Pretty-prints JSON responses |

Install on macOS:
```sh
brew install curl jq
```

### Install

```sh
# From the repo:
make install-local   # copies to /usr/local/bin/plexctl

# Or manually:
cp scripts/plexctl /usr/local/bin/plexctl
chmod +x /usr/local/bin/plexctl
```

### Usage

```sh
plexctl <command> [version]
plexctl [host:port] <command> [version]
```

The default host is `rd-plex:8080`. Override it by passing a host as the first argument.

### Commands

| Command | Description |
|---|---|
| `plexctl healthz` | Check if plex-updater is running |
| `plexctl status` | Show Plex service status |
| `plexctl start` | Start Plex |
| `plexctl stop` | Stop Plex |
| `plexctl restart` | Restart Plex |
| `plexctl upgrade <version>` | Upgrade Plex to the given version |

### Examples

```sh
plexctl status
plexctl restart
plexctl upgrade 1.43.3.10828-00f62d37d

# Target a different host
plexctl 192.168.1.50:8080 status
plexctl 192.168.1.50:8080 upgrade 1.43.3.10828-00f62d37d
```

Output is pretty-printed JSON if `jq` is installed, otherwise raw JSON.

---

## Repository Structure

```
cmd/plex-updater/
  main.go              ← Go HTTP server source
rc.d/
  plexmediaserver      ← FreeBSD rc.d service script for Plex Media Server
  plexupdater          ← FreeBSD rc.d service script for plex-updater
scripts/
  install.sh           ← One-shot installer for FreeBSD
  plexctl              ← Local bash CLI for controlling plex-updater
  plex-start           ← Plex startup environment wrapper
  update-plex          ← Upgrade shell script
MAKEFILE               ← Build and install targets
```
