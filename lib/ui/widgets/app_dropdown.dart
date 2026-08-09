import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final bool isDense;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Widget? hint;
  final Widget? icon;
  final TextStyle? textStyle;
  final double? menuMaxHeight;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.isDense = false,
    this.width,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.hint,
    this.icon,
    this.textStyle,
    this.menuMaxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppTheme.getTextPrimary(context),
          fontSize: 14,
        );

    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(
          color: AppTheme.getBorderColor(context).withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: hint,
          isExpanded: isExpanded,
          isDense: isDense,
          icon: icon ??
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: AppTheme.getTextSecondary(context),
              ),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          dropdownColor: AppTheme.getSurfaceColor(context),
          style: textStyle ?? defaultTextStyle,
          menuMaxHeight: menuMaxHeight,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
