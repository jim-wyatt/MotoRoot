# Working on this repository

The user-facing documentation is the site built from `docs/` ([online](https://jim-wyatt.github.io/aosp-academy/)). This file is the short reference for changing the repository itself. Set up a workstation first (`aosp-academy setup`, see [docs/start/workstation.md](docs/start/workstation.md)); the commands below assume a shell from `aosp-academy shell`, at the repository root (`.\aosp-academy` on Windows, `./aosp-academy` elsewhere).

## Tests and checks

```text
aosp-academy check                                  # the workstation end to end; exit code = failures
python -I -m unittest discover -s tests             # the package's unit tests (no phone, no network)
python -I -m unittest discover -s stock/modules -p "test_*.py"   # the module builder and the committed ZIPs
aosp-academy device test                            # the phone side: root, logs, NDK, app, debug, trace, Frida, scrcpy
aosp-academy docs build                             # the site, --strict
```

`check` uses each tool rather than reading its version, and runs the unit tests, the stock rebuild, the docs build and the shell-script checks. It never talks to the phone and never starts an ADB server. `device test` is its other half, on the connected phone, and `deploy` runs it after every install.

CI (`.github/workflows/checks.yml`) runs what needs no SDK, phone or AOSP tree: the module builder test, `toolchain.json` as JSON, every shell script for LF line endings, `bash -n` and ShellCheck errors, the pre-commit hook's own test (`bash .githooks/test-pre-commit.sh`), the unit tests, and `./aosp-academy --help`. `.github/workflows/docs.yml` builds the site on every push and pull request and publishes it from `main`.

The package uses the **standard library only**: don't add a dependency that needs `pip install`. Describe a command in the docs only from what `aosp_academy/cli.py` and the module code do.

## Pins

Every version and download is pinned, with its hash, in `toolchain.json`; nothing else names a version. To change one:

1. Take the new URL and hash from the publisher (for SDK packages and platform-tools, Google's `repository2-3.xml`; for F-Droid and Fossify APKs, F-Droid's signed index, with the signing certificate as `signerSha256`).
2. Edit `toolchain.json`, keeping its `_note` current: what the pin was and why it moved.
3. Delete the old file from `work/` if the name is the same (a present file that doesn't match its pin is never overwritten), re-run `aosp-academy setup` (or `aosp-academy image inputs` on the build node for `buildOnly` pins), then `aosp-academy check`.
4. **Don't change the `inputs` section** unless you are deliberately re-validating the device procedure. Those are the exact inputs of the tested runs; record a re-validation in `docs/environment/validation.md`.

[docs/reference/pins.md](docs/reference/pins.md) explains each section.

## The pre-commit hook

`aosp-academy setup` sets `core.hooksPath` to `.githooks`. The hook blocks device images, installers, logs, key material, adb keys, Wi-Fi credentials, traces, recordings, native libraries, files over 1 MiB, the private working folders, and added lines that look like IMEIs or serial numbers. Change it together with its test, `.githooks/test-pre-commit.sh`. `git commit --no-verify` only for a false positive you have checked.

`work/` holds everything private: `private-backups/`, `lk-analysis/`, `lk-patch-analysis/` and `magisk-patch-files/` are per-unit data, and `remote-build.json`, `wifi.json` and `adb_keys` describe your machines and network. Keep `work/` off any cloud-synced folder as well.

## Keep shell scripts LF

bash and the phone's `sh` read a `\r` at the end of a line as part of the command, so every `.sh` file and the hook must have LF line endings. `.gitattributes` asks git for LF on every file except `*.cmd`. On Windows, tools that rewrite files can still add CRLF: in Python, write with `newline=""` (or bytes), not in text mode with the default newline. `aosp-academy check` and CI fail on a CRLF script; `sed -i 's/\r$//' <file>` repairs one. Inside the module ZIPs, the builder packs scripts as LF, without a byte-order mark, mode 755, whatever git checked out.

## Diagrams in the docs

The site renders Mermaid through the theme's own loader, which wraps node labels at a width far too narrow for 16 px text (labels fold into tall columns and spill past their boxes). Every `flowchart` therefore starts with:

```text
%%{init: {"flowchart": {"wrappingWidth": 300}}}%%
```

Sequence diagrams don't need it. `docs/stylesheets/extra.css` keeps a diagram inside the content column. To check rendering without a browser session, headless Edge works (`msedge --headless=new --screenshot=... file:///.../site/<page>/index.html`); it clamps the viewport to 510 px, so phone widths can't be simulated that way.

The site builds with `--strict`: every nav entry, link and anchor must resolve. Link between pages with relative `.md` links, and to repository files with full GitHub URLs.

## Rebuilding the stock artifacts

The two helper DEX files and the seven module ZIPs in `stock/` are committed build outputs, so the walkthrough can push them straight to the phone.

```text
aosp-academy stock build             # rebuild into work/build/stock and compare with stock/
aosp-academy stock build --promote   # copy the changed ones over the committed copies
```

Helpers are built with `javac --release 8` and the pinned R8's D8, and compared byte for byte; a mismatch usually means a different `javac` build changed the debug line tables, not the bytecode. Modules are built by `stock/modules/build_modules.py` from `stock/modules/manifests/*.json`, deterministically (fixed entry order and timestamps). There are two kinds: **overlay** modules list `packages` (the builder refuses any path outside the `/product` and `/system_ext` app directories), and **script** modules name Magisk lifecycle scripts under `stock/modules/scripts/`. Each ZIP carries its manifest as `manifest.json`, so a module found later describes itself. `stock/modules/test_build_modules.py` checks that every committed ZIP holds exactly what its manifest builds (entry by entry: names, timestamps, modes, contents; not the archive hash, because deflate output differs between zlib builds) and that malformed manifests are refused. Review `git diff` and commit the source and the artifact together.

## The image

The product (`image/product/aospacademy/gsi/`), the patches (`image/patches/`, one upstream project per file, `<project-path-with-dashes>-NNNN-<what>.patch`) and the build wrappers (`image/build/`) change through the change loop: on a branch, built by the build node (`aosp-academy image build`), deployed and verified by the device node (`aosp-academy deploy`), then merged. See [docs/environment/](docs/environment/index.md). The AOSP tree lives on the build node, never in this repository.

## Legal files

- `LICENSE`: MIT, for the project.
- `NOTICE.md`: the original MIT notice for the parts derived from parsimo2010's guide, and the licenses of the third-party software `setup` downloads.
- `DISCLAIMER.md`: the terms of use. `docs/reference/disclaimer.md` is the same text, differing only in its links (site-relative and GitHub URLs) and in saying that it is a copy; change both together.

The project's name, and the image's, carry no trademarks: no "Android", "Moto", "droid" or other marks.
