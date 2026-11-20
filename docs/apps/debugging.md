# Debugging

On a retail phone a debugger reaches only your own app, and only a debug build of it. On the aosp-academy image it reaches **every process on the device**, the system's own included, and root is one command away. This page shows how to use that: attaching a debugger, the system log, root shells and bug reports.

## How Java debugging works on Android

Each app runs in its own process, in ART, Android's Java runtime. A debugger talks to ART over **JDWP**, the Java Debug Wire Protocol, the same protocol desktop Java debuggers use. The phone's adb daemon keeps a list of the processes that have JDWP open, and forwards a connection from the PC to any of them. Android Studio's debugger is a JDWP client; so is `jdb`, the command-line debugger that comes with the JDK.

Which processes open JDWP is decided when Zygote, the process every app is started from, starts. Normally only apps marked `android:debuggable` (your debug builds) get it. The image sets `persist.debug.dalvik.vm.jdwp.enabled=1`, and on a `userdebug` build that makes Zygote open JDWP in **every** app process: `system_server` (the process that runs Android's system services), SystemUI, Settings, the phone and Bluetooth processes, the network stack, the Fossify apps and whatever you install. The image has done this since build 9; see [what the image gives you](the-image.md#debugging-and-profiling-any-process) for the property itself and how to turn it off.

## Attach to any process

### From Android Studio

1. Open any project (your app's, or an empty one just for debugging).
2. **Run, Attach Debugger to Android Process.**
3. Tick **Show all processes**, pick the process (for example `system_server` or `com.android.systemui`) and confirm.

Breakpoints in your own code work as usual. To step through framework code you didn't write, Studio needs the source: the SDK Manager's *Sources for Android* package for the platform, where it offers one for API 37, gives Studio the framework's Java source to show. It's Google's source for that API level, close to but not exactly the tag the image is built from, so a line here or there can be off. Classes from other apps show as decompiled code.

### From the command line

`adb jdwp` lists the process ids that accept a debugger, and keeps running until you stop it (Ctrl+C):

```sh
adb jdwp                                   # one process id per line
adb shell ps -A -o PID,NAME | grep 1234    # which process an id belongs to
adb shell pidof com.android.systemui       # or the other way round
```

To attach `jdb`, forward a local TCP port to the process's JDWP channel and connect to it:

```sh
adb forward tcp:8700 jdwp:1234
jdb -connect com.sun.jdi.SocketAttach:hostname=localhost,port=8700
adb forward --remove tcp:8700              # when you're done
```

(The `-connect` form works on every OS; on Windows `jdb -attach` would try a shared-memory connection instead of TCP.)

To debug an app from its very first line, start it suspended and attach before it runs: `adb shell am start -D -n <package>/<activity>`. The app waits with *Waiting for debugger* until a debugger connects. A `userdebug` build allows this for any app, not only debuggable ones.

### Native code

The same property also allows `ptrace` on app processes, which is what native debuggers use. For your own app's C or C++ code, Studio's debugger (set to *Dual* or *Native*) attaches LLDB through adb as on any phone; with `adb root`, native debuggers can reach the system's processes as well. [Native code](native-code.md) covers building it.

### Check it

The device test counts the processes that accept a debugger:

```sh
./aosp-academy device test
```

Its `debug` area runs `adb root` and back (on a `userdebug` image), then lists `adb jdwp` for four seconds and reports the number together with the property's value. On build 9 it listed 24 processes at idle; the number follows how many apps are running. A count of 0 is what a system shows that opens JDWP only for debuggable apps: the phone's stock system, or an image with the property off.

## Logs

Android's system log is a set of ring buffers in memory, kept by the `logd` daemon: `main` (apps), `system` (system services), `crash` (crashes), `events` (structured system events), `radio` and `kernel`. `adb logcat` reads them. Studio's **Logcat** window is the same data with filters.

On the image every buffer is **16 MiB**, not logd's 256 KiB default, which the vendor's log spam fills within minutes. With 16 MiB, the lines from the start of a test session are still there when you look.

```sh
adb logcat -g                                       # buffer sizes ("ring buffer is 16 MiB")
adb logcat --pid=$(adb shell pidof -s com.example.firstapp)   # one process (bash; in PowerShell, get the pid first)
adb logcat -s MyTag                                 # one tag
adb logcat -b crash -d                              # crashes since boot, then exit
adb logcat -d -T '11-19 14:00:00.000'               # everything since a time, then exit
adb logcat -c                                       # clear the buffers before a test run
```

Crash details beyond the log are in `/data/tombstones` (native crashes) and `/data/anr` (app-not-responding traces), which need root to read: `adb shell su 0 ls /data/tombstones`. `adb shell dumpsys <service>` prints the state of any system service (`dumpsys activity`, `dumpsys package <pkg>`, `dumpsys meminfo <pkg>`); `adb shell dumpsys -l` lists them.

## Root: `adb root`

```sh
adb root          # adbd restarts as root; every adb shell after this is a root shell
adb shell id      # uid=0(root)
adb unroot        # back to the unprivileged shell user
```

`adb root` works because the image is a real `userdebug` build; on the phone's stock system it doesn't. With it you can read any app's private data under `/data/data/<package>`, pull system files, and change any property or setting. For a single command without restarting adbd, `adb shell su 0 <command>` does the same.

For your own debuggable app there is also the unprivileged way, which works on every phone: `adb shell run-as com.example.firstapp ls files` runs as the app's own user, inside its data folder.

## Bug reports

A bug report is Android's full snapshot of a device's state: every log buffer, `dumpsys` of every service, tombstones, ANRs, process and memory lists. It's what you attach when a problem needs someone else's eyes, or what you keep from a run you can't repeat.

```sh
./aosp-academy device info --bugreport --label my-crash
```

This writes a hardware and software inventory to `work/device-info/<timestamp>-my-crash/`: raw dumps (properties, packages, `dumpsys` output, the whole log and the crash buffer, the VINTF manifests, the partition table), a `summary.txt` without identifiers, and with `--bugreport` the full `bugreport.zip` (it takes several minutes). It only reads from the phone. Without the option, you get the inventory alone; `adb bugreport <file>.zip` takes just the bug report.

!!! warning "Bug reports and raw dumps are private"
    They contain the phone's serial number, IMEI, MAC addresses, network names and the full app list. `work/` is git-ignored, so they never reach the repository; don't post them in public issues either. `summary.txt` is the part written to be shared.
