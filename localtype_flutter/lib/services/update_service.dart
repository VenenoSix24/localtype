import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final bool available;
  final bool skipped;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.available,
    this.skipped = false,
  });
}

class UpdateService {
  static const String _githubApiUrl =
      'https://api.github.com/repos/VenenoSix24/localtype/releases/latest';
  static const String _skipVersionKey = 'skipped_update_version';

  static Future<UpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final response = await http.get(
      Uri.parse(_githubApiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to check updates: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final tagName = data['tag_name'] as String;
    final latestVersion = tagName.replaceFirst('v', '');
    final releaseNotes = data['body'] as String? ?? '';

    if (_compareVersions(latestVersion, currentVersion) <= 0) {
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        downloadUrl: '',
        available: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final skippedVersion = prefs.getString(_skipVersionKey);
    final skipped = skippedVersion == latestVersion;

    final assets = data['assets'] as List<dynamic>;
    final downloadUrl = _findApkUrl(assets);

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: releaseNotes,
      downloadUrl: downloadUrl,
      available: true,
      skipped: skipped,
    );
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, version);
  }

  static Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipVersionKey);
  }

  static String _findApkUrl(List<dynamic> assets) {
    for (final arch in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      final match = assets.firstWhere(
        (a) => (a['name'] as String).contains(arch),
        orElse: () => null,
      );
      if (match != null) return match['browser_download_url'] as String;
    }
    final anyApk = assets.firstWhere(
      (a) => (a['name'] as String).endsWith('.apk'),
      orElse: () => null,
    );
    return anyApk?['browser_download_url'] as String? ?? '';
  }

  static int _compareVersions(String a, String b) {
    // 去除 pre-release 后缀（如 "1.2.3-beta" → "1.2.3"）
    final cleanA = a.split('-').first;
    final cleanB = b.split('-').first;
    final aParts = cleanA.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = cleanB.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal != bVal) return aVal.compareTo(bVal);
    }
    return 0;
  }
}
