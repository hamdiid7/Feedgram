import 'package:drift/drift.dart';

import '../domain/for_you_ranking.dart';
import 'app_database.dart';
import 'message_repository.dart';
import 'post_link.dart';

/// Position in the For You feed.
///
/// Keyed on `(score, message_id)` rather than date, because that is the order the
/// feed is in. `message_id` breaks ties so a page boundary can never land in the
/// middle of a group of equal scores and repeat or skip them.
class ScoreCursor {
  const ScoreCursor({required this.score, required this.messageId});

  final double score;
  final int messageId;
}

/// Scores and serves the For You feed.
class ForYouRepository {
  ForYouRepository({
    required AppDatabase db,
    this.weights = const ForYouWeights(),
  }) : _db = db;

  final AppDatabase _db;
  final ForYouWeights weights;

  /// Cached pooled mean from the last scoring pass.
  ///
  /// Held so a single `updateMessageInteractionInfo` can rescore one row without
  /// re-aggregating the whole window. Lost on restart, which is harmless: the next
  /// full pass recomputes it, and until then per-row updates use the last known
  /// value or 0.
  double _meanRatio = 0;
  double get meanRatio => _meanRatio;

  /// Window start, or 0 when there is no window — `date > 0` then matches
  /// everything, so the same SQL serves both cases.
  int _windowStart(int now) =>
      weights.hasWindow ? now - weights.windowSeconds : 0;

  /// Recomputes `m` and every candidate's score. Run after a backfill or refresh.
  ///
  /// Two passes rather than one statement: `m` is an aggregate over the same rows
  /// being updated, and SQLite cannot both read the aggregate and write the column
  /// in a single `UPDATE` without a subquery per row.
  Future<int> recomputeScores({int? nowSeconds}) async {
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final since = _windowStart(now);

    final totals = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(m.reaction_count), 0) AS likes,
             COALESCE(SUM(m.view_count), 0)     AS views
      FROM messages m
      JOIN channel_lists l
        ON l.chat_id = m.chat_id AND l.list_name = 'for_you'
      WHERE m.date > ?1
        AND m.view_count >= ?2
        -- Only posts that *could* be liked inform the prior. A channel with
        -- reactions off would otherwise drag `m` toward zero and distort every
        -- other score.
        AND m.reaction_count > 0
        AND m.content_kind NOT IN ('document', 'audio', 'voice')
        AND m.via_bot = 0
      ''',
      variables: [Variable.withInt(since), Variable.withInt(weights.minViews)],
      readsFrom: {_db.messages, _db.channelLists},
    ).getSingle();

    _meanRatio = pooledMeanRatio(
      totalLikes: totals.read<int>('likes'),
      totalViews: totals.read<int>('views'),
    );

    final score = forYouScoreSql(
      likes: 'reaction_count',
      views: 'view_count',
      date: 'date',
      nowParam: '?3',
      meanRatio: _meanRatio,
      weights: weights,
    );

    // Scores are written only for rows that actually qualify. Everything else is
    // reset to null so a post that drops out of the window — or below the floor —
    // cannot linger in the ranking on a stale value.
    return _db.customUpdate(
      '''
      UPDATE messages SET score = CASE
        WHEN date > ?1
         AND view_count >= ?2
         AND content_kind NOT IN ('document', 'audio', 'voice')
         AND via_bot = 0
         AND chat_id IN (SELECT chat_id FROM channel_lists
                         WHERE list_name = 'for_you')
        THEN $score
        ELSE NULL
      END
      ''',
      variables: [
        Variable.withInt(since),
        Variable.withInt(weights.minViews),
        Variable.withInt(now),
      ],
      updates: {_db.messages},
    );
  }

  /// Rescores one post after its counters change.
  ///
  /// Uses the cached `m` rather than re-aggregating: interaction updates arrive
  /// constantly while scrolling, and a full pass per update would be absurd. The
  /// prior barely moves between passes, so the approximation is not worth
  /// correcting.
  Future<void> rescoreMessage(int chatId, int messageId,
      {int? nowSeconds}) async {
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final score = forYouScoreSql(
      likes: 'reaction_count',
      views: 'view_count',
      date: 'date',
      nowParam: '?5',
      meanRatio: _meanRatio,
      weights: weights,
    );

    await _db.customUpdate(
      '''
      UPDATE messages SET score = CASE
        WHEN date > ?3
         AND view_count >= ?4
         AND content_kind NOT IN ('document', 'audio', 'voice')
         AND via_bot = 0
         AND chat_id IN (SELECT chat_id FROM channel_lists
                         WHERE list_name = 'for_you')
        THEN $score
        ELSE NULL
      END
      WHERE chat_id = ?1 AND message_id = ?2
      ''',
      variables: [
        Variable.withInt(chatId),
        Variable.withInt(messageId),
        Variable.withInt(_windowStart(now)),
        Variable.withInt(weights.minViews),
        Variable.withInt(now),
      ],
      updates: {_db.messages},
    );
  }

  /// One page of For You, ranked and diversified.
  ///
  /// The `ROW_NUMBER() OVER (PARTITION BY chat_id)` cap is what stops the most
  /// reaction-heavy channel taking the whole page — a real problem measured on live
  /// data before it existed, where one channel held 26 of the top 50 slots.
  /// Ordering by `(rank_in_channel, score DESC)` interleaves the channels, so no
  /// two consecutive cards come from the same one while more than one qualifies.
  ///
  /// A channel with more than [ForYouWeights.maxPerPage] qualifying posts has the
  /// surplus skipped for this page rather than deferred. They mostly reappear
  /// naturally: rank-4 has a lower score than rank-3 by construction, so it usually
  /// falls below the page's cursor and is reconsidered on the next one.
  Future<List<FeedEntry>> page({
    ScoreCursor? after,
    int limit = 50,
    int? nowSeconds,
  }) async {
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final rows = await _db.customSelect(
      '''
      WITH candidates AS (
        SELECT m.*, c.title AS channel_title, c.username AS channel_username,
               c.subscriber_count AS channel_subscribers,
               c.source AS channel_source,
               c.last_synced_message_id AS channel_cursor
        FROM messages m
        JOIN channel_lists l
          ON l.chat_id = m.chat_id AND l.list_name = 'for_you'
        JOIN channels c ON c.id = m.chat_id
        WHERE m.score IS NOT NULL
          AND m.date > ?1
          -- Already shown once. For You is a discovery feed, so repeating itself
          -- is the one thing it must not do.
          AND NOT EXISTS (
            SELECT 1 FROM seen_posts s
            WHERE s.link = CASE
              WHEN c.username IS NOT NULL AND c.username <> ''
                THEN 't.me/' || c.username || '/' || m.message_id
              ELSE 'c/' || m.chat_id || '/' || m.message_id
            END
          )
          AND (?2 = 0 OR m.score < ?3
               OR (m.score = ?3 AND m.message_id < ?4))
      ),
      ranked AS (
        SELECT *, ROW_NUMBER() OVER (
                    PARTITION BY chat_id
                    -- Tie-break by date so equal scores are at least fresh.
                    -- view_count breaks ties inside the zero-reaction block,
                    -- which all scores at the pool mean; date then keeps equals
                    -- fresh.
                    ORDER BY score DESC, view_count DESC, date DESC,
                             message_id DESC
                  ) AS rank_in_channel
        FROM candidates
      )
      SELECT * FROM ranked
      WHERE rank_in_channel <= ?5
      ORDER BY rank_in_channel ASC, score DESC, view_count DESC,
               date DESC, message_id DESC
      LIMIT ?6
      ''',
      variables: [
        Variable.withInt(_windowStart(now)),
        Variable.withInt(after == null ? 0 : 1),
        Variable.withReal(after?.score ?? 0),
        Variable.withInt(after?.messageId ?? 0),
        Variable.withInt(weights.maxPerPage),
        Variable.withInt(limit),
      ],
      readsFrom: {_db.messages, _db.channels, _db.channelLists, _db.seenPosts},
    ).get();

    return [
      for (final row in rows)
        FeedEntry(
          message: _db.messages.map(row.data),
          channel: Channel(
            id: row.read<int>('chat_id'),
            username: row.readNullable<String>('channel_username'),
            title: row.read<String>('channel_title'),
            subscriberCount: row.read<int>('channel_subscribers'),
            lastSyncedMessageId: row.readNullable<int>('channel_cursor'),
            source: ChannelSource.values.firstWhere(
              (s) => s.name == row.read<String>('channel_source'),
              orElse: () => ChannelSource.curated,
            ),
          ),
        ),
    ];
  }

  /// Cursor for the next page: the lowest-ranked row actually returned.
  static ScoreCursor? cursorFrom(List<FeedEntry> page) {
    if (page.isEmpty) return null;
    final last = page.reduce((a, b) {
      final aScore = a.message.score ?? 0;
      final bScore = b.message.score ?? 0;
      if (aScore != bScore) return aScore < bScore ? a : b;
      return a.message.messageId < b.message.messageId ? a : b;
    });
    return ScoreCursor(
      score: last.message.score ?? 0,
      messageId: last.message.messageId,
    );
  }

  /// Records posts as shown, so they never appear in For You again.
  ///
  /// Called as cards are built rather than on a visibility threshold: the
  /// exclusion applies at *query* time, so nothing disappears under the reader's
  /// finger — the effect is only visible on the next load or refresh.
  Future<void> markSeen(Iterable<FeedEntry> entries) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = [
      for (final entry in entries)
        SeenPostsCompanion.insert(
          link: postLink(
            chatId: entry.message.chatId,
            messageId: entry.message.messageId,
            username: entry.channel.username,
          ),
          chatId: entry.message.chatId,
          messageId: entry.message.messageId,
          seenAt: now,
        ),
    ];
    if (rows.isEmpty) return;

    await _db.batch((batch) {
      // Ignore rather than replace: the first sighting is the interesting one.
      batch.insertAll(_db.seenPosts, rows, mode: InsertMode.insertOrIgnore);
    });
  }

  Future<int> countSeen() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n FROM seen_posts',
            readsFrom: {_db.seenPosts})
        .getSingle();
    return row.read<int>('n');
  }

  /// Clears the seen history — the only way back to a feed you have exhausted.
  Future<void> forgetSeen() async {
    await _db.delete(_db.seenPosts).go();
  }

  Future<int> countCandidates({int? nowSeconds}) async {
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM messages WHERE score IS NOT NULL AND date > ?1',
      variables: [Variable.withInt(_windowStart(now))],
      readsFrom: {_db.messages},
    ).getSingle();
    return row.read<int>('n');
  }
}
