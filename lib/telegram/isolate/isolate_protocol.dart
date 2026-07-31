import 'dart:isolate';

import 'package:handy_tdlib/api.dart' as td;

/// Messages exchanged between the UI isolate and the two TDLib worker isolates.
///
/// `Isolate.spawn` puts every isolate in the same isolate group, so plain Dart
/// objects — including [td.TdObject] and [td.TdFunction] instances — can travel
/// over a [SendPort] without being reduced to JSON first. That is what lets the
/// worker do all `jsonEncode` / `convertJsonToObject` work off the main thread.
sealed class TdIsolateMessage {
  const TdIsolateMessage();
}

// ---------------------------------------------------------------------------
// Worker -> main
// ---------------------------------------------------------------------------

/// Sent once by the invokes isolate after it has opened the native library and
/// created the TDLib client ID.
final class InvokeIsolateReady extends TdIsolateMessage {
  const InvokeIsolateReady({required this.clientId, required this.commandPort});

  /// The single TDLib client ID for this process, created on the invokes
  /// isolate and handed to the receive isolate by the main isolate.
  final int clientId;

  /// Port accepting [InvokeRequest] / [SetRawCapture] / [ShutdownRequest].
  final SendPort commandPort;
}

/// Sent once by the receive isolate when its receive loop is about to start.
final class ReceiveIsolateReady extends TdIsolateMessage {
  const ReceiveIsolateReady({required this.commandPort});

  final SendPort commandPort;
}

/// A worker isolate failed to start up at all.
final class WorkerStartupFailure extends TdIsolateMessage {
  const WorkerStartupFailure(this.worker, this.error, this.stackTrace);

  final String worker;
  final String error;
  final String stackTrace;
}

/// One object received from TDLib, already converted on the worker isolate.
final class TdIncoming extends TdIsolateMessage {
  const TdIncoming(this.object, [this.raw]);

  final td.TdObject object;

  /// Original JSON line, present only while raw capture is enabled.
  final String? raw;
}

/// TDLib returned a line the installed `handy_tdlib` version cannot map to a
/// typed class. Kept rather than dropped — a new TDLib object type showing up
/// here is the signal that the package version is behind.
final class TdUnconvertible extends TdIsolateMessage {
  const TdUnconvertible(this.raw, this.error);

  final String raw;
  final String error;
}

/// An outgoing request could not be handed to TDLib. Carries the `@extra` so
/// the main isolate can fail the matching [Future] instead of leaking it.
final class InvokeFailure extends TdIsolateMessage {
  const InvokeFailure(this.extra, this.error, this.stackTrace);

  final String extra;
  final String error;
  final String stackTrace;
}

/// Non-fatal error inside the receive loop.
final class ReceiveLoopError extends TdIsolateMessage {
  const ReceiveLoopError(this.error, this.stackTrace);

  final String error;
  final String stackTrace;
}

// ---------------------------------------------------------------------------
// Main -> worker
// ---------------------------------------------------------------------------

/// One outgoing TDLib request. [extra] is echoed back by TDLib on the matching
/// response, which is how a fire-and-forget stream is turned into a `Future`.
final class InvokeRequest extends TdIsolateMessage {
  const InvokeRequest(this.function, this.extra);

  final td.TdFunction function;
  final String extra;
}

/// Toggle raw-JSON forwarding on the receive isolate. Off by default so normal
/// operation does not pay for shipping every update twice.
final class SetRawCapture extends TdIsolateMessage {
  const SetRawCapture(this.enabled);

  final bool enabled;
}

/// Ask a worker isolate to wind down its loop and exit.
final class ShutdownRequest extends TdIsolateMessage {
  const ShutdownRequest();
}

// ---------------------------------------------------------------------------
// Spawn arguments
// ---------------------------------------------------------------------------

final class InvokeIsolateArgs {
  const InvokeIsolateArgs({required this.toMain, required this.logVerbosity});

  final SendPort toMain;

  /// TDLib log verbosity applied via `td_execute` before any request is sent.
  /// 0 = fatal only; TDLib defaults to 5, which is very noisy in logcat.
  final int logVerbosity;
}

final class ReceiveIsolateArgs {
  const ReceiveIsolateArgs({
    required this.toMain,
    required this.clientId,
    required this.captureRaw,
  });

  final SendPort toMain;
  final int clientId;
  final bool captureRaw;
}
