import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medha/features/chat/rich_reply.dart';

Future<void> render(WidgetTester tester, String text) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RichReply(text)))),
    );

void main() {
  testWidgets('renders bold text without the ** markers', (tester) async {
    await render(tester, 'The range is **maximum at 45°**.');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('maximum at 45°', findRichText: true), findsOneWidget);
  });

  testWidgets('renders inline and display maths without showing the delimiters', (tester) async {
    await render(tester, r'Use \(\sin 2\theta = 2\sin\theta\cos\theta\):' '\n\n' r'\[ R = \frac{u^2 \sin 2\theta}{g} \]');
    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\frac', findRichText: true), findsNothing);
    expect(find.textContaining(r'\[', findRichText: true), findsNothing);
  });

  testWidgets('a formula cut off mid-stream does not throw', (tester) async {
    await render(tester, r'Step 3: \[ R = \frac{u^2');
    expect(tester.takeException(), isNull);
  });
}
