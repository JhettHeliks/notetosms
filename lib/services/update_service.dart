import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Data model representing a GitHub Release of the application.
class AppRelease {
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final String? apkDownloadUrl;
  final int? apkSizeBytes;
  final bool isPrerelease;

  const AppRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    this.apkDownloadUrl,
    this.apkSizeBytes,
    this.isPrerelease = false,
  });

  /// The raw semantic version without leading 'v'.
  String get versionString => tagName.startsWith('v') ? tagName.substring(1) : tagName;

  /// Human-readable download size string (e.g. "103.7 MB").
  String get formattedSize {
    if (apkSizeBytes == null || apkSizeBytes! <= 0) return '';
    final mb = apkSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Metadata model representing an available or checked application update.
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseTitle;
  final String releaseNotes;
  final String apkDownloadUrl;
  final DateTime? publishedAt;
  final bool isPrerelease;
  final int downloadSizeBytes;
  final AppRelease? release;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    this.publishedAt,
    this.isPrerelease = false,
    this.downloadSizeBytes = 0,
    this.release,
  });

  String get formattedSize {
    if (downloadSizeBytes <= 0) return '';
    final mb = downloadSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Service handling in-app GitHub release checks, version history, and OTA direct APK installation.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String defaultRepo = 'JhettHeliks/notetosms';

  /// Retrieves the currently installed package version from platform info.
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version.isNotEmpty ? packageInfo.version : '1.0.0';
    } catch (_) {
      return '1.0.0';
    }
  }

  /// Fetches all non-draft releases from the GitHub repository.
  Future<List<AppRelease>> fetchAllReleases({
    String githubRepo = defaultRepo,
  }) async {
    final url = Uri.parse('https://api.github.com/repos/$githubRepo/releases');
    final response = await http.get(
      url,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'notetosms-updater',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch releases from GitHub: HTTP ${response.statusCode}',
        uri: url,
      );
    }

    final List<dynamic> releasesJson = jsonDecode(response.body);
    final List<AppRelease> releases = [];

    for (final rel in releasesJson) {
      if (rel is! Map<String, dynamic>) continue;
      if (rel['draft'] == true) continue;

      final tagName = (rel['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) continue;

      final name = (rel['name'] as String? ?? tagName).trim();
      final body = (rel['body'] as String? ?? '').trim();
      final isPrerelease = rel['prerelease'] == true;
      final publishedAtStr = rel['published_at'] as String?;
      final publishedAt = publishedAtStr != null ? (DateTime.tryParse(publishedAtStr) ?? DateTime.now()) : DateTime.now();

      // Scan release assets for APK file
      final assets = (rel['assets'] as List<dynamic>? ?? []);
      String? apkUrl;
      int? apkSize;

      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final assetName = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String? ?? '';
        final size = asset['size'] as int?;

        if (assetName.endsWith('.apk')) {
          // Prefer named notetosms apk or universal
          if (assetName.contains('notetosms') || assetName.contains('universal') || assetName.contains('app-release') || apkUrl == null) {
            apkUrl = downloadUrl;
            apkSize = size;
          }
        }
      }

      releases.add(AppRelease(
        tagName: tagName,
        name: name,
        body: body,
        publishedAt: publishedAt,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize,
        isPrerelease: isPrerelease,
      ));
    }

    return releases;
  }

  /// Queries GitHub releases to determine if a newer version is available.
  Future<AppUpdateInfo> checkForUpdate({
    String githubRepo = defaultRepo,
    bool allowPrereleases = true,
  }) async {
    final currentVersion = await getCurrentVersion();
    final releases = await fetchAllReleases(githubRepo: githubRepo);

    if (releases.isEmpty) {
      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        hasUpdate: false,
        releaseTitle: 'No Releases Found',
        releaseNotes: 'No releases published on GitHub repository yet.',
        apkDownloadUrl: '',
      );
    }

    // Filter candidate releases (honor prereleases if configured)
    final candidateReleases = releases.where((rel) {
      if (!allowPrereleases && rel.isPrerelease) return false;
      return true;
    }).toList();

    if (candidateReleases.isEmpty) {
      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        hasUpdate: false,
        releaseTitle: 'Up to Date',
        releaseNotes: '',
        apkDownloadUrl: '',
      );
    }

    final latestRelease = candidateReleases.first;
    final hasUpdate = isNewerVersion(latestRelease.versionString, currentVersion);
    final apkUrl = latestRelease.apkDownloadUrl ?? '';
    final apkSize = latestRelease.apkSizeBytes ?? 0;

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestRelease.versionString,
      hasUpdate: hasUpdate && apkUrl.isNotEmpty,
      releaseTitle: latestRelease.name,
      releaseNotes: latestRelease.body,
      apkDownloadUrl: apkUrl,
      publishedAt: latestRelease.publishedAt,
      isPrerelease: latestRelease.isPrerelease,
      downloadSizeBytes: apkSize,
      release: latestRelease,
    );
  }

  /// Downloads the APK and triggers Android's package installer intent.
  Stream<OtaEvent> executeDownloadAndInstall({
    required String apkDownloadUrl,
    String destinationFilename = 'notetosms_update.apk',
  }) {
    if (!kIsWeb && !Platform.isAndroid) {
      throw UnsupportedError('In-app OTA APK installation is only supported on Android.');
    }
    return OtaUpdate().execute(
      apkDownloadUrl,
      destinationFilename: destinationFilename,
    );
  }

  /// Compares two version strings (supports SemVer with pre-release tags like 1.0.0-beta.1).
  static bool isNewerVersion(String latest, String current) {
    if (latest.trim() == current.trim()) return false;

    final latestClean = latest.trim().replaceFirst(RegExp(r'^v'), '');
    final currentClean = current.trim().replaceFirst(RegExp(r'^v'), '');

    if (latestClean == currentClean) return false;

    final latestCore = latestClean.split('-')[0].split('+')[0];
    final currentCore = currentClean.split('-')[0].split('+')[0];

    final latestParts = latestCore.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = currentCore.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (latestParts.length < 3) {
      latestParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    // Core versions are equal, check pre-release suffix (e.g. 1.0.0 vs 1.0.0-beta.1)
    final latestHasPre = latestClean.contains('-');
    final currentHasPre = currentClean.contains('-');

    // A non-prerelease version is newer than a prerelease version with the same core
    if (!latestHasPre && currentHasPre) return true;
    if (latestHasPre && !currentHasPre) return false;

    // Both are prereleases (e.g. 1.0.0-beta.2 vs 1.0.0-beta.1)
    if (latestHasPre && currentHasPre) {
      final latestPre = latestClean.substring(latestClean.indexOf('-') + 1);
      final currentPre = currentClean.substring(currentClean.indexOf('-') + 1);
      return _comparePreRelease(latestPre, currentPre) > 0;
    }

    return false;
  }

  static int _comparePreRelease(String pre1, String pre2) {
    final parts1 = pre1.split('.');
    final parts2 = pre2.split('.');

    final minLen = parts1.length < parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < minLen; i++) {
      final p1 = parts1[i];
      final p2 = parts2[i];

      final n1 = int.tryParse(p1);
      final n2 = int.tryParse(p2);

      if (n1 != null && n2 != null) {
        if (n1 != n2) return n1.compareTo(n2);
      } else {
        final cmp = p1.compareTo(p2);
        if (cmp != 0) return cmp;
      }
    }
    return parts1.length.compareTo(parts2.length);
  }
}
