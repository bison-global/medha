import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renders a model reply: Markdown (bold, lists, headings, code, tables) and
/// LaTeX maths in `\( … \)`, `\[ … \]`, `$ … $` and `$$ … $$`.
///
/// While a reply streams, an unfinished formula shows as plain text until its
/// closing delimiter arrives.
class RichReply extends StatelessWidget {
  const RichReply(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => SelectionArea(
        child: DefaultTextStyle.merge(
          style: style ?? const TextStyle(fontSize: 15, height: 1.5),
          child: GptMarkdown(text, useDollarSignsForLatex: true),
        ),
      );
}
