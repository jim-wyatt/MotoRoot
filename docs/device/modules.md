# The Magisk modules

[Magisk modules](../concepts/magisk-modules.md) are how this project changes the stock system's behaviour without touching the read-only system partitions. The prepared stock system runs seven of them; [The stock system](stock.md#the-seven-modules) says what each one does. This page is about how they are made: the manifests that describe them, the builder that turns a manifest into a ZIP, how the committed ZIPs are verified, and how to write a module of your own.

Modules belong to the stock system. Inside an aosp-academy image they don't apply: Magisk keeps them in the stock system's `/data`, which the image doesn't see.

## The smallest useful module

A module is a ZIP with a `module.prop` and, usually, a `system/` tree that Magisk overlays onto the real `/system` at boot. Here's one that adds a system-wide command.

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

Zip it with the files at the root of the archive (not inside a parent folder), install it and reboot. Python's standard library does the zipping the same way on every OS; the commands run in a shell opened with `aosp-academy shell`:

```sh
python -c "import shutil; shutil.make_archive('hellomod', 'zip', 'hellomod')"
adb push hellomod.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/hellomod.zip'"
adb reboot
adb shell hello        # after the reboot
```

`hello` is now a system command, because Magisk overlaid `/system/bin/hello` at boot. The real `/system` partition was never written. Disable the module in the Magisk app and reboot, and the command is gone. (A script made on Windows may have CRLF line endings, which `sh` on the phone chokes on; the project's builder normalises its own scripts for exactly that reason, as below.)

## The lifecycle scripts

Beyond overlaying files, a module can run scripts at defined boot points:

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 300}}}%%
flowchart LR
    I["customize.sh<br/>once, at install"] -.-> B
    B["post-fs-data.sh<br/>early boot, before apps"] --> S["service.sh<br/>late boot, system up"]
```

- `customize.sh` runs once when you install the module; use it to set things up based on the device.
- `post-fs-data.sh` runs early and blocks boot until it finishes; it's for changes that must happen before apps start.
- `service.sh` runs late and doesn't block; it's the usual place for "do something every boot".
- `uninstall.sh` runs when the module is removed.

All run as **root**. A broken script can slow or stop boot, so test step by step, and remember that a bad module is removed, not a bricked device: boot into Magisk's safe mode (hold **Volume Down** while the phone boots), disable or delete `/data/adb/modules/<id>`, and reboot.

## How the project builds its modules

The project's seven modules are built by one script, not zipped by hand, which is a good pattern once modules get repetitive. `stock/modules/build_modules.py` reads every manifest in `stock/modules/manifests/`, validates it, and writes one ZIP per manifest. It runs on the PC only and never talks to a phone.

### The manifests

Each `manifests/*.json` describes one module: its `module.prop` fields (`id`, `name`, `version`, `versionCode`, `description`) plus one or both of:

- **`packages`**, for an **overlay** module: the apps it hides. Each entry names the `package`, a human `label`, and its `hidden_directory` on the phone (optionally the `apk` inside it, for information). For every package the ZIP gets an empty `system<hidden_directory>/.replace` marker, which tells Magisk to mount that directory as empty at boot, so the APK inside isn't there while the module is enabled. The builder refuses any directory outside `/product/app/`, `/product/priv-app/`, `/system_ext/app/` and `/system_ext/priv-app/`, and refuses duplicates.
- **`scripts`**, for a **script** module: the Magisk lifecycle scripts it runs (`customize.sh`, `post-fs-data.sh`, `service.sh`, `uninstall.sh`), each a path under `stock/modules/scripts/`. An optional `sepolicy` entry names a file of `magiskpolicy` statements, packed as `sepolicy.rule`, which Magisk patches into the live SELinux policy at every boot while the module is enabled.

The five overlay modules (`wifi_ota_guard`, `wifi_carrier_debloat`, `wifi_extra_debloat`, `google_debloat`, `vendor_extras_debloat`) use only `packages`; the two development modules (`dev_debuggable`, `dev_adb_tcp`) use only `scripts`, and `dev_debuggable` has a `sepolicy` rule as well. The ZIP is named after the id with dashes for underscores (`dev_debuggable` → `dev-debuggable.zip`). Each ZIP also carries its manifest as `manifest.json`, so a module found later is self-describing.

Scripts run as root, so the builder packs them as **LF line endings, no BOM, mode 755**, whatever git or Windows did to them on checkout.

### Deterministic ZIPs

The build is **deterministic**: entry order is fixed and every entry gets the same timestamp (1980-01-01, the earliest a ZIP can record), so the same manifest and scripts always give a byte-identical ZIP on the same platform, and the committed ZIPs can be checked by hash there. Across platforms the compressed (deflate) bytes can differ between zlib builds while every entry is identical, so the tests compare entries instead.

`stock/modules/test_build_modules.py` (standard-library `unittest`) checks that every committed ZIP holds exactly what its manifest builds, entry by entry (names, order, timestamps, permissions and contents), that no ZIP is committed without a manifest, that the build is deterministic, and that malformed manifests are refused. `aosp-academy check` runs it, and so does CI (`.github/workflows/checks.yml`):

```sh
python -m unittest discover -s stock/modules -p "test_*.py" -v
```

### Rebuild and promote

`aosp-academy stock build` runs the builder into `work/build/stock/modules/`, rebuilds the two [helpers](helpers.md) at the same time, and reports each artifact as `identical` or `DIFFERS` against the committed copy in `stock/` (modules by hash). Its exit code is the number that differ. `--promote` copies the changed artifacts over the committed ones:

```sh
aosp-academy stock build             # compare
aosp-academy stock build --promote   # copy changed ZIPs and DEX files into stock/
```

After promoting, review `git diff` and commit the source (manifest or script) and the artifact together. Then install the new ZIP on the phone the usual way and reboot.

## Changing what a module hides

To hide a different set of apps, add a manifest, or edit one to bring an app back:

1. Find each package's APK on the phone: `adb shell pm path <package>`. The directory that holds it is the `hidden_directory`.
2. Add the entry (or remove it) in `stock/modules/manifests/`, and bump `version` and `versionCode`.
3. `aosp-academy stock build --promote`, review, commit.
4. Push and install the ZIP, then reboot.

To run something at boot instead, point a manifest's `scripts` at a `post-fs-data.sh` or `service.sh` under `stock/modules/scripts/`, as the two development modules do. Reading `build_modules.py` is the fastest way to see how a real, parameterised module generator is structured.

!!! tip "Keep modules reversible and scoped"
    The whole value of a module on a development device is that it's an experiment you can turn off. Resist editing the real system partitions; a module that overlays is always the cleaner choice.

Next: [Inspecting app packages](../apps/inspecting-apps.md).
