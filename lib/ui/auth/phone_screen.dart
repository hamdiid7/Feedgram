import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../telegram/auth/auth_controller.dart';
import '../../telegram/auth/auth_status.dart';
import 'auth_scaffold.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.status, required this.auth});

  final AuthStatus status;
  final AuthController auth;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _controller = TextEditingController(text: '+');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _looksComplete => _controller.text.replaceAll(RegExp(r'\D'), '').length >= 7;

  void _submit() {
    if (widget.status.busy || !_looksComplete) return;
    widget.auth.submitPhoneNumber(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Your phone number',
      subtitle: 'Telegram will send a login code. Nothing leaves this device '
          'except the request to Telegram itself.',
      error: widget.status.message,
      busy: widget.status.busy,
      primaryLabel: 'Send code',
      onPrimary: _looksComplete ? _submit : null,
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        enabled: !widget.status.busy,
        // Digits and a leading +; TDLib accepts spaces and dashes too, but
        // keeping it clean avoids PHONE_NUMBER_INVALID from stray characters.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+251 …',
          helperText: 'Include the country code.',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
