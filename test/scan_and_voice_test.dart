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
  Object? error;
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

    testWidgets('Use This starts a new expense filled in from the receipt', (
      tester,
    ) async {
      final reader = FakeReader(text: 'JOLLIBEE\nTOTAL 150.00');
      await pumpScreen(
        tester,
        OcrScreen(reader: reader, wallets: Stream.value(const [])),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      // What will be filled in is shown first.
      expect(find.text('Filled in for you'), findsOneWidget);
      expect(find.text('₱150'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Jollibee'), findsOneWidget);

      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();

      // Nothing is saved: the form is open for the user to check.
      expect(find.byType(AddExpenseScreen), findsOneWidget);
      expect(find.text('Check the text'), findsNothing);
      expect(fieldText(tester, '0.00'), '150');
      expect(fieldText(tester, 'What did you spend money on?'), 'Jollibee');
      expect(
        fieldText(tester, 'Add additional notes...'),
        'JOLLIBEE\nTOTAL 150.00',
      );
      expect(find.text('Food'), findsOneWidget);
      expect(
        find.text("Suggested for you. Change it if it's wrong."),
        findsOneWidget,
      );
    });

    testWidgets('a receipt with nothing recognisable leaves the form to the '
        'user', (tester) async {
      final reader = FakeReader(text: 'Thank you for shopping');
      await pumpScreen(
        tester,
        OcrScreen(reader: reader, wallets: Stream.value(const [])),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('Filled in for you'), findsNothing);

      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, '0.00'), '');
      expect(
        fieldText(tester, 'Add additional notes...'),
        'Thank you for shopping',
      );
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
      // In the text, and as the store found in it.
      expect(find.text('SM Supermarket'), findsNWidgets(2));
      await tester.tap(find.text('Choose Another'));
      await tester.pump();
      expect(reader.sources, [
        ImageSource.camera,
        ImageSource.gallery,
        ImageSource.gallery,
      ]);
    });

    testWidgets('a long receipt is taken in parts and read as one', (
      tester,
    ) async {
      final reader = FakeReader(
        text: 'PUREGOLD\nRice 5kg  250.00\nEggs  120.00',
      );
      await pumpScreen(
        tester,
        OcrScreen(reader: reader, wallets: Stream.value(const [])),
      );
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('Part 1'), findsNothing, reason: 'one photo, no parts');
      expect(find.text('Filled in for you'), findsOneWidget);
      expect(find.text('₱465'), findsNothing);

      // The next photo overlaps the first by two lines.
      reader.text =
          'Rice 5kg  250.00\nEggs  120.00\nMilk  95.00\nTOTAL  465.00';
      await tester.tap(find.text('Add Next Part'));
      await tester.pump();
      expect(find.text('Part 1'), findsOneWidget);
      expect(find.text('Part 2'), findsOneWidget);
      expect(find.text('₱465'), findsOneWidget);
      expect(find.text('Puregold'), findsOneWidget);
      expect(reader.sources, [ImageSource.camera, ImageSource.camera]);

      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, '0.00'), '465');
      expect(
        fieldText(tester, 'Add additional notes...'),
        'PUREGOLD\nRice 5kg  250.00\nEggs  120.00\nMilk  95.00\nTOTAL  465.00',
        reason: 'the overlapping lines only once',
      );
    });

    testWidgets('Retake redoes the last part, and any part can be removed', (
      tester,
    ) async {
      final reader = FakeReader(text: 'SAVEMORE\nBread  50.00');
      await pumpScreen(tester, OcrScreen(reader: reader));
      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      reader.text = 'blurry';
      await tester.tap(find.text('Add Next Part'));
      await tester.pump();
      expect(find.text('blurry'), findsOneWidget);

      reader.text = 'TOTAL  50.00';
      await tester.tap(find.text('Retake'));
      await tester.pump();
      expect(find.text('blurry'), findsNothing);
      expect(find.text('TOTAL  50.00'), findsOneWidget);
      expect(find.text('Part 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove part 1'));
      await tester.pump();
      expect(find.text('SAVEMORE\nBread  50.00'), findsNothing);
      expect(find.text('Part 1'), findsNothing, reason: 'one part left');
      expect(find.text('TOTAL  50.00'), findsOneWidget);
    });

    testWidgets('a part that fails to read keeps what was read so far', (
      tester,
    ) async {
      final reader = FakeReader(text: 'JOLLIBEE\nTOTAL 150.00');
      await pumpScreen(tester, OcrScreen(reader: reader));
      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      reader.text = '';
      await tester.tap(find.text('Add Next Part'));
      await tester.pump();
      expect(find.text('JOLLIBEE\nTOTAL 150.00'), findsOneWidget);
      expect(find.text('Part 2'), findsNothing);
      expect(
        find.text('No text found in that photo, so nothing changed.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retake'));
      await tester.pump();
      expect(
        find.text('JOLLIBEE\nTOTAL 150.00'),
        findsOneWidget,
        reason: 'a failed retake keeps the photo it was replacing',
      );

      reader.error = PlatformException(code: 'camera_access_denied');
      await tester.tap(find.text('Add Next Part'));
      await tester.pump();
      expect(find.text('Check the text'), findsOneWidget);
      expect(find.textContaining("Can't use the camera."), findsOneWidget);
    });

    testWidgets('photos taken out of order are put in order', (tester) async {
      const top = 'SAVEMORE MARKET\nOfficial Receipt\nRice  289.00';
      const bottom = 'Eggs  240.00\nTOTAL  529.00\nCASH  600.00';
      final reader = FakeReader(text: bottom);
      await pumpScreen(tester, OcrScreen(reader: reader));
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      expect(find.text('₱529'), findsOneWidget);

      reader.text = top;
      await tester.tap(find.text('Add Next Part'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text(top)).dy,
        lessThan(tester.getTopLeft(find.text(bottom)).dy),
      );
      expect(find.text('Savemore Market'), findsOneWidget, reason: 'store');
      expect(
        find.text(
          'Added as part 1, where it fits. Use the arrows to change the order.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Move part 1 up'), findsNothing);

      // Retake redoes the photo just taken, wherever it was put.
      reader.text = '$top\nBread  72.00';
      await tester.tap(find.text('Retake'));
      await tester.pump();
      expect(find.text('$top\nBread  72.00'), findsOneWidget);
      expect(find.text(bottom), findsOneWidget);

      // The order can always be changed by hand.
      await tester.tap(find.byTooltip('Move part 2 up'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text(bottom)).dy,
        lessThan(tester.getTopLeft(find.text('$top\nBread  72.00')).dy),
      );
    });

    testWidgets('a photo of another receipt is asked about first', (
      tester,
    ) async {
      const puregold = 'PUREGOLD\nRice  289.00\nTOTAL  289.00';
      const jollibee = 'JOLLIBEE\nChickenjoy  99.00\nTOTAL  99.00';
      final reader = FakeReader(text: puregold);
      await pumpScreen(tester, OcrScreen(reader: reader));
      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      reader.text = jollibee;
      await tester.tap(find.text('Add Next Part'));
      await tester.pumpAndSettle();
      expect(find.text('A different receipt?'), findsOneWidget);
      expect(
        find.text(
          'It is from Jollibee, not Puregold. Each receipt is its own '
          'expense, so add only parts of this one.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text("Don't Add"));
      await tester.pumpAndSettle();
      expect(find.text(jollibee), findsNothing);
      expect(find.text('Part 2'), findsNothing);
      expect(find.text('₱289'), findsOneWidget);

      await tester.tap(find.text('Add Next Part'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Anyway'));
      await tester.pumpAndSettle();
      expect(find.text('Part 2'), findsOneWidget);
      expect(find.text(jollibee), findsOneWidget);
    });

    test('what shows a part is from another receipt', () {
      final now = DateTime(2026, 9, 19, 10);
      String? reason(List<String> parts, String part) =>
          anotherReceiptReason(parts, part, now: now);

      const top = 'SAVEMORE MARKET\nOfficial Receipt\n09/18/2026\nRice  289.00';
      const bottom = 'Eggs  240.00\nTOTAL  529.00\nCASH  600.00';

      // Parts of the same receipt, in either order.
      expect(reason(const [], top), isNull);
      expect(reason(const [top], bottom), isNull);
      expect(reason(const [bottom], top), isNull);
      expect(reason(const [top], 'Eggs  240.00\nMilk  98.50'), isNull);

      expect(
        reason(const [top], 'JOLLIBEE\nChickenjoy  99.00\nTOTAL  99.00'),
        'It is from Jollibee, not Savemore Market.',
      );
      expect(
        reason(const [bottom], 'Coke  45.00\nTOTAL  45.00'),
        'Its total is ₱45, not ₱529.',
      );
      expect(
        reason(const [top], 'Official Receipt\n09/16/2026\nCoke  45.00'),
        'It is dated Sep 16, 2026, not Sep 18, 2026.',
      );
      expect(
        reason(const [top], 'Official Receipt\nCoke  45.00'),
        'It starts like a new receipt.',
      );

      // Overlapping photos belong together, whatever else they show.
      expect(
        reason(const [
          'Official Receipt\nRice  289.00\nEggs  240.00',
        ], 'Rice  289.00\nEggs  240.00\nTOTAL  529.00'),
        isNull,
      );
    });

    test('a new part goes where it fits among the others', () {
      const top = 'SM SUPERMARKET\nOfficial Receipt\nRice  289.00';
      const middle = 'Eggs  240.00\nMilk  98.50';
      const bottom = 'Bread  72.00\nTOTAL  699.50\nCASH  1,000.00';

      expect(placeForPart(const [], top), 0);
      expect(placeForPart(const [top], middle), 1, reason: 'nothing to go on');
      expect(placeForPart(const [bottom], top), 0, reason: 'starts like a top');
      expect(
        placeForPart(const [bottom], middle),
        0,
        reason: 'no total, so before the part that has it',
      );
      expect(placeForPart(const [top, bottom], middle), 1);
      expect(placeForPart(const [top, middle], bottom), 2);

      // Overlapping photos settle it, even against the other clues.
      const upper = 'Official Receipt\nRice  289.00\nEggs  240.00\nMilk  98.50';
      const lower = 'Eggs  240.00\nMilk  98.50\nTOTAL  627.50';
      expect(placeForPart(const [lower], upper), 0);
      expect(placeForPart(const [upper], lower), 1);
    });

    test('parts are joined without the lines where photos overlap', () {
      expect(joinReceiptParts(const []), '');
      expect(joinReceiptParts(const ['A\n\nB  ']), 'A\nB');
      expect(
        joinReceiptParts(const [
          'STORE\nRice  50\nEggs  90',
          'rice 50\nEggs   90\nTOTAL  140',
        ]),
        'STORE\nRice  50\nEggs  90\nTOTAL  140',
        reason: 'case and spacing can differ between photos',
      );
      expect(
        joinReceiptParts(const ['STORE\nCoke  45', 'Coke  45\nTOTAL  90']),
        'STORE\nCoke  45\nCoke  45\nTOTAL  90',
        reason: 'one matching line may be a second item, so it stays',
      );
      expect(
        joinReceiptParts(const [
          'STORE\nInstant Noodles x10  95.00\nCanned Tuna x5  175.00',
          'Instant Noodles x1e  95.00\nCanned Tuna X5  175.00\nTOTAL  270.00',
        ]),
        'STORE\nInstant Noodles x10  95.00\nCanned Tuna x5  175.00\n'
        'TOTAL  270.00',
        reason: 'a character misread in one photo is still the same line',
      );
      expect(
        joinReceiptParts(const ['Coke  45\nFries  60', 'Coke  46\nFries  65']),
        'Coke  45\nFries  60\nCoke  46\nFries  65',
        reason: 'short lines must match exactly',
      );
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

    testWidgets('an amount said out loud fills the amount and category', (
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
      speech.hear!('lunch at jollibee 150 pesos');
      await tester.pump();
      speech.end!(null);
      await tester.pump();

      expect(find.text('Filled in for you'), findsOneWidget);
      expect(find.text('₱150'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);

      await tester.tap(find.text('Use This'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, '0.00'), '150');
      expect(
        fieldText(tester, 'What did you spend money on?'),
        'Lunch at jollibee',
      );
      expect(find.text('Food'), findsOneWidget);
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

  group('Add Expense suggests a category while typing', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(
        find.ancestor(
          of: find.text('What did you spend money on?'),
          matching: find.byType(TextField),
        ),
        text,
      );
      await tester.pump();
    }

    testWidgets('from the description, until the user picks one', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        AddExpenseScreen(wallets: Stream.value(const [])),
      );

      await type(tester, 'Grab papunta sa school');
      expect(find.text('Transportation'), findsOneWidget);
      expect(
        find.text("Suggested for you. Change it if it's wrong."),
        findsOneWidget,
      );

      // A better match replaces a suggestion.
      await type(tester, 'Netflix');
      expect(find.text('Entertainment'), findsOneWidget);
      expect(find.text('Transportation'), findsNothing);

      // Once the user picks, typing never changes it.
      await tester.tap(find.text('Entertainment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await type(tester, 'Meralco bill');
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Bills'), findsNothing);
      expect(
        find.text("Suggested for you. Change it if it's wrong."),
        findsNothing,
      );
    });

    testWidgets('never when editing an expense that already has one', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        AddExpenseScreen(
          wallets: Stream.value(const []),
          documentId: 'e1',
          initialAmount: 99,
          initialCategory: 'Shopping',
          initialDescription: 'Shirt',
        ),
      );
      await type(tester, 'Jollibee');
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
    });
  });
}
