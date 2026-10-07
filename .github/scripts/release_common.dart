import 'dart:async';
import 'dart:io';

final versionPattern =
    RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');

String environment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('$name is required');
  }
  return value;
}

String releaseVersion(String tag) {
  if (!tag.startsWith('v') || !versionPattern.hasMatch(tag.substring(1))) {
    throw FormatException('Invalid release tag: $tag; expected vX.Y.Z');
  }
  return tag.substring(1);
}

void exportOutput(String name, String value) {
  if (value.contains('\n') || value.contains('\r')) {
    throw FormatException('Invalid multiline value for $name');
  }
  File(environment('GITHUB_OUTPUT')).writeAsStringSync(
    '$name=$value\n',
    mode: FileMode.append,
  );
}

Future<void> command(String executable, List<String> arguments,
    {String? workingDirectory}) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  await stdout.flush();
  final process = await Process.start(executable, arguments,
      workingDirectory: workingDirectory, mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  if (code != 0) {
    throw StateError('$executable failed with exit code $code');
  }
}

ProcessResult captureCommand(String executable, List<String> arguments,
    {String? workingDirectory, bool allowFailure = false}) {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final result = Process.runSync(executable, arguments,
      workingDirectory: workingDirectory);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0 && !allowFailure) {
    throw StateError('$executable failed with exit code ${result.exitCode}');
  }
  return result;
}

Future<void> runStep(List<String> arguments,
    Map<String, FutureOr<void> Function()> steps) async {
  try {
    if (arguments.length != 1 || !steps.containsKey(arguments.single)) {
      throw ArgumentError('Expected one step: ${steps.keys.join(', ')}');
    }
    await steps[arguments.single]!();
  } catch (error, stackTrace) {
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Future<bool> isPublished(String version) async {
  final uri =
      Uri.https('pub.dev', '/api/packages/nubrick_flutter/versions/$version');
  for (var attempt = 0;; attempt++) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final status = await (() async {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      })()
          .timeout(const Duration(seconds: 60));
      if (status == 200) return true;
      if (status == 404) return false;
      if (attempt >= 3 || ![408, 429, 500, 502, 503, 504].contains(status)) {
        throw StateError('pub.dev lookup returned HTTP $status');
      }
    } on IOException {
      if (attempt >= 3) rethrow;
    } on TimeoutException {
      if (attempt >= 3) rethrow;
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(Duration(seconds: 1 << attempt));
  }
}

class ReleaseMetadata {
  ReleaseMetadata(this.version, {Directory? directory})
      : directory = directory ?? Directory.current;

  final String version;
  final Directory directory;

  File file(String path) => File('${directory.path}/$path');

  String get currentVersion {
    final matches = RegExp(r'^version: (\S+)$', multiLine: true)
        .allMatches(file('pubspec.yaml').readAsStringSync());
    if (matches.length != 1) {
      throw StateError('Expected exactly one version in pubspec.yaml');
    }
    return matches.single.group(1)!;
  }

  void checkChangelog(String expected, {bool requireNotes = false}) {
    final lines = file('CHANGELOG.md').readAsLinesSync();
    if (lines.isEmpty || lines.first != '## $expected') {
      throw StateError('CHANGELOG.md must start with ## $expected');
    }
    if (requireNotes && (lines.length < 3 || !lines[2].startsWith('- '))) {
      throw StateError('CHANGELOG.md needs release notes below ## $expected');
    }
  }

  void verify() {
    if (currentVersion != version) {
      throw StateError('pubspec.yaml does not match $version');
    }
    if (!file('lib/version.dart')
        .readAsLinesSync()
        .contains("const String nubrickFlutterSdkVersion = '$version';")) {
      throw StateError('lib/version.dart does not match $version');
    }
    checkChangelog(version, requireNotes: true);
  }
}
