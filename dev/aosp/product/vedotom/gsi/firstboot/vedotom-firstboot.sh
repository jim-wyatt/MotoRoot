#!/system/bin/sh
# VedoTom first-boot service (see init.vedotom.rc). Root, after boot completes, every boot;
# everything here checks a marker before it acts, so later boots cost nothing.
#
# It reports in two places that outlast the log buffers: $STATE/log gets every line with a time,
# and $STATE/status holds one line, "running" while it works and "done failures=<n>" at the end.
# Deploy-Image.ps1 reads both (as root: adb shell su 0 cat ...). The same lines go to logcat
# under the tag vedotom-firstboot.

TAG=vedotom-firstboot
STATE=/data/local/vedotom-firstboot
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

# 2. Development-target settings, the same values dev\Set-DevSettings.ps1 applies on the stock
#    system: no animations (UI tests expect it, screens settle at once), no verification scan of
#    adb installs, and no expiry of an authorised PC's ADB key. Set once, as defaults: a value
#    changed later in Developer options is kept. SettingsProvider has resource defaults for only
#    two of the five in this tag, so they are all set here, in one place.
if [ ! -e "$STATE/dev-settings" ]; then
    ok=1
    for kv in window_animation_scale=0 transition_animation_scale=0 animator_duration_scale=0 \
              verifier_verify_adb_installs=0 adb_allowed_connection_time=0; do
        k="${kv%%=*}"; v="${kv#*=}"
        settings put global "$k" "$v" >/dev/null 2>&1
        [ "$(settings get global "$k" 2>/dev/null)" = "$v" ] || { ok=0; note "setting $k=$v did not stick"; }
    done
    if [ "$ok" = 1 ]; then touch "$STATE/dev-settings"; note "development settings applied"
    else failed "development settings"; fi
fi

# 3. Hide the AOSP Files icon. Fossify File Manager is the file app; DocumentsUI stays installed
#    because it is the system file picker behind every open, get-content and save dialog
#    (.picker.PickActivity), Fossify's included. Only its launcher entry, the activity-alias
#    .LauncherActivity (not gated on any resource in this tag), is disabled. Once: the user can
#    enable it again with pm enable.
if [ ! -e "$STATE/files-icon" ] && pm path com.android.documentsui >/dev/null 2>&1; then
    if pm disable com.android.documentsui/.LauncherActivity >/dev/null 2>&1; then
        touch "$STATE/files-icon"; restart_launcher=1
        note "AOSP Files icon hidden (DocumentsUI kept as the file picker)"
    else
        failed "hiding the AOSP Files icon"
    fi
fi

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
