#!/system/bin/sh
# VedoTom first-boot service (see init.vedotom.rc). Root, after boot completes, every boot;
# everything here checks a marker before it acts, so later boots cost nothing.

TAG=vedotom-firstboot
STATE=/data/local/vedotom-firstboot
mkdir -p "$STATE"
log -t "$TAG" "start"

# 1. Preloaded apps: APKs carried in /product/etc/preload are installed as ordinary apps on first
#    boot, with F-Droid recorded as installer so it keeps them updated. They keep the publisher's
#    signature, which a system-image prebuilt could not have done for an APK with compressed
#    native libraries (Organic Maps).
for apk in /product/etc/preload/*.apk; do
    [ -e "$apk" ] || continue
    marker="$STATE/$(basename "$apk").installed"
    [ -e "$marker" ] && continue
    if pm install -i org.fdroid.fdroid "$apk" >/dev/null 2>&1; then
        log -t "$TAG" "installed $apk"
        touch "$marker"
    else
        log -t "$TAG" "install of $apk failed; will retry next boot"
    fi
done

# 2. Fossify Launcher as the home screen. It and AOSP's Launcher3 (which stays for SystemUI's
#    gesture navigation and recents) answer HOME with equal priority, so the role controller's
#    fallback picks neither and Android shows a chooser. Assign the HOME role once, explicitly; a
#    launcher the user picks later is respected.
if [ ! -e "$STATE/home-role" ] && pm path org.fossify.home >/dev/null 2>&1; then
    if cmd role add-role-holder android.app.role.HOME org.fossify.home 0 >/dev/null 2>&1; then
        touch "$STATE/home-role"
        log -t "$TAG" "HOME role -> org.fossify.home"
    else
        log -t "$TAG" "HOME role assignment failed; will retry next boot"
    fi
fi

# 2b. Fennec F-Droid (a preload from step 1) as the default browser, so links from other apps
#     open in it without a chooser. Once, like the HOME role; a browser the user picks later wins.
if [ ! -e "$STATE/browser-role" ] && pm path org.mozilla.fennec_fdroid >/dev/null 2>&1; then
    if cmd role add-role-holder android.app.role.BROWSER org.mozilla.fennec_fdroid 0 >/dev/null 2>&1; then
        touch "$STATE/browser-role"
        log -t "$TAG" "BROWSER role -> org.mozilla.fennec_fdroid"
    else
        log -t "$TAG" "BROWSER role assignment failed; will retry next boot"
    fi
fi

# 3. Fossify app icons in teal, to match the image's wallpaper and accent (the suite's default is
#    green). Inside the apps Fossify already follows the system's Material You colours on
#    Android 12+; the launcher icon colour is a separate per-app choice, implemented as one
#    activity-alias per colour (SplashActivity.<Colour>) plus two preferences the app reconciles
#    on every start (app_icon_color and last_icon_color in shared_prefs/Prefs.xml). Setting all
#    three together is exactly what the app's own Customize screen does. Done once per app, so a
#    colour the user picks later is never overridden.
ICON_ALIAS=Teal
ICON_COLOR=-16746133        # md_teal_700, #ff00796b, as the signed int Android stores
changed=0
for pkg in $(pm list packages org.fossify. | sed 's/^package://'); do
    marker="$STATE/$pkg.icon"
    [ -e "$marker" ] && continue
    data="/data/data/$pkg"
    [ -d "$data" ] || continue
    pm enable "$pkg/$pkg.activities.SplashActivity.$ICON_ALIAS" >/dev/null 2>&1 || continue
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
    touch "$marker"; changed=1
    log -t "$TAG" "icon colour $ICON_ALIAS for $pkg"
done
# The launcher caches icons; restart it so the new ones show.
[ "$changed" = 1 ] && am force-stop org.fossify.home

log -t "$TAG" "done"
exit 0
