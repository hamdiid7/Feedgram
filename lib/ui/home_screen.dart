import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'channels/channels_screen.dart';
import 'debug/td_debug_screen.dart';
import 'feed/chronological_feed.dart';
import 'feed/for_you_feed.dart';

/// The app shell. Phase 5's deliverable: a merged, scrolling, newest-first
/// timeline over every tracked channel.
///
/// "For You" arrives in Phase 7; its tab is present but empty so the structure
/// is visible.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _backfilling = false;
  String? _progress;

  Future<void> _backfill() async {
    setState(() {
      _backfilling = true;
      _progress = 'Starting…';
    });

    try {
      final total = await AppScope.messagesOf(context).backfillAll(
        perChannel: 40,
        onProgress: (done, all) {
          if (mounted) setState(() => _progress = 'Channel $done of $all');
        },
      );
      if (mounted) setState(() => _progress = 'Pulled $total posts.');
    } catch (e) {
      if (mounted) setState(() => _progress = 'Backfill failed: $e');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Feedgram'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Following'),
              Tab(text: 'For You'),
            ],
          ),
          actions: [
            IconButton(
              icon: _backfilling
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              tooltip: 'Backfill posts',
              onPressed: _backfilling ? null : _backfill,
            ),
            IconButton(
              icon: Icon(AppScope.autoLoadImagesOf(context)
                  ? Icons.image_outlined
                  : Icons.image_not_supported_outlined),
              tooltip: AppScope.autoLoadImagesOf(context)
                  ? 'Auto-load images: on'
                  : 'Auto-load images: off (tap to load)',
              onPressed: () => AppScope.setAutoLoadImages(
                context,
                !AppScope.autoLoadImagesOf(context),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.rss_feed),
              tooltip: 'Channels',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChannelsScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'TDLib debug',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TdDebugScreen()),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  _progress!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Expanded(
              child: TabBarView(
                children: [
                  ChronologicalFeed(),
                  ForYouFeed(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
