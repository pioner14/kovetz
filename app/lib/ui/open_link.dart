import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import 'l10n.dart';

@visibleForTesting
Future<bool> Function(Uri) linkLauncher = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openGuide(BuildContext context) =>
    openLink(context, Uri.parse(appGuideUrl).resolve(context.tr('ru/', 'en/')));

Future<void> openLink(BuildContext context, Uri uri) async {
  try {
    if (await linkLauncher(uri)) return;
  } catch (_) {
    // Use the clipboard if the platform cannot launch a browser.
  }

  await Clipboard.setData(ClipboardData(text: uri.toString()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.tr(
          'Не удалось открыть браузер. Ссылка скопирована: $uri',
          'Could not open the browser. Link copied: $uri',
        ),
      ),
    ),
  );
}
