# Upstream source of this folder

Everything in `kit/` except this file is the original **Moto G Power 2026 Straight Talk WiFi and persistent root guide** by **parsimo2010**. It is kept exactly as published, byte for byte.

| | |
| --- | --- |
| Upstream repository | <https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide> |
| Imported at commit | `9526ee0805a4c4a76ddb86908ae2c5599f32107c` ("Document verified XT2617V Wi-Fi setup and persistent Magisk root", 2026-11-14) |
| Author | parsimo2010 |
| License | MIT. See [LICENSE](LICENSE), an unmodified copy of the upstream license, which also applies to the repository root. |
| Release | Guide kit version 1 ([RELEASE_NOTES.md](RELEASE_NOTES.md)) |

## What changed, and what didn't

- **Moved, not edited.** The files were moved from the repository root into `kit/` with `git mv`, so `git log --follow kit/<file>` shows their full upstream history.
- **Verified unchanged.** [SHA256SUMS.txt](SHA256SUMS.txt) is upstream's own release manifest. `dev/Test-DevEnv.ps1` checks that every file it lists in this folder still matches. (It also lists `.gitattributes` and `.gitignore`, which belong to this repository's root and have been extended for the dev environment.)
- **Paths still work.** GUIDE.md uses two variables: `$Kit` for this folder, and `$Work` for downloads and generated files. `dev/Enter-DevShell.ps1` sets `$Kit` to `kit\` and `$Work` to `work\`, so the guide's commands run as written. Skip the guide's own "Make a work folder" variable block, because the dev shell replaces it.
- **New work lives elsewhere.** The documentation site (`docs/`), the dev environment (`dev/`) and the repository README were written for this fork. They are not part of the upstream project.

## Pulling upstream updates

`upstream` is configured as a fetch-only remote:

```powershell
git fetch upstream
git merge upstream/main     # git's rename detection maps upstream root files onto kit/
.\dev\Test-DevEnv.ps1        # the SHA256SUMS check will flag files upstream changed
```

If upstream adds new files at its root, move them into `kit/` with `git mv` in the merge commit.

## Third-party tools the guide uses

They aren't redistributed here. `dev/Bootstrap-DevEnv.ps1` downloads each one from its publisher, pinned by hash in `dev/toolchain.json`:
[Test DPC](https://github.com/googlesamples/android-testdpc) (Google),
[DFRoot](https://github.com/diabl0w/DFRoot),
[KernelSU](https://github.com/tiann/KernelSU),
[Val Protocol](https://github.com/Maikyxd/val-protocol),
[Magisk](https://github.com/topjohnwu/Magisk),
[Platform Tools](https://developer.android.com/tools/releases/platform-tools) (Google), and the
[Motorola USB driver](https://en-us.support.motorola.com/app/usb-drivers) (Motorola). Their own licenses apply.
