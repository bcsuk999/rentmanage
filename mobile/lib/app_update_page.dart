import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'widgets.dart';

const _owner = 'bcsuk999';
const _repo = 'rentmanage';

/// App update info resolved from GitHub.
class _Release {
  _Release({
    required this.version,
    required this.title,
    required this.notes,
    required this.downloadUrl,
    required this.pageUrl,
    required this.size,
  });

  final String version;
  final String title;
  final String notes;
  final String downloadUrl;
  final String pageUrl;
  final int size;
}

/// In-app updater: compares the installed build with the newest APK
/// published on GitHub (a formal Release when one exists, otherwise the
/// highest `rentmanage-arm64-vX.Y.Z.apk` under `releases/` on main).
class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  String? _installed;
  _Release? _latest;
  bool _checking = true;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  static List<int> _parts(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
    if (m == null) return [0, 0, 0];
    return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
  }

  /// >0 when [a] is newer than [b].
  static int _compare(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  Map<String, String> get _ghHeaders => const {
        'User-Agent': 'rentmanage-app',
        'Accept': 'application/vnd.github+json',
      };

  /// Formal GitHub Release with an .apk asset, or null when none is published.
  Future<_Release?> _fromReleasesApi() async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      headers: _ghHeaders,
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    Map<String, dynamic>? apk;
    for (final a in (body['assets'] as List? ?? [])) {
      final name = '${(a as Map)['name']}';
      if (name.endsWith('.apk')) {
        apk = a as Map<String, dynamic>;
        break;
      }
    }
    if (apk == null) return null;
    return _Release(
      version: '${body['tag_name'] ?? body['name'] ?? 'latest'}',
      title: '${body['name'] ?? 'Update'}',
      notes: '${body['body'] ?? ''}',
      downloadUrl: '${apk['browser_download_url']}',
      pageUrl: '${body['html_url']}',
      size: (apk['size'] as num? ?? 0).toInt(),
    );
  }

  /// Fallback: newest versioned APK committed under releases/ on main.
  Future<_Release?> _fromRepoFolder() async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/releases?ref=main'),
      headers: _ghHeaders,
    );
    if (res.statusCode != 200) return null;
    final files = (jsonDecode(res.body) as List).cast<Map>();
    Map<String, dynamic>? best;
    for (final f in files) {
      final name = '${f['name']}';
      if (!name.endsWith('.apk')) continue;
      if (best == null || _compare(name, '${best['name']}') > 0) {
        best = f.cast<String, dynamic>();
      }
    }
    if (best == null) return null;
    return _Release(
      version: _parts('${best['name']}').join('.'),
      title: '${best['name']}',
      notes: 'Published in the releases folder on GitHub.',
      downloadUrl: '${best['download_url']}',
      pageUrl: 'https://github.com/$_owner/$_repo/tree/main/releases',
      size: (best['size'] as num? ?? 0).toInt(),
    );
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final latest = await _fromReleasesApi() ?? await _fromRepoFolder();
      if (!mounted) return;
      setState(() {
        _installed = info.version;
        _latest = latest;
        _checking = false;
        if (latest == null) _error = 'No published updates found yet.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Could not reach GitHub. Check your internet connection and try again.';
      });
    }
  }

  Future<void> _download() async {
    final url = _latest?.downloadUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _opening = true);
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the download link.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _latest;
    final updateAvailable = _installed != null &&
        latest != null &&
        _compare(latest.version, _installed!) > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('App Updates')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'logo.png',
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.home_work_outlined,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Rent Manager',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          _installed == null
                              ? 'Installed: …'
                              : 'Installed: v$_installed',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_checking)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_error != null && latest == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _check,
                            child: const Text('Check Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (latest != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  updateAvailable
                                      ? 'Update available: v${latest.version}'
                                      : 'You are up to date (v${latest.version})',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: updateAvailable
                                          ? AppColors.primary
                                          : AppColors.success),
                                ),
                              ),
                              StatusPill(
                                text: updateAvailable ? 'New' : 'Latest',
                                color: updateAvailable
                                    ? AppColors.primary
                                    : AppColors.success,
                                soft: updateAvailable
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : AppColors.successSoft,
                              ),
                            ],
                          ),
                          if (latest.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              latest.notes.length > 300
                                  ? '${latest.notes.substring(0, 300)}…'
                                  : latest.notes,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.secondaryText),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (updateAvailable)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _opening ? null : _download,
                                icon: const Icon(Icons.download_outlined),
                                label: Text(_opening
                                    ? 'Opening…'
                                    : 'Download v${latest.version} (${_mb(latest.size)})'),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _opening ? null : _check,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Check Again'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Updates come from the project GitHub. On Android, open the downloaded APK to install it.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _mb(int bytes) {
    if (bytes <= 0) return '';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}
