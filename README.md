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
