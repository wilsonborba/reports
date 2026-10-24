import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/l10n/strings.dart';

/// Every interface text exists in en-US, pt-BR and Thai, and every key the code uses exists.
void main() {
  test('every key has English, Portuguese and Thai text', () {
    final missing = <String>[];
    Strings.values.forEach((key, v) {
      for (final lang in ['en', 'th']) {
        if ((v[lang] ?? '').trim().isEmpty) missing.add('$key:$lang');
      }
      if ((Strings.portuguese[key] ?? '').trim().isEmpty) missing.add('$key:pt-BR');
    });
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('every literal key used in lib/ is defined', () {
    final used = <String>{};
    final pattern = RegExp(r"""\.tr\(\s*'([a-z0-9_]+)'""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in pattern.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    final undefined = used.where((k) => !Strings.values.containsKey(k)).toList()..sort();
    expect(undefined, isEmpty, reason: undefined.join('\n'));
  });

  test('no text of the old work projects remains', () {
    final old = RegExp(r'smart ?city|hat ?yai|agritech|hydrology|data lake|datalake|flood|assam|jira|kan-\d', caseSensitive: false);
    final hits = <String>[];
    void check(String where, String text) {
      if (old.hasMatch(text)) hits.add('$where: $text');
    }
    Strings.values.forEach((k, v) => v.forEach((lang, text) => check('$k:$lang', text)));
    Strings.portuguese.forEach((k, text) => check('$k:pt-BR', text));
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
