import 'package:flutter/material.dart';

import '../state/connection_log_provider.dart';
import '../state/toast.dart';
import '../theme.dart';

/// Renders the shared connection/activity log: one timestamped monospace line
/// per entry, newest first, with a subtle placeholder while the log is empty.
/// Used by the Connection Manager's log card and the Browser's log strip.
class LogLinesView extends StatelessWidget {
  final List<ConnLogLine> lines;
  final String emptyText;
  const LogLinesView({super.key, required this.lines, required this.emptyText});

  static String _two(int n) => n < 10 ? '0$n' : '$n';
  static String _stamp(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static Color _color(ToastKind kind) => switch (kind) {
    ToastKind.success => FsColors.green,
    ToastKind.error => FsColors.red,
    ToastKind.info => FsColors.text2,
  };

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: FsType.sans(size: 11, color: FsColors.text3),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final line = lines[lines.length - 1 - i]; // newest first
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stamp(line.time),
                style: FsType.mono(size: 11, color: FsColors.text3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line.message,
                  style: FsType.mono(
                    size: 11,
                    color: _color(line.kind),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
