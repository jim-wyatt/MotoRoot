#!/system/bin/sh
# aosp-academy first-boot service (see init.aospacademy.rc). Root, after boot completes, every boot;
# everything here checks a marker before it acts, so later boots cost nothing.
#
# It reports in two places that outlast the log buffers: $STATE/log gets every line with a time,
# and $STATE/status holds one line, "running" while it works and "done failures=<n>" at the end.
# aosp-academy deploy reads both (as root: adb shell su 0 cat ...). The same lines go to logcat
# under the tag aospacademy-firstboot.

TAG=aospacademy-firstboot
STATE=/data/local/aospacademy-firstboot
LOG="$STATE/log"
STATUS="$STATE/status"
mkdir -p "$STATE"
failures=0
restart_launcher=0

note() {
    log -t "$TAG" "$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}
failed() { note "$* failed; will retry next boot"; failures=$((failures + 1)); }

# Charge-limit mode (init.aospacademy.rc starts it after boot and whenever the property changes):
# write persist.aospacademy.charge_limit to qpnp_adaptive_charge's upper_limit, the same single write
# Motorola's health HAL makes on stock. The module's own setter validates the value (1..100 above
# lower_limit, which stays -1: auto mode, as on stock); this checks it too. Reading parameters of
# the vendor charger modules in bulk has panicked this phone's kernel, so this touches two named
# files only: it writes upper_limit and never reads it (or lower_limit) back, and it checks the
# result through blocking, a read-only parameter with its own getter, which reports 1 while the
# module holds charging off. The result goes to the log and to $STATE/charge-limit for
# aosp-academy deploy. Verified by hand on the device first (2026-11-17): at 100% on the charger,
# blocking went 0 -> 1 and the battery status to "Not charging", as on stock with protection on.
#
# init's `start` does nothing for a oneshot that is still running, so a setprop during the 30 s
# wait would be lost. After the wait the property is read again, and a changed value is applied
# in turn. The result file is removed first: it lives in /data and outlasts reboots, and
# aosp-academy deploy must not read the previous boot's result as this one's.
if [ "$1" = charge-limit ]; then
    mod=/sys/module/qpnp_adaptive_charge/parameters
    rm -f "$STATE/charge-limit"
    result() { note "charge limit: $*"; echo "$*" > "$STATE/charge-limit"; exit 0; }
    v="$(getprop persist.aospacademy.charge_limit)"
    while :; do
        case "$v" in
            ''|*[!0-9]*) result "'$v' is not a number; left unchanged" ;;
        esac
        { [ "$v" -lt 50 ] || [ "$v" -gt 100 ]; } && result "$v is outside 50..100; left unchanged"
        [ -e "$mod/upper_limit" ] || result "qpnp_adaptive_charge not present; left unchanged"
        echo "$v" > "$mod/upper_limit" 2>/dev/null || result "writing $v to upper_limit failed"
        sleep 30    # the module re-evaluates on its next battery update
        now="$(getprop persist.aospacademy.charge_limit)"
        [ "$now" = "$v" ] && break
        note "charge limit: property changed to '$now' while $v was applied; applying it"
        v="$now"
    done
    result "upper_limit=$v, blocking=$(cat "$mod/blocking" 2>/dev/null) (1 = holding charge off)"
fi

echo running > "$STATUS"
note "start"

# 1. Fossify Launcher as the home screen. It and AOSP's Launcher3 (which stays for SystemUI's
#    gesture navigation and recents) answer HOME with equal priority, so the role controller's
#    fallback picks neither and Android shows a chooser. Assign the HOME role once, explicitly; a
#    launcher the user picks later is respected.
if [ ! -e "$STATE/home-role" ] && pm path org.fossify.home >/dev/null 2>&1; then
    if cmd role add-role-holder android.app.role.HOME org.fossify.home 0 >/dev/null 2>&1; then
        touch "$STATE/home-role"
        note "HOME role -> org.fossify.home"
    else
        failed "HOME role assignment"
    fi
fi

# 2. Development-target settings, the same values 'aosp-academy device settings' applies on the stock
#    system: Developer options shown, the screen kept on while charging (Stay awake: AC, USB,
#    wireless and dock, as the toggle writes), no animations (UI tests expect it, screens settle
#    at once), no verification scan of adb installs, no expiry of an authorised PC's ADB key, and
#    manual brightness at 64 of 255 (the OLED panel stays on while charging; it still dims when idle).
#    Entries are global settings unless prefixed system/.
#    Set once, as defaults: a value changed later in Developer options is kept. SettingsProvider
#    has resource defaults for only some of them in this tag, so they are all set here, in one place.
if [ ! -e "$STATE/dev-settings" ]; then
    ok=1
    for kv in development_settings_enabled=1 stay_on_while_plugged_in=15 window_animation_scale=0 transition_animation_scale=0 animator_duration_scale=0 \
              verifier_verify_adb_installs=0 adb_allowed_connection_time=0 \
              system/screen_brightness_mode=0 system/screen_brightness=64; do
        case "$kv" in system/*) ns=system; kv="${kv#system/}";; *) ns=global;; esac
        k="${kv%%=*}"; v="${kv#*=}"
        settings put "$ns" "$k" "$v" >/dev/null 2>&1
        [ "$(settings get "$ns" "$k" 2>/dev/null)" = "$v" ] || { ok=0; note "setting $ns $k=$v did not stick"; }
    done
    if [ "$ok" = 1 ]; then touch "$STATE/dev-settings"; note "development settings applied"
    else failed "development settings"; fi
fi

# 3. Hide the app-drawer icons of AOSP apps that stay for what they do in the background, where a
#    Fossify app is the one to open. Only the launcher entry is disabled, once per entry (neither
#    is gated on a resource in this tag); pm enable on the same component brings an icon back.
#      Files      DocumentsUI stays: it is the system file picker behind every open, get-content
#                 and save dialog (.picker.PickActivity), Fossify's included. Fossify File
#                 Manager is the file app. The icon is the activity-alias .LauncherActivity.
#      Keyboard   LatinIME stays as the fallback keyboard. Its settings are still reachable from
#                 Settings, System, Keyboard. Fossify Keyboard is the keyboard app.
for entry in "files com.android.documentsui/.LauncherActivity" \
             "keyboard com.android.inputmethod.latin/.setup.SetupActivity"; do
    name="${entry%% *}"; component="${entry#* }"
    [ -e "$STATE/$name-icon" ] && continue
    pm path "${component%%/*}" >/dev/null 2>&1 || continue
    if pm disable "$component" >/dev/null 2>&1; then
        touch "$STATE/$name-icon"; restart_launcher=1
        note "launcher icon hidden: $component"
    else
        failed "hiding the launcher icon $component"
    fi
done

# 4. Fossify app icons in teal, to match the image's wallpaper and accent (the suite's default is
#    green). Inside the apps Fossify already follows the system's Material You colours on
#    Android 12+; the launcher icon colour is a separate per-app choice, implemented as one
#    activity-alias per colour (SplashActivity.<Colour>) plus two preferences the app reconciles
#    on every start (app_icon_color and last_icon_color in shared_prefs/Prefs.xml). Setting all
#    three together is exactly what the app's own Customize screen does. Done once per app, so a
#    colour the user picks later is never overridden.
ICON_ALIAS=Teal
ICON_COLOR=-16746133        # md_teal_700, #ff00796b, as the signed int Android stores
for pkg in $(pm list packages org.fossify. | sed 's/^package://'); do
    marker="$STATE/$pkg.icon"
    [ -e "$marker" ] && continue
    data="/data/data/$pkg"
    [ -d "$data" ] || continue
    pm enable "$pkg/$pkg.activities.SplashActivity.$ICON_ALIAS" >/dev/null 2>&1 || { failed "icon colour for $pkg"; continue; }
    pm disable "$pkg/$pkg.activities.SplashActivity.Green" >/dev/null 2>&1
    am force-stop "$pkg"
    prefs="$data/shared_prefs"; f="$prefs/Prefs.xml"; uid=$(stat -c %u "$data")
    mkdir -p "$prefs"
    if [ -f "$f" ]; then
        sed -i '/name="app_icon_color"/d; /name="last_icon_color"/d' "$f"
        sed -i "s#</map>#    <int name=\"app_icon_color\" value=\"$ICON_COLOR\" />\n    <int name=\"last_icon_color\" value=\"$ICON_COLOR\" />\n</map>#" "$f"
    else
        printf "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    <int name=\"app_icon_color\" value=\"%s\" />\n    <int name=\"last_icon_color\" value=\"%s\" />\n</map>\n" "$ICON_COLOR" "$ICON_COLOR" > "$f"
    fi
    chown -R "$uid:$uid" "$prefs"; chmod 771 "$prefs"; chmod 660 "$f"
    restorecon -RF "$prefs" >/dev/null 2>&1
    touch "$marker"; restart_launcher=1
    note "icon colour $ICON_ALIAS for $pkg"
done

# The launcher caches icons and its app list; restart it so the changes above show.
[ "$restart_launcher" = 1 ] && am force-stop org.fossify.home

note "done failures=$failures"
echo "done failures=$failures" > "$STATUS"
exit 0
