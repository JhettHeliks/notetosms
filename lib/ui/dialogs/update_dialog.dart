import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// Queries GitHub for updates and displays the dialog if an update is found,
  /// or shows a snackbar confirmation if up to date.
  static Future<void> checkAndShow(BuildContext context, {bool showToastIfUpToDate = true}) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Show quick progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Text(
                'Checking for updates...',
                style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading

      if (info.hasUpdate) {
        if (!context.mounted) return;
        show(context, info);
      } else if (showToastIfUpToDate) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('notetosms is up to date (v${info.currentVersion})'),
              ],
            ),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check for updates: $e'),
          backgroundColor: colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  /// Opens the update modal directly with known update information.
  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  StreamSubscription<UpdateProgressEvent>? _updateSubscription;
  bool _isDownloading = false;
  int _progressPercent = 0;
  String _statusText = '';
  String? _errorMessage;
  String? _downloadedFilePath;

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _showPermissionDialog(String filePath) async {
    final colorScheme = Theme.of(context).colorScheme;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Row(
          children: [
            Icon(Icons.security_update_warning_rounded, color: colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            const Text('Permission Needed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'To install updates directly, allow NoteToSMS to install unknown apps in Android Settings.',
          style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await UpdateService.instance.openInstallPermissionSetting();
    }
  }

  Future<void> _startDownload() async {
    if (!kIsWeb && !Platform.isAndroid) {
      setState(() {
        _errorMessage = 'In-app OTA installation is only supported on Android devices.';
      });
      return;
    }

    // If already downloaded, try installing directly
    if (_downloadedFilePath != null && File(_downloadedFilePath!).existsSync()) {
      final hasPerm = await UpdateService.instance.checkInstallPermission();
      if (!hasPerm) {
        await _showPermissionDialog(_downloadedFilePath!);
        return;
      }
      try {
        setState(() {
          _statusText = 'Launching installer...';
          _errorMessage = null;
        });
        await UpdateService.instance.installApk(_downloadedFilePath!);
        return;
      } catch (e) {
        setState(() {
          _errorMessage = 'Installation failed: $e';
        });
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _progressPercent = 0;
      _errorMessage = null;
      _statusText = 'Starting download...';
    });

    try {
      _updateSubscription?.cancel();
      _updateSubscription = UpdateService.instance
          .downloadAndInstallApk(apkDownloadUrl: widget.updateInfo.apkDownloadUrl)
          .listen(
        (UpdateProgressEvent event) async {
          if (!mounted) return;

          setState(() {
            switch (event.status) {
              case UpdateStatus.idle:
                break;
              case UpdateStatus.downloading:
                _progressPercent = event.progressPercent;
                _statusText = 'Downloading: ${event.formattedProgress}';
                if (event.filePath != null) {
                  _downloadedFilePath = event.filePath;
                }
                break;
              case UpdateStatus.permissionRequired:
                _isDownloading = false;
                _progressPercent = 100;
                _downloadedFilePath = event.filePath;
                _statusText = 'Permission required to install package.';
                break;
              case UpdateStatus.installing:
                _isDownloading = false;
                _progressPercent = 100;
                _downloadedFilePath = event.filePath;
                _statusText = 'Launching system package installer...';
                break;
              case UpdateStatus.completed:
                _isDownloading = false;
                _statusText = 'Update ready.';
                break;
              case UpdateStatus.error:
                _isDownloading = false;
                _errorMessage = event.errorMessage ?? 'Download error occurred. Please retry.';
                break;
            }
          });

          if (event.status == UpdateStatus.permissionRequired && event.filePath != null) {
            await _showPermissionDialog(event.filePath!);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isDownloading = false;
            _errorMessage = 'Download error: $error';
          });
        },
        onDone: () {
          if (mounted && _isDownloading && _errorMessage == null) {
            setState(() {
              _isDownloading = false;
              _statusText = 'Download complete.';
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Failed to start download: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final info = widget.updateInfo;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: Row(
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
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update Available',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  info.isPrerelease ? 'Beta Release' : 'Production Release',
                  style: TextStyle(
                    fontSize: 12,
                    color: info.isPrerelease ? AppTheme.accentAmber : colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version transition badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      Text(
                        'v${info.currentVersion}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                    ],
                  ),
                  Icon(Icons.arrow_forward_rounded, color: colorScheme.primary, size: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('New Version', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      Text(
                        'v${info.latestVersion}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Release Notes Section
            if (info.releaseNotes.isNotEmpty) ...[
              Text(
                'Release Notes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Download size info
            if (info.formattedSize.isNotEmpty && !_isDownloading)
              Row(
                children: [
                  Icon(Icons.folder_zip_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Download package size: ${info.formattedSize}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),

            // Progress state
            if (_isDownloading) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progressPercent > 0 ? _progressPercent / 100.0 : null,
                  backgroundColor: colorScheme.surfaceContainerLowest,
                  color: colorScheme.primary,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _statusText,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_progressPercent > 0)
                    Text(
                      '$_progressPercent%',
                      style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ],

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Later',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _isDownloading ? null : _startDownload,
          child: Text(_errorMessage != null ? 'Retry Update' : 'Update Now'),
        ),
      ],
    );
  }
}
