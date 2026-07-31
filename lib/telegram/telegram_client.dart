import 'dart:async';
import 'dart:isolate';

import 'package:handy_tdlib/api.dart' as td;

import 'isolate/invoke_isolate.dart';
import 'isolate/isolate_protocol.dart';
import 'isolate/receive_isolate.dart';
import 'td_exception.dart';

/// The only thing in the app that knows TDLib exists.
///
/// Presents a normal Dart surface — `Future`-returning [send] plus an [updates]
/// broadcast `Stream` — over what is really a pair of blocking native calls on
/// two background isolates. Nothing above this class should import
/// `handy_tdlib/client.dart`, spawn isolates, or touch `@extra`.
///
/// Keeping the package's types from leaking past the repository layer is also
/// what makes swapping `handy_tdlib` for `libtdjson` a contained change.
class TelegramClient {
  TelegramClient({
    this.defaultTimeout = const Duration(seconds: 30),
    this.logVerbosity = 1,
  });

  /// Applied to [send] when the call site does not pass its own timeout.
  final Duration defaultTimeout;

  /// TDLib's own log verbosity (0 = fatal only). Kept low: TDLib logs request
  /// contents at higher levels, which would put phone numbers and auth codes in
  /// logcat.
  final int logVerbosity;

  Isolate? _invokeIsolate;
  Isolate? _receiveIsolate;
  SendPort? _invokeCommands;
  SendPort? _receiveCommands;
  ReceivePort? _fromWorkers;
  int? _clientId;

  final _pending = <String, _PendingRequest>{};
  final _updates = StreamController<td.Update>.broadcast();
  final _rawLines = StreamController<String>.broadcast();

  var _extraCounter = 0;
  Future<void>? _startup;
  var _disposed = false;

  /// Unsolicited TDLib updates — every response that arrives without an
  /// `@extra`. Repositories subscribe here; this is the only path by which
  /// `updateAuthorizationState`, `updateNewChat`, `updateNewMessage` and friends
  /// reach the app.
  Stream<td.Update> get updates => _updates.stream;

  /// Raw JSON lines, only while [setRawCapture] is on. Feeds the debug dump
  /// screen; off by default so normal operation does not ship every update
  /// across the port twice.
  Stream<String> get rawLines => _rawLines.stream;

  bool get isRunning => _clientId != null && !_disposed;

  /// Spawns both worker isolates and completes once the receive loop is live.
  /// Safe to call more than once — later calls await the first.
  Future<void> start() {
    if (_disposed) {
      throw StateError('TelegramClient was disposed and cannot be restarted');
    }
    return _startup ??= _start();
  }

  Future<void> _start() async {
    final fromWorkers = ReceivePort();
    _fromWorkers = fromWorkers;

    final invokeReady = Completer<InvokeIsolateReady>();
    final receiveReady = Completer<ReceiveIsolateReady>();

    void failStartup(Object error) {
      if (!invokeReady.isCompleted) invokeReady.completeError(error);
      if (!receiveReady.isCompleted) receiveReady.completeError(error);
    }

    fromWorkers.listen((message) {
      if (message is InvokeIsolateReady) {
        if (!invokeReady.isCompleted) invokeReady.complete(message);
      } else if (message is ReceiveIsolateReady) {
        if (!receiveReady.isCompleted) receiveReady.complete(message);
      } else if (message is WorkerStartupFailure) {
        failStartup(StateError(
          'TDLib ${message.worker} isolate failed to start: ${message.error}',
        ));
      } else if (message is TdIsolateMessage) {
        _handleWorkerMessage(message);
      } else if (message is List && message.length == 2) {
        // An uncaught error in a worker, delivered via `onError`. Without this
        // port a dying isolate is indistinguishable from a hung one — there is
        // no exception to catch, the awaits below simply never complete.
        failStartup(StateError('TDLib isolate crashed: ${message.first}\n'
            '${message.last}'));
      } else if (message == null) {
        // `onExit`. Only a problem if it happens before handshake.
        failStartup(StateError(
          'TDLib isolate exited before it finished starting up',
        ));
      }
    });

    // Order matters: the client ID must exist before anything calls
    // `td_receive` against it.
    _invokeIsolate = await Isolate.spawn(
      invokeIsolateMain,
      InvokeIsolateArgs(
        toMain: fromWorkers.sendPort,
        logVerbosity: logVerbosity,
      ),
      debugName: 'tdlib-invoke',
      onError: fromWorkers.sendPort,
      onExit: fromWorkers.sendPort,
    );

    final invoke = await _withStartupTimeout(invokeReady.future, 'invoke');
    _clientId = invoke.clientId;
    _invokeCommands = invoke.commandPort;

    _receiveIsolate = await Isolate.spawn(
      receiveIsolateMain,
      ReceiveIsolateArgs(
        toMain: fromWorkers.sendPort,
        clientId: invoke.clientId,
        captureRaw: false,
      ),
      debugName: 'tdlib-receive',
      onError: fromWorkers.sendPort,
      onExit: fromWorkers.sendPort,
    );

    _receiveCommands =
        (await _withStartupTimeout(receiveReady.future, 'receive')).commandPort;
  }

  /// Backstop so a worker that neither reports ready nor dies cannot leave the
  /// app on a spinner forever.
  Future<T> _withStartupTimeout<T>(Future<T> future, String worker) {
    return future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError(
        'TDLib $worker isolate did not start within 15s',
      ),
    );
  }

  /// Sends [function] and completes with its matching response.
  ///
  /// [T] is the response type documented on the function class (`td.Ok` for the
  /// many setters). A returned TDLib `error` becomes a [TdException]; check
  /// [TdException.floodWait] before retrying anything.
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration? timeout,
  }) async {
    await start();
    final commands = _invokeCommands;
    if (commands == null || _disposed) {
      throw StateError('TelegramClient is not running');
    }

    final requestType = function.currentObjectId;
    final effectiveTimeout = timeout ?? defaultTimeout;
    final extra = '${requestType}_${_extraCounter++}';

    final completer = Completer<td.TdObject>();
    final timer = Timer(effectiveTimeout, () {
      final pending = _pending.remove(extra);
      pending?.completer.completeError(
        TdTimeoutException(requestType, effectiveTimeout),
      );
    });
    _pending[extra] = _PendingRequest(completer, timer, requestType);

    commands.send(InvokeRequest(function, extra));

    final response = await completer.future;
    if (response is td.TdError) {
      throw TdException(
        code: response.code,
        message: response.message,
        request: requestType,
      );
    }
    if (response is T) return response;
    throw TdUnexpectedResponse(
      request: requestType,
      received: response.currentObjectId,
    );
  }

  /// Turns raw-JSON forwarding on the receive isolate on or off at runtime.
  Future<void> setRawCapture(bool enabled) async {
    await start();
    _receiveCommands?.send(SetRawCapture(enabled));
  }

  void _handleWorkerMessage(TdIsolateMessage message) {
    switch (message) {
      case TdIncoming(:final object, :final raw):
        if (raw != null) _rawLines.add(raw);
        final extra = object.extra;
        if (extra is String) {
          final pending = _pending.remove(extra);
          if (pending != null) {
            pending.timer.cancel();
            pending.completer.complete(object);
            return;
          }
        }
        // No `@extra`, or an `@extra` we already timed out on: unsolicited.
        if (object is td.Update && !_updates.isClosed) _updates.add(object);

      case TdUnconvertible(:final raw):
        _rawLines.add(raw);

      case InvokeFailure(:final extra, :final error):
        final pending = _pending.remove(extra);
        pending?.timer.cancel();
        pending?.completer.completeError(
          TdException(
            code: -1,
            message: 'send failed: $error',
            request: pending.request,
          ),
        );

      case ReceiveLoopError(:final error):
        _rawLines.add('{"@type":"clientReceiveError","message":"$error"}');

      // Handshake and main->worker cases never reach here.
      case InvokeIsolateReady():
      case ReceiveIsolateReady():
      case WorkerStartupFailure():
      case InvokeRequest():
      case SetRawCapture():
      case ShutdownRequest():
        break;
    }
  }

  /// Winds both isolates down and fails anything still in flight.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _invokeCommands?.send(const ShutdownRequest());
    _receiveCommands?.send(const ShutdownRequest());

    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError('TelegramClient disposed before ${pending.request} '
              'received a response'),
        );
      }
    }
    _pending.clear();

    // The receive loop can be mid-`td_receive`; give it one timeout window to
    // notice the shutdown request and exit on its own before killing it.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _invokeIsolate?.kill(priority: Isolate.beforeNextEvent);
    _receiveIsolate?.kill(priority: Isolate.beforeNextEvent);
    _fromWorkers?.close();

    await _updates.close();
    await _rawLines.close();
    _clientId = null;
  }
}

class _PendingRequest {
  _PendingRequest(this.completer, this.timer, this.request);

  final Completer<td.TdObject> completer;
  final Timer timer;
  final String request;
}
