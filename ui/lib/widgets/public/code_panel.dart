import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../themes/report_palette.dart';
import 'public_motion.dart';

/// Languages that the code panel colors.
enum CodeLanguage { json, yaml, python, shell }

/// Syntax colors from the palette. Text never uses a chart series color: the state colors
/// are mixed with the text color, so every token keeps its contrast on the panel.
class CodeColors {
  final Color plain;
  final Color keyword;
  final Color string;
  final Color number;
  final Color key;
  final Color comment;

  const CodeColors({required this.plain, required this.keyword, required this.string, required this.number, required this.key, required this.comment});

  factory CodeColors.of(ReportPalette p) {
    Color mix(Color c) => Color.lerp(c, p.textPrimary, 0.3)!;
    return CodeColors(
      plain: p.textPrimary,
      keyword: mix(p.info),
      string: mix(p.positive),
      number: mix(p.caution),
      key: mix(p.negative),
      comment: p.textMuted,
    );
  }
}

/// One colored piece of code.
class CodeToken {
  final String text;
  final String kind;

  const CodeToken(this.text, this.kind);
}

/// Small tokenizer for the panels of the public site (not a full parser).
class CodeHighlighter {
  static const _python = {
    'import', 'from', 'as', 'def', 'return', 'for', 'in', 'if', 'else', 'elif', 'with', 'class', 'while', 'not',
    'and', 'or', 'None', 'True', 'False', 'lambda', 'yield', 'try', 'except', 'raise', 'pass', 'break',
  };

  static final _word = RegExp(r'\w+');

  static List<CodeToken> tokens(String code, CodeLanguage language) {
    final out = <CodeToken>[];
    // Patterns in priority order: the first one that matches at the position wins.
    final patterns = <(RegExp, String)>[
      if (language != CodeLanguage.json) (RegExp(r'#[^\n]*'), 'comment'),
      if (language == CodeLanguage.json) (RegExp(r'"(?:[^"\\]|\\.)*"(?=\s*:)'), 'key'),
      if (language == CodeLanguage.yaml) (RegExp(r'(?<=^[ \t]*(?:- )?)[A-Za-z_][\w.-]*(?=:)', multiLine: true), 'key'),
      if (language == CodeLanguage.shell) (RegExp(r'(?<=^[ \t]*)[a-z]+\b', multiLine: true), 'keyword'),
      if (language == CodeLanguage.shell) (RegExp(r'(?<=\s)-{1,2}[A-Za-z][\w-]*'), 'keyword'),
      (RegExp(r'"(?:[^"\\\n]|\\.)*"'), 'string'),
      (RegExp(r"""'(?:[^'\\\n]|\\.)*'"""), 'string'),
      (RegExp(r'(?<![\w.])-?\d+(?:\.\d+)?(?:e-?\d+)?\b'), 'number'),
      if (language == CodeLanguage.json || language == CodeLanguage.yaml) (RegExp(r'\b(?:true|false|null)\b'), 'keyword'),
    ];
    var i = 0;
    while (i < code.length) {
      CodeToken? token;
      for (final (re, kind) in patterns) {
        final m = re.matchAsPrefix(code, i);
        if (m != null && m.end > m.start) {
          token = CodeToken(m[0]!, kind);
          break;
        }
      }
      if (token == null) {
        final word = _word.matchAsPrefix(code, i);
        if (word != null) {
          final text = word[0]!;
          final keyword = language == CodeLanguage.python && _python.contains(text);
          token = CodeToken(text, keyword ? 'keyword' : 'plain');
        } else {
          token = CodeToken(code[i], 'plain');
        }
      }
      out.add(token);
      i += token.text.length;
    }
    return out;
  }
}

/// Code panel: a header with the file name and the language, line numbers, and code
/// colored from the palette. The code types in once when the panel comes into view;
/// phones and reduced motion show the whole code at once.
class CodePanel extends StatelessWidget {
  final String title;
  final String code;
  final CodeLanguage language;

  /// Milliseconds per character of the typing run (the run is at most 4 s).
  final double msPerChar;

  /// Wait before the typing starts (a response panel waits for its request panel).
  final Duration delay;

  const CodePanel({super.key, required this.title, required this.code, required this.language, this.msPerChar = 9, this.delay = Duration.zero});

  static String languageName(CodeLanguage l) => switch (l) {
        CodeLanguage.json => 'JSON',
        CodeLanguage.yaml => 'YAML',
        CodeLanguage.python => 'Python',
        CodeLanguage.shell => 'Shell',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = CodeColors.of(p);
    final tokens = CodeHighlighter.tokens(code, language);
    final lines = '\n'.allMatches(code).length + 1;
    const mono = TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 13, height: 1.6);
    final duration = Duration(milliseconds: math.min(4000, (code.length * msPerChar).round()).clamp(200, 4000));
    return Container(
      key: Key('code_panel_${languageName(language).toLowerCase()}'),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: p.surfaceAlt, border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 12, color: p.textMuted)),
            ),
            Text(languageName(language), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textMuted)),
          ]),
        ),
        PlayWhenVisible(
          duration: duration,
          delay: delay,
          curve: Curves.linear,
          staticOnPhone: true,
          builder: (context, t) {
            final shown = (code.length * t).round();
            var used = 0;
            final spans = <InlineSpan>[];
            for (final tok in tokens) {
              final color = switch (tok.kind) {
                'keyword' => colors.keyword,
                'string' => colors.string,
                'number' => colors.number,
                'key' => colors.key,
                'comment' => colors.comment,
                _ => colors.plain,
              };
              final visible = (shown - used).clamp(0, tok.text.length);
              // The part that is not typed yet keeps its place, so the panel does not jump.
              if (visible > 0) {
                spans.add(TextSpan(
                    text: tok.text.substring(0, visible),
                    style: TextStyle(color: color, fontStyle: tok.kind == 'comment' ? FontStyle.italic : null)));
              }
              if (visible < tok.text.length) {
                if (shown >= used && shown < used + tok.text.length) {
                  spans.add(WidgetSpan(child: Container(width: 8, height: 15, color: t < 1 ? p.textPrimary : Colors.transparent)));
                }
                spans.add(TextSpan(text: tok.text.substring(visible), style: const TextStyle(color: Colors.transparent)));
              }
              used += tok.text.length;
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
                    textAlign: TextAlign.right,
                    style: mono.copyWith(color: p.textMuted.withValues(alpha: 0.7)),
                  ),
                ),
                const SizedBox(width: 16),
                Text.rich(TextSpan(style: mono.copyWith(color: colors.plain), children: spans), key: const Key('code_text')),
              ]),
            );
          },
        ),
      ]),
    );
  }
}
