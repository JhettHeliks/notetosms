import 'package:flutter_test/flutter_test.dart';
import 'package:notetosms/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison Tests', () {
    test('standard patch, minor, and major comparisons', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('handles leading "v" prefix gracefully', () {
      expect(UpdateService.isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.1', 'v1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0.0'), isFalse);
    });

    test('handles pre-release beta and rc tags', () {
      // Release is newer than beta of same core
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0-beta.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0-beta.1', '1.0.0'), isFalse);

      // Higher beta number is newer
      expect(UpdateService.isNewerVersion('1.0.0-beta.2', '1.0.0-beta.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0-beta.1', '1.0.0-beta.2'), isFalse);

      // Major/minor bumps are newer even with beta tags
      expect(UpdateService.isNewerVersion('1.1.0-beta.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.1.0-beta.1'), isFalse);
    });

    test('AppUpdateInfo model format and helpers', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0-beta.1',
        latestVersion: '1.0.0-beta.2',
        hasUpdate: true,
        releaseTitle: 'notetosms v1.0.0-beta.2',
        releaseNotes: 'Fixed bugs and added self-updater',
        apkDownloadUrl: 'https://github.com/JhettHeliks/notetosms/releases/download/v1.0.0-beta.2/notetosms-v1.0.0-beta.2-release.apk',
        downloadSizeBytes: 104857600, // 100 MB
      );

      expect(info.hasUpdate, isTrue);
      expect(info.formattedSize, '100.0 MB');
    });

    test('AppRelease model properties and formatted size', () {
      final release = AppRelease(
        tagName: 'v1.0.0-beta.1',
        name: 'notetosms v1.0.0-beta.1',
        body: 'Initial beta release with encrypted chat storage',
        publishedAt: DateTime(2026, 8, 24),
        apkDownloadUrl: 'https://github.com/JhettHeliks/notetosms/releases/download/v1.0.0-beta.1/notetosms-v1.0.0-beta.1.apk',
        apkSizeBytes: 108789760, // ~103.75 MB
        isPrerelease: true,
      );

      expect(release.versionString, '1.0.0-beta.1');
      expect(release.formattedSize, '103.8 MB');
      expect(release.isPrerelease, isTrue);
    });
  });
}
