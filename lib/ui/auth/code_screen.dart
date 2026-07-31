import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../telegram/auth/auth_controller.dart';
import '../../telegram/auth/auth_status.dart';
import 'auth_scaffold.dart';

class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key, required this.status, required this.auth});

  final AuthStatus status;
  final AuthController auth;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// When Telegram tells us the length, submit as soon as it's reached; that is
  /// how the official clients behave.
  bool get _looksComplete {
    final entered = _controller.text.trim().length;
    final expected = widget.status.codeLength;
    return expected == null ? entered >= 4 : entered >= expected;
  }

  void _submit() {
    if (widget.status.busy || !_looksComplete) return;
    widget.auth.submitCode(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;

    return AuthScaffold(
      title: 'Enter the code',
      subtitle: _where(status),
      error: status.message,
      busy: status.busy,
      primaryLabel: 'Continue',
      onPrimary: _looksComplete ? _submit : null,
      secondary: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: status.busy ? null : widget.auth.restartPhoneEntry,
            child: const Text('Change number'),
          ),
          TextButton(
            onPressed: status.busy ? null : widget.auth.resendCode,
            child: const Text('Resend'),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        enabled: !status.busy,
        maxLength: status.codeLength,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Login code',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          setState(() {});
          // Auto-submit only when Telegram gave an exact length, so we never
          // fire a request on a half-typed code.
          final expected = status.codeLength;
          if (expected != null && _controller.text.length == expected) {
            _submit();
          }
        },
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

String _where(AuthStatus status) {
  final number = status.phoneNumber;
  final suffix = number == null ? '' : ' sent to $number';

  return switch (status.delivery) {
    CodeDelivery.telegramMessage =>
      'Check Telegram on your other devices — the code was sent as a message, '
          'not an SMS.',
    CodeDelivery.sms => 'Check your SMS$suffix.',
    CodeDelivery.call => 'You will get a phone call$suffix reading the code.',
    CodeDelivery.flashCall =>
      'You will get a brief call$suffix; the code is in the calling number.',
    CodeDelivery.missedCall =>
      'You will get a missed call$suffix; the code is the last digits of the '
          'calling number.',
    CodeDelivery.fragment => 'The code was delivered via Fragment$suffix.',
    _ => 'Enter the code$suffix.',
  };
}
