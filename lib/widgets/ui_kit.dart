import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';

/// The shared visual vocabulary every screen is built from.
///
/// These are not "components that happen to exist" — they are the four shapes
/// the design is made of: a soft rounded icon tile, a row of one, a search box
/// and a logo lockup. Building each screen from the same primitives is what
/// makes the app read as one designed thing instead of fifteen assembled ones.
class AppIconTile extends StatelessWidget {
  /// Either [icon] or [child] must be given; [child] wins when both are.
  final IconData? icon;
  final Widget? child;
  final double size;
  final double iconSize;
  final Color color;
  final Color background;
  final BorderRadius? borderRadius;
  final bool circular;

  const AppIconTile({
    super.key,
    this.icon,
    this.child,
    this.size = 40,
    this.iconSize = 20,
    this.color = AppColors.primary,
    this.background = AppColors.primarySoft,
    this.borderRadius,
    this.circular = false,
  }) : assert(icon != null || child != null, 'give an icon or a child');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular
            ? null
            : (borderRadius ?? BorderRadius.circular(AppRadius.input)),
      ),
      child: child ?? Icon(icon, size: iconSize, color: color),
    );
  }
}

/// A tappable row: icon tile, a title with an optional second line, and a
/// trailing slot. This is the shape of the settings list, the sessions list,
/// the file-type list and the student roster — one widget, not four.
class AppListRow extends StatelessWidget {
  /// Either [icon] or [leading] must be given; [leading] wins when both are,
  /// and exists so a row can carry a drawn mark (see [GitHubMark]) instead of
  /// a Material glyph.
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool circularIcon;
  final Color iconColor;
  final Color iconBackground;
  final double iconSize;

  const AppListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.circularIcon = false,
    this.iconColor = AppColors.primary,
    this.iconBackground = AppColors.primarySoft,
    this.iconSize = 40,
  }) : assert(icon != null || leading != null, 'give an icon or a leading');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          AppIconTile(
            icon: icon,
            child: leading,
            size: iconSize,
            iconSize: iconSize * 0.5,
            color: iconColor,
            background: iconBackground,
            circular: circularIcon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return Material(
      color: selected ? AppColors.primarySoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// A stack of [AppListRow]s inside one card, hairline-separated.
class AppListGroup extends StatelessWidget {
  final List<Widget> rows;

  const AppListGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Divider(height: 1, indent: 12, endIndent: 12));
      }
      children.add(rows[i]);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The chevron that says "this row opens something".
class AppChevron extends StatelessWidget {
  const AppChevron({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.chevron_right, size: size, color: AppColors.muted);
  }
}

/// A small labelled heading above a group of content.
class AppSectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? action;

  /// [title] is positional on purpose: every section heading in the app is
  /// written `AppSectionTitle('Network')`, and a named-only parameter made
  /// that read worse for no gain.
  const AppSectionTitle(this.title, {super.key, this.trailing, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          if (action != null)
            action!
          else if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// A field label sitting above its input, the way the design draws forms.
class AppFieldLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const AppFieldLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The search box from the design, used by the file library and the share
/// picker.
class AppSearchField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const AppSearchField({
    super.key,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// The green / grey dot from the design, used to mark a live session.
///
/// Wrapped in [Semantics] because it is otherwise a colour-only signal: a
/// screen reader would just announce "image".
class LiveDot extends StatelessWidget {
  final bool active;
  final double size;
  final Color activeColor;

  const LiveDot({
    super.key,
    required this.active,
    this.size = 10,
    this.activeColor = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: active ? 'Live' : 'Not live',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? activeColor : AppColors.muted,
        ),
      ),
    );
  }
}

/// Logo over a two-line product lockup — the header on role selection, the
/// join screen and the waiting room.
class AppBrandLockup extends StatelessWidget {
  final double logoSize;
  final String title;
  final String subtitle;
  final bool onBlue;
  final double gap;

  const AppBrandLockup({
    super.key,
    this.logoSize = 72,
    this.title = 'ClassCast',
    this.subtitle = 'Offline',
    this.onBlue = false,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = onBlue ? Colors.white : AppColors.ink;
    final subtitleColor = onBlue ? Colors.white70 : AppColors.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize, filled: onBlue),
        SizedBox(height: gap),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: titleColor,
            height: 1.1,
          ),
        ),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: subtitleColor,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The GitHub mark, drawn rather than shipped.
///
/// Material's icon set has no GitHub logo, and the package that does —
/// `font_awesome_flutter` — builds its icons by subclassing `IconData`, which
/// is now a `final class`, so it no longer compiles on current Flutter. Rather
/// than go without the mark, it is drawn: the real silhouette is one disc with
/// three holes cut out of it, the gap under the head, the notch between the
/// legs, and the tail on the lower left.
///
/// Nine lines of geometry instead of a dependency that broke the build.
class GitHubMark extends StatelessWidget {
  final double size;
  final Color color;

  const GitHubMark({super.key, this.size = 24, this.color = AppColors.ink});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GitHubPainter(color)),
    );
  }
}

class _GitHubPainter extends CustomPainter {
  final Color color;
  _GitHubPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    var path = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(12 * s, 12 * s), radius: 10 * s));

    // The gap under the head.
    path = Path.combine(
      PathOperation.difference,
      path,
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(12 * s, 8.8 * s), width: 8.4 * s, height: 2.0 * s)),
    );
    // The notch between the legs.
    path = Path.combine(
      PathOperation.difference,
      path,
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(12.4 * s, 20.4 * s),
            width: 3.0 * s,
            height: 5.4 * s)),
    );
    // The tail on the lower left.
    path = Path.combine(
      PathOperation.difference,
      path,
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(4.4 * s, 15.4 * s), width: 4.2 * s, height: 4.6 * s)),
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GitHubPainter old) => old.color != color;
}

/// The soft overlapping wave that closes the splash and the end screen.
///
/// Drawn rather than shipped as an asset: it is two arcs, it scales to any
/// width, and it costs no download on a phone that may be on a 2G tether.
class SoftWave extends StatelessWidget {
  final Color color;
  final bool flipped;

  const SoftWave({
    super.key,
    this.color = AppColors.primary,
    this.flipped = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(color, flipped),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final bool flipped;
  _WavePainter(this.color, this.flipped);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Two overlapping arcs, the far one lighter — the same depth cue the
    // design uses behind the splash wordmark.
    canvas.drawArc(
      Rect.fromLTWH(-w * 0.1, flipped ? 0 : -h * 0.5, w * 1.2, h * 1.5),
      0,
      3.14159,
      true,
      paint,
    );
    final back = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.25, flipped ? -h * 0.2 : -h * 0.85, w * 1.2, h * 1.5),
      3.14159,
      3.14159,
      true,
      back,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.color != color || old.flipped != flipped;
}

/// A pill-shaped "or" separator, as drawn between the manual join form and the
/// QR scanner.
class OrDivider extends StatelessWidget {
  final String label;

  const OrDivider({super.key, this.label = 'or'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}