import 'package:flutter/material.dart';

/// Shared frame for the three input steps, so they stay visually identical and
/// each screen only has to supply its field.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.error,
    this.busy = false,
    this.primaryLabel,
    this.onPrimary,
    this.secondary,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Actionable problem from the last submit, e.g. a wrong code.
  final String? error;

  final bool busy;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Optional extra action below the primary button (resend, change number).
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  child,
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (primaryLabel != null)
                    FilledButton(
                      onPressed: busy ? null : onPrimary,
                      child: busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(primaryLabel!),
                    ),
                  if (secondary != null) ...[
                    const SizedBox(height: 8),
                    secondary!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
