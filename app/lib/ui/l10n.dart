import 'package:material_ui/material_ui.dart';

/// Picks the Russian or English text for the current locale.
typedef Translate = String Function(String ru, String en);

String localText(BuildContext context, String ru, String en) =>
    Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

extension LocalText on BuildContext {
  /// `context.tr('Русский', 'English')`.
  String tr(String ru, String en) => localText(this, ru, en);
}
