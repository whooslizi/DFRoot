#!/usr/bin/env bash
set -euo pipefail

DFROOT_PKG="df.root"
DFROOT_SVC="df.root/.AdbExploitService"
ADB_ARGS=()
SU_MANAGER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s)
            ADB_ARGS+=("-s" "$2")
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s <serial>] [<su_manager_package>]"
            exit 0
            ;;
        *)
            SU_MANAGER="$1"
            shift
            ;;
    esac
done

adb_cmd() {
    adb "${ADB_ARGS[@]}" "$@"
}

if ! adb_cmd get-state >/dev/null 2>&1; then
    echo "No ADB device found."
    exit 1
fi

if ! adb_cmd shell pm path "$DFROOT_PKG" >/dev/null 2>&1; then
    echo "DFRoot app is not installed."
    exit 1
fi

if [[ -z "$SU_MANAGER" ]]; then
    SU_MANAGER=$(adb_cmd shell "cat /data/user_de/0/${DFROOT_PKG}/shared_prefs/dfroot.xml 2>/dev/null" | grep -o 'su_manager">[^<]*' | cut -d'>' -f2 || true)
fi

if [[ -z "$SU_MANAGER" ]]; then
    echo "No SU manager specified and none saved."
    exit 1
fi

if adb_cmd shell "test -e /dev/df" 2>/dev/null; then
    echo "/dev/df exists; already hooked."
    exit 0
fi

adb_cmd logcat -c 2>/dev/null || true

EXTRAS="--es su_manager $SU_MANAGER"
adb_cmd shell am startservice -n "$DFROOT_SVC" $EXTRAS >/dev/null 2>&1 || {
    echo "Failed to start AdbExploitService."
    exit 1
}

adb_cmd logcat -s "DFRoot-ADB:*" | while IFS= read -r line; do
    msg=$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')
    echo "$msg"
    if echo "$line" | grep -q "RESULT: SUCCESS"; then
        kill $$ 2>/dev/null || true
        exit 0
    elif echo "$line" | grep -q "RESULT: ERROR"; then
        kill $$ 2>/dev/null || true
        exit 1
    fi
done
