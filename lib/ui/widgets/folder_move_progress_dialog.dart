import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/services/folder_move_progress.dart';
import '../theme/app_theme.dart';

class _MoveOutcome {
  FolderMoveResult? result;
  Object? error;
  StackTrace? stackTrace;
}

enum _MoveUiState { running, success, cancelled, failed }

Future<FolderMoveResult> runFolderMoveWithProgress({
  required BuildContext context,
  required String title,
  required Future<FolderMoveResult> Function(
    void Function(FolderMoveProgress progress) onProgress,
    bool Function() shouldCancel,
  ) task,
}) async {
  final outcome = _MoveOutcome();
  await showDialog<FolderMoveResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (dialogContext) => _FolderMoveProgressDialog(
      title: title,
      task: task,
      outcome: outcome,
    ),
  );
  if (outcome.error != null) {
    Error.throwWithStackTrace(
      outcome.error!,
      outcome.stackTrace ?? StackTrace.current,
    );
  }
  final result = outcome.result;
  if (result == null) throw const FolderMoveCancelledException();
  return result;
}

class _FolderMoveProgressDialog extends StatefulWidget {
  final String title;
  final Future<FolderMoveResult> Function(
    void Function(FolderMoveProgress progress) onProgress,
    bool Function() shouldCancel,
  ) task;
  final _MoveOutcome outcome;

  const _FolderMoveProgressDialog({
    required this.title,
    required this.task,
    required this.outcome,
  });

  @override
  State<_FolderMoveProgressDialog> createState() =>
      _FolderMoveProgressDialogState();
}

class _FolderMoveProgressDialogState extends State<_FolderMoveProgressDialog> {
  final ValueNotifier<FolderMoveProgress> _progress = ValueNotifier(
    const FolderMoveProgress(phase: FolderMovePhase.scanning),
  );

  bool _cancelled = false;
  bool _cancelling = false;
  _MoveUiState _state = _MoveUiState.running;
  FolderMoveResult? _result;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final result = await widget.task(
        (progress) {
          if (!mounted) return;
          _progress.value = progress;
        },
        () => _cancelled,
      );
      if (!mounted) return;
      widget.outcome.result = result;
      setState(() {
        _result = result;
        _state = _MoveUiState.success;
      });
    } on FolderMoveCancelledException catch (error, stackTrace) {
      if (!mounted) return;
      widget.outcome.error = error;
      widget.outcome.stackTrace = stackTrace;
      setState(() {
        _failure = error;
        _state = _MoveUiState.cancelled;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      widget.outcome.error = error;
      widget.outcome.stackTrace = stackTrace;
      setState(() {
        _failure = error;
        _state = _MoveUiState.failed;
      });
    }
  }

  void _requestCancel() {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _cancelled = true;
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop(widget.outcome.result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: PopScope(
        canPop: false,
        child: SizedBox(
          width: 440,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassConstants.blurLarge,
                sigmaY: GlassConstants.blurLarge,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color:
                      AppTheme.getSurfaceColor(context).withValues(alpha: 0.92),
                  borderRadius:
                      BorderRadius.circular(GlassConstants.radiusLarge),
                  border: Border.all(
                    color:
                        AppTheme.getBorderColor(context).withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.drive_file_move,
                          size: 22,
                          color: AppTheme.getPrimaryColor(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppTheme.getTextPrimary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_state == _MoveUiState.running)
                      _buildProgressBody(context)
                    else
                      _buildResultBody(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBody(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = AppTheme.getPrimaryColor(context);
    final secondary = AppTheme.getTextSecondary(context);

    return ValueListenableBuilder<FolderMoveProgress>(
      valueListenable: _progress,
      builder: (context, progress, _) {
        final hasTotal = progress.bytesTotal > 0 || progress.filesTotal > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _phaseLabel(progress.phase),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  hasTotal
                      ? '${(progress.fraction * 100).toStringAsFixed(1)}%'
                      : '扫描中…',
                  style: textTheme.bodySmall?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                backgroundColor: primary.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已传 ${_formatBytes(progress.bytesDone)} / '
                    '${_formatBytes(progress.bytesTotal)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '文件 ${progress.filesDone}/${progress.filesTotal}',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 18,
              child: Text(
                progress.currentFile ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: secondary.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _cancelling ? null : _requestCancel,
                child: Text(_cancelling ? '正在取消…' : '取消'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultBody(BuildContext context) {
    switch (_state) {
      case _MoveUiState.success:
        final result = _result!;
        return _statusView(
          context,
          icon: Icons.check_circle,
          iconColor: AppTheme.successColor,
          headline: '移动完成',
          details: [
            '共 ${result.fileCount} 个文件 · '
                '${_formatBytes(result.totalBytes)} · 校验通过',
            '耗时 ${result.elapsed.inSeconds} 秒',
          ],
          warning: result.warning,
          closeLabel: '完成',
        );
      case _MoveUiState.cancelled:
        final cancelError = _failure;
        final cancelCleanup = cancelError is FolderMoveCancelledException
            ? cancelError.cleanupWarning
            : null;
        return _statusView(
          context,
          icon: Icons.info_outline,
          iconColor: AppTheme.getPrimaryColor(context),
          headline: '已取消',
          details: [
            '源目录未改动',
            if (cancelCleanup == null) '已清理目标残留',
          ],
          warning: cancelCleanup,
          warningIsError: cancelCleanup != null,
        );
      case _MoveUiState.failed:
        final failure = _failure;
        if (failure is FolderMoveException) {
          if (failure.filesMoved) {
            return _statusView(
              context,
              icon: Icons.warning_amber_rounded,
              iconColor: AppTheme.warningColor,
              headline: '文件已移动，记录未更新',
              details: [
                failure.message,
                '源目录已搬到新位置，请到游戏详情页核对路径',
              ],
            );
          }
          return _statusView(
            context,
            icon: Icons.error_outline,
            iconColor: AppTheme.errorColor,
            headline: '移动失败',
            details: [
              failure.message,
              if (failure.relativePath != null) '文件：${failure.relativePath}',
              if (failure.bytesWritten != null && failure.expectedBytes != null)
                '已写入 ${_formatBytes(failure.bytesWritten!)} / '
                    '${_formatBytes(failure.expectedBytes!)}',
              '源目录未改动',
              if (failure.cleanupWarning == null) '已清理目标残留',
            ],
            warning: failure.cleanupWarning,
          );
        }
        return _statusView(
          context,
          icon: Icons.error_outline,
          iconColor: AppTheme.errorColor,
          headline: '移动失败',
          details: ['$failure'],
        );
      case _MoveUiState.running:
        return _buildProgressBody(context);
    }
  }

  Widget _statusView(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String headline,
    required List<String> details,
    String? warning,
    bool warningIsError = false,
    String closeLabel = '关闭',
  }) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = AppTheme.getTextSecondary(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                headline,
                style: textTheme.titleMedium?.copyWith(
                  color: AppTheme.getTextPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              detail,
              style: TextStyle(fontSize: 13, color: secondary, height: 1.4),
            ),
          ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: warningIsError
                      ? AppTheme.errorColor
                      : AppTheme.warningColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 12,
                      color: warningIsError
                          ? AppTheme.errorColor
                          : AppTheme.warningColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _close, child: Text(closeLabel)),
        ),
      ],
    );
  }
}

String _phaseLabel(FolderMovePhase phase) {
  switch (phase) {
    case FolderMovePhase.scanning:
      return '正在扫描文件…';
    case FolderMovePhase.copying:
      return '正在复制到目标位置';
    case FolderMovePhase.verifying:
      return '正在校验文件完整性';
    case FolderMovePhase.cleaning:
      return '正在清理源目录';
    case FolderMovePhase.done:
      return '完成';
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
