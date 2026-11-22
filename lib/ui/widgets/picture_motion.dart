import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import '../theme/app_theme.dart';

class PictureOrigins {
  final _sources = <_PictureOriginState>{};
  OverlayEntry? _flight;
  _PictureOriginState? _covered;
  int _generation = 0;

  Object? visible(Object identity, {Object? preferred}) {
    Object? fallback;
    for (final source in _sources) {
      if (source.widget.identity == identity && source.visibleRect != null) {
        if (identical(source, preferred)) return source;
        fallback ??= source;
      }
    }
    return fallback;
  }

  void cancelFlight({bool restore = true}) {
    _generation++;
    _flight?.remove();
    _flight?.dispose();
    _flight = null;
    if (restore) _covered?.hide(false);
    _covered = null;
  }

  void moveAcrossLayout(BuildContext context, Object identity, Widget image) {
    cancelFlight();
    if (AppMotion.reduced(context)) return;
    final first = (visible(identity) as _PictureOriginState?)?.visibleRect;
    if (first == null) return;
    final revision = _generation;
    final overlay = Overlay.of(context, rootOverlay: true);
    final viewport = MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted ||
          revision != _generation ||
          AppMotion.reduced(context)) return;
      final target = visible(identity) as _PictureOriginState?;
      final last = target?.visibleRect;
      if (target == null || last == null || last == first) return;
      final origin = (overlay.context.findRenderObject()! as RenderBox)
          .localToGlobal(Offset.zero);
      final tween =
          RectTween(begin: first.shift(-origin), end: last.shift(-origin));
      _covered = target..hide(true);
      _flight = OverlayEntry(builder: (context) {
        if (MediaQuery.sizeOf(context) != viewport ||
            AppMotion.reduced(context)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_generation == revision) cancelFlight();
          });
          return const SizedBox.shrink();
        }
        return Positioned.fill(
            child: IgnorePointer(
                child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.duration(context, AppMotion.medium),
            curve: AppMotion.curve,
            child: image,
            builder: (context, value, child) => Stack(children: [
              Positioned.fromRect(rect: tween.transform(value)!, child: child!)
            ]),
            onEnd: () => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_generation == revision) cancelFlight();
            }),
          ),
        )));
      });
      overlay.insert(_flight!);
    });
  }
}

class PictureOrigin extends StatefulWidget {
  const PictureOrigin(
      {super.key,
      required this.origins,
      required this.identity,
      required this.child,
      this.borderRadius = BorderRadius.zero,
      this.onOpen});
  final PictureOrigins origins;
  final Object identity;
  final Widget child;
  final BorderRadius borderRadius;
  final ValueChanged<Object>? onOpen;

  @override
  State<PictureOrigin> createState() => _PictureOriginState();
}

class _PictureOriginState extends State<PictureOrigin> {
  bool _hidden = false;
  void hide(bool hidden) {
    if (mounted && hidden != _hidden) setState(() => _hidden = hidden);
  }

  @override
  void initState() {
    super.initState();
    widget.origins._sources.add(this);
  }

  @override
  void didUpdateWidget(PictureOrigin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origins != widget.origins) {
      oldWidget.origins._sources.remove(this);
      widget.origins._sources.add(this);
    }
  }

  Rect? get visibleRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty)
      return null;
    var rect = MatrixUtils.transformRect(
        box.getTransformTo(null), Offset.zero & box.size);
    RenderObject node = box;
    while (node.parent != null) {
      final parent = node.parent!;
      if (parent is RenderOffstage && parent.offstage) return null;
      final clip = parent.describeApproximatePaintClip(node);
      if (clip != null)
        rect = rect.intersect(
            MatrixUtils.transformRect(parent.getTransformTo(null), clip));
      node = parent;
    }
    return rect.isEmpty || !rect.isFinite ? null : rect;
  }

  @override
  void dispose() {
    widget.origins._sources.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = pictureHero(
        context,
        this,
        _hidden ? Opacity(opacity: 0, child: widget.child) : widget.child,
        borderRadius: widget.borderRadius);
    return widget.onOpen == null
        ? child
        : InkWell(onTap: () => widget.onOpen!(this), child: child);
  }
}

Widget pictureHero(BuildContext context, Object? tag, Widget child,
        {BorderRadius borderRadius = BorderRadius.zero}) =>
    tag == null || AppMotion.reduced(context)
        ? child
        : Hero(
            tag: tag,
            createRectTween: (begin, end) => RectTween(begin: begin, end: end),
            flightShuttleBuilder: _pictureFlight,
            child: _PictureHeroChild(borderRadius: borderRadius, child: child));

Widget _pictureFlight(BuildContext context, Animation<double> animation,
    HeroFlightDirection direction, BuildContext from, BuildContext to) {
  RenderImage? findImage(BuildContext context) {
    RenderImage? result;
    void visit(RenderObject object) {
      if (object is RenderImage && object.image != null) {
        result ??= object;
      }
      if (result == null) object.visitChildren(visit);
    }

    final render = context.findRenderObject();
    if (render != null) visit(render);
    return result;
  }

  final source = findImage(from);
  final target = findImage(to);
  final image = target?.image ?? source?.image;
  if (source == null || target == null || image == null)
    return (to.widget as Hero).child;
  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  (Rect, Rect) geometry(RenderImage render) {
    final fit =
        applyBoxFit(render.fit ?? BoxFit.scaleDown, imageSize, render.size);
    final source =
        Alignment.center.inscribe(fit.source, Offset.zero & imageSize);
    final destination =
        Alignment.center.inscribe(fit.destination, Offset.zero & render.size);
    return (
      source,
      Rect.fromLTRB(
          destination.left / render.size.width,
          destination.top / render.size.height,
          destination.right / render.size.width,
          destination.bottom / render.size.height)
    );
  }

  final start = geometry(source);
  final end = geometry(target);
  return _PictureFlight(
      image: image.clone(),
      animation: animation,
      direction: direction,
      start: start,
      end: end,
      startRadius: _pictureHeroRadius(from),
      endRadius: _pictureHeroRadius(to));
}

BorderRadius _pictureHeroRadius(BuildContext context) {
  final child = (context.widget as Hero).child;
  return child is _PictureHeroChild ? child.borderRadius : BorderRadius.zero;
}

class _PictureHeroChild extends StatelessWidget {
  const _PictureHeroChild({required this.borderRadius, required this.child});
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipRRect(borderRadius: borderRadius, child: child);
}

class _PictureFlight extends StatefulWidget {
  const _PictureFlight(
      {required this.image,
      required this.animation,
      required this.direction,
      required this.start,
      required this.end,
      required this.startRadius,
      required this.endRadius});
  final ui.Image image;
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final (Rect, Rect) start, end;
  final BorderRadius startRadius, endRadius;
  @override
  State<_PictureFlight> createState() => _PictureFlightState();
}

class _PictureFlightState extends State<_PictureFlight> {
  @override
  void didUpdateWidget(_PictureFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) oldWidget.image.dispose();
  }

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final progress = widget.direction == HeroFlightDirection.push
            ? widget.animation.value
            : 1 - widget.animation.value;
        return CustomPaint(
            painter: _PictureFlightPainter(
                widget.image,
                Rect.lerp(widget.start.$1, widget.end.$1, progress)!,
                Rect.lerp(widget.start.$2, widget.end.$2, progress)!,
                BorderRadius.lerp(widget.startRadius, widget.endRadius,
                    progress)!));
      });
}

class _PictureFlightPainter extends CustomPainter {
  _PictureFlightPainter(this.image, this.source, this.destination,
      this.borderRadius);
  final ui.Image image;
  final Rect source, destination;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
        destination.left * size.width,
        destination.top * size.height,
        destination.right * size.width,
        destination.bottom * size.height);
    canvas
      ..save()
      ..clipRRect(borderRadius.toRRect(rect))
      ..drawImageRect(
          image, source, rect, Paint()..filterQuality = FilterQuality.low)
      ..restore();
  }

  @override
  bool shouldRepaint(_PictureFlightPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.destination != destination ||
      oldDelegate.borderRadius != borderRadius;
}

class _PictureRoute<T> extends PageRouteBuilder<T> {
  _PictureRoute(
      {required super.pageBuilder,
      required super.transitionsBuilder,
      required super.transitionDuration,
      required super.reverseTransitionDuration,
      required super.barrierColor,
      required super.barrierLabel})
      : super(
            opaque: false, allowSnapshotting: false, barrierDismissible: true);
  @override
  TraversalEdgeBehavior get traversalEdgeBehavior =>
      TraversalEdgeBehavior.closedLoop;
  bool _finishScheduled = false;
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (AppMotion.reduced(context) &&
        controller?.isAnimating == true &&
        !_finishScheduled) {
      _finishScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _finishScheduled = false;
        final current = controller;
        if (navigator != null && current != null && current.isAnimating) {
          current.value = current.status == AnimationStatus.reverse ? 0 : 1;
        }
      });
    }
    return super
        .buildTransitions(context, animation, secondaryAnimation, child);
  }
}

Future<T?> showPictureDialog<T>(
    BuildContext context, WidgetBuilder builder) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final route = _PictureRoute<T>(
    barrierColor: AppTheme.getOverlayColor(context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration:
        AppMotion.frameAlignedDuration(context, AppMotion.slow),
    reverseTransitionDuration:
        AppMotion.frameAlignedDuration(context, AppMotion.medium),
    pageBuilder: (context, _, __) => themes.wrap(SafeArea(
        child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).maybePop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: builder)))),
    transitionsBuilder: (context, animation, _, child) => AppDialogTransition(
      animation: animation,
      initialScale: 0.96,
      child: RepaintBoundary(child: child),
    ),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}
