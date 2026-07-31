import 'package:flutter/material.dart';

import '../../telegram/td_options.dart';
import '../app_scope.dart';

/// Two lines of ground truth about the native layer, rendered even when the app
/// cannot get past auth.
///
/// * TDLib version — `getOption("version")` works before `setTdlibParameters`,
///   so a value here proves the isolate round trip is intact.
/// * Local database — a row count means `libsqlite3` loaded and the schema
///   exists. Worth surfacing separately: SQLite arrives through a completely
///   different mechanism (Dart build hooks) than TDLib does, so the two can fail
///   independently.
class DiagnosticsFooter extends StatefulWidget {
  const DiagnosticsFooter({super.key});

  @override
  State<DiagnosticsFooter> createState() => _DiagnosticsFooterState();
}

class _DiagnosticsFooterState extends State<DiagnosticsFooter> {
  String? _tdlib;
  String? _database;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final scope = AppScope.of(context);

    try {
      final version = await scope.client.tdlibVersion();
      if (mounted) {
        setState(() => _tdlib = version == null ? 'TDLib ?' : 'TDLib $version');
      }
    } catch (e) {
      if (mounted) setState(() => _tdlib = 'TDLib unreachable');
    }

    try {
      final count = await scope.channels.countChannels();
      if (mounted) setState(() => _database = 'SQLite ok · $count channels');
    } catch (e) {
      if (mounted) setState(() => _database = 'SQLite failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final lines = [_tdlib, _database].whereType<String>();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final line in lines)
          Text(line, textAlign: TextAlign.center, style: style),
      ],
    );
  }
}
