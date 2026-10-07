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

## Publishing

Create a release tag such as `v0.21.8` on a commit in `main` whose version matches `pubspec.yaml`, `lib/version.dart`, and the latest changelog entry. Run `Publish Nubrick Flutter SDK` against that tag with the same tag as the `version` input.

The `.github/workflows/publish.yaml` workflow validates the release metadata and checks that the tag's commit is in `main` history. It uses GitHub OIDC to publish to pub.dev, skips publication if the version already exists, and creates or finalizes the GitHub Release.

The package's pub.dev settings allow `workflow_dispatch`. Tag pushes do not start the publisher; dispatch the workflow explicitly. Check the publisher run before considering the release complete.

If publication fails, rerun the publisher workflow against the same tag. It checks whether the version is already published before attempting to publish again.
