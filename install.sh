#!/bin/sh
# Install unn from a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/jetcuhh/unn/main/install.sh | sh
#
# Environment:
#   PREFIX    install prefix (default: ~/.local)
#   VERSION   release to install, with or without the leading v (default: latest)
set -eu

repo=jetcuhh/unn
prefix=${PREFIX:-$HOME/.local}
version=${VERSION:-latest}

usage() {
    cat <<'EOF'
Install unn from a GitHub release.

  install.sh [--system] [--prefix DIR] [--version VER]

  --system         install under /usr/local (needs write access)
  --prefix DIR     install under DIR instead of ~/.local
  --version VER    install a specific release instead of the latest
  -h, --help       show this help

Environment: PREFIX, VERSION.
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --system) prefix=/usr/local ;;
        --prefix)
            shift
            prefix=${1:?--prefix needs a directory}
            ;;
        --version)
            shift
            version=${1:?--version needs a version}
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "install: unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

die() {
    echo "install: $*" >&2
    exit 1
}

for cmd in curl tar; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done

arch=$(uname -m)
case $arch in
    x86_64 | amd64) arch=x86_64 ;;
    *) die "release builds are x86_64 only; build from source instead" ;;
esac

libc=gnu
if ldd --version 2>&1 | grep -qi musl; then
    libc=musl
elif [ -e "/lib/ld-musl-$arch.so.1" ] && [ ! -e "/lib64/ld-linux-$arch.so.2" ]; then
    libc=musl
fi

if [ "$version" = latest ]; then
    tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") ||
        die "cannot reach github"
    tag=${tag##*/}
else
    case $version in
        v*) tag=$version ;;
        *) tag=v$version ;;
    esac
fi
[ -n "$tag" ] || die "cannot determine which release to install"
ver=${tag#v}

name=unn-$ver-linux-$arch-$libc
base=https://github.com/$repo/releases/download/$tag

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

echo "downloading $name"
curl -fsSL -o "$tmp/$name.tar.gz" "$base/$name.tar.gz" ||
    die "no $libc build of $ver; see https://github.com/$repo/releases"

if curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" 2>/dev/null &&
    command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp" && grep -F " $name.tar.gz" SHA256SUMS | sha256sum -c --status -) ||
        die "checksum mismatch for $name.tar.gz"
fi

tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
src=$tmp/$name
[ -x "$src/bin/unn" ] || die "malformed archive: bin/unn is missing"

# Replace atomically: copy next to the target, then rename over it. A
# plain cp onto a running binary fails with "Text file busy"; a rename
# works while the old version is running (it keeps running until closed).
install_file() {
    mkdir -p "$(dirname "$2")"
    cp "$1" "$2.new.$$"
    chmod "$3" "$2.new.$$"
    mv -f "$2.new.$$" "$2"
}

install_file "$src/bin/unn" "$prefix/bin/unn" 755
install_file "$src/share/applications/jet.unn.desktop" \
    "$prefix/share/applications/jet.unn.desktop" 644
install_file "$src/share/icons/hicolor/scalable/apps/jet.unn.svg" \
    "$prefix/share/icons/hicolor/scalable/apps/jet.unn.svg" 644
install_file "$src/share/man/man1/unn.1" "$prefix/share/man/man1/unn.1" 644
install_file "$src/share/man/man5/unn.5" "$prefix/share/man/man5/unn.5" 644
install_file "$src/share/doc/unn/examples/50-unn.conf" \
    "$prefix/share/doc/unn/examples/50-unn.conf" 644
install_file "$src/share/terminfo/u/unn" "$prefix/share/terminfo/u/unn" 644

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qtf "$prefix/share/icons/hicolor" >/dev/null 2>&1 || true
fi

if command -v ldd >/dev/null 2>&1; then
    missing=$(ldd "$prefix/bin/unn" 2>/dev/null | awk '/not found/ { print $1 }' | sort -u)
    if [ -n "$missing" ]; then
        echo
        echo "warning: missing shared libraries:"
        printf '  %s\n' $missing
        if command -v pacman >/dev/null 2>&1; then
            echo "  sudo pacman -S --needed wayland libxkbcommon fontconfig freetype2 harfbuzz"
        elif command -v apt-get >/dev/null 2>&1; then
            echo "  sudo apt-get install libwayland-client0 libxkbcommon0 libfontconfig1 libfreetype6 libharfbuzz0b"
        elif command -v dnf >/dev/null 2>&1; then
            echo "  sudo dnf install libwayland-client libxkbcommon fontconfig freetype harfbuzz"
        elif command -v apk >/dev/null 2>&1; then
            echo "  sudo apk add wayland-libs-client libxkbcommon fontconfig freetype harfbuzz"
        fi
    fi
fi

echo
echo "installed unn $ver ($libc) to $prefix"
found=$(command -v unn 2>/dev/null || true)
if [ -n "$found" ] && [ "$found" != "$prefix/bin/unn" ]; then
    echo "warning: 'unn' in your PATH is $found, which shadows the one just installed"
    echo "  remove it, or put $prefix/bin earlier in PATH"
fi
if pgrep -x unn >/dev/null 2>&1; then
    echo "note: unn is running; restart it to use the new version"
fi
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *)
        echo "add it to PATH:"
        echo "  fish_add_path $prefix/bin"
        ;;
esac
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "note: no WAYLAND_DISPLAY in this environment; unn needs a Wayland session"
fi