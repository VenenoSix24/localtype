import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/local_type_provider.dart';
import '../services/update_service.dart';

void showUpdateDialog(
    BuildContext context, LocalTypeProvider provider, UpdateInfo info) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded,
              color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text('发现新版本 v${info.latestVersion}',
                style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前版本: v${info.currentVersion}',
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            if (info.releaseNotes.isNotEmpty) ...[
              Text('更新日志',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(info.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            provider.skipCurrentUpdate();
            Navigator.pop(ctx);
          },
          child: const Text('跳过此版本'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (info.downloadUrl.isNotEmpty) {
              launchUrl(Uri.parse(info.downloadUrl),
                  mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('下载更新'),
        ),
      ],
    ),
  );
}
