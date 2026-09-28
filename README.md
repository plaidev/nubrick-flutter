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

The release workflow uses a personal access token (PAT) because a tag push made with the workflow's built-in `GITHUB_TOKEN` does not start the follow-up publisher. In particular, [pub.dev automated publishing](https://dart.dev/tools/pub/automated-publishing) only accepts a GitHub Actions run triggered by a matching tag push. The PAT lets the release PR trigger CI without manual workflow approval and the tag push trigger `.github/workflows/publish.yaml`. The publisher then uses GitHub OIDC to authenticate to pub.dev; the PAT is not a pub.dev credential. See [GitHub's workflow-trigger rules](https://docs.github.com/en/actions/concepts/security/github_token).

Create a fine-grained PAT under Tomi's GitHub account with `plaidev` as the resource owner, access limited to `nubrick-flutter`, and Contents and Pull requests read/write permissions. Give it a descriptive name such as `nubrick-flutter release (TOMI)`. Store the token as the `RELEASE_TOMI_PAT` environment secret in **Settings → Environments → Only Main → Environment secrets**. The `TOMI` suffix identifies the token owner; `RELEASE_APP_ID` is not used with a PAT. The organization may require approval for the PAT. Track its expiration and rotate the secret before it expires; the release workflow also stops working if the owner's repository access is removed. Never commit or print the token. See [GitHub's PAT instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

Run the `Release SDK` workflow from `main` with a version such as `v0.21.8` and release notes. Separate multiple notes with `|`, for example `Fix modal layout | Improve initialization`. The workflow adds the notes to `CHANGELOG.md` and updates `pubspec.yaml`, `lib/version.dart`, and the example and E2E pubspec lockfiles in a `release/0.21.8` PR. The workflow opens the PR and stops; review its CI results and merge it manually only after they pass. The merged PR triggers another `Release SDK` run that tests the merged commit and pushes the tag. The tag-triggered publisher then publishes to pub.dev and creates the GitHub Release after publication succeeds.

To enforce the CI gate in GitHub, add the `test` check from `[flutter] Test Nubrick SDK` to the required status checks in the `main` ruleset. Until that rule is enabled, GitHub allows a manual merge before CI completes.

If pub.dev publication fails after the tag is pushed, rerun the failed tag-triggered `Publish Nubrick Flutter SDK` workflow. It checks whether that version is already published before attempting to publish again.
