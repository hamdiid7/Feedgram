import 'package:flutter/material.dart';

import '../../telegram/auth/auth_status.dart';
import '../app_scope.dart';
import '../root_shell.dart';
import 'code_screen.dart';
import 'password_screen.dart';
import 'phone_screen.dart';
import 'status_screen.dart';

/// Renders whichever screen the current [AuthStage] calls for.
///
/// There is no navigation stack here on purpose. TDLib owns the sequence, so the
/// UI is a pure function of the state it reports — which is also why a restart
/// on a live session lands on [RootShell] with no login screens flashing past.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final status = auth.status;

        return switch (status.stage) {
          AuthStage.connecting => const StatusScreen(
              title: 'Connecting',
              busy: true,
            ),
          AuthStage.needPhone => PhoneScreen(status: status, auth: auth),
          AuthStage.needCode => CodeScreen(status: status, auth: auth),
          AuthStage.needPassword => PasswordScreen(status: status, auth: auth),
          AuthStage.ready => const RootShell(),
          AuthStage.unsupported => StatusScreen(
              title: 'Not supported',
              message: status.message,
              onRetry: auth.restartPhoneEntry,
              retryLabel: 'Use another number',
              showDiagnostics: true,
            ),
          AuthStage.loggedOut => StatusScreen(
              title: 'Signed out',
              message: status.message,
              busy: true,
            ),
          AuthStage.closed => StatusScreen(
              title: 'Restart required',
              message: status.message,
            ),
          AuthStage.failed => StatusScreen(
              title: 'Cannot start',
              message: status.message,
              onRetry: auth.start,
              retryLabel: 'Try again',
              showDiagnostics: true,
            ),
        };
      },
    );
  }
}
