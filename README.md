<p align="center">
  <img width="400" alt="nubrick-logo" src="https://github.com/user-attachments/assets/cdac41ce-d0f4-40ac-b18f-177c21e9952f" />
</p>

# Nubrick Flutter SDK

documentations

https://docs.nubrick.app

## Android build requirements

| Requirement | Value | Scope |
| --- | --- | --- |
| `compileSdk` | **36 or higher** | Build time — required to resolve Nubrick Android SDK and its transitive Compose dependencies |
| `minSdk` | **26 or higher** | Runtime — minimum Android API level supported by Nubrick |

## Development

This repository pins its Flutter SDK with [FVM](https://fvm.app/). From the repository root, run:

```sh
fvm install
fvm flutter pub get
```

Run the example app with:

```sh
cd example
fvm flutter run
```

VS Code uses the pinned SDK automatically through the workspace settings. CI reads the same version from `.fvmrc`.

## Release workflow

Update iOS and Android Nubrick dependency versions in a separate PR with native build validation. The release workflow uses the versions already on `main` and checks that the CocoaPods, Swift Package Manager, and SwiftPM lockfile versions match.

The `.github/workflows/publish.yaml` workflow handles release preparation, tagging, and publishing using the built-in `GITHUB_TOKEN`. Run `Release Nubrick Flutter SDK` from `main` with a version such as `v0.21.8` and release notes separated by `|`. In one release run, it updates `CHANGELOG.md`, `pubspec.yaml`, `lib/version.dart`, and the example and E2E pubspec lockfiles, opens a `release/0.21.8` PR, runs `flutter test` and `dart pub publish --dry-run`, merges the PR, validates the merged commit, and creates the tag. A `GITHUB_TOKEN` tag push does not start the `push` workflow, so the release run dispatches the publisher against the tag. The publisher uses GitHub OIDC to publish to pub.dev and then creates a GitHub Release.

GitHub rulesets enforce these release protections:

- For `main`, the ruleset requires a pull request but has no required approval or status check. The release workflow runs `flutter test` and `dart pub publish --dry-run` before merging, then checks the merged commit again before tagging.
- If a ruleset is added for tags matching `v*`, allow the GitHub Actions app to create release tags. The release workflow pushes tags with `GITHUB_TOKEN`.

The publisher is configured for both tag pushes and `workflow_dispatch` from a release tag. The package's pub.dev settings allow `workflow_dispatch`; the workflow validates the tag and release metadata before publishing. Check the separate publisher run before considering the release complete.

The release run fails if its branch, tag, or pub.dev version already exists. If it fails after creating a branch, inspect and resolve that partial release before starting again. If publication fails after tagging, rerun the publisher workflow; it checks whether the version is already published before attempting to publish again.
