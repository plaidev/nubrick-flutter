import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../.github/scripts/release_common.dart';

void main() {
  late Directory directory;
  late ReleaseMetadata metadata;

  File file(String path) => File('${directory.path}/$path');

  Future<ProcessResult> dispatchPublisher(Map<String, dynamic> response) async {
    Directory('${directory.path}/bin').createSync();
    final gh = file('bin/gh')..writeAsStringSync(r'''#!/bin/sh
printf '%s\n' "$@" > "$GH_ARGUMENTS_FILE"
printf '%s\n' "$GH_DISPATCH_RESPONSE"
''');
    final chmod = Process.runSync('chmod', ['+x', gh.path]);
    expect(chmod.exitCode, 0);
    return Process.run('dart', [
      '.github/scripts/release.dart',
      'start-publisher'
    ], environment: {
      'PATH': '${directory.path}/bin:${Platform.environment['PATH']}',
      'GH_ARGUMENTS_FILE': file('gh-arguments').path,
      'GH_DISPATCH_RESPONSE': jsonEncode(response),
      'GITHUB_REPOSITORY': 'example/sdk',
      'GITHUB_OUTPUT': file('outputs').path,
      'GITHUB_STEP_SUMMARY': file('summary').path,
      'RELEASE_TAG': 'v0.10.0',
    });
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release-script-test-');
    Directory('${directory.path}/lib').createSync();
    file('pubspec.yaml').writeAsStringSync('name: example\nversion: 0.9.9\n');
    file('lib/version.dart').writeAsStringSync(
        "const String nubrickFlutterSdkVersion = '0.9.9';\n");
    file('CHANGELOG.md').writeAsStringSync('## 0.9.9\n\n- Previous notes\n');
    metadata = ReleaseMetadata('0.10.0', directory: directory);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('compares version components numerically', () {
    metadata.checkNextVersion();
    for (final version in ['0.9.9', '0.9.8', '0.8.99']) {
      expect(
        () => ReleaseMetadata(version, directory: directory).checkNextVersion(),
        throwsStateError,
      );
    }
  });

  test('prepares consistent versions and preserves changelog history', () {
    final previous = file('CHANGELOG.md').readAsStringSync();
    metadata.prepare(' - First note | * Second note\nThird note');
    metadata.verify();
    expect(file('CHANGELOG.md').readAsStringSync(),
        '## 0.10.0\n\n- First note\n- Second note\n- Third note\n\n$previous');
  });

  test('rejects invalid notes before changing any files', () {
    final original = file('pubspec.yaml').readAsStringSync();
    for (final notes in ['', ' ', 'TODO', '- tBd', 'Valid|', 'Valid||Other']) {
      expect(() => metadata.prepare(notes), throwsFormatException);
      expect(file('pubspec.yaml').readAsStringSync(), original);
    }
  });

  test('rejects malformed version declarations before changing files', () {
    final original = file('pubspec.yaml').readAsStringSync();
    file('lib/version.dart').writeAsStringSync('');
    expect(() => metadata.prepare('Valid notes'), throwsStateError);
    expect(file('pubspec.yaml').readAsStringSync(), original);
    file('pubspec.yaml').writeAsStringSync('${original}version: 0.9.9\n');
    expect(() => metadata.prepare('Valid notes'), throwsStateError);
  });

  test('rejects a mismatched changelog before preparing a release', () {
    file('CHANGELOG.md').writeAsStringSync('## 0.9.8\n\n- Old notes\n');
    expect(() => metadata.prepare('Valid notes'), throwsStateError);
  });

  test('publisher dispatch exports its exact run ID and summary link',
      () async {
    const url = 'https://github.com/example/sdk/actions/runs/12345';
    final result = await dispatchPublisher({
      'workflow_run_id': 12345,
      'html_url': url,
    });
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(file('outputs').readAsStringSync(), 'run_id=12345\n');
    expect(file('summary').readAsStringSync(), 'Publisher: [v0.10.0]($url)\n');
    expect(file('gh-arguments').readAsLinesSync(), [
      'api',
      '--method',
      'POST',
      'repos/example/sdk/actions/workflows/publish.yaml/dispatches',
      '--header',
      'X-GitHub-Api-Version: 2022-11-28',
      '--field',
      'return_run_details=true',
      '--raw-field',
      'ref=v0.10.0',
      '--raw-field',
      'inputs[version]=v0.10.0',
    ]);
  });

  test('publisher dispatch fails with a stack trace if its run ID is missing',
      () async {
    final result = await dispatchPublisher({
      'html_url': 'https://github.com/example/sdk/actions/runs/12345',
    });
    expect(result.exitCode, 1);
    expect(result.stderr, contains('no valid run ID or URL'));
    expect(result.stderr, contains('startPublisher'));
    expect(file('outputs').existsSync(), isFalse);
    expect(file('summary').existsSync(), isFalse);
  });
}
