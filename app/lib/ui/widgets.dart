import 'dart:ui' show FontFeature, PathMetric;

import 'package:material_ui/material_ui.dart';

import 'l10n.dart';
import 'theme.dart';

/// "Processed only on your device" pill.
class PrivacyBadge extends StatelessWidget {
  const PrivacyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.tr(
                  'Обработка только на вашем устройстве',
                  'Processed only on your device',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded box with a dashed outline, used as a drop zone.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(Gap.xl),
  });

  final Widget child;
  final bool highlighted;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashedPainter(
        highlighted ? colors.primary : colors.outlineVariant,
        highlighted ? 2 : 1.5,
        Radii.xl,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: padding,
        decoration: BoxDecoration(
          color: highlighted
              ? colors.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.color, this.width, this.radius);

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(width / 2),
      );
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 7), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.width != width || old.radius != radius;
}

/// A tile that is one of several mutually exclusive choices.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.55)
            : colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: selected
              ? BorderSide(color: colors.primary, width: 2)
              : BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(icon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: Gap.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.primary : colors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label and a number, as in the result summary.
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
