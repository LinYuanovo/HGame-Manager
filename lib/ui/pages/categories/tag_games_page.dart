import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';

const double _sidebarHalfWidth = LayoutConstants.sidebarWidth / 2;

class TagRouteTitle extends StatelessWidget {
  const TagRouteTitle({super.key, required this.anchor, required this.name, required this.style});

  final Object? anchor;
  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final title = Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (anchor == null || AppMotion.reduced(context)) return title;
    return Hero(
      tag: anchor!,
      flightShuttleBuilder: _tagTitleFlight,
      child: DefaultTextStyle(
          style: DefaultTextStyle.of(context).style, child: title),
    );
  }
}

Widget _tagTitleFlight(BuildContext context, Animation<double> animation,
    HeroFlightDirection direction, BuildContext from, BuildContext to) {
  final fromWrapper = (from.widget as Hero).child;
  final toWrapper = (to.widget as Hero).child;
  if (fromWrapper is! DefaultTextStyle ||
      fromWrapper.child is! Text ||
      toWrapper is! DefaultTextStyle ||
      toWrapper.child is! Text) {
    return toWrapper;
  }
  final fromText = fromWrapper.child as Text;
  final toText = toWrapper.child as Text;
  final fromStyle = fromText.style ?? fromWrapper.style;
  final toStyle = toText.style ?? toWrapper.style;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = direction == HeroFlightDirection.push
          ? animation.value
          : 1 - animation.value;
      return Text(
        toText.data ?? fromText.data ?? '',
        style: TextStyle.lerp(fromStyle, toStyle, progress),
        textAlign: toText.textAlign,
        softWrap: toText.softWrap,
        overflow: toText.overflow,
        maxLines: toText.maxLines,
        textWidthBasis: toText.textWidthBasis,
        textHeightBehavior: toText.textHeightBehavior,
        textScaler: toText.textScaler,
        locale: toText.locale,
        semanticsLabel: toText.semanticsLabel,
        strutStyle: toText.strutStyle,
      );
    },
  );
}

class TagGamesPage extends ConsumerStatefulWidget {
  final int tagId;
  final String tagName;
  final Object? titleAnchor;

  const TagGamesPage({super.key, required this.tagId, required this.tagName, this.titleAnchor});

  static Route<void> route({
    required BuildContext context,
    required int tagId,
    required String tagName,
    Object? titleAnchor,
  }) {
    return _TagGamesRoute(
      pageBuilder: (context, _, __) => TagGamesPage(
        tagId: tagId,
        tagName: tagName,
        titleAnchor: titleAnchor,
      ),
      transitionDuration: AppMotion.duration(context, AppMotion.medium),
      reverseTransitionDuration: AppMotion.duration(context, AppMotion.fast),
    );
  }

  @override
  ConsumerState<TagGamesPage> createState() => _TagGamesPageState();
}

class _TagGamesPageState extends ConsumerState<TagGamesPage> {
  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(gamesByTagProvider(widget.tagId));

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissPageIntent(),
      },
      child: Actions(
        actions: {
          _DismissPageIntent: CallbackAction<_DismissPageIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                GlassAppBar(
                  title: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            size: GlassConstants.iconControl, color: AppTheme.getTextSecondary(context)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: GlassConstants.spacingSmall),
                      Flexible(child: TagRouteTitle(name: widget.tagName, anchor: widget.titleAnchor,
                          style: TextStyle(
                              fontSize: GlassConstants.fontSection,
                              fontWeight: AppTypography.semibold,
                              color: AppTheme.getTextPrimary(context)))),
                    ],
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _sidebarHalfWidth),
                      child: gamesAsync.when(
                      data: (games) {
                        if (games.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.label_off_outlined,
                                    size: GlassConstants.iconEmptyState,
                                    color: AppTheme.getTextSecondary(context).withValues(alpha: 0.3)),
                                const SizedBox(height: GlassConstants.spacingMedium),
                                Text('该标签下暂无游戏',
                                    style: TextStyle(
                                        color:
                                            AppTheme.getTextSecondary(context).withValues(alpha: 0.6),
                                        fontSize: GlassConstants.fontTitle)),
                              ],
                            ),
                          );
                        }
                        return GameListWidget(
                          games: games,
                          showPlayTimeSort: true,
                          onTagTap: (tag) {
                            Navigator.of(context).pushReplacement(
                              TagGamesPage.route(
                                  context: context,
                                  tagId: tag.id!,
                                  tagName: tag.name),
                            );
                          },
                        );
                      },
                      loading: () => const GameListSkeleton(),
                      error: (error, _) => AppLoadError(message: '加载失败：$error', onRetry: () => ref.invalidate(gamesByTagProvider(widget.tagId))),
                    ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissPageIntent extends Intent {
  const _DismissPageIntent();
}

class _TagGamesRoute extends PageRouteBuilder<void> {
  _TagGamesRoute({
    required super.pageBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  });

  Animation<double>? _animationParent;
  CurvedAnimation? _curve;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (AppMotion.reduced(context)) return child;
    if (!identical(animation, _animationParent)) {
      _curve?.dispose();
      _animationParent = animation;
      _curve = CurvedAnimation(
        parent: animation,
        curve: AppMotion.curve,
        reverseCurve: Curves.easeInCubic,
      );
    }
    final opacity = animation.drive(CurveTween(curve: AppMotion.curve));
    final position = Tween<Offset>(
      begin: const Offset(0.025, 0),
      end: Offset.zero,
    ).animate(_curve!);
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: position, child: child),
    );
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }
}
