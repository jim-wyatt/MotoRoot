#!/system/bin/sh
# dev_debuggable: apply the log buffer size that deploy\Set-DevSettings.ps1 stores.
#
# persist.logd.size is the property Developer options' "Logger buffer sizes" writes, but logd on
# this build does not apply it at boot or on logd --reinit (verified on Android 16: the buffers
# come up at the stock 256 KiB with the property set to 16M). logcat -G does apply it, until the
# next reboot, so this re-applies the stored value once boot has finished. With the property
# unset (Set-DevSettings.ps1 -Reset) this does nothing and the stock size stays.
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
size=$(getprop persist.logd.size)
[ -n "$size" ] && logcat -G "$size"
