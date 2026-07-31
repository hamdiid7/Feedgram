import 'package:flutter/material.dart';

import '../debug/td_debug_screen.dart';
import '../debug/diagnostics_footer.dart';

/// Plain message screen for the auth stages that need no input.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    super.key,
    required this.title,
    this.message,
    this.busy = false,
    this.onRetry,
    this.retryLabel,
    this.showDiagnostics = false,
  });

  final String title;
  final String? message;
  final bool busy;
  final VoidCallback? onRetry;
  final String? retryLabel;

  /// Shows the TDLib version and a link to the raw update dump.
  ///
  /// On for the stages where something has gone wrong — that is precisely when
  /// the debug surface is worth reaching, and it does not require being signed
  /// in.
  final bool showDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(title, style: theme.textTheme.headlineSmall),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(retryLabel ?? 'Retry'),
                ),
              ],
              if (showDiagnostics) ...[
                const SizedBox(height: 32),
                const DiagnosticsFooter(),
                const SizedBox(height: 4),
                TextButton.icon(
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Raw TDLib updates'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TdDebugScreen()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
