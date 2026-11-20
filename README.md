# Office Linux x86_64 CI

This repository holds the shared recipe that proves an Office app's Linux
desktop build works on a **native x86_64** runner. The same steps are copied
into each app's own repository as
`.github/workflows/linux-x64-verify.yml`, so every app keeps its
verification next to its code and no app depends on this repository.

## What the recipe does

1. Installs Flutter 3.44.9 and the GTK/Linux desktop build toolchain.
2. Builds the app with `flutter build linux --release`, which on
   `ubuntu-latest` produces a genuine x86_64 bundle.
3. Asserts the produced executable is an x86-64 ELF binary.
4. Launches the bundle under Xvfb with software rendering and Openbox, waits
   for the GTK window to map, and captures a screenshot.
5. Fails the job when the window never appears or renders a blank screen.
6. Uploads the x86_64 bundle and the screenshot as artifacts.

## Proof that the recipe works

Run `Linux x86_64 verify` in this repository (run 44764816942) built a real
x86-64 bundle on a hosted x86_64 runner:

    file bundle/ci_probe
    -> ELF 64-bit LSB pie executable, x86-64, ... for GNU/Linux 3.2.0

The launch step captured a rendered window (`colors=1046 mean=0.71084`), and
the bundle and screenshot were uploaded as artifacts.

## Running a private app from this repository

A private app can call the shared workflow here, and its code stays private —
the shared workflow checks out the calling repository:

```yaml
jobs:
  verify:
    uses: jayaanandabalaji/office-linux-x64-ci/.github/workflows/reusable-linux-x64-verify.yml@main
    with:
      app_dir: 'app'
      binary: 'office_vault'
      window_title: 'Office Vault'
```

Note that the minutes a job uses are billed to the **calling** repository, so
a private app still needs Actions minutes on its own account.

## A note on minutes

Jobs in private repositories are billed to the private repository's Actions
allowance. When that allowance is exhausted, GitHub still creates the job but
never assigns a runner, and the job fails immediately:

    runner_id: 0, no steps, failed within a couple of seconds

Public repositories are unaffected. Runs on `macos-latest` are billed at ten
times the minute rate, which is what exhausted the allowance here.
