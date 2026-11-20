# Git workflow

How this repository is organized for safety, how a change moves through it, and the commands you'll use day to day.

## The layout, and why

```text
aosp-academy/
├── aosp_academy/   the command line            (generic: no unit, no network, no person)
├── image/          the image's product, patches and build wrappers
├── stock/          the stock system's helpers and modules
├── tests/ docs/    unit tests; this site
├── toolchain.json  every pin
└── work/           everything local and private: git-ignored in full
```

The split exists so the **one rule** is easy to keep: nothing private ever gets committed. All downloads, backups, build outputs and private settings (the build node's address, your Wi-Fi details, adb keys) go in `work/`, which is ignored wholesale. Everything outside it is generic to the model, never to your unit or your network.

## The safety net

Two layers stop device data reaching version control:

1. **`.gitignore`** ignores `work/`, every image, key, log and trace type, and the build outputs, wherever they turn up.
2. **A pre-commit hook** (`.githooks/pre-commit`, enabled by `aosp-academy setup`) blocks a commit if it contains device images, installers, logs, key material, adb keys, Wi-Fi credentials, traces, screen recordings, native libraries pulled from a device, files over 1 MiB, the private working folders, or added lines that look like an IMEI or a serial number.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 300}}}%%
flowchart LR
    S[git commit] --> H{pre-commit hook}
    H -->|image, key, trace, IMEI-like line| X[blocked]
    H -->|clean| C[commit proceeds]
```

A fresh clone isn't protected until the hook is enabled, which `setup` does with `git config core.hooksPath .githooks`. If the hook blocks a file you have checked and know to be safe, `git commit --no-verify` bypasses it, sparingly. `.githooks/test-pre-commit.sh` tests the hook in a throwaway repository (every forbidden kind of file must be blocked, ordinary files must pass), and CI runs it.

`aosp-academy check` verifies all of this on your workstation: the hook is active, a list of private paths is ignored, and the commit email is a GitHub no-reply address, so your own email address doesn't end up in a public history. The repository is public by design; the ignore rules and the hook are what keep device data out of it.

## How a change moves

Every change goes on a branch and is merged into `main` once it has been checked. For a change to the image or to a build input, "checked" means the [change loop](../environment/index.md): the build node builds the branch, the device node deploys the image and verifies it, then the branch is merged. Build requests name a branch and a commit, so the image on the phone can always be traced to its source.

```bash
git switch main && git pull
git switch -c my-change        # a branch for anything non-trivial
# ... edit ...
aosp-academy check             # the workstation side still passes
git add -p                     # review each hunk
git commit -m "What and why"   # the hook runs automatically
git push -u origin my-change   # then open a pull request
```

Pull requests run two workflows. **Checks** (`.github/workflows/checks.yml`) needs no SDK, phone or AOSP tree. It has four jobs:

- **checks** rebuilds the Magisk modules and compares them with the committed ZIPs, checks that `toolchain.json` is valid JSON, checks every shell script for LF line endings, `bash -n` and ShellCheck errors, tests the pre-commit hook, runs the package's unit tests, and checks that `./aosp-academy --help` loads.
- **portable** runs the unit tests, the module builder tests and the launcher on Windows, macOS and Linux. The device node is a Windows PC, and most bugs in the Python port were Windows-only.
- **patches** runs `image/build/check-patches.sh`: it clones only the AOSP projects that `image/patches/` touches, at the pinned tag (shallow, blobless, nothing checked out), and runs `git apply --cached --check`. A patch that no longer applies fails in seconds, not hours into a build. Before moving the tag, run it locally against the new one: `AOSP_TAG=<new tag> bash image/build/check-patches.sh`.
- **privacy** runs [gitleaks](https://github.com/gitleaks/gitleaks) (a pinned release, checksum verified) over the whole history, then `tests/test_privacy.py` over every tracked file. That test looks for private network addresses, private keys, whole adb public keys, IMEI-like numbers and serial assignments, and for the project's own private values. Those values are never committed. Locally the test reads them from `work/wifi.json`, `work/remote-build.json` and `work/private-terms.txt` (one term per line, git-ignored). In CI it reads the repository secret `AOSP_ACADEMY_PRIVATE_TERMS` (newline-separated). Failures name the file and line, never the value. The pre-commit hook checks each commit; this job checks the whole tree, and it can't be skipped with `--no-verify`.

**Documentation** (`.github/workflows/docs.yml`) builds this site with `zensical build --strict`.

## Where the procedure came from

The device procedure, the helpers and the first two modules were imported from [parsimo2010's guide](credits.md) and then integrated into this project rather than mirrored. There is no `upstream` remote to track. If the original author publishes a change worth adopting, read it and apply it here deliberately, then update the [validation page](../environment/validation.md) if it changes what has been tested. `NOTICE.md` records the imported commit.

## Rebuilding the stock artifacts

The helper DEX files and module ZIPs in `stock/` are build outputs, committed so the walkthrough can push them straight to the phone. After changing a helper source or a module manifest:

```text
aosp-academy stock build            # rebuilds into work/build/stock and reports which committed copies differ
aosp-academy stock build --promote  # copies the rebuilt files over the committed ones
git diff --stat                     # review, then commit the source and the artifact together
```

Module builds are deterministic, so an unchanged manifest always reproduces the committed ZIP's contents. `aosp-academy check` runs the same comparison, so an edited manifest with a stale ZIP is caught.

## Publishing the docs

Pushing to `main` runs `.github/workflows/docs.yml`, which builds the site with `zensical build --strict --clean` and deploys it to GitHub Pages at <https://jim-wyatt.github.io/aosp-academy/>. Pull requests build but don't deploy, so a broken docs change is caught before it publishes. Preview locally with `aosp-academy docs` (live reload) or build with `aosp-academy docs build`.

## If something private was committed

Stop and don't push. If it's only staged, `git restore --staged <file>`. If it's in your last local commit, `git reset --soft HEAD~1` and commit again without it. If it was already pushed, the history must be rewritten and anything exposed (a key, a serial number, a network address) treated as compromised, which is exactly what the hook exists to prevent.
