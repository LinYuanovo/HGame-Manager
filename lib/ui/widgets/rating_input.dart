import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class RatingInput extends StatefulWidget {
  const RatingInput({super.key, required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<RatingInput> createState() => _RatingInputState();
}

class _RatingInputState extends State<RatingInput> {
  double? _preview;
  bool _focused = false;
  void _change(double value) {
    setState(() => _preview = null);
    widget.onChanged(value.clamp(0.0, 5.0));
  }

  @override
  Widget build(BuildContext context) {
    const starSize = GlassConstants.iconFeature;
    const starGap = GlassConstants.spacingTiny;
    const width = 5 * (starSize + starGap) - starGap;
    double fromPosition(Offset position) =>
        ((position.dx / width * 10).clamp(0, 10)).round() / 2;
    final displayed = _preview ?? widget.value;
    return Semantics(
      label: '评分',
      value: '${widget.value} / 5',
      increasedValue: '${(widget.value + .5).clamp(0, 5)} / 5',
      decreasedValue: '${(widget.value - .5).clamp(0, 5)} / 5',
      onIncrease: () => _change(widget.value + .5),
      onDecrease: () => _change(widget.value - .5),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent)
            return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp) {
            _change(widget.value + .5);
          } else if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowDown) {
            _change(widget.value - .5);
          } else if (key == LogicalKeyboardKey.home) {
            _change(0);
          } else if (key == LogicalKeyboardKey.end) {
            _change(5);
          } else {
            return KeyEventResult.ignored;
          }
          setState(() => _preview = null);
          return KeyEventResult.handled;
        },
        child: Builder(
            builder: (context) => MouseRegion(
                  onHover: (event) => setState(
                      () => _preview = fromPosition(event.localPosition)),
                  onExit: (_) => setState(() => _preview = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (event) {
                      Focus.of(context).requestFocus();
                      _change(fromPosition(event.localPosition));
                    },
                    onHorizontalDragUpdate: (event) =>
                        _change(fromPosition(event.localPosition)),
                    onHorizontalDragStart: (event) =>
                        _change(fromPosition(event.localPosition)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: _focused
                                      ? AppTheme.getPrimaryColor(context)
                                      : Colors.transparent))),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (index) {
                            final gap = index == 4 ? 0.0 : starGap;
                            return Padding(
                              padding: EdgeInsets.only(right: gap),
                              child: Icon(
                                  displayed >= index + 1
                                      ? Icons.star
                                      : displayed >= index + .5
                                          ? Icons.star_half
                                          : Icons.star_border,
                                  size: starSize,
                                  color: displayed > index
                                      ? AppTheme.getStarColor(context)
                                      : AppTheme.getTextSecondary(context)),
                            );
                          })),
                    ),
                  ),
                )),
      ),
    );
  }
}
