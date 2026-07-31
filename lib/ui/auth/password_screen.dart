import 'package:flutter/material.dart';

import '../../telegram/auth/auth_controller.dart';
import '../../telegram/auth/auth_status.dart';
import 'auth_scaffold.dart';

/// Only reached when the account has 2FA enabled — TDLib emits
/// `authorizationStateWaitPassword` after the code, or skips it entirely.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, required this.status, required this.auth});

  final AuthStatus status;
  final AuthController auth;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _controller = TextEditingController();
  var _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.status.busy || _controller.text.isEmpty) return;
    widget.auth.submitPassword(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final hint = status.passwordHint;

    return AuthScaffold(
      title: 'Two-step verification',
      subtitle: hint == null
          ? 'This account has a cloud password. It is checked by Telegram and '
              'never stored on this device.'
          : 'Hint: $hint',
      error: status.message,
      busy: status.busy,
      primaryLabel: 'Sign in',
      onPrimary: _controller.text.isEmpty ? null : _submit,
      secondary: status.hasRecoveryEmail && status.recoveryEmailPattern != null
          ? Text(
              'Password recovery goes to ${status.recoveryEmailPattern}. '
              'Use the official Telegram app to reset it.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            )
          : null,
      child: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        enabled: !status.busy,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Cloud password',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
            tooltip: _obscure ? 'Show' : 'Hide',
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
