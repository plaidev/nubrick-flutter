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

## Swift Package Manager validation

PRs validate Flutter 3.44.0 and the version pinned in `.fvmrc`. Each version runs the package tests, publication dry-run, and an iOS Simulator build of the E2E app with Xcode 26.5. Flutter 3.44.0 also builds the unsigned iOS Release app and the Android example. This is the SPM validation baseline; the package's declared support range is changed separately during the CocoaPods retirement.

The reusable `.github/workflows/validate-spm.yaml` workflow checks out the requested commit and rejects CocoaPods commands during the consumer build. It does not upload apps to MagicPod. The existing main-branch app uploads remain separate.

## Release workflow

Update iOS and Android Nubrick dependency versions in a separate PR with native build validation. The release workflow uses the versions already on `main`.

The `.github/workflows/release.yaml` workflow prepares and tags a release using the built-in `GITHUB_TOKEN`. Run `Release Nubrick Flutter SDK` from `main` with a version such as `v0.23.0` and release notes separated by `|`. It updates `CHANGELOG.md`, `pubspec.yaml`, `lib/version.dart`, and the example and E2E pubspec lockfiles, opens a release PR, runs `flutter test` and `dart pub publish --dry-run`, merges the PR, and validates the merged commit. A separate SPM Simulator build must pass before the finalizer creates the tag on that exact commit.

The finalizer dispatches `.github/workflows/publish.yaml` against the tag because a `GITHUB_TOKEN` tag push does not start another workflow. For an unpublished version, the publisher runs the full validation above against the tag's commit. Only successful validation permits the separate OIDC publishing job to publish to pub.dev and create a GitHub Release. Already published versions skip validation and publication and only recover a missing GitHub Release.

GitHub rulesets enforce these release protections:

- For `main`, the ruleset requires a pull request but has no required approval or status check. The release and publisher workflows therefore call their validation jobs directly rather than relying on PR-triggered checks.
- If a ruleset is added for tags matching `v*`, allow the GitHub Actions app to create release tags. The release workflow pushes tags with `GITHUB_TOKEN`.

The publisher runs through `workflow_dispatch` from a release tag. The package's pub.dev settings allow `workflow_dispatch`; the workflow checks that the tag matches `pubspec.yaml`, `lib/version.dart`, and the changelog before publishing. A manually pushed tag also requires a publisher dispatch. The release workflow links to the dispatched publisher in its run summary and waits up to 120 minutes for it to finish. A publisher failure or wait timeout fails the release workflow. A wait timeout does not cancel the publisher; check its linked run before retrying publication.

The initial release preparation fails if its branch, tag, or pub.dev version already exists. Inspect an existing release PR before retrying that preparation. After the PR is merged, rerun failed validation or finalization jobs using the recorded merge SHA. The finalizer can reuse an existing tag only when it points to that validated commit; it never moves a conflicting tag.

If publication fails after tagging, dispatch the publisher against the existing tag after checking that no publisher is still running:

```sh
gh workflow run publish.yaml --ref "$RELEASE_TAG" -f "version=$RELEASE_TAG"
```

If pub.dev publication succeeded but GitHub Release creation failed, the same command recovers the GitHub Release without republishing. Code changes after tagging require a new version.
