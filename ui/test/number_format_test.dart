import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/widgets/charts/format.dart';

void main() {
  tearDown(() => numberLanguage = 'en');

  test('English and Thai write 1,234.5; pt-BR writes 1.234,5', () {
    for (final (lang, int, dec, compact) in [
      ('en', '519,209', '12.35', '1.2k'),
      ('th', '519,209', '12.35', '1.2k'),
      ('pt-BR', '519.209', '12,35', '1,2k'),
    ]) {
      numberLanguage = lang;
      expect(numberText(519209, 0), int, reason: lang);
      expect(numberText(12.345, 2), dec, reason: lang);
      expect(compactNumber(1200), compact, reason: lang);
    }
  });

  test('the language controller sets the separators of the screen', () async {
    final c = LanguageController();
    await c.set(AppLanguage.pt);
    expect(numberText(1234, 0), '1.234');
    await c.set(AppLanguage.th);
    expect(numberText(1234, 0), '1,234');
  });

  test('an export uses its own language, also after an await, and the screen keeps its language', () async {
    numberLanguage = 'en';
    final text = await withNumberLanguage('pt-BR', () async {
      await Future<void>.delayed(Duration.zero);
      return numberText(4599892, 0);
    });
    expect(text, '4.599.892');
    expect(numberText(4599892, 0), '4,599,892');
  });

  test('pt-BR writes dates as DD/MM/AAAA; English and Thai keep the ISO date', () {
    const day = FieldInfo(name: 'day', label: 'Day', type: 'date', role: 'dimension');
    for (final (lang, full, short) in [
      ('en', '2026-10-25', '10-25'),
      ('th', '2026-10-25', '10-25'),
      ('pt-BR', '25/10/2026', '25/10'),
    ]) {
      numberLanguage = lang;
      expect(valueText('2026-10-25', day), full, reason: lang);
      expect(shortDateText('2026-10-25'), short, reason: lang);
    }
    numberLanguage = 'pt-BR';
    expect(dateText('2026-10'), '2026-10', reason: 'a month bucket is not a full date');
    expect(valueText('2026-10-25', const FieldInfo(name: 'code', label: 'Code', type: 'string', role: 'dimension')), '2026-10-25',
        reason: 'only date fields change');
  });

  test('an export in pt-BR writes its dates in pt-BR', () {
    numberLanguage = 'en';
    final text = withNumberLanguage('pt-BR', () => dateText('2026-10-25'));
    expect(text, '25/10/2026');
    expect(dateText('2026-10-25'), '2026-10-25');
  });
}
