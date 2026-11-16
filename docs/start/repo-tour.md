# Tour the repository

```text
OtomDev/
├── kit/                 The tested procedure, unchanged
│   ├── GUIDE.md           the step-by-step phone procedure (the source of truth)
│   ├── README.md          exact tested phone, build and results
│   ├── VALIDATION.md      what was tested and what was not
│   ├── helpers/           two tiny Java programs + their compiled .dex files
│   ├── modules/           two Magisk module ZIPs
│   ├── scripts/           the Magisk image preparation script and the module builder
│   ├── carrier-debloat-manifest.json
│   ├── SHA256SUMS.txt     upstream's release manifest; the self-test checks kit/ against it
│   └── UPSTREAM.md        where this came from and how to pull updates
├── dev/                 The development environment
│   ├── toolchain.json     every version and hash, in one place
│   ├── Bootstrap-DevEnv.ps1   installs everything
│   ├── Enter-DevShell.ps1     per-terminal setup (dot-source it)
│   ├── Build-Kit.ps1          rebuilds the helpers and modules from source
│   ├── Test-DevEnv.ps1        the 36-check self-test
│   ├── modules/               this fork's wifi-extra-debloat module: manifest, builder, ZIP
│   ├── .tools/ .cache/ build/ .venv-docs/    generated; git-ignored
├── docs/                These pages (Zensical / Markdown)
├── work/                YOUR files. Git-ignored in full.
│   ├── platform-tools/    adb and fastboot 37.0.1
│   ├── *.apk, *.msi       the guide's downloads
│   ├── val-protocol/      bootloader patching tool, at its pinned commit
│   ├── .venv/             Python for val-protocol
│   └── private-backups/   created during the procedure: your phone's original images
├── .githooks/pre-commit The safety net
├── .github/workflows/   Builds and publishes this site
├── .vscode/             Terminal profile, tasks, recommended extensions
└── zensical.toml        Site configuration
```

## The three folders that matter

### `kit/`: read, don't edit

This is parsimo2010's guide exactly as published. The self-test verifies it against the author's own checksum manifest, so if you accidentally change something you'll know. Treat it as a reference book. When these docs say "the guide says...", this is what they mean. [`UPSTREAM.md`](../reference/credits.md) explains how to pull the author's future updates.

### `work/`: yours, and private

Every download and every file the phone procedure creates goes here. The folder is ignored by Git in its entirety, and the pre-commit hook blocks it as a second line of defence. Your phone's backup images live in `work/private-backups/`. **Back that folder up somewhere safe that isn't a public cloud share**: it is the only way to restore the phone if something goes wrong.

### `dev/`: the tooling you'll use every day

The dev shell gives you these variables, which the guide's commands use directly:

| Variable | Points to | Used for |
| --- | --- | --- |
| `$Kit` | `kit\` | `& "$Kit\scripts\Prepare-MagiskImage.ps1"`, `"$Kit\modules\..."` |
| `$Work` | `work\` | downloads, generated images |
| `$Backup` | `work\private-backups` | your original partition images |
| `$adb` | `work\platform-tools\adb.exe` | every ADB command |
| `$fb` | `work\platform-tools\fastboot.exe` | bootloader-mode commands |
| `$py` | `work\.venv\Scripts\python.exe` | the Val Protocol scripts |

And these commands:

| Command | What it does |
| --- | --- |
| `docs` | Serves this documentation at <http://localhost:8000> with live reload |
| `apktool ...` | Decode or rebuild an APK's resources |
| `r8d8 ...` | Google's D8 compiler: `.class` → `.dex` (the exact version the guide's helpers were built with) |
| `.\dev\Build-Kit.ps1` | Rebuild the helpers and all three modules and compare with the committed copies |
| `.\dev\Test-DevEnv.ps1` | Self-test everything |

## Why pin everything?

Open `dev/toolchain.json`. Every tool has a version and a hash. This matters more here than in most projects: the root procedure was validated with *specific* versions, and a newer Magisk or a newer `adb` might behave differently in ways nobody has tested on this phone. Pinning means your environment matches the one the procedure was proven on, and that someone else can reproduce yours exactly.

Next: [Your first ADB session](first-adb-session.md).
