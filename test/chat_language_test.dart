import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/chat_language.dart';
import 'package:testapp/backend/services/financial_ai_service.dart';

void main() {
  group('detectChatLanguage', () {
    test('detects English-only financial questions', () {
      expect(
        detectChatLanguage('How much should I save for my house?'),
        ChatLanguage.english,
      );
      expect(
        detectChatLanguage('Can you explain my monthly budget?'),
        ChatLanguage.english,
      );
    });

    test('detects Tagalog-only financial questions', () {
      expect(
        detectChatLanguage('Magkano ang dapat kong itabi para sa bahay?'),
        ChatLanguage.tagalog,
      );
      expect(
        detectChatLanguage('Ano ang gastos ko sa pagkain ngayong buwan?'),
        ChatLanguage.tagalog,
      );
    });

    test('detects messages that mix Tagalog and English as Taglish', () {
      expect(
        detectChatLanguage('Magkano nagastos ko sa food this month?'),
        ChatLanguage.taglish,
      );
      expect(
        detectChatLanguage(
          'Gusto kong bumili ng bahay worth 5000000 in the next 2 years',
        ),
        ChatLanguage.taglish,
      );
      expect(
        detectChatLanguage('Can I save kahit maliit lang?'),
        ChatLanguage.taglish,
      );
      expect(
        detectChatLanguage('May bills ba ako this week?'),
        ChatLanguage.taglish,
      );
      expect(
        detectChatLanguage(
          'kaya mo ba akong bigyan ng maayos na insights sa susunod',
        ),
        ChatLanguage.taglish,
      );
    });

    test('returns null for a short message without language signals', () {
      expect(detectChatLanguage('Okay?'), isNull);
    });
  });

  group('chatResponseLanguage', () {
    test('the current question overrides the language of earlier turns', () {
      expect(
        chatResponseLanguage(
          'How much should I save?',
          history: const [
            FinancialChatTurn(
              isUser: true,
              text: 'Magkano ang dapat kong itabi?',
            ),
          ],
        ),
        ChatLanguage.english,
      );
      expect(
        chatResponseLanguage(
          'Can I save kahit maliit lang?',
          history: const [
            FinancialChatTurn(
              isUser: true,
              text: 'Magkano ang dapat kong itabi?',
            ),
          ],
        ),
        ChatLanguage.taglish,
      );
      expect(
        chatResponseLanguage(
          'Magkano ang dapat kong itabi?',
          history: const [
            FinancialChatTurn(isUser: true, text: 'How much should I save?'),
          ],
        ),
        ChatLanguage.tagalog,
      );
    });

    test(
      'a short follow-up inherits the latest recognizable user language',
      () {
        expect(
          chatResponseLanguage(
            'Why?',
            history: const [
              FinancialChatTurn(isUser: true, text: 'How much should I save?'),
              FinancialChatTurn(
                isUser: false,
                text: 'Set a realistic savings target.',
              ),
            ],
          ),
          ChatLanguage.english,
        );
        expect(
          chatResponseLanguage(
            'Bakit?',
            history: const [
              FinancialChatTurn(
                isUser: true,
                text: 'Gaano kalaki ang dapat kong ipunin?',
              ),
            ],
          ),
          ChatLanguage.tagalog,
        );
      },
    );

    test('a recognizable language switch applies to the latest message', () {
      expect(
        chatResponseLanguage(
          'Magkano ang gastos ko ngayong buwan?',
          history: const [
            FinancialChatTurn(
              isUser: true,
              text: 'How much did I spend this month?',
            ),
          ],
        ),
        ChatLanguage.tagalog,
      );
      expect(
        chatResponseLanguage(
          'How much did I spend this month?',
          history: const [
            FinancialChatTurn(
              isUser: true,
              text: 'Magkano ang gastos ko ngayong buwan?',
            ),
          ],
        ),
        ChatLanguage.english,
      );
    });

    test('defaults to English when there is no recognizable user language', () {
      expect(
        chatResponseLanguage('Okay?', history: const []),
        ChatLanguage.english,
      );
    });
  });
}
