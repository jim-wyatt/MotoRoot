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

log -t "$TAG" "done"
exit 0
