import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../.github/scripts/release_common.dart';

void main() {
  late Directory directory;
  late ReleaseMetadata metadata;

  File file(String path) => File('${directory.path}/$path');

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

  test('requires a stable release tag without leading zeroes', () {
    expect(releaseVersion('v0.10.0'), '0.10.0');
    for (final tag in [
      '0.10.0',
      'v01.0.0',
      'v1.0.0-rc.1',
      'v1.0',
      'v1.0.0\n'
    ]) {
      expect(() => releaseVersion(tag), throwsFormatException);
    }
  });

  test('verification accepts consistent package metadata', () {
    file('pubspec.yaml').writeAsStringSync('name: example\nversion: 0.10.0\n');
    file('lib/version.dart').writeAsStringSync(
        "const String nubrickFlutterSdkVersion = '0.10.0';\n");
    file('CHANGELOG.md').writeAsStringSync('## 0.10.0\n\n- Valid notes\n');
    metadata.verify();
  });

  test('verification rejects mismatched versions and missing notes', () {
    file('pubspec.yaml').writeAsStringSync('version: 0.9.9\n');
    expect(metadata.verify, throwsStateError);
    file('pubspec.yaml').writeAsStringSync('version: 0.10.0\n');
    file('lib/version.dart').writeAsStringSync(
        "const String nubrickFlutterSdkVersion = '0.9.9';\n");
    expect(metadata.verify, throwsStateError);
    file('lib/version.dart').writeAsStringSync(
        "const String nubrickFlutterSdkVersion = '0.10.0';\n");
    file('CHANGELOG.md').writeAsStringSync('## 0.10.0\n');
    expect(metadata.verify, throwsStateError);
  });

  test('a failed external command stops the release step', () async {
    await expectLater(
        command('git', ['--invalid-release-test']), throwsStateError);
  });

  test('command streams stdout and stderr before the child exits', () async {
    final common = File('.github/scripts/release_common.dart').absolute.uri;
    final child = file('stream-command.sh')..writeAsStringSync(r'''
printf 'stdout-ready\n'
printf 'stderr-ready\n' >&2
read -r acknowledgement
test "$acknowledgement" = continue
''');
    final runner = file('stream-command.dart')..writeAsStringSync('''
import ${jsonEncode(common.toString())};

Future<void> main() async {
  await command('sh', [${jsonEncode(child.path)}]);
}
''');
    final process = await Process.start('dart', [runner.path]);
    final stdoutReady = Completer<void>();
    final stderrReady = Completer<void>();
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line == 'stdout-ready') stdoutReady.complete();
    });
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line == 'stderr-ready') stderrReady.complete();
    });
    try {
      await Future.wait([stdoutReady.future, stderrReady.future])
          .timeout(const Duration(seconds: 10));
      process.stdin.writeln('continue');
      await process.stdin.flush();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    } finally {
      process.kill();
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  });
}
