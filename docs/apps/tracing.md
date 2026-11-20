# Tracing with Perfetto

[Perfetto](https://perfetto.dev/) is Android's built-in tracing system. The `perfetto` command and its `traced` daemons ship with every recent Android, the image included. A trace records, on one timeline, what every CPU was doing, when each thread was scheduled, CPU frequencies, process memory, what the framework was doing (activity starts, binder calls, view inflation, frames) and the system log. Android Studio's system-trace recording is Perfetto underneath; the command line gives you the whole device, not one app. No root is needed.

## Record a trace

```sh
./aosp-academy device trace --seconds 15 --name app-launch
```

It records for 15 seconds (default 10, at most 600): do what you want to look at on the phone meanwhile. Then it pulls the result to `work/traces/app-launch.pftrace` and removes the copies on the phone. Without `--name` the file is named after the date and time; a name may hold letters, digits, dots, underscores and dashes, and an existing trace is never overwritten.

Open the file at [ui.perfetto.dev](https://ui.perfetto.dev) by dragging it onto the page. The UI runs in your browser, and the trace isn't uploaded anywhere.

The default recording is the right starting point for most questions:

| Source | What it records |
| --- | --- |
| `linux.ftrace` | CPU scheduling (`sched_switch`, `sched_wakeup`), CPU frequency and idle states |
| atrace categories `am`, `wm`, `view`, `gfx`, `input`, `binder_driver`, for all apps | The framework's own trace slices: activity and window management, view work, graphics and frames, input, binder |
| `linux.process_stats` | Every process and thread, with memory, polled each second |
| `android.log` | The system log, lined up with everything else |

Two lines in the output are normal: perfetto's "No PTY, CTRL+C won't gracefully stop the trace" (there is no terminal behind `adb shell`; the trace stops on its own at the end of the duration) and its `Wrote N bytes` confirmation. The configuration is pushed to `/data/misc/perfetto-configs/`, the one directory SELinux lets `perfetto` read configurations from (`/data/local/tmp` is refused), and removed afterwards.

## Read it

The first time, trace an app launch: start the recording, open an app that wasn't running, wait for the recording to end. In the UI:

1. The **CPU** tracks at the top show each core's scheduling. A cold launch is a burst on the big cores (cpu6 and cpu7 on this phone; see the [hardware inventory](../device/hardware.md)).
2. Expand the launched app's process to see its threads, and the slices the framework emitted on them (`activityStart`, `bindApplication`, `inflate`, frame work).
3. The **Android logs** track shows the log lines at the moment they were written.
4. Press `?` for the keyboard shortcuts: `w` and `s` zoom, `a` and `d` pan, and a click on a slice shows its details.

The [Perfetto UI documentation](https://perfetto.dev/docs/visualization/perfetto-ui) explains the rest. The **Query (SQL)** page is the power tool once you want to ask questions like "what ran while the UI thread was blocked".

Your own app can add slices to the timeline with `android.os.Trace.beginSection("name")` and `endSection()` (or `androidx.tracing`), which show up on its threads when the trace includes the app (the default `atrace_apps` is all apps).

## Your own configuration

```sh
./aosp-academy device trace --config my-config.pbtxt --name heap
```

A Perfetto text configuration records exactly what you ask for: more `ftrace_events`, `heapprofd` for native allocations, `android.java_hprof` for Java heap dumps, a bigger buffer. With `--config`, the duration is the `duration_ms` in your file, not `--seconds`. The [configuration reference](https://perfetto.dev/docs/concepts/config) and the UI's **Record new trace** page (which generates text configurations) cover the options.

Traces land in `work/traces/`, which is git-ignored: they contain the package list and log lines, so they stay private.

## Profiling apps that aren't yours

Perfetto's heap profilers (`android.java_hprof` for Java heap dumps, `heapprofd` for native allocations) only profile apps that are *profileable* or *debuggable*, unless the system is a `userdebug` build. The image is one, so a heap dump of any app works, the system's own apps included. On the stock system that needed a module that makes the phone report itself as userdebug: there, with the module, a heap dump of Settings came back as 24 MB, and without it logcat said `not profileable` and the trace was empty. Your own debug builds are profileable everywhere.

## The simpleperf gap

`simpleperf`, the NDK's sampling CPU profiler, is **not usable on this phone**. The vendor kernel, which the image runs on unchanged, exposes no performance-counter events to it: `simpleperf record` fails with "Event type 'cpu-cycles' is not supported on the device", and `-e cpu-clock` fails the same way. Android Studio's *Callstack Sample* CPU recording is simpleperf underneath and is limited the same way. Perfetto's system trace and Studio's system-trace recording work, because they use the kernel's ftrace, not performance counters.

| You want | Use |
| --- | --- |
| The whole device on one timeline: scheduling, memory, framework events, logs | `aosp-academy device trace`, or Studio's system trace |
| A Java heap dump or native allocations, of any app | Perfetto with `android.java_hprof` or `heapprofd`, or Studio's memory profiler |
| Where your own code spends time | `Trace.beginSection` slices in a Perfetto trace, or timing hooks with [Frida](instrumentation.md) |
| Hot functions by CPU sampling | not available on this phone (no performance counters) |
| What a process is doing, call by call | [Frida](instrumentation.md) |

The device test records a 2-second trace with the default configuration, checks it isn't empty and deletes it, so `./aosp-academy device test` tells you whether tracing works right now.
