import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ota_update/ota_update.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/update_service.dart';

class VersionHistoryDialog extends StatefulWidget {
  const VersionHistoryDialog({super.key});

  /// Displays the Version History modal sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const VersionHistoryDialog(),
    );
  }

  @override
  State<VersionHistoryDialog> createState() => _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends State<VersionHistoryDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  String _currentVersion = '...';
  List<AppRelease> _releases = [];
  
  // Track active downloading release
  String? _activeDownloadingTag;
  int _downloadPercent = 0;
  String _downloadStatus = '';
  String? _downloadError;
  StreamSubscription<OtaEvent>? _otaSubscription;

  // Track expanded release notes
  final Set<String> _expandedReleaseTags = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _otaSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentVer = await UpdateService.instance.getCurrentVersion();
      final releases = await UpdateService.instance.fetchAllReleases();

      if (!mounted) return;
      setState(() {
        _currentVersion = currentVer;
        _releases = releases;
        _isLoading = false;
        // Expand the first release by default
        if (releases.isNotEmpty) {
          _expandedReleaseTags.add(releases.first.tagName);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startDownload(AppRelease release) {
    if (!kIsWeb && !Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct OTA installation is only supported on Android devices.')),
      );
      return;
    }

    if (release.apkDownloadUrl == null || release.apkDownloadUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Android APK asset found for this release.')),
      );
      return;
    }

    _otaSubscription?.cancel();

    setState(() {
      _activeDownloadingTag = release.tagName;
      _downloadPercent = 0;
      _downloadError = null;
      _downloadStatus = 'Starting download...';
    });

    try {
      _otaSubscription = UpdateService.instance
          .executeDownloadAndInstall(apkDownloadUrl: release.apkDownloadUrl!)
          .listen(
        (OtaEvent event) {
          if (!mounted) return;

          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                _downloadPercent = int.tryParse(event.value ?? '0') ?? _downloadPercent;
                _downloadStatus = 'Downloading update: $_downloadPercent%';
                break;
              case OtaStatus.INSTALLING:
                _downloadPercent = 100;
                _downloadStatus = 'Installing package...';
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _downloadError = 'An update download is already in progress.';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _downloadError = 'Install unknown apps permission denied in Android Settings.';
                break;
              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.CHECKSUM_ERROR:
                _downloadError = 'Download failed (${event.status.name}). Please check your connection.';
                break;
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _downloadError = 'Download error: $error';
          });
        },
        onDone: () {
          if (mounted && _downloadError == null) {
            setState(() {
              _downloadStatus = 'Package installer triggered';
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _downloadError = 'Failed to start download: $e';
      });
    }
  }

  bool _isCurrentlyInstalled(AppRelease release) {
    final cleanCurrent = _currentVersion.replaceFirst(RegExp(r'^v'), '').trim();
    final cleanRelease = release.versionString.trim();
    return cleanCurrent == cleanRelease;
  }

  bool _isNewer(AppRelease release) {
    return UpdateService.isNewerVersion(release.versionString, _currentVersion);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    final hasAnyUpdate = _releases.any((r) => _isNewer(r));

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.88),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag Handle
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Updates & Versions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'GitHub Releases & Sideload Installer',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                          )
                        : const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'Refresh Releases',
                    onPressed: _isLoading ? null : _fetchData,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Current Version Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hasAnyUpdate
                        ? colorScheme.primary.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Installed Version',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'v$_currentVersion',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: hasAnyUpdate
                            ? colorScheme.primary.withValues(alpha: 0.15)
                            : AppTheme.tertiary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasAnyUpdate
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : AppTheme.tertiary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasAnyUpdate ? Icons.new_releases_rounded : Icons.check_circle_rounded,
                            size: 14,
                            color: hasAnyUpdate ? colorScheme.primary : AppTheme.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasAnyUpdate ? 'Update Available' : 'Up to date',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: hasAnyUpdate ? colorScheme.primary : AppTheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            const Divider(height: 1),

            // Releases Content List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: 14),
                          Text(
                            'Fetching releases from GitHub...',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 42, color: colorScheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  'Could not fetch releases',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _fetchData,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _releases.isEmpty
                          ? Center(
                              child: Text(
                                'No releases published yet.',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                              itemCount: _releases.length,
                              itemBuilder: (context, index) {
                                final release = _releases[index];
                                return _buildReleaseCard(context, release);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseCard(BuildContext context, AppRelease release) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrent = _isCurrentlyInstalled(release);
    final isNewerVer = _isNewer(release);
    final isExpanded = _expandedReleaseTags.contains(release.tagName);
    final isDownloading = _activeDownloadingTag == release.tagName;

    final formattedDate = DateFormat.yMMMd().format(release.publishedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent
              ? AppTheme.tertiary.withValues(alpha: 0.7)
              : isNewerVer
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            release.tagName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.tertiary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'CURRENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.tertiary,
                                ),
                              ),
                            ),
                          if (release.isPrerelease) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentAmber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BETA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentAmber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        release.name.isNotEmpty && release.name != release.tagName
                            ? '${release.name} • $formattedDate'
                            : formattedDate,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (release.formattedSize.isNotEmpty)
                  Text(
                    release.formattedSize,
                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),

          // Release Notes (Collapsible)
          if (release.body.isNotEmpty) ...[
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedReleaseTags.remove(release.tagName);
                  } else {
                    _expandedReleaseTags.add(release.tagName);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      isExpanded ? 'Hide release notes' : 'View release notes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    release.body,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],

          // Active Download Progress Bar
          if (isDownloading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _downloadPercent > 0 ? _downloadPercent / 100.0 : null,
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.surfaceContainerHigh,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _downloadStatus,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_downloadPercent > 0)
                        Text(
                          '$_downloadPercent%',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  if (_downloadError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _downloadError!,
                      style: TextStyle(fontSize: 11.5, color: colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Action Button Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Spacer(),
                if (isCurrent)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.tertiary,
                      side: BorderSide(color: AppTheme.tertiary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Installed', style: TextStyle(fontSize: 12)),
                    onPressed: () {},
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isNewerVer ? colorScheme.primary : colorScheme.surfaceContainerHigh,
                      foregroundColor: isNewerVer ? colorScheme.onPrimary : colorScheme.onSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      isDownloading ? Icons.sync : Icons.download_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isDownloading
                          ? 'Downloading...'
                          : isNewerVer
                              ? 'Install Update'
                              : 'Install this Build',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: isDownloading ? null : () => _startDownload(release),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
