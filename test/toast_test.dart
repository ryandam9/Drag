import 'package:drag/state/toast.dart';
import 'package:drag/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToastKindStyle', () {
    test('icon per kind', () {
      expect(ToastKind.success.icon, '✅');
      expect(ToastKind.error.icon, '❌');
      expect(ToastKind.info.icon, 'ℹ️');
    });

    test('colour per kind', () {
      expect(ToastKind.success.color, FsColors.green);
      expect(ToastKind.error.color, FsColors.red);
      expect(ToastKind.info.color, FsColors.accent);
    });

    test('foreground per kind', () {
      expect(ToastKind.success.fg, FsColors.badgeDoneFg);
      expect(ToastKind.error.fg, FsColors.badgeErrorFg);
      expect(ToastKind.info.fg, FsColors.accentHi);
    });
  });

  test('ToastMessage carries its fields', () {
    final m = ToastMessage(7, 'T', 'S', ToastKind.info, detail: 'd');
    expect(m.id, 7);
    expect(m.title, 'T');
    expect(m.subtitle, 'S');
    expect(m.detail, 'd');
    expect(m.kind, ToastKind.info);
  });
}
