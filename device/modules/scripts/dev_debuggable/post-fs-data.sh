#!/system/bin/sh
# dev_debuggable: make the running system report itself as a debuggable build.
#
# ro.debuggable=1 is what userdebug and eng builds set. With it, ART lets a debugger attach to
# any app (not only those with android:debuggable="true"), `run-as <package>` works for every
# package, `am set-debug-app` accepts any app, and tools that gate on the property (profilers,
# Frida's spawn gating, Android Studio's "attach to process") behave as on an engineering build.
#
# It does NOT make `adb root` work on a user build: the shipped adbd is compiled to drop root
# unconditionally, and this module does not replace adbd. Use `su -c` for root commands.
#
# resetprop -n sets the property without firing init's property triggers, so nothing else in
# init reacts to the change. This runs at post-fs-data, before zygote and adbd start, so both
# read the new value. Disable the module and reboot to return to the stock value (0).
#
# If the device ever fails to boot with this enabled, hold Volume Down during boot: Magisk's
# safe mode starts with every module disabled.
resetprop -n ro.debuggable 1
