import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;

/// Why voice entry could not listen.
enum SpeechProblem {
  /// The microphone is not allowed for FinAssist.
  noPermission,

  /// The phone has no speech recognition, or none for its language.
  unavailable,

  /// Speech recognition needs a connection on this phone, and there isn't one.
  offline,

  /// Anything else. Trying again usually works.
  failed,
}

/// The phone's own speech recognition, used for voice entry.
///
/// Kept apart from the voice screen so tests can stand in for the microphone.
class SpeechInput {
  SpeechInput({speech.SpeechToText? engine}) : _given = engine;

  final speech.SpeechToText? _given;

  // The plugin is one shared object for the whole app, unless a test gives
  // its own.
  speech.SpeechToText get _engine => _given ?? speech.SpeechToText();

  /// Counts listens, so a message from an earlier one is never taken as news
  /// about this one.
  static int _listens = 0;

  /// Shuts down the listen in progress, timers and all, when the user stops
  /// or a new listen starts.
  static void Function()? _dropCurrent;

  /// Listening never runs longer than this, whatever the plugin reports.
  static const limit = Duration(seconds: 35);

  /// Starts listening. [onWords] gets the words heard so far. [onStopped]
  /// runs once listening ends, with the problem if there was one; it may run
  /// again if the problem is only reported after the end.
  ///
  /// Returns why listening could not start, or null once it has.
  Future<SpeechProblem?> start({
    required ValueChanged<String> onWords,
    required ValueChanged<SpeechProblem?> onStopped,
  }) async {
    final engine = _engine;
    _dropCurrent?.call();
    _dropCurrent = null;
    final listen = ++_listens;
    var dropped = false;
    bool current() => listen == _listens && !dropped;

    // Asks for the microphone the first time.
    if (!await engine.initialize()) {
      return await engine.hasPermission
          ? SpeechProblem.unavailable
          : SpeechProblem.noPermission;
    }

    // An earlier listen that is still shutting down would send its last
    // messages into this one, so it is ended first, with no one listening.
    engine
      ..statusListener = null
      ..errorListener = null;
    await engine.cancel();
    if (!current()) return null;

    SpeechProblem? problem;
    // Whether this listen has shown a sign of life yet.
    var active = false;
    var stopped = false;
    Timer? lastWords;
    Timer? tooLong;

    void end() {
      if (stopped || !current()) return;
      stopped = true;
      lastWords?.cancel();
      tooLong?.cancel();
      onStopped(problem);
    }

    // Once words are heard, the plugin can hold back "done" for good while
    // it waits for a final result that never comes. After the phone stops
    // listening, the last words get a moment to arrive, then it ends.
    void windDown() {
      lastWords ??= Timer(const Duration(milliseconds: 800), end);
    }

    // The plugin keeps the listeners from its first start, so every listen
    // sets its own. Otherwise a second visit never hears that it stopped.
    engine.statusListener = (status) {
      if (!current()) return;
      if (status == speech.SpeechToText.listeningStatus) {
        active = true;
      } else if (!active) {
        // Before this listen began: the end of an earlier one.
        return;
      } else if (status == speech.SpeechToText.doneStatus) {
        end();
      } else if (status == speech.SpeechToText.notListeningStatus) {
        windDown();
      }
    };
    engine.errorListener = (error) {
      if (!current()) return;
      problem = problemFor(error.errorMsg);
      if (stopped) {
        // Android can say it has stopped before it says why.
        if (problem != null) onStopped(problem);
      } else if (!active) {
        // It never began listening, so nothing else will follow.
        problem ??= SpeechProblem.failed;
        end();
      } else {
        windDown();
      }
    };

    tooLong = Timer(limit, end);
    _dropCurrent = () {
      dropped = true;
      lastWords?.cancel();
      tooLong?.cancel();
    };
    try {
      await engine.listen(
        onResult: (result) {
          if (!current() || stopped) return;
          active = true;
          onWords(result.recognizedWords);
          if (result.finalResult) end();
        },
        listenOptions: speech.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (_) {
      // The screen reports it; this listen is over.
      stopped = true;
      tooLong.cancel();
      rethrow;
    }
    return null;
  }

  /// Stops listening. The screen keeps whatever was heard; nothing more is
  /// reported for this listen.
  Future<void> stop() {
    _dropCurrent?.call();
    _dropCurrent = null;
    return _engine.stop();
  }
}

/// What a speech recognition error means for the user. Hearing nothing is not
/// a problem, just an empty result.
@visibleForTesting
SpeechProblem? problemFor(String errorMsg) {
  switch (errorMsg) {
    case 'error_no_match':
    case 'error_speech_timeout':
      return null;
    case 'error_permission':
      return SpeechProblem.noPermission;
    case 'error_network':
    case 'error_network_timeout':
    case 'error_server':
    case 'error_server_disconnected':
      return SpeechProblem.offline;
    case 'error_language_not_supported':
    case 'error_language_unavailable':
      return SpeechProblem.unavailable;
    default:
      return SpeechProblem.failed;
  }
}
