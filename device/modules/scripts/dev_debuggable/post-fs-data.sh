#!/system/bin/sh
# dev_debuggable: make the running system report itself as a userdebug (engineering) build.
#
# Two properties, set at post-fs-data before zygote, system_server and adbd start:
#   ro.debuggable=1          what userdebug and eng builds set; tools that gate on it treat the
#                            device as debuggable.
#   ro.build.type=userdebug  what Perfetto's heap profilers (and other tooling) actually check
#                            before touching an app that is not itself profileable. Verified on
#                            this device: with it, Perfetto takes a Java heap dump of any app;
#                            with ro.debuggable alone it refuses ("not profileable").
#
# Not changed on this build (Android 16, tested): `run-as <package>` still checks the app's own
# debuggable flag, and `adb root` still does not work (the shipped adbd is compiled to drop
# root; asking makes it abort and restart as shell), so use `su -c` for root commands. Some
# apps refuse to run on a build that reports itself as debuggable or userdebug; disable the
# module and reboot to return to the stock values (0 / user).
#
# resetprop -n sets the properties without firing init's property triggers, so nothing else in
# init reacts. If the device ever fails to boot with this enabled, hold Volume Down during
# boot: Magisk's safe mode starts with every module disabled.
resetprop -n ro.debuggable 1
resetprop -n ro.build.type userdebug
