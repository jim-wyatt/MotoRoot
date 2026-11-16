# Instrument running code with Frida

[Frida](https://frida.re/) injects a JavaScript engine into a running process and lets you hook any function in it, Java or native, from your PC. On an emulator you'd rarely bother; on a rooted real device it is the fastest way there is to learn what the framework and the vendor's apps actually do. This page gets it running and shows the three things you'll use most.

!!! note "Your device, your processes"
    Hooking is a normal engineering activity on a device you own: reading how system services behave, debugging your own apps against real hardware, checking what a preinstalled app does. Keep it to that. The [disclaimer](../reference/disclaimer.md) applies.

## What the bootstrap set up

Two halves, pinned to the same version in `dev/toolchain.json` (they must match):

- **On the device:** `frida-server`, an ARM64 binary that runs as root and does the injecting. Downloaded from Frida's GitHub release, hash-verified, extracted to `work\device-tools\frida-server`.
- **On the PC:** `frida-tools` in `work\.venv-frida`, which the dev shell puts on PATH: `frida`, `frida-ps`, `frida-trace`, `frida-discover`.

The self-test confirms both halves are present and the same version.

## Start the agent

```powershell
Start-Frida        # pushes frida-server, starts it as root, lists a few processes to prove the link
frida-ps -U        # every process on the device (-U = USB; the TCP device works the same)
frida-ps -Ua       # only apps, with their package names
```

`Start-Frida` is idempotent; the server stays up until reboot. Stop it with `& $adb shell su -c 'pkill -x frida-server'`. A line reading `Unable to start idund: idund did not start listening` from `frida-ps` is noise: recent `frida-tools` first try to auto-deploy their own helper over ADB, fail because the pinned server already answers, and carry on using it.

## Trace function calls without writing code

`frida-trace` generates hooks from a pattern and prints every call with its arguments:

```powershell
# Which files does Settings open? Trace libc's open() in the running Settings process.
frida-trace -U -i 'open' com.android.settings

# Which system properties does the Play Store read at startup? Spawn it fresh and hook the Java API.
frida-trace -U -f com.android.vending -j 'android.os.SystemProperties!get'
```

`-i` matches native exports, `-j` matches `Class!method` in Java, `-f` spawns the app so you catch startup, and a bare package name attaches to the running one. The generated handlers land in a `__handlers__` folder next to you; edit one to log arguments or change return values, and `frida-trace` picks the edit up live.

## Write a hook

A script that watches a system API from inside any app, here the property reads that tell an app which device it's on:

```javascript title="props.js"
Java.perform(() => {
  const SystemProperties = Java.use('android.os.SystemProperties');
  SystemProperties.get.overload('java.lang.String').implementation = function (key) {
    const value = this.get(key);
    console.log(`SystemProperties.get(${key}) -> ${value}`);
    return value;
  };
});
```

```powershell
frida -U -f com.android.vending -l props.js      # spawn the app with the hook installed
```

Everything in `Java.use` is the real framework class on the device, so the same technique reaches hidden APIs, vendor services and your own app's internals. The [Frida JavaScript API](https://frida.re/docs/javascript-api/) is the reference; `Interceptor.attach` is the native equivalent of the Java override above.

## When to reach for it

| You want to know | Use |
| --- | --- |
| Which files, sockets or properties a process touches | `frida-trace -i` / `-j` |
| What a hidden or vendor API returns in practice | a `Java.use` hook that logs |
| Why your app behaves differently on this device than in the emulator | hook the call that differs and compare |
| Where time goes, system-wide | not Frida: [Perfetto](tracing.md) |

Next: [Trace the system with Perfetto](tracing.md).
