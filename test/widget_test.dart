import 'package:flutter_test/flutter_test.dart';
import 'package:mindful_chat/main.dart';

void main() {
  testWidgets('shows Mori welcome and suggested prompts', (tester) async {
    await tester.pumpWidget(const MindfulChatApp());

    expect(find.text('A little space\nto think clearly.'), findsOneWidget);
    expect(find.text('I have a lot on my mind'), findsOneWidget);
    expect(find.text('Share what’s on your mind…'), findsOneWidget);
  });
}
