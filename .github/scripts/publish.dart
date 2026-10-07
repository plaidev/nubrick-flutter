import 'dart:convert';

import 'release_common.dart';

String get tag => environment('RELEASE_TAG');

Future<void> main(List<String> arguments) => runStep(arguments, {
      'validate': validateRelease,
      'publish': () async {
        await command('dart', ['pub', 'get']);
        await command('dart', ['pub', 'publish', '-f']);
      },
      'create-release': createRelease,
    });

Future<void> validateRelease() async {
  final version = releaseVersion(tag);
  if (environment('INPUT_VERSION') != tag) {
    throw StateError('INPUT_VERSION must match release tag $tag');
  }
  await command('git', ['fetch', 'origin', 'main']);
  await command('git', [
    'merge-base',
    '--is-ancestor',
    environment('GITHUB_SHA'),
    'FETCH_HEAD',
  ]);
  ReleaseMetadata(version).verify();
  exportOutput('published', '${await isPublished(version)}');
}

Future<void> createRelease() async {
  final release = captureCommand(
      'gh', ['release', 'view', tag, '--json', 'isDraft'],
      allowFailure: true);
  if (release.exitCode == 0) {
    final details =
        jsonDecode(release.stdout as String) as Map<String, dynamic>;
    if (details['isDraft'] == true) {
      await command('gh', ['release', 'edit', tag, '--draft=false']);
    }
  } else {
    await command('gh', [
      'release',
      'create',
      tag,
      '--verify-tag',
      '--title',
      tag,
      '--target',
      environment('GITHUB_SHA'),
      '--generate-notes',
    ]);
  }
}
