#!/usr/bin/env python3
"""Prepare and validate the metadata for a Flutter SDK release."""

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION_RE = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def fail(message: str) -> None:
    raise SystemExit(message)


def replace_once(path: Path, pattern: str, replacement: str) -> None:
    original = path.read_text()
    updated, count = re.subn(pattern, replacement, original, count=1, flags=re.MULTILINE)
    if count != 1:
        fail(f"Expected exactly one version field in {path.relative_to(ROOT)}")
    path.write_text(updated)


def release_version() -> str:
    tag = os.environ.get("RELEASE_TAG", "")
    if not VERSION_RE.fullmatch(tag):
        fail(f"Invalid release tag: {tag!r}; expected vX.Y.Z")
    return tag[1:]


def check_native_dependencies() -> tuple[str, str]:
    podspec = (ROOT / "ios/nubrick_flutter.podspec").read_text()
    package = (ROOT / "ios/nubrick_flutter/Package.swift").read_text()
    gradle = (ROOT / "android/build.gradle").read_text()
    pod_version = re.search(r"s\.dependency 'Nubrick', '([^']+)'", podspec)
    spm_version = re.search(r'exact: "([^"]+)"', package)
    android_version = re.search(r"implementation 'app\.nubrick:nubrick:([^']+)'", gradle)
    if not pod_version or not spm_version or not android_version:
        fail("Unable to find all three native SDK dependency versions")
    if pod_version.group(1) != spm_version.group(1):
        fail("CocoaPods and Swift Package Manager Nubrick versions differ")
    for name, value in (("iOS", pod_version.group(1)), ("Android", android_version.group(1))):
        if not VERSION_RE.fullmatch("v" + value):
            fail(f"Invalid {name} Nubrick dependency version: {value}")
    return pod_version.group(1), android_version.group(1)


def swift_package_lockfiles() -> list[Path]:
    return [
        ROOT / project / "ios" / workspace / "xcshareddata/swiftpm/Package.resolved"
        for project in ("example", "e2e")
        for workspace in ("Runner.xcworkspace", "Runner.xcodeproj/project.xcworkspace")
    ]


def check_swift_package_lockfiles(ios_version: str) -> None:
    revisions = set()
    for path in swift_package_lockfiles():
        data = json.loads(path.read_text())
        pins = [pin for pin in data["pins"] if pin.get("identity") == "nubrick-ios"]
        if len(pins) != 1 or pins[0]["state"].get("version") != ios_version:
            fail(f"{path.relative_to(ROOT)} does not lock nubrick-ios {ios_version}")
        revision = pins[0]["state"].get("revision", "")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            fail(f"Invalid nubrick-ios revision in {path.relative_to(ROOT)}")
        revisions.add(revision)
    if len(revisions) != 1:
        fail("Swift Package Manager lockfiles disagree on the nubrick-ios revision")


def check_changelog(version: str) -> None:
    changelog = (ROOT / "CHANGELOG.md").read_text()
    sections = re.split(r"(?m)^## ", changelog)
    if len(sections) < 2 or not sections[1].startswith(version + "\n"):
        fail(f"CHANGELOG.md must start with ## {version}")
    body = sections[1].split("\n", 1)[1].strip()
    if not body or body in ("-", "- TODO"):
        fail(f"CHANGELOG.md needs release notes below ## {version}")


def release_notes() -> list[str]:
    raw = os.environ.get("RELEASE_NOTES", "")
    notes = [re.sub(r"^[-*]\s+", "", part.strip()) for part in re.split(r"\r?\n|\|", raw)]
    if not notes or any(not note or note.upper() in ("TODO", "TBD") for note in notes):
        fail("Release notes must contain one or more nonempty items")
    return notes


def current_version() -> str:
    pubspec = (ROOT / "pubspec.yaml").read_text()
    match = re.search(r"(?m)^version: ([^\s]+)$", pubspec)
    if not match:
        fail("Unable to read pubspec.yaml version")
    return match.group(1)


def check_lockfile(path: Path, version: str) -> None:
    lockfile = path.read_text()
    section = re.search(r"(?m)^  nubrick_flutter:\n((?:    .*\n)+)", lockfile)
    if not section or f'version: "{version}"' not in section.group(1):
        fail(f"{path.relative_to(ROOT)} does not lock nubrick_flutter {version}")


def verify(version: str) -> None:
    # Ensure the package version in pubspec.yaml matches the release tag.
    if current_version() != version:
        fail("pubspec.yaml does not match the release tag")

    # Read the version constant exposed by the Flutter SDK.
    dart_version = (ROOT / "lib/version.dart").read_text()

    # Ensure the Flutter SDK version constant matches the release tag.
    if not re.search(rf"(?m)^const String nubrickFlutterSdkVersion = '{re.escape(version)}';$", dart_version):
        fail("lib/version.dart does not match the release tag")

    # Confirm the changelog starts with this release and contains release notes.
    check_changelog(version)

    # Validate native SDK dependency declarations and obtain the iOS SDK version.
    ios_version, _ = check_native_dependencies()

    # Ensure example and E2E SPM lockfiles use that iOS version and the same revision.
    check_swift_package_lockfiles(ios_version)

    # Ensure example and E2E Flutter lockfiles resolve nubrick_flutter to this version.
    for path in (ROOT / "example/pubspec.lock", ROOT / "e2e/pubspec.lock"):
        check_lockfile(path, version)


def prepare(version: str) -> None:
    # Read the current package version from pubspec.yaml.
    previous = current_version()

    # Validate the current version using the release tag's X.Y.Z format.
    if not VERSION_RE.fullmatch("v" + previous):
        fail(f"Invalid current pubspec.yaml version: {previous}")

    # Require the requested release version to be newer than the current version.
    if tuple(map(int, version.split("."))) <= tuple(map(int, previous.split("."))):
        fail(f"Release version {version} must be newer than {previous}")

    # Ensure the current release has changelog notes before starting the next release.
    check_changelog(previous)

    # Read and validate the release notes that will be added to the changelog.
    notes = release_notes()

    # Confirm native SDK versions and Swift Package Manager lockfiles are consistent.
    ios_version, _ = check_native_dependencies()
    check_swift_package_lockfiles(ios_version)

    # Update the package version declared in pubspec.yaml.
    replace_once(ROOT / "pubspec.yaml", r"^version: [^\s]+$", f"version: {version}")

    # Keep the version constant used by the Flutter SDK in sync.
    replace_once(
        ROOT / "lib/version.dart",
        r"^const String nubrickFlutterSdkVersion = '[^']+';$",
        f"const String nubrickFlutterSdkVersion = '{version}';",
    )

    # Add the new release notes at the top while preserving the existing changelog.
    changelog = ROOT / "CHANGELOG.md"
    entries = "\n".join(f"- {note}" for note in notes)
    changelog.write_text(f"## {version}\n\n{entries}\n\n" + changelog.read_text())


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("prepare", "verify"):
        fail("Usage: release.py prepare|verify")
    release = release_version()
    if sys.argv[1] == "prepare":
        prepare(release)
    else:
        verify(release)
