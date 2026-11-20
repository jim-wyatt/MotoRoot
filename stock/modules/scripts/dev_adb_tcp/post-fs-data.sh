#!/system/bin/sh
# dev_adb_tcp: have adbd listen on TCP port 5555 from boot, so ADB works over Wi-Fi.
#
# adbd reads service.adb.tcp.port when it starts. Setting it here, at post-fs-data and before
# adbd starts, means every boot comes up listening on 5555 in addition to USB, with no
# `adb tcpip` step and no Android 11+ pairing dialog. From the dev shell: adbwifi
#
# Security: adbd still enforces key authorization (ro.adb.secure=1 on this build), so a PC
# must hold an RSA key you have approved on the phone before it gets a shell. The port is
# nevertheless reachable by anyone on the same network, so keep this module disabled on
# networks you don't control. Disable the module and reboot to go back to USB only.
resetprop -n service.adb.tcp.port 5555
