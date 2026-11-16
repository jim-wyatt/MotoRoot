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

## CPU profiling one process: simpleperf

For "where in *my* code is the time going", the NDK's `simpleperf` samples a single process with symbols:

```powershell
& $adb shell simpleperf record -p (& $adb shell pidof com.example.myapp) --duration 10 -o /data/local/tmp/perf.data
& $adb pull /data/local/tmp/perf.data "$Work\traces\perf.data"
```

Android Studio's CPU profiler wraps the same tool with a UI, which is where you'll normally use it once your projects live there.

| You want | Tool |
| --- | --- |
| The whole device on one timeline: scheduling, memory, framework events, logs | Perfetto (`Trace-Device.ps1`) |
| Hot functions in one process | simpleperf, or Studio's CPU profiler |
| What a process is *doing*, call by call | [Frida](instrumentation.md) |

Next: [Your first app in Android Studio](android-studio.md).
