import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/client.dart';

import 'isolate_protocol.dart';

/// Entry point of the outgoing-request isolate.
///
/// Owns the TDLib client ID: it is created here, once, and handed to the main
/// isolate which passes it on to the receive isolate. Every `td_send` and every
/// `jsonEncode` happens here so the UI isolate never does either.
Future<void> invokeIsolateMain(InvokeIsolateArgs args) async {
  final int clientId;
  final ReceivePort commands;

  try {
    await TdPlugin.initialize();
    // Synchronous, must run before the first request so TDLib does not dump
    // its default verbosity-5 firehose into logcat.
    TdPlugin.instance.tdExecute(
      jsonEncode(td.SetLogVerbosityLevel(
        newVerbosityLevel: args.logVerbosity,
      ).toJson()),
    );
    clientId = TdPlugin.instance.tdCreateClientId();
    commands = ReceivePort();
  } catch (e, st) {
    args.toMain.send(WorkerStartupFailure('invoke', '$e', '$st'));
    return;
  }

  args.toMain.send(
    InvokeIsolateReady(clientId: clientId, commandPort: commands.sendPort),
  );

  await for (final message in commands) {
    if (message is InvokeRequest) {
      try {
        TdPlugin.instance.tdSend(
          clientId,
          jsonEncode(message.function.toJson(message.extra)),
        );
      } catch (e, st) {
        args.toMain.send(InvokeFailure(message.extra, '$e', '$st'));
      }
    } else if (message is ShutdownRequest) {
      break;
    }
  }

  commands.close();
}
