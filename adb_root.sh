#!/usr/bin/env bash

DFROOT_PKG="df.root"
DFROOT_ACT="df.root/.MainActivity"
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

state=$(adb_cmd get-state 2>&1)
if [[ "$state" != "device" ]]; then
    echo "ADB device not ready. Status: $state"
    exit 1
fi

pkg_path=$(adb_cmd shell pm path "$DFROOT_PKG" 2>&1)
if ! echo "$pkg_path" | grep -q "package:"; then
    echo "DFRoot app is not installed on this device."
    exit 1
fi

if [[ -z "$SU_MANAGER" ]]; then
    SU_MANAGER=$(adb_cmd shell "cat /data/user_de/0/${DFROOT_PKG}/shared_prefs/dfroot.xml 2>/dev/null" | grep -o 'su_manager">[^<]*' | cut -d'>' -f2 || true)
fi

if [[ -z "$SU_MANAGER" ]]; then
    echo "No SU manager specified and none saved in app settings."
    exit 1
fi

if adb_cmd shell "test -e /dev/df" 2>/dev/null; then
    echo "/dev/df exists; already hooked on this boot."
    exit 0
fi

echo "Target SU manager: $SU_MANAGER"
echo "Launching DFRoot..."

adb_cmd logcat -c 2>/dev/null || true

# Save the SU manager choice into the app prefs directly
adb_cmd shell "mkdir -p /data/user_de/0/${DFROOT_PKG}/shared_prefs && echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map><string name=\"su_manager\">${SU_MANAGER}</string></map>' > /data/user_de/0/${DFROOT_PKG}/shared_prefs/dfroot.xml" 2>/dev/null || true

# Start MainActivity directly with autorun
adb_cmd shell am start -n "$DFROOT_ACT" --ez autorun true >/dev/null 2>&1

echo "Monitoring exploit logs (Ctrl+C to exit)..."
adb_cmd logcat -s "dfroot:*" "DFRoot-ADB:*" | while IFS= read -r line; do
    msg=$(echo "$line" | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //')
    echo "$msg"
    if echo "$line" | grep -q "SUCCESS"; then
        kill $$ 2>/dev/null || true
        exit 0
    elif echo "$line" | grep -q "Error\|nonzero"; then
        kill $$ 2>/dev/null || true
        exit 1
    fi
done
