import 'dart:async';
import 'dart:isolate';

import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/client.dart';

import 'isolate_protocol.dart';

/// How long a single `td_receive` may block this isolate's thread. Also the
/// upper bound on how long a [ShutdownRequest] or [SetRawCapture] waits before
/// the loop notices it.
const double _receiveTimeoutSeconds = 1.0;

/// Entry point of the incoming-updates isolate.
///
/// `td_receive` blocks its thread, so it gets an isolate to itself and nothing
/// else. Conversion from JSON to typed objects also happens here — the main
/// isolate only ever sees finished [td.TdObject]s.
Future<void> receiveIsolateMain(ReceiveIsolateArgs args) async {
  final ReceivePort commands;

  try {
    await TdPlugin.initialize();
    commands = ReceivePort();
  } catch (e, st) {
    args.toMain.send(WorkerStartupFailure('receive', '$e', '$st'));
    return;
  }

  var running = true;
  var captureRaw = args.captureRaw;

  commands.listen((message) {
    if (message is ShutdownRequest) {
      running = false;
    } else if (message is SetRawCapture) {
      captureRaw = message.enabled;
    }
  });

  args.toMain.send(ReceiveIsolateReady(commandPort: commands.sendPort));

  while (running) {
    String? raw;
    try {
      raw = TdPlugin.instance.tdReceive(_receiveTimeoutSeconds);
    } catch (e, st) {
      args.toMain.send(ReceiveLoopError('$e', '$st'));
    }

    if (raw != null) {
      try {
        final object = td.convertJsonToObject(raw);
        if (object != null) {
          args.toMain.send(TdIncoming(object, captureRaw ? raw : null));
        }
      } catch (e) {
        // Unknown `@type` for the installed handy_tdlib version. Forward the
        // raw line instead of swallowing it.
        args.toMain.send(TdUnconvertible(raw, '$e'));
      }
    }

    // `td_receive` is a blocking native call, so this isolate's event loop only
    // runs when we hand it back. Without this yield the command port above
    // would never be drained and shutdown would hang.
    await Future<void>.delayed(Duration.zero);
  }

  commands.close();
}
