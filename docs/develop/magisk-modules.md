# Build a system module

[Magisk modules](../concepts/magisk-modules.md) are how you change system behavior on a development device without touching the read-only system image. This page builds one from scratch, then shows how the project's own modules are generated.

## The smallest useful module

A module is a ZIP with a `module.prop` and, usually, a `system/` tree that gets overlaid onto the real `/system`. Here's one that adds a system-wide command.

```text
hellomod/
├── module.prop
└── system/
    └── bin/
        └── hello
```

```ini title="module.prop"
id=hellomod
name=Hello dev module
version=1.0
versionCode=1
author=you
description=Adds a 'hello' command to the system.
```

```sh title="system/bin/hello"
#!/system/bin/sh
echo "Hello from a Magisk module, running as $(id -un)."
```

Zip it with the files at the root (not inside a parent folder), install and reboot:

```powershell
Compress-Archive -Path hellomod\* -DestinationPath hellomod.zip
& $adb push hellomod.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/hellomod.zip'
& $adb reboot
# after reboot:
& $adb shell hello
```

`hello` is now a system command — because Magisk overlaid `/system/bin/hello` at boot. The real `/system` partition was never written. Disable the module in the Magisk app and reboot, and the command is gone.

## The lifecycle scripts

Beyond overlaying files, a module can run scripts at defined boot points:

```mermaid
flowchart LR
    I["customize.sh<br/>once, at install"] -.-> B
    B["post-fs-data.sh<br/>early boot, before apps"] --> S["service.sh<br/>late boot, system up"]
```

- `customize.sh` — runs once when you install the module; use it to set things up based on the device.
- `post-fs-data.sh` — early, blocking; for changes that must happen before apps start.
- `service.sh` — late, non-blocking; the usual place for "do something every boot."

All run as **root**. A broken script can slow or stop boot, so test incrementally — and remember a bad module is removed, not a bricked device: delete `/data/adb/modules/<id>` (from [recovery](../device/maintenance.md#recovery) or another root shell) and reboot.

## How the project generates its modules

The two shipped modules are built by a Python script, not hand-zipped — a good pattern once modules get repetitive. `kit/scripts/build_modules.py` reads `kit/carrier-debloat-manifest.json` (the 22 carrier packages and their directories) and writes both module ZIPs, validating every path as it goes.

Rebuild and verify them against the committed copies:

```powershell
.\dev\Build-Kit.ps1
```

Both use the `.replace` convention — an empty overlay that *hides* a system directory rather than adding to it (see [the modules concept page](../concepts/magisk-modules.md#the-two-modules-in-this-project)). Reading `build_modules.py` is the fastest way to see how a real, parameterized module generator is structured.

!!! tip "Keep modules reversible and scoped"
    The whole value of a module on a dev device is that it's an experiment you can turn off. Resist editing the real system partition directly; a module that overlays is always the cleaner choice.

Next: [Inspect app packages](inspecting-apps.md).
