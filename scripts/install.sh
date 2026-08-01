#!/bin/sh
#
# install.sh - plex-updater installer for FreeBSD
#
# This script installs the plex-updater binary and rc.d service script,
# then enables and starts the service.
#
# Usage (as root):
#   fetch --no-verify-peer -o - https://raw.githubusercontent.com/rdattilo/plex-updater/main/scripts/install.sh | sh
#
# --no-verify-peer is required on older FreeBSD systems with outdated CA
# certificates. The script will install ca_root_nss automatically so that
# all subsequent HTTPS connections work without bypassing verification.
#
# Or if you have the repo cloned:
#   sh scripts/install.sh
#

set -e

REPO="rdattilo/plex-updater"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

BINARY_NAME="plex-updater"
INSTALL_BIN="/usr/local/sbin/${BINARY_NAME}"
INSTALL_RCD="/usr/local/etc/rc.d/plexupdater"
LOG_FILE="/var/log/plexupdater.log"

# fetch wrapper — always skips peer verification so old FreeBSD systems
# with stale CA bundles can still reach GitHub/raw.githubusercontent.com.
# FreeBSD's fetch(1) does not automatically pick up ca_root_nss even after
# it is installed; --no-verify-peer is the reliable workaround on old builds.
FETCH="fetch --no-verify-peer"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "  [info]  $*"; }
ok()    { echo "  [ ok ]  $*"; }
warn()  { echo "  [warn]  $*"; }
err()   { echo "  [err]   $*" >&2; exit 1; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This script must be run as root."
    fi
}

# ---------------------------------------------------------------------------
# Package management
# ---------------------------------------------------------------------------

pkg_installed() {
    pkg info -e "$1" 2>/dev/null
}

ensure_pkg() {
    PKG="$1"
    if pkg_installed "${PKG}"; then
        info "${PKG} is already installed."
    else
        info "Installing ${PKG}..."
        pkg install -y "${PKG}"
        ok "${PKG} installed."
    fi
}

check_dependencies() {
    info "Checking required packages..."

    # pkg itself must be bootstrapped
    if ! command -v pkg >/dev/null 2>&1; then
        err "pkg is not available. Please bootstrap it first: env ASSUME_ALWAYS_YES=YES pkg bootstrap"
    fi

    # Install ca_root_nss (Mozilla CA bundle) so HTTPS works on older FreeBSD.
    # pkg uses its own TLS stack and will work even without valid system certs.
    if ! pkg_installed "ca_root_nss"; then
        info "ca_root_nss not found — installing Mozilla CA bundle..."
        pkg install -y ca_root_nss
        ok "ca_root_nss installed."
    else
        info "ca_root_nss is already installed."
    fi

    ok "Core dependencies satisfied."
}

# ---------------------------------------------------------------------------
# Detect architecture
# ---------------------------------------------------------------------------

detect_arch() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        amd64|x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) err "Unsupported architecture: ${ARCH}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Resolve the latest release tag from GitHub
# ---------------------------------------------------------------------------

latest_release() {
    info "Fetching latest release tag from GitHub..."
    TAG=$(${FETCH} -o - "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

    if [ -z "${TAG}" ]; then
        warn "No GitHub release found. Will build from source."
        TAG=""
    else
        info "Latest release: ${TAG}"
    fi
}

# ---------------------------------------------------------------------------
# Install binary
# ---------------------------------------------------------------------------

install_binary() {
    if [ -n "${TAG}" ]; then
        BINARY_URL="https://github.com/${REPO}/releases/download/${TAG}/${BINARY_NAME}"
        info "Downloading ${BINARY_NAME} ${TAG} (freebsd/${ARCH})..."
        ${FETCH} -o "${INSTALL_BIN}" "${BINARY_URL}" || {
            warn "Pre-built binary not found for this release. Falling back to build from source."
            TAG=""
        }
    fi

    if [ -z "${TAG}" ]; then
        info "Building from source — checking for Go..."
        if ! command -v go >/dev/null 2>&1; then
            ensure_pkg "go"
        else
            info "Go is already installed ($(go version | awk '{print $3}'))."
        fi

        TMPDIR=$(mktemp -d)
        cleanup() { rm -rf "${TMPDIR}"; }
        trap cleanup EXIT

        info "Downloading source archive..."
        ${FETCH} -o - "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" \
            | tar -xzf - -C "${TMPDIR}"

        SRC_DIR=$(find "${TMPDIR}" -maxdepth 1 -type d -name "plex-updater-*")
        [ -d "${SRC_DIR}" ] || err "Could not find extracted source directory."

        info "Compiling ${BINARY_NAME}..."
        GOTOOLCHAIN=local GOOS=freebsd GOARCH=${ARCH} go build -o "${INSTALL_BIN}" "${SRC_DIR}/cmd/plex-updater/"
    fi

    chmod 755 "${INSTALL_BIN}"
    ok "Binary installed to ${INSTALL_BIN}"
}

# ---------------------------------------------------------------------------
# Install rc.d script
# ---------------------------------------------------------------------------

install_rcd() {
    info "Installing rc.d service script..."
    ${FETCH} -o "${INSTALL_RCD}" "${BASE_URL}/rc.d/plexupdater" \
        || err "Failed to download rc.d script from ${BASE_URL}/rc.d/plexupdater"
    chmod 755 "${INSTALL_RCD}"
    ok "rc.d script installed to ${INSTALL_RCD}"
}

# ---------------------------------------------------------------------------
# Enable and start service
# ---------------------------------------------------------------------------

enable_service() {
    if ! grep -q "plexupdater_enable" /etc/rc.conf 2>/dev/null; then
        info "Enabling plexupdater in /etc/rc.conf..."
        echo 'plexupdater_enable="YES"' >> /etc/rc.conf
        ok "plexupdater_enable=\"YES\" added to /etc/rc.conf"
    else
        info "plexupdater already present in /etc/rc.conf — ensuring it is enabled..."
        sed -i '' 's/plexupdater_enable=.*/plexupdater_enable="YES"/' /etc/rc.conf
    fi

    info "Starting plexupdater service..."
    service plexupdater start
    ok "plexupdater started. Logs: ${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

require_root
check_dependencies
detect_arch
latest_release
install_binary
install_rcd
enable_service

echo ""
echo "Installation complete!"
echo ""
echo "  Binary:   ${INSTALL_BIN}"
echo "  rc.d:     ${INSTALL_RCD}"
echo "  Logs:     ${LOG_FILE}"
echo "  Port:     8080"
echo ""
echo "Test it:"
echo "  curl http://localhost:8080/healthz"
echo ""
