import 'dart:convert';
import 'dart:io';

import 'release_common.dart';

String get tag => environment('RELEASE_TAG');
String get version => releaseVersion(tag);
String get branch => 'release/$version';
ReleaseMetadata get metadata => ReleaseMetadata(version);

Future<void> main(List<String> arguments) => runStep(arguments, {
      'check': checkRelease,
      'prepare': prepareBranch,
      'validate': () async {
        metadata.verify();
        await validatePackage();
      },
      'push': () => command('git', ['push', 'origin', branch]),
      'create-pr': createPullRequest,
      'merge-pr': mergePullRequest,
      'validate-merged': validateMergedRelease,
      'tag': createTag,
      'start-publisher': startPublisher,
    });

Future<void> checkRelease() async {
  metadata.parseNotes(environment('RELEASE_NOTES'));
  metadata.checkNextVersion();
  if (output('git', ['ls-remote', '--heads', 'origin', 'refs/heads/$branch'])
      .isNotEmpty) {
    throw StateError('Release branch $branch already exists');
  }
  if (output(
          'git', ['ls-remote', '--tags', '--refs', 'origin', 'refs/tags/$tag'])
      .isNotEmpty) {
    throw StateError('Release tag $tag already exists');
  }
  if (await isPublished(version)) {
    throw StateError('Version $version is already published on pub.dev');
  }
}

Future<void> prepareBranch() async {
  await command('gh', ['auth', 'setup-git']);
  metadata.prepare(environment('RELEASE_NOTES'));
  for (final project in ['example', 'e2e']) {
    await command('flutter', ['pub', 'get'], workingDirectory: project);
  }
  await command('git', ['diff', '--check']);
  await command('git', ['config', 'user.name', 'github-actions[bot]']);
  await command('git', [
    'config',
    'user.email',
    '41898282+github-actions[bot]@users.noreply.github.com',
  ]);
  await command('git', ['switch', '-c', branch]);
  await command('git', [
    'add',
    'pubspec.yaml',
    'lib/version.dart',
    'CHANGELOG.md',
    'example/pubspec.lock',
    'e2e/pubspec.lock',
  ]);
  await command('git', ['commit', '-m', 'Prepare $tag release']);
}

void createPullRequest() {
  final temporary = Directory.systemTemp.createTempSync('release-pr-');
  try {
    final body = File('${temporary.path}/body.md')..writeAsStringSync('''
## Summary
- Prepare Flutter SDK $tag for release.
- Keep the native SDK dependency versions pinned in main.

## Validation
- Release tag, package version, and changelog checks
- flutter test
- dart pub publish --dry-run
''');
    final url = output('gh', [
      'pr',
      'create',
      '--base',
      'main',
      '--head',
      branch,
      '--title',
      'Prepare $tag release',
      '--body-file',
      body.path,
    ]);
    final number = Uri.parse(url).pathSegments.last;
    if (!RegExp(r'^[0-9]+$').hasMatch(number)) {
      throw StateError('Unable to read PR number from $url');
    }
    exportOutput('pr_number', number);
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<void> mergePullRequest() async {
  final number = environment('PR_NUMBER');
  final releaseSha = output('git', ['rev-parse', 'HEAD']);
  await command('gh', [
    'pr',
    'merge',
    number,
    '--squash',
    '--match-head-commit',
    releaseSha,
  ]);
  final mergeSha = output('gh', [
    'pr',
    'view',
    number,
    '--json',
    'mergeCommit',
    '--jq',
    '.mergeCommit.oid',
  ]);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(mergeSha)) {
    throw StateError('PR #$number has no valid merge commit: $mergeSha');
  }
  exportOutput('merge_sha', mergeSha);
}

Future<void> validateMergedRelease() async {
  final mergeSha = environment('MERGE_SHA');
  await command('git', ['fetch', 'origin', 'main']);
  await command('git', ['merge-base', '--is-ancestor', mergeSha, 'FETCH_HEAD']);
  await command('git', ['checkout', '--detach', mergeSha]);
  metadata.verify();
  await validatePackage();
}

Future<void> createTag() async {
  await command('git',
      ['tag', '-a', tag, '-m', 'Release $tag', environment('MERGE_SHA')]);
  await command('git', ['push', 'origin', 'refs/tags/$tag']);
}

void startPublisher() {
  final details = jsonDecode(output('gh', [
    'api',
    '--method',
    'POST',
    'repos/${environment('GITHUB_REPOSITORY')}/actions/workflows/publish.yaml/dispatches',
    '--header',
    'X-GitHub-Api-Version: 2022-11-28',
    '--field',
    'return_run_details=true',
    '--raw-field',
    'ref=$tag',
    '--raw-field',
    'inputs[version]=$tag',
  ])) as Map<String, dynamic>;
  final runId = details['workflow_run_id'];
  final url = details['html_url'];
  if (runId is! int || runId <= 0 || url is! String || url.isEmpty) {
    throw StateError('Publisher dispatch returned no valid run ID or URL');
  }
  exportOutput('run_id', '$runId');
  File(environment('GITHUB_STEP_SUMMARY')).writeAsStringSync(
    'Publisher: [$tag]($url)\n',
    mode: FileMode.append,
  );
}
