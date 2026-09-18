import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;

import 'package:testapp/main.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/add_expense_screen.dart';
import 'package:testapp/screens/ocr_screen.dart';
import 'package:testapp/screens/voice_recognition_screen.dart';
import 'package:testapp/services/receipt_reader.dart';
import 'package:testapp/services/speech_input.dart';

/// Stands in for the camera and the text reading.
class FakeReader extends ReceiptReader {
  FakeReader({this.photo = '/receipt.jpg', this.text = '', this.error});

  final String? photo;
  String text;
  final Object? error;
  Completer<String>? reading;
  final sources = <ImageSource>[];

  @override
  Future<String?> pickPhoto(ImageSource source) async {
    sources.add(source);
    if (error != null) throw error!;
    return photo;
  }

  @override
  Future<String> readText(String path) => reading?.future ?? Future.value(text);
}

/// Stands in for the microphone; the test says what is heard and when it
/// stops.
class FakeSpeech extends SpeechInput {
  FakeSpeech({this.startProblem});

  final SpeechProblem? startProblem;
  ValueChanged<String>? hear;
  ValueChanged<SpeechProblem?>? end;
  var starts = 0;
  var stops = 0;

  @override
  Future<SpeechProblem?> start({
    required ValueChanged<String> onWords,
    required ValueChanged<SpeechProblem?> onStopped,
  }) async {
    starts++;
    hear = onWords;
    end = onStopped;
    return startProblem;
  }

  @override
  Future<void> stop() async => stops++;
}

/// Plays Android's side of the speech plugin, sending what a real phone sends.
class AndroidSpeech {
  AndroidSpeech(this.tester) {
    _messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'initialize' || 'has_permission' || 'listen' => true,
        _ => null,
      };
    });
  }

  static const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final WidgetTester tester;

  TestDefaultBinaryMessenger get _messenger =>
      tester.binding.defaultBinaryMessenger;

  Future<void> _send(String method, String argument) async {
    await _messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, argument)),
      (_) {},
    );
  }

  Future<void> status(String status) => _send('notifyStatus', status);

  /// Words heard so far; [last] marks Android's final result.
  Future<void> words(String words, {bool last = false}) {
    return _send(
      'textRecognition',
      jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'confidence': 0.9},
        ],
        'resultType': last ? 2 : 0,
      }),
    );
  }

  Future<void> error(String error) =>
      _send('notifyError', jsonEncode({'errorMsg': error, 'permanent': true}));

  void dispose() => _messenger.setMockMethodCallHandler(channel, null);
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MyApp(home: screen),
    ),
  );
  await tester.pump();
}

/// The text in the Add Expense field whose hint is [hint].
String fieldText(WidgetTester tester, String hint) {
  final field = tester.widget<TextField>(
    find.ancestor(of: find.text(hint), matching: find.byType(TextField)),
  );
  return field.controller!.text;
}

void main() {
  group('Scan Receipt', () {
    testWidgets('starts with tips and two ways to get a photo', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, OcrScreen(reader: FakeReader()));

      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.text('Scan a receipt'), findsOneWidget);
      expect(find.text('For a clear scan'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('shows what it is doing, then the text it read', (
      tester,
    ) async {
      final reader = FakeReader()..reading = Completer<String>();
      await pumpScreen(tester, OcrScreen(reader: reader));

      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('Reading your receipt…'), findsOneWidget);

      reader.reading!.complete('JOLLIBEE\nTOTAL 150.00');
      await tester.pump();
      expect(find.text('Check the text'), findsOneWidget);
      expect(find.text('JOLLIBEE\nTOTAL 150.00'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
      expect(find.text('Use This'), findsOneWidget);
    });

    testWidgets('Use This opens a new expense with the text in its notes', (
      tester,
    ) async {
      final reader = FakeReader(text: 'JOLLIBEE\nTOTAL 150.00');
      await pumpScreen(
        tester,
        OcrScreen(reader: reader, wallets: Stream.value(const [])),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();

      // Nothing is saved: the form is open for the user to finish.
      expect(find.byType(AddExpenseScreen), findsOneWidget);
      expect(find.text('Check the text'), findsNothing);
      expect(
        fieldText(tester, 'Add additional notes...'),
        'JOLLIBEE\nTOTAL 150.00',
      );
      expect(fieldText(tester, 'What did you spend money on?'), '');
      expect(fieldText(tester, '0.00'), '', reason: 'the user adds it');
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      final reader = FakeReader(photo: null);
      await pumpScreen(tester, OcrScreen(reader: reader));

      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('Scan a receipt'), findsOneWidget);
      expect(reader.sources, [ImageSource.camera]);
    });

    testWidgets('no text found says what to try, and gallery retakes from '
        'the gallery', (tester) async {
      final reader = FakeReader();
      await pumpScreen(tester, OcrScreen(reader: reader));

      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('No text found'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);

      reader.text = 'SM Supermarket';
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();
      expect(find.text('SM Supermarket'), findsOneWidget);
      await tester.tap(find.text('Choose Another'));
      await tester.pump();
      expect(reader.sources, [
        ImageSource.camera,
        ImageSource.gallery,
        ImageSource.gallery,
      ]);
    });

    test('receipt text comes back in printed rows, prices beside items', () {
      Rect at(double left, double top, [double width = 100]) =>
          Rect.fromLTWH(left, top, width, 20);

      // The reader lists names and prices as separate blocks.
      expect(
        readingOrder([
          ('1 Chickenjoy w/ Rice', at(10, 100, 200)),
          ('JOLLIBEE', at(80, 20)),
          ('1 Coke Float', at(10, 140, 150)),
          ('99.00', at(300, 103)), // a little lower: the photo is tilted
          ('45.00', at(300, 139)),
          ('TOTAL', at(10, 200)),
          ('204.00', at(300, 198)),
        ]),
        [
          'JOLLIBEE',
          '1 Chickenjoy w/ Rice  99.00',
          '1 Coke Float  45.00',
          'TOTAL  204.00',
        ],
      );
      expect(readingOrder(const []), isEmpty);
    });

    testWidgets('a blocked camera and a failed read get plain messages', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        OcrScreen(
          reader: FakeReader(
            error: PlatformException(code: 'camera_access_denied'),
          ),
        ),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text("Can't use the camera"), findsOneWidget);

      await pumpScreen(
        tester,
        OcrScreen(
          key: UniqueKey(),
          reader: FakeReader(error: StateError('decoder')),
        ),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text("Couldn't read that photo"), findsOneWidget);
      expect(find.textContaining('Bad state'), findsNothing);
    });
  });

  group('Voice Entry', () {
    testWidgets('waits with an example and a labelled mic', (tester) async {
      final handle = tester.ensureSemantics();
      final speech = FakeSpeech();
      await pumpScreen(tester, VoiceRecognitionScreen(input: speech));

      expect(find.text('Voice Entry'), findsOneWidget);
      expect(find.text('Say what you spent'), findsOneWidget);
      expect(find.text('“Lunch at Jollibee, 150 pesos”'), findsOneWidget);
      expect(find.byTooltip('Start speaking'), findsOneWidget);
      expect(speech.starts, 0);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('from Home it listens straight away and shows the words', (
      tester,
    ) async {
      final speech = FakeSpeech();
      await pumpScreen(
        tester,
        VoiceRecognitionScreen(
          autoStart: true,
          input: speech,
          wallets: Stream.value(const []),
        ),
      );
      await tester.pump();

      expect(speech.starts, 1);
      expect(find.text('Listening…'), findsOneWidget);
      expect(find.byTooltip('Stop listening'), findsOneWidget);

      speech.hear!('lunch at jollibee');
      await tester.pump();
      expect(find.text('lunch at jollibee'), findsOneWidget);

      speech.end!(null);
      await tester.pump();
      expect(find.text('Is this right?'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();
      expect(find.byType(AddExpenseScreen), findsOneWidget);
      expect(
        fieldText(tester, 'What did you spend money on?'),
        'Lunch at jollibee',
      );
      expect(fieldText(tester, '0.00'), '', reason: 'the user adds it');
    });

    testWidgets('Stop keeps what was heard so far', (tester) async {
      final speech = FakeSpeech();
      await pumpScreen(tester, VoiceRecognitionScreen(input: speech));
      await tester.tap(find.byTooltip('Start speaking'));
      await tester.pump();

      speech.hear!('taxi 200');
      await tester.pump();
      await tester.tap(find.byTooltip('Stop listening'));
      await tester.pump();

      expect(speech.stops, 1);
      expect(find.text('Is this right?'), findsOneWidget);
      expect(find.text('taxi 200'), findsOneWidget);
    });

    testWidgets('hearing nothing, then the reason arriving late', (
      tester,
    ) async {
      final speech = FakeSpeech();
      await pumpScreen(tester, VoiceRecognitionScreen(input: speech));
      await tester.tap(find.byTooltip('Start speaking'));
      await tester.pump();

      speech.end!(null);
      await tester.pump();
      expect(find.text("Didn't catch that"), findsOneWidget);
      expect(find.byTooltip('Start speaking'), findsOneWidget);

      speech.end!(SpeechProblem.offline);
      await tester.pump();
      expect(find.text('No connection'), findsOneWidget);
    });

    testWidgets('a blocked microphone says how to fix it', (tester) async {
      await pumpScreen(
        tester,
        VoiceRecognitionScreen(
          autoStart: true,
          input: FakeSpeech(startProblem: SpeechProblem.noPermission),
        ),
      );
      await tester.pump();

      expect(find.text('The microphone is off'), findsOneWidget);
      expect(find.byTooltip('Start speaking'), findsOneWidget);
    });

    group('listening, replaying what Android sent', () {
      late AndroidSpeech android;
      late SpeechInput input;
      late List<String> heard;
      late List<SpeechProblem?> ends;

      Future<void> listen() async {
        heard = [];
        ends = [];
        final problem = await input.start(
          onWords: heard.add,
          onStopped: ends.add,
        );
        expect(problem, isNull);
      }

      Future<void> begin(WidgetTester tester) async {
        android = AndroidSpeech(tester);
        addTearDown(android.dispose);
        input = SpeechInput(engine: speech.SpeechToText.withMethodChannel());
        await listen();
      }

      /// Stops the plugin's own timers so none is left running.
      Future<void> finish(WidgetTester tester) async {
        await input.stop();
        await tester.pump(const Duration(seconds: 3));
      }

      testWidgets('words, then Android stops without ever saying done', (
        tester,
      ) async {
        // As sent on the emulator while "lunch at Jollibee 150 pesos" was said.
        await begin(tester);
        await android.status('listening');
        await android.words('launch');
        await android.words('launch at jollibee');
        await android.words('launch at jollibee 150 pesos');
        await android.status('notListening');
        await android.status('done');
        await android.words('launch at jollibee 150 pesos');

        await tester.pump(const Duration(milliseconds: 500));
        expect(ends, isEmpty, reason: 'the last words still get a moment');
        await tester.pump(const Duration(milliseconds: 400));
        expect(ends, [null]);
        expect(heard.last, 'launch at jollibee 150 pesos');
        await finish(tester);
      });

      testWidgets('silence ends once; "no match" is not a problem', (
        tester,
      ) async {
        await begin(tester);
        await android.status('listening');
        await android.status('notListening');
        await android.status('doneNoResult');
        await android.words('');
        await android.error('error_no_match');
        await tester.pump(const Duration(seconds: 1));

        expect(ends, [null]);
        await finish(tester);
      });

      testWidgets('a reason sent after the end is passed on', (tester) async {
        await begin(tester);
        await android.status('listening');
        await android.status('notListening');
        await android.status('doneNoResult');
        await android.error('error_network');

        expect(ends, [null, SpeechProblem.offline]);
        await finish(tester);
      });

      testWidgets('an earlier listen ending late does not end this one', (
        tester,
      ) async {
        await begin(tester);
        await android.status('listening');
        await input.stop();
        await listen();

        // The first listen's end arrives before the second one begins.
        await android.status('notListening');
        await android.status('doneNoResult');
        expect(ends, isEmpty);

        await android.status('listening');
        await android.words('taxi 200');
        await android.status('notListening');
        await tester.pump(const Duration(seconds: 1));
        expect(ends, [null]);
        expect(heard.last, 'taxi 200');
        await finish(tester);
      });

      testWidgets('words without the "listening" message still end', (
        tester,
      ) async {
        await begin(tester);
        await android.words('coffee 120');
        await android.status('notListening');
        await android.status('done');
        await tester.pump(const Duration(seconds: 1));

        expect(ends, [null]);
        expect(heard, ['coffee 120']);
        await finish(tester);
      });

      testWidgets('a final result ends it straight away', (tester) async {
        await begin(tester);
        await android.status('listening');
        await android.words('jeep fare 13', last: true);

        expect(ends, [null]);
        expect(heard, ['jeep fare 13']);
        await finish(tester);
      });

      testWidgets('an error before listening begins ends it', (tester) async {
        await begin(tester);
        await android.error('error_busy');

        expect(ends, [SpeechProblem.failed]);
        await finish(tester);
      });

      testWidgets('it never listens past the limit', (tester) async {
        await begin(tester);
        await android.status('listening');
        await tester.pump(SpeechInput.limit);

        expect(ends, [null]);
        await finish(tester);
      });
    });

    test('speech errors become what the user is told', () {
      expect(problemFor('error_no_match'), isNull);
      expect(problemFor('error_speech_timeout'), isNull);
      expect(problemFor('error_permission'), SpeechProblem.noPermission);
      expect(problemFor('error_network'), SpeechProblem.offline);
      expect(problemFor('error_server_disconnected'), SpeechProblem.offline);
      expect(
        problemFor('error_language_unavailable'),
        SpeechProblem.unavailable,
      );
      expect(problemFor('error_busy'), SpeechProblem.failed);
    });
  });
}
