#!/usr/bin/env bash
# Run the HustlerCore tests without a Mac and without spending macOS CI minutes.
#
#   tools/local-test.sh              use an already-installed toolchain
#   tools/local-test.sh --install    fetch the pinned Swift toolchain first
#
# Extra arguments are passed to `swift test`, e.g. --filter MoneyTests.
# On macOS with Xcode command line tools it uses the system toolchain and
# downloads nothing. On Linux it fetches the official swift.org tarball.
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.0.3}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
SWIFT_DIR="${SWIFT_DIR:-$HOME/.local/swift-${SWIFT_VERSION}}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hustler"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/ios-app/HustlerCore"

INSTALL=0
EXTRA_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) EXTRA_ARGS+=("$arg") ;;
  esac
done

find_swift() {
  if [ -x "$SWIFT_DIR/usr/bin/swift" ]; then
    echo "$SWIFT_DIR/usr/bin/swift"
    return 0
  fi
  if command -v swift >/dev/null 2>&1; then
    command -v swift
    return 0
  fi
  return 1
}

install_linux_swift() {
  local arch platform_dir file_platform archive url
  arch="$(uname -m)"
  # swift.org puts "ubuntu2404" in the path but "ubuntu24.04" in the filename.
  platform_dir="ubuntu${UBUNTU_VERSION//./}"
  file_platform="ubuntu${UBUNTU_VERSION}"
  case "$arch" in
    x86_64)        ;;
    aarch64|arm64) platform_dir="$platform_dir-aarch64"; file_platform="$file_platform-aarch64" ;;
    *) echo "unsupported architecture: $arch" >&2; return 1 ;;
  esac

  archive="swift-${SWIFT_VERSION}-RELEASE-${file_platform}.tar.gz"
  url="https://download.swift.org/swift-${SWIFT_VERSION}-release/${platform_dir}/swift-${SWIFT_VERSION}-RELEASE/${archive}"

  mkdir -p "$CACHE_DIR" "$SWIFT_DIR"
  if [ ! -s "$CACHE_DIR/$archive" ]; then
    echo "downloading $url"
    curl -fL --retry 2 --connect-timeout 20 "$url" -o "$CACHE_DIR/$archive" || {
      rm -f "$CACHE_DIR/$archive"
      echo "download failed: $url" >&2
      return 1
    }
  else
    echo "using cached $CACHE_DIR/$archive"
  fi

  if [ -n "${SWIFT_SHA256:-}" ]; then
    echo "${SWIFT_SHA256}  $CACHE_DIR/$archive" | sha256sum -c -
  else
    echo "note: set SWIFT_SHA256 to verify the archive checksum (HTTPS only otherwise)"
  fi

  echo "extracting into $SWIFT_DIR"
  tar xzf "$CACHE_DIR/$archive" -C "$SWIFT_DIR" --strip-components=1
  [ -x "$SWIFT_DIR/usr/bin/swift" ] || { echo "extraction did not produce usr/bin/swift" >&2; return 1; }
  echo "installed: $("$SWIFT_DIR/usr/bin/swift" --version | head -1)"
}

if ! SWIFT_BIN="$(find_swift)"; then
  if [ "$(uname -s)" != "Linux" ]; then
    echo "no Swift toolchain found. On macOS run: xcode-select --install" >&2
    exit 2
  fi
  if [ "$INSTALL" -ne 1 ]; then
    cat >&2 <<'MSG'
No Swift toolchain found.

  Re-run with --install to fetch the pinned toolchain into ~/.local:
      ios-app/tools/local-test.sh --install

  Or install Swift from swift.org and re-run.
MSG
    exit 2
  fi
  install_linux_swift
  SWIFT_BIN="$SWIFT_DIR/usr/bin/swift"
fi

echo "swift: $("$SWIFT_BIN" --version | head -1)"
cd "$PACKAGE_DIR"
if [ "${#EXTRA_ARGS[@]}" -eq 0 ]; then
  exec "$SWIFT_BIN" test
fi
exec "$SWIFT_BIN" test "${EXTRA_ARGS[@]}"
