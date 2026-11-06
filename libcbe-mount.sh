#!/bin/sh
# Cover /usr/lib/libcbe.so with a patched file from the writable app partition.
# The squashfs copy is never written. umount puts it back.
# boot does nothing unless $STATE/enabled exists.
# A boot that mounts and is never confirmed disables itself the next time.
# apply mounts only when builds.txt names the patched sha256 for the file on this TV.

TARGET=${LIBCBE_TARGET:-/usr/lib/libcbe.so}
DIR=${LIBCBE_DIR:-/media/developer/libcbe}
ORIG=$DIR/original.so
PATCHED=$DIR/patched.so
STATE=${LIBCBE_STATE:-/var/lib/webosbrew/libcbe}
LINK=${LIBCBE_LINK:-/var/lib/webosbrew/init.d/45-libcbe-mount}
SELF=${LIBCBE_SELF:-/var/lib/webosbrew/libcbe-mount.sh}
MOUNTS=${LIBCBE_MOUNTS:-/proc/mounts}
LOG=$STATE/log

script_dir() {
    CDPATH= cd -- "$(dirname "$0")" && pwd
}

builds_file() {
    if [ -n "$LIBCBE_BUILDS" ]; then
        printf '%s\n' "$LIBCBE_BUILDS"
        return
    fi
    here=$(script_dir) || return 1
    if [ -f "$here/builds.txt" ]; then
        printf '%s\n' "$here/builds.txt"
        return
    fi
    printf '%s\n' /var/lib/webosbrew/libcbe-builds.txt
}

log() {
    mkdir -p "$STATE"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

is_mounted() {
    awk -v t="$TARGET" '$2==t { found=1 } END { exit !found }' "$MOUNTS"
}

hash_of() {
    sha256sum "$1" | awk '{ print $1 }'
}

# lookup <sha256> sets FOUND_PATCHED, FOUND_FW, FOUND_NOTE.
# Returns 1 when the hash is absent.
lookup() {
    want=$1
    file=$(builds_file) || return 1
    [ -f "$file" ] || return 1
    FOUND_PATCHED=
    FOUND_FW=
    FOUND_NOTE=
    while IFS= read -r line; do
        case $line in
            '' | '#'*) continue ;;
        esac
        set -- $line
        if [ "$1" = "$want" ]; then
            FOUND_PATCHED=$2
            FOUND_FW=$3
            shift 3
            FOUND_NOTE=$*
            return 0
        fi
    done < "$file"
    return 1
}

cmd_status() {
    file=$(builds_file)
    echo "target $TARGET"
    echo "builds $file"
    if is_mounted; then
        echo "mount present"
        awk -v t="$TARGET" '$2==t { print }' "$MOUNTS"
    else
        echo "mount absent"
    fi
    if [ -f "$STATE/enabled" ]; then echo "enabled yes"; else echo "enabled no"; fi
    if [ -f "$STATE/booting" ]; then echo "awaiting confirm"; else echo "awaiting confirm no"; fi
    if [ -f "$ORIG" ]; then echo "original $(hash_of "$ORIG")"; else echo "original missing"; fi
    if [ -f "$PATCHED" ]; then echo "patched $(hash_of "$PATCHED")"; else echo "patched missing"; fi
    if [ -f "$TARGET" ]; then
        live=$(hash_of "$TARGET")
        echo "live $live"
        if lookup "$live"; then
            echo "firmware $FOUND_FW"
            echo "note $FOUND_NOTE"
            if [ "$FOUND_PATCHED" = "-" ]; then
                echo "published patched none"
            else
                echo "published patched $FOUND_PATCHED"
            fi
        else
            echo "firmware unknown"
        fi
    else
        echo "live missing"
    fi
}

cmd_prepare() {
    mkdir -p "$DIR" "$STATE"
    if is_mounted; then
        echo "A mount is already covering $TARGET. Restore before taking a new backup."
        exit 1
    fi
    [ -f "$TARGET" ] || {
        echo "missing $TARGET"
        exit 1
    }
    cp -a "$TARGET" "$ORIG" || exit 1
    live=$(hash_of "$ORIG")
    echo "backup $ORIG"
    echo "sha256 $live"
    if lookup "$live"; then
        echo "firmware $FOUND_FW"
        echo "note $FOUND_NOTE"
        if [ "$FOUND_PATCHED" = "-" ]; then
            echo "No patched libcbe.so is published for this file yet. apply will refuse."
        else
            echo "A patched build is published. Place it at $PATCHED and run apply."
        fi
    else
        echo "This libcbe.so is not in builds.txt."
        echo "Save the sha256, the model, the webOS version, and the firmware, and send those with a report."
        echo "A libcbe.so from another firmware will not run on this TV. apply will refuse."
    fi
}

cmd_install() {
    here=$(script_dir) || exit 1
    [ -f "$here/builds.txt" ] || {
        echo "builds.txt is not next to $0"
        exit 1
    }
    mkdir -p "$STATE" "$(dirname "$LINK")" "$DIR"
    cp "$0" "$SELF" || exit 1
    cp "$here/builds.txt" /var/lib/webosbrew/libcbe-builds.txt || exit 1
    chmod 755 "$SELF"
    ln -sfn "$SELF" "$LINK"
    echo "installed $SELF"
    echo "boot hook $LINK"
}

mount_patched() {
    live_orig=$(hash_of "$ORIG")
    lookup "$live_orig" || {
        echo "backup hash is not in builds.txt"
        return 1
    }
    if [ "$FOUND_PATCHED" = "-" ] || [ -z "$FOUND_PATCHED" ]; then
        echo "No patched libcbe.so is published for firmware $FOUND_FW."
        return 1
    fi
    [ -f "$PATCHED" ] || {
        echo "missing $PATCHED"
        return 1
    }
    ph=$(hash_of "$PATCHED")
    [ "$ph" = "$FOUND_PATCHED" ] || {
        echo "patched sha256 is $ph"
        echo "builds.txt expects $FOUND_PATCHED"
        return 1
    }
    if is_mounted; then
        umount "$TARGET" || umount -l "$TARGET" || return 1
    fi
    mount --bind "$PATCHED" "$TARGET"
}

cmd_restore() {
    rm -f "$STATE/enabled" "$STATE/booting"
    rm -f "$LINK"
    if is_mounted; then
        umount "$TARGET" || umount -l "$TARGET" || {
            echo "umount failed"
            exit 1
        }
        log "unmounted"
    fi
    echo "restored. WebAppMgr keeps whatever it already loaded until it is started again."
}

cmd_boot() {
    [ -f "$STATE/enabled" ] || exit 0
    if [ -f "$STATE/booting" ]; then
        rm -f "$STATE/enabled" "$STATE/booting" "$LINK"
        if is_mounted; then
            umount "$TARGET" || umount -l "$TARGET"
        fi
        log "disabled: previous boot was never confirmed"
        exit 0
    fi
    mkdir -p "$STATE"
    touch "$STATE/booting"
    if is_mounted; then
        log "already mounted"
        exit 0
    fi
    mount_patched || {
        rm -f "$STATE/booting" "$STATE/enabled"
        log "boot refused the patched file"
        exit 0
    }
    log "mounted"
}

cmd_confirm() {
    rm -f "$STATE/booting"
    log "confirmed"
    echo "confirmed"
}

cmd_apply() {
    [ -f "$ORIG" ] || {
        echo "missing $ORIG"
        echo "Run prepare first."
        exit 1
    }
    mkdir -p "$STATE" "$(dirname "$LINK")"
    mount_patched || exit 1
    ln -sfn "$SELF" "$LINK"
    touch "$STATE/enabled" "$STATE/booting"
    log "applied $(hash_of "$PATCHED")"
    echo "mounted. WebAppMgr is still running the copy it loaded at start."
    echo "Start WebAppMgr again, and once the screen is back run: sh $SELF confirm"
    echo "Rollback: sh $SELF restore"
}

case "${1:-boot}" in
    status) cmd_status ;;
    prepare) cmd_prepare ;;
    install) cmd_install ;;
    restore) cmd_restore ;;
    boot) cmd_boot ;;
    confirm) cmd_confirm ;;
    apply) cmd_apply ;;
    *)
        echo "usage: $0 status|prepare|install|restore|boot|confirm|apply"
        exit 1
        ;;
esac
