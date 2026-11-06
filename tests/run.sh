#!/bin/sh
# Exercise the hash gate without a TV. The real /usr/lib/libcbe.so is never opened.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state" "$tmp/dir" "$tmp/init.d"
cat > "$tmp/bin/sha256sum" << 'EOF'
#!/bin/sh
# Test double: the file's contents are the digest line "digest  name".
awk '{ print $1; exit }' "$1"
EOF
chmod 755 "$tmp/bin/sha256sum"

known=965c00c5fc97610b9de62d251a64bb312ebe0b681d21561626338c9569384b2c
other=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
patched=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

printf '%s  libcbe.so\n' "$known" > "$tmp/live.so"
printf '%s  patched.so\n' "$other" > "$tmp/dir/patched.so"
: > "$tmp/mounts"

export PATH="$tmp/bin:$PATH"
export LIBCBE_TARGET="$tmp/live.so"
export LIBCBE_DIR="$tmp/dir"
export LIBCBE_STATE="$tmp/state"
export LIBCBE_LINK="$tmp/init.d/45-libcbe-mount"
export LIBCBE_SELF="$tmp/installed.sh"
export LIBCBE_BUILDS="$root/builds.txt"
export LIBCBE_MOUNTS="$tmp/mounts"

out=$(sh "$root/libcbe-mount.sh" prepare)
printf '%s\n' "$out" | grep -q "sha256 $known"
printf '%s\n' "$out" | grep -q "No patched libcbe.so is published"
echo "prepare refuses a known engine with no published build"

if sh "$root/libcbe-mount.sh" apply; then
    echo "apply should have failed" >&2
    exit 1
fi
echo "apply exits non-zero"

# A published row must still reject a file with the wrong digest.
cat > "$tmp/builds.txt" << EOF
# original patched firmware note
$known $patched 43.21.84 test row
EOF
export LIBCBE_BUILDS="$tmp/builds.txt"
if sh "$root/libcbe-mount.sh" apply; then
    echo "apply accepted the wrong patched digest" >&2
    exit 1
fi
echo "apply rejects a mismatched patched digest"

# Unknown engines are backed up and refused.
printf '%s  libcbe.so\n' "$other" > "$tmp/live.so"
export LIBCBE_BUILDS="$root/builds.txt"
out=$(sh "$root/libcbe-mount.sh" prepare)
printf '%s\n' "$out" | grep -q "not in builds.txt"
if sh "$root/libcbe-mount.sh" apply; then
    echo "apply accepted an unknown engine" >&2
    exit 1
fi
echo "apply rejects an unknown engine"

echo "ok"
