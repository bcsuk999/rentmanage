import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// The latest build, as published in `releases/version.json`.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.message,
  });

  final String version;
  final int build;
  final String apkUrl;
  final String message;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version'] as String? ?? '',
      build: (json['build'] as num?)?.toInt() ?? 0,
      apkUrl: json['apkUrl'] as String? ?? '',
      message: json['message'] as String? ?? 'A new version is available.',
    );
  }
}

/// Installed build vs. the published one.
class AppUpdateStatus {
  const AppUpdateStatus({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.update,
  });

  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final AppUpdateInfo? update;

  bool get updateAvailable => update != null;
}

/// Live download figures for the progress bar.
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final int receivedBytes;
  final int? totalBytes;
  final int bytesPerSecond;

  double? get value => totalBytes == null || totalBytes == 0
      ? null
      : receivedBytes / totalBytes!;
}

class AppUpdateService {
  static const _manifestUrl =
      'https://raw.githubusercontent.com/bcsuk999/rentmanage/main/releases/version.json';

  Future<AppUpdateStatus> checkStatus() async {
    final info = await PackageInfo.fromPlatform();
    final manifestUrl = '$_manifestUrl?v=${info.buildNumber}';
    final response = await http
        .get(Uri.parse(manifestUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('Update check failed (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid update manifest.');
    }

    final update = AppUpdateInfo.fromJson(decoded);
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    return AppUpdateStatus(
      currentVersion: info.version,
      currentBuild: currentBuild,
      latestVersion: update.version,
      latestBuild: update.build,
      update: update.build > currentBuild && update.apkUrl.isNotEmpty
          ? update
          : null,
    );
  }

  Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw HttpException('APK download failed (${response.statusCode}).');
      }

      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/rentmanage-update.apk');
      final sink = apkFile.openWrite();
      var receivedBytes = 0;
      final totalBytes = response.contentLength;
      final startedAt = DateTime.now();
      onProgress(
        DownloadProgress(
          receivedBytes: 0,
          totalBytes: totalBytes,
          bytesPerSecond: 0,
        ),
      );
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final elapsedSeconds =
            DateTime.now().difference(startedAt).inMilliseconds / 1000;
        onProgress(
          DownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            bytesPerSecond: elapsedSeconds <= 0
                ? receivedBytes
                : (receivedBytes / elapsedSeconds).round(),
          ),
        );
      }
      await sink.close();
      onProgress(
        DownloadProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          bytesPerSecond: receivedBytes,
        ),
      );

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } finally {
      client.close();
    }
  }
}
