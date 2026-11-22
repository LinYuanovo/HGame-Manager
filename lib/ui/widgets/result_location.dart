import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';

class ResultLocation extends StatefulWidget {
  const ResultLocation({super.key, required this.child, this.reveal = true});
  final Widget child;
  final bool reveal;

  @override
  State<ResultLocation> createState() => _ResultLocationState();
}

class _ResultLocationState extends State<ResultLocation> {
  @override
  void initState() {
    super.initState();
    if (widget.reveal)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          Scrollable.ensureVisible(context,
              alignment: .45,
              duration: AppMotion.duration(context, AppMotion.medium),
              curve: AppMotion.curve);
      });
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: AppMotion.reduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 1250),
        curve: const Interval(.7, 1),
        builder: (context, value, child) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withValues(
                  alpha: .16 * (AppMotion.reduced(context) ? 1 : value)),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
          child: child,
        ),
        child: widget.child,
      );
}

Future<void> seekListIndex(ScrollController controller, int index,
    {int stride = 1, bool Function()? isCurrent}) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (isCurrent != null && !isCurrent()) return;
    if (!controller.hasClients || controller.positions.length != 1) return;
    final position = controller.position;
    RenderSliverMultiBoxAdaptor? sliver;
    void visit(RenderObject child) {
      if (child is RenderSliverMultiBoxAdaptor) {
        sliver ??= child;
      } else if (sliver == null) {
        child.visitChildren(visit);
      }
    }

    position.context.notificationContext
        ?.findRenderObject()
        ?.visitChildren(visit);
    final list = sliver;
    if (list == null || list.firstChild == null || list.lastChild == null)
      return;
    final first = list.firstChild!;
    final last = list.lastChild!;
    final target = index * stride;
    if (target >= list.indexOf(first) && target <= list.indexOf(last)) {
      var row = first;
      while (list.indexOf(row) < target) {
        row = list.childAfter(row)!;
      }
      final offset =
          RenderAbstractViewport.of(row).getOffsetToReveal(row, .45).offset;
      final context = position.context.notificationContext;
      if (context != null && context.mounted)
        AppMotion.scrollTo(context, controller,
            offset.clamp(position.minScrollExtent, position.maxScrollExtent));
      return;
    }
    final double offset;
    if (list is RenderSliverGrid) {
      offset = list.gridDelegate
          .getLayout(list.constraints)
          .getGeometryForChildIndex(target)
          .scrollOffset;
    } else {
      final count = list.indexOf(last) - list.indexOf(first) + 1;
      final average = (list.childScrollOffset(last)! +
              last.size.height -
              list.childScrollOffset(first)!) /
          count;
      offset = list.childScrollOffset(first)! +
          average * (target - list.indexOf(first));
    }
    controller.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent));
    WidgetsBinding.instance.ensureVisualUpdate();
    await WidgetsBinding.instance.endOfFrame;
  }
}
