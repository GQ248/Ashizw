#!/system/bin/sh
# Ashizw - Action Script for KernelSU Button
# Volume key controls with non-blocking output

CONFIG_DIR="/data/adb/.config/ashizw"
LOG_FILE="$CONFIG_DIR/ashizw.log"

log() {
    echo "[*] $(date '+%Y-%m-%d %H:%M:%S'): [ACTION] $1" >> "$LOG_FILE"
}

update_ksu_status() {
    status_msg="$1"
    if command -v ksud >/dev/null 2>&1; then
        ksud module config set override.description "$status_msg" 2>/dev/null
    fi
}

# Print to action screen only — no sleep, no blocking
show_message() {
    echo "$2 $1"
    log "$1"
}

start_shizuku() {
    show_message "Starting Shizuku..." "🔄"
    log "🚀 Starting Shizuku via Action..."
    update_ksu_status "🔄 Ashizw: Starting Shizuku..."

    # Use cached path first (fast), fall back to find with timeout (slow)
    LIB_CACHE="/data/adb/.config/ashizw/lib_cache"
    LIB_PATH=""

    if [ -f "$LIB_CACHE" ]; then
        cached=$(cat "$LIB_CACHE")
        [ -f "$cached" ] && LIB_PATH="$cached"
    fi

    if [ -z "$LIB_PATH" ]; then
        show_message "Locating libshizuku.so..." "🔍"
        LIB_PATH=$(timeout 5 find /data/app/ -type f -name "libshizuku.so" 2>/dev/null | head -n 1)
        [ -n "$LIB_PATH" ] && echo "$LIB_PATH" > "$LIB_CACHE"
    fi

    if [ -z "$LIB_PATH" ]; then
        show_message "libshizuku.so not found! Check Shizuku setup." "❌"
        update_ksu_status "❌ Ashizw: libshizuku.so Not Found"
        return 1
    fi

    show_message "Found: $LIB_PATH" "📍"
    chmod 755 "$LIB_PATH" 2>/dev/null
    "$LIB_PATH" &
    RET=$?

    if [ "$RET" -eq 0 ]; then
        show_message "Shizuku started successfully!" "✅"
        update_ksu_status "✅ Ashizw: Shizuku Restored"
        sleep 2
        update_ksu_status "💓 Shizuku Running | Watchdog Active ✅"
    else
        show_message "Failed to start (Exit: $RET)" "⚠️"
        update_ksu_status "⚠️ Ashizw: Start Failed (Code: $RET)"
    fi
}

stop_shizuku() {
    show_message "Stopping Shizuku..." "🛑"
    log "🛑 Stopping Shizuku via Action..."
    update_ksu_status "🛑 Ashizw: Stopping Shizuku..."

    pkill -f shizuku_server 2>/dev/null
    pkill -f shizuku 2>/dev/null
    sleep 2

    if ! pidof shizuku_server >/dev/null 2>&1; then
        show_message "Shizuku stopped successfully!" "✅"
        update_ksu_status "⚠️ Shizuku Stopped | Tap Action to Start"
    else
        show_message "Failed to stop Shizuku" "⚠️"
        update_ksu_status "⚠️ Ashizw: Stop Failed"
    fi
}

open_shizuku_app() {
    local line pkg PKG=""
    local lib_cache="/data/adb/.config/ashizw/lib_cache"

    # UI feedback: inform user that we are starting
    show_message "Opening Shizuku app..." "📱"

    # --- Dynamic extraction from lib cache ---
    if [ -r "$lib_cache" ]; then
        # Read first non-empty line from the cache file
        while IFS= read -r line && [ -z "$line" ]; do :; done < "$lib_cache"

        if [ -n "$line" ]; then
            # 1) Strip '/lib/' and everything after it from the end.
            #    /data/app/~~abc/com.pkg-xyz/lib/arm64/...  →  /data/app/~~abc/com.pkg-xyz
            line="${line%%/lib/*}"

            # 2) Strip all leading path components up to the last '/'.
            #    /data/app/~~abc/com.pkg-xyz  →  com.pkg-xyz
            line="${line##*/}"

            # 3) Strip the '-random' suffix from the end.
            #    com.pkg-xyz  →  com.pkg
            line="${line%%-*}"

            # Validate: a real package name must contain at least one dot
            case "$line" in
                *.*) PKG="$line" ;;
            esac
        fi
    fi

    # --- Fallback: check known Shizuku forks ---
    if [ -z "$PKG" ]; then
        for pkg in moe.shizuku.privileged.api com.hamondev.shevery; do
            # pm path exits 0 only if the package is installed
            if pm path "$pkg" >/dev/null 2>&1; then
                PKG="$pkg"
                break
            fi
        done
    fi

    # --- Launch with suppressed output and result feedback ---
    if [ -n "$PKG" ] && monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; then
        show_message "Shizuku app opened" "✅"
    else
        show_message "Failed to open Shizuku app" "⚠️"
    fi
}

# ============================================================
# Volume key detection
# ---------------------------------------------------------------
# getevent is the standard Android approach used by most module
# devs and is present in all Android versions (it reads directly
# from /dev/input/). The alternative — reading /dev/input/event*
# manually with dd — is much more complex and not more reliable.
#
# What we improved vs the original:
#   • Use `-q` (quiet) + `-c 1` (one event) in a fast loop
#   • No `sleep 3` blocking between messages
#   • Match both KEY_VOLUMEUP/DOWN and raw EV_KEY codes (0x73/0x72)
#     so it works even on kernels that report raw codes
# ---------------------------------------------------------------
wait_for_volume_key() {
    timeout=0
    while [ $timeout -lt 100 ]; do
        event=$(getevent -qlc 1 2>/dev/null)

        # Match by name OR raw hex code for broader device compat
        if echo "$event" | grep -qE "KEY_VOLUMEUP|0{0,4}73 00000001"; then
            echo "vol_up"
            return
        elif echo "$event" | grep -qE "KEY_VOLUMEDOWN|0{0,4}72 00000001"; then
            echo "vol_down"
            return
        fi

        timeout=$((timeout + 1))
        sleep 0.1
    done
    echo "timeout"
}

# ============================================================
# MAIN
# ============================================================
echo ""
echo "================================="
echo "   Ashizw Quick Action"
echo "================================="
echo ""

if pidof shizuku_server >/dev/null 2>&1; then
    CURRENT_STATE="running"
    ACTION_NAME="Stop"
    STATE_ICON="💓"
else
    CURRENT_STATE="stopped"
    ACTION_NAME="Start"
    STATE_ICON="⚠️"
fi

echo "  Status : $STATE_ICON Shizuku is $CURRENT_STATE"
echo ""
echo "  [Vol ↑]  $ACTION_NAME Shizuku"
echo "  [Vol ↓]  Open Shizuku App"
echo ""
echo "  Waiting for input (10s)..."
echo "---------------------------------"
log "Action menu displayed. State: $CURRENT_STATE"

KEY=$(wait_for_volume_key)

case "$KEY" in
    vol_up)
        echo "→ VOLUME UP: $ACTION_NAME Shizuku"
        log "Volume Up pressed: $ACTION_NAME action"
        if [ "$CURRENT_STATE" = "running" ]; then
            stop_shizuku
        else
            start_shizuku
        fi
        ;;
    vol_down)
        echo "→ VOLUME DOWN: Open Shizuku App"
        log "Volume Down pressed: Open app"
        open_shizuku_app
        ;;
    timeout)
        echo "⚠️  No input received. Exiting."
        log "Action timeout: no input"
        ;;
esac

exit 0
