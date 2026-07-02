import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';

/// Static "About" page: what Drag is, what it does, and how it's built.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  /// Keep in sync with the `version:` field in pubspec.yaml.
  static const _version = '1.0.0';
  static const _repoUrl = 'https://github.com/ryandam9/Drag';

  static const _features = <(IconData, String, String)>[
    (
      Icons.swap_horiz_rounded,
      'Three real endpoints',
      'Move files between your local disk, Amazon S3 and SFTP servers — in any '
          'combination, including streamed copies between two S3 accounts in '
          'different regions.',
    ),
    (
      Icons.folder_copy_outlined,
      'Dual-pane browser',
      'Tabbed sessions, drag-and-drop transfers, multi-select, full keyboard '
          'navigation, quick file preview, clickable breadcrumbs and a live '
          'in-pane filter.',
    ),
    (
      Icons.bolt_outlined,
      'Live transfer engine',
      'Streams real bytes with live speed/ETA, auto-retries transient failures '
          '(resuming from the partial file), and lets you pause, resume, cancel '
          'and cap the parallel thread count.',
    ),
    (
      Icons.compare_arrows_rounded,
      'Compare & mirror',
      'Compare the two panes folder-by-folder and mirror one side onto the '
          'other — recursively — with a preview of every file it will copy, '
          'create or delete first.',
    ),
    (
      Icons.insights_outlined,
      'Queue & history',
      'A live transfer queue with per-file progress, plus a persistent, '
          'searchable history dashboard with throughput stats and CSV export.',
    ),
    (
      Icons.shield_outlined,
      'Security by default',
      'S3 is signed by a hand-written AWS Signature V4 implementation; SFTP host '
          'keys are trust-on-first-use; secrets live in the OS keychain and are '
          'never written to disk.',
    ),
  ];

  static const _stack = <(String, String)>[
    ('Flutter', 'Cross-platform desktop UI — macOS, Linux & Windows.'),
    ('Riverpod', 'Idiomatic, testable state management end-to-end.'),
    ('SQLite', 'Persists connections, open sessions, settings & history.'),
    ('AWS SigV4', 'Hand-written signer + minimal S3 REST client — no AWS SDK.'),
    ('dartssh2', 'Real SFTP (password or private-key auth).'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SelectionArea makes every piece of text on this page selectable/copyable.
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hero(),
            const SizedBox(height: 24),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(Icons.info_outline, 'What is Drag?'),
                  const SizedBox(height: 10),
                  Text(
                    'Drag is a dark, dense, developer-focused file-transfer client. '
                    'Point either pane at your local disk, an Amazon S3 bucket or an '
                    'SFTP server, then drag files between them to start a transfer. '
                    'Everything is real — there is no dummy data, and your credentials '
                    'never leave your machine except to the endpoints you configure.',
                    style: FsType.sans(
                      size: 13,
                      color: FsColors.text2,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _heading(Icons.auto_awesome_outlined, 'What it does'),
            const SizedBox(height: 14),
            _featureMasonry(),
            const SizedBox(height: 24),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(Icons.handyman_outlined, 'Under the hood'),
                  const SizedBox(height: 12),
                  for (final (name, desc) in _stack) _stackRow(name, desc),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _footer(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Masonry grid of feature cards: two independent columns on a wide window
  /// (one on a narrow one), each stacking on its own so a tall card never
  /// leaves a gap beside a short one. Cards are dealt to the currently-shortest
  /// column, estimating height from the body length.
  Widget _featureMasonry() {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 2 : 1;
        const gap = 16.0;
        final colWidth = (c.maxWidth - gap * (cols - 1)) / cols;
        final columns = List.generate(cols, (_) => <Widget>[]);
        final loads = List<int>.filled(cols, 0);
        for (final (icon, title, body) in _features) {
          var t = 0;
          for (var k = 1; k < cols; k++) {
            if (loads[k] < loads[t]) t = k;
          }
          if (columns[t].isNotEmpty) {
            columns[t].add(const SizedBox(height: gap));
          }
          columns[t].add(_featureCard(icon, title, body));
          loads[t] += body.length + 60; // rough height proxy
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) const SizedBox(width: gap),
              SizedBox(
                width: colWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: columns[k],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Hero header ──────────────────────────────────────────────────────────
  Widget _hero() {
    return _card(
      padded: false,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FsColors.rCard),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              FsColors.accent.withValues(alpha: 0.16),
              FsColors.bgSurface,
            ],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/icons/drag_512.png',
                width: 76,
                height: 76,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Drag',
                        style: FsType.sans(
                          size: 30,
                          weight: FontWeight.w800,
                          color: FsColors.text1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _versionChip(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A cross-platform file-transfer client for Local, Amazon S3 & SFTP.',
                    style: FsType.sans(
                      size: 14,
                      color: FsColors.text2,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in const ['macOS', 'Linux', 'Windows'])
                        _platformChip(p),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _versionChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: FsColors.accent.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: FsColors.accent.withValues(alpha: 0.4)),
    ),
    child: Text(
      'v$_version',
      style: FsType.sans(
        size: 12,
        weight: FontWeight.w700,
        color: FsColors.accentHi,
      ),
    ),
  );

  Widget _platformChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: FsColors.bgScaffold,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: FsColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.desktop_windows_outlined, size: 13, color: FsColors.text3),
        const SizedBox(width: 6),
        Text(
          label,
          style: FsType.sans(
            size: 11,
            weight: FontWeight.w600,
            color: FsColors.text2,
          ),
        ),
      ],
    ),
  );

  // ── Feature card ─────────────────────────────────────────────────────────
  Widget _featureCard(IconData icon, String title, String body) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FsColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: FsColors.accentHi),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: FsType.sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: FsColors.text1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: FsType.sans(size: 12.5, color: FsColors.text2, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _stackRow(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              name,
              style: FsType.mono(
                size: 12,
                weight: FontWeight.w700,
                color: FsColors.accentHi,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              desc,
              style: FsType.sans(
                size: 12.5,
                color: FsColors.text2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────
  Widget _footer() {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.code_rounded, size: 18, color: FsColors.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open source',
                  style: FsType.sans(
                    size: 13,
                    weight: FontWeight.w700,
                    color: FsColors.text1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _repoUrl,
                  style: FsType.mono(size: 12, color: FsColors.accentHi),
                ),
              ],
            ),
          ),
          Text(
            'Built with Flutter',
            style: FsType.sans(size: 11, color: FsColors.text3),
          ),
        ],
      ),
    );
  }

  // ── Shared bits ──────────────────────────────────────────────────────────
  Widget _heading(IconData icon, String title) => Row(
    children: [
      Icon(icon, size: 18, color: FsColors.accentHi),
      const SizedBox(width: 8),
      Text(
        title,
        style: FsType.sans(
          size: 16,
          weight: FontWeight.w700,
          color: FsColors.text1,
        ),
      ),
    ],
  );

  Widget _card({required Widget child, bool padded = true}) {
    return Container(
      width: double.infinity,
      padding: padded ? const EdgeInsets.all(18) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
        boxShadow: FsColors.cardShadow,
      ),
      child: child,
    );
  }
}
