# Trace the system with Perfetto

[Perfetto](https://perfetto.dev/) is Android's built-in tracing system: the `perfetto` command and the `traced` daemons ship in every modern firmware, including this one (`persist.traced.enable=1` out of the box). A trace records what every CPU was doing, when processes were scheduled, how memory moved, what the framework was up to (app launches, window transitions, binder calls) and the system log, all on one timeline. Android Studio's profilers use it underneath; the command line gives you the whole device instead of one app. No root is needed.

## Record a trace

From the dev shell:

```powershell
.\dev\Trace-Device.ps1 -Seconds 15 -Name app-launch
```

It sends a text config over ADB, records for 15 seconds (do the thing you want to look at on the phone meanwhile), pulls the result to `work\traces\app-launch.pftrace`, and removes the copy on the device. The default config records CPU scheduling and frequency, process and memory stats, the system log, and the standard `atrace` categories for app, UI and binder work, which is the right starting point for most questions.

Open the file at [ui.perfetto.dev](https://ui.perfetto.dev): drag it onto the page. The UI runs in your browser and the trace is not uploaded anywhere.

Two lines in the output are normal: perfetto's "No PTY, CTRL+C won't gracefully stop the trace" (there is no terminal behind `adb shell`; the trace stops on its own at the duration) and the `Wrote N bytes` confirmation. The config file is pushed to `/data/misc/perfetto-configs/`, the one place SELinux lets `perfetto` read configs from, and removed afterwards; a copy stays next to the trace as `<name>.pbtxt`.

## Read it

The first time, try an app launch: start the trace, open an app that was closed, stop. In the UI:

1. The **CPU** tracks at the top show each core's scheduling; a cold launch is a burst on the big cores (cpu6–7 on this device; see the [hardware inventory](../device/hardware.md)).
2. Expand the launched app's process to see its threads and the atrace slices the framework emitted (`activityStart`, `bindApplication`, `inflate`, frame work).
3. The **Android logs** track lines the logcat output up with everything else.
4. Press `?` for the keyboard shortcuts; `w`/`s` zoom, `a`/`d` pan, click a slice for its details.

The [Perfetto UI docs](https://perfetto.dev/docs/visualization/perfetto-ui) explain the rest; SQL over the trace (the **Query** page) is the power tool once you want to answer questions like "what ran while the UI thread was blocked".

## Your own config

Pass `-Config myconfig.pbtxt` to record exactly what you want: more `ftrace_events`, `heapprofd` for native allocations, `android.java_hprof` for Java heap snapshots, or longer `duration_ms`. The [config reference](https://perfetto.dev/docs/concepts/config) and the **Record new trace** page of the UI (which generates text configs) cover the options. Traces land in `work\traces\`, which is git-ignored: they contain package lists and log lines, so they stay private.

## Profiling other apps, and the simpleperf gap

Perfetto's heap profilers (`android.java_hprof` for Java heap dumps, `heapprofd` for native allocations) only touch apps that are *profileable* or *debuggable*, unless the build itself is a `userdebug` build. On this device the [`dev_debuggable` module](../device/dev-setup.md) makes the system report exactly that, and with it a heap dump of any app works; without it, logcat shows `not profileable` and the trace is empty. Your own debug builds are profileable regardless.

`simpleperf`, the NDK's sampling CPU profiler, is **not usable on this device**: the MediaTek kernel exposes no perf events to it (`simpleperf record` fails with "Event type 'cpu-cycles' is not supported on the device", and `-e cpu-clock` fails the same way). That also limits Android Studio's sampled CPU profiler, which is simpleperf underneath; Perfetto's system trace and Studio's system-trace mode work fine, because they use ftrace, not perf counters.

| You want | Tool |
| --- | --- |
| The whole device on one timeline: scheduling, memory, framework events, logs | Perfetto (`Trace-Device.ps1`), or Studio's system trace |
| Memory: Java heap dump or native allocations of any app | Perfetto `android.java_hprof` / `heapprofd` (with the userdebug module for apps that aren't yours) |
| Hot functions by CPU sampling | not available on this device (no perf events); use trace slices and Frida timing instead |
| What a process is *doing*, call by call | [Frida](instrumentation.md) |

Next: [Your first app in Android Studio](android-studio.md).
