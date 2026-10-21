import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'motion.dart';
import 'update_service.dart';
import 'widgets.dart';

/// In-app updater: compares the installed build with the newest published
/// `version.json` manifest and installs the APK without leaving the app.
class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  final _service = AppUpdateService();
  AppUpdateStatus? _status;
  bool _checking = true;
  bool _inFlight = false;
  bool _downloading = false;
  DownloadProgress? _progress;
  String? _error;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final status = await _service.checkStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checking = false;
        _lastChecked = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _lastChecked = DateTime.now();
        _error = 'Could not check for updates. Check your internet connection.';
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _downloadAndInstall() async {
    final update = _status?.update;
    if (update == null || _downloading) return;

    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });

    try {
      await _service.downloadAndInstall(
        update,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() => _downloading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloading = false);
      toastError(context, 'Update failed. Please try again later.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final updateAvailable = status?.updateAvailable ?? false;
    return Scaffold(
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: const PressScale(child: BackButton()),
        centerTitle: true,
        title: const Text(
          'App Updates',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _versionCard(status, updateAvailable),
          ),
        ),
      ),
      bottomNavigationBar: _bottomAction(status, updateAvailable),
    );
  }

  Widget _versionCard(AppUpdateStatus? status, bool updateAvailable) {
    final latestVersion = status?.latestVersion ?? '';
    final showLatest = updateAvailable && latestVersion.isNotEmpty;
    final message = status?.update?.message ?? '';
    final notes = _notes(message);
    return SizedBox(
      width: double.infinity,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _statusIcon(updateAvailable),
              const SizedBox(height: 8),
              Text(
                _checking && status == null
                    ? 'Checking for updates…'
                    : updateAvailable
                        ? 'Update available'
                        : _error != null
                            ? _error!
                            : 'You are up to date',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.mainText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _versionBadge(
                    label: 'Current',
                    version: status?.currentVersion,
                    highlighted: false,
                  ),
                  if (showLatest) ...[
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: AppColors.secondaryText,
                    ),
                    _versionBadge(
                      label: 'Latest',
                      version: latestVersion,
                      highlighted: true,
                    ),
                  ],
                ],
              ),
              if (updateAvailable && notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.neutralChip,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "WHAT'S NEW",
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...notes.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: CircleAvatar(
                                  radius: 2.5,
                                  backgroundColor: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    color: AppColors.mainText,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: _progress?.value,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_downloadSpeed(_progress)} · ${_downloadSize(_progress)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.5,
                  ),
                ),
              ],
              if (_lastChecked != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Last checked · ${_checkedAt(_lastChecked!)}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static List<String> _notes(String raw) {
    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.length > 8 ? lines.sublist(0, 8) : lines;
  }

  static String _downloadSize(DownloadProgress? progress) {
    if (progress == null) return 'Starting download…';
    final downloaded = _mb(progress.receivedBytes);
    final total =
        progress.totalBytes == null ? '?' : _mb(progress.totalBytes!);
    return '$downloaded / $total';
  }

  static String _downloadSpeed(DownloadProgress? progress) {
    if (progress == null || progress.bytesPerSecond == 0) {
      return 'Calculating speed…';
    }
    return '${_mb(progress.bytesPerSecond)}/s';
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  static String _checkedAt(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _statusIcon(bool updateAvailable) {
    if (_checking && _status == null) {
      return const Icon(
        Icons.cloud_sync_outlined,
        size: 30,
        color: AppColors.primary,
      );
    }
    if (updateAvailable) {
      return const Icon(
        Icons.rocket_launch_outlined,
        size: 30,
        color: AppColors.primary,
      );
    }
    if (_error != null) {
      return const Icon(
        Icons.info_outline,
        size: 30,
        color: AppColors.danger,
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 22, color: Colors.white),
    );
  }

  Widget _versionBadge({
    required String label,
    required String? version,
    required bool highlighted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.neutralChip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        version == null ? '$label version' : '$label · v$version',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: highlighted ? AppColors.primary : AppColors.secondaryText,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// The page's primary action, pinned to a shadowed bar. While a request is
  /// running the button is muted instead of showing a spinner.
  Widget _bottomAction(AppUpdateStatus? status, bool updateAvailable) {
    late final VoidCallback? onPressed;
    late final String label;
    var busy = false;
    if (status == null) {
      onPressed = _checking ? null : _check;
      label = 'Check for Updates';
      busy = _checking;
    } else if (updateAvailable) {
      onPressed = _downloading ? null : _downloadAndInstall;
      label = _downloading
          ? 'Downloading… ${((_progress?.value ?? 0) * 100).toStringAsFixed(0)}%'
          : 'Download & Install v${status.latestVersion}';
      busy = _downloading;
    } else {
      onPressed = _checking ? null : _check;
      label = 'Check Again';
      busy = _checking;
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: AppColors.mainText.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 50,
            child: AnimatedOpacity(
              opacity: busy ? 0.45 : 1,
              duration: MotionDuration.quick,
              child: PressScale(
                enabled: !busy,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: onPressed,
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
