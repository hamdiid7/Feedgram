import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/td_credentials.dart';
import '../../telegram/td_options.dart';
import '../../telegram/telegram_client.dart';
import '../app_scope.dart';
import 'media_debug_screen.dart';

/// Raw TDLib update dump.
///
/// Without a desktop target there is no fast way to see what TDLib is actually
/// saying, so this screen is the debugging surface: it turns raw capture on
/// while open and off when closed.
class TdDebugScreen extends StatefulWidget {
  const TdDebugScreen({super.key});

  @override
  State<TdDebugScreen> createState() => _TdDebugScreenState();
}

class _TdDebugScreenState extends State<TdDebugScreen> {
  static const _maxLines = 300;

  final _lines = <String>[];
  StreamSubscription<String>? _subscription;

  /// Held directly because `dispose` cannot look up an InheritedWidget.
  TelegramClient? _client;

  String? _version;
  String? _commitHash;

  @override
  void initState() {
    super.initState();
    // Deferred so context is available for AppScope.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  Future<void> _attach() async {
    if (!mounted) return;
    final client = AppScope.clientOf(context);
    _client = client;
    await client.setRawCapture(true);

    _subscription = client.rawLines.listen((line) {
      if (!mounted) return;
      setState(() {
        _lines.insert(0, line);
        if (_lines.length > _maxLines) _lines.removeLast();
      });
    });

    final version = await client.tdlibVersion();
    final commit = await client.tdlibCommitHash();
    if (!mounted) return;
    setState(() {
      _version = version;
      _commitHash = commit;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Raw capture doubles port traffic per update; do not leave it on.
    _client?.setRawCapture(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TDLib debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy log',
            onPressed: _lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(
                      ClipboardData(text: _lines.reversed.join('\n')),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Log copied')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear log',
            onPressed: () => setState(_lines.clear),
          ),
          IconButton(
            icon: const Icon(Icons.image_search_outlined),
            tooltip: 'Media scheduler',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MediaDebugScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: 'Reset local session',
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TDLib ${_version ?? '…'}',
                    style: theme.textTheme.titleMedium),
                if (_commitHash != null)
                  Text('commit $_commitHash',
                      style: theme.textTheme.bodySmall),
                Text(
                  'api credentials: '
                  '${TdCredentials.isConfigured ? 'configured' : 'MISSING'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text('waiting for updates…',
                        style: theme.textTheme.bodySmall),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => SelectableText(
                      _lines[index],
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Dev reset. Deletes TDLib's local database so the next launch signs in fresh.
///
/// Never `logOut`: that invalidates the session server-side and burns a login
/// code every time.
Future<void> _confirmReset(BuildContext context) async {
  final auth = AppScope.authOf(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset local session?'),
      content: const Text(
        'Deletes the TDLib database and cached files on this device, then the '
        'app needs a restart.\n\n'
        'This does not sign you out on Telegram\'s side, so no fresh login code '
        'is burned — but you will have to enter a new one to sign back in.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );

  if (confirmed ?? false) await auth.resetLocalSession();
}
