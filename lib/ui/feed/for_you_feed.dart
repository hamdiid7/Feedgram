import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import 'chronological_feed.dart';

/// For You — **interim**: the `for_you` channel pool, newest first.
///
/// This is not the final behaviour. Phase 6 replaces the *ordering* with smoothed
/// likes ÷ views over a rolling 7-day window, which needs a stored `score` column
/// because keyset pagination cannot page against a value computed on the fly.
///
/// Until then this reuses [ChronologicalFeed] scoped to the other list, so
/// choosing a channel visibly does something and the membership plumbing is
/// exercised end to end. When Phase 6 lands, only the ordering changes — the
/// pool, the cards, the paging and the album grouping all stay.
class ForYouFeed extends StatelessWidget {
  const ForYouFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Says plainly that this is not ranked yet. A feed that silently orders
        // by date while claiming to be curated is worse than an empty one.
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.schedule,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Newest first — ranking arrives in Phase 6',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const Expanded(
          child: ChronologicalFeed(
            list: ChannelList.forYou,
            emptyMessage: 'No channels in For You yet.\n\n'
                'Open Channels and tap the "For You" chip on the ones you want '
                'ranked here.',
          ),
        ),
      ],
    );
  }
}
