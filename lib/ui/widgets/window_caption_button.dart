import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WindowCaptionButton extends StatelessWidget {
  const WindowCaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
    this.isActive = false,
    this.iconSize = GlassConstants.iconSmall,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;
  final bool isActive;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: LayoutConstants.titleBarHeight,
        height: LayoutConstants.titleBarHeight,
        child: IconButton(
          tooltip: tooltip,
          iconSize: iconSize,
          onPressed: onPressed,
          style: AppButtonStyles.caption(context, close: isClose, active: isActive),
          icon: Icon(icon),
        ),
      );
}
