import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every static text key exists in English and Thai', () {
    final missing = <String>[];
    Strings.values.forEach((key, langs) {
      for (final code in ['en', 'th']) {
        if ((langs[code] ?? '').trim().isEmpty) missing.add('$key.$code');
      }
    });
    expect(missing, isEmpty);
  });

  test('section names exist for every section number', () {
    for (final n in Strings.sectionNumbers) {
      expect(Strings.values.containsKey('section_$n'), isTrue, reason: n);
    }
  });

  test('placeholders are replaced and the language persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = LanguageController();
    expect(c.t('report_count', {'n': 3}), '3 reports');
    await c.toggle();
    expect(c.code, 'th');
    expect(c.t('report_count', {'n': 3}), '3 รายงาน');
    final restored = LanguageController();
    await restored.load();
    expect(restored.code, 'th');
  });

  test('Brazilian Portuguese is selectable and persisted', () async {
    final c = LanguageController(initial: AppLanguage.en);
    await c.set(AppLanguage.pt);
    expect(c.code, 'pt-BR');
    expect(c.t('data_tier_real'), 'Dados reais');
    final restored = LanguageController();
    await restored.load();
    // The mock storage keeps the selected locale across controller instances.
    expect(restored.code, 'pt-BR');
  });
}
