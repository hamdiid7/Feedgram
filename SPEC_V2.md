# Feedgram — Rework Spec (v2)

Builds on the shipped app. Read the existing README first; this replaces the For You
system, fixes media, and reworks paging and theming.

## Decisions — settled, do not revisit

- **Forward graph is removed entirely.** No discovery mechanism. Every channel is added
  by hand.
- **Two independent channel lists**, each with its own input: `following` and `for_you`.
  A channel may belong to both.
- **Synced Telegram subscriptions land in `following`** by default, never in `for_you`.
- **For You ranking = likes ÷ views**, Bayesian-smoothed, minimum view floor, over a
  **rolling 7-day window**.
- **Following = strict reverse-chronological.** Already correct; do not change its ordering.
- **Paging: 100 on first load, 50 per page thereafter.** Channel profile opens with 50.
- **Hidden from both feeds:** posts containing documents, audio, or voice; posts sent via
  a bot.
- **Video autoplays muted inline; tap plays with sound. GIFs autoplay looped, always muted.**
- **Material 3 with dynamic color.**

---

## Phase 0 — Delete the forward graph

Do this first and alone, so nothing downstream is written against dead code.

Remove: `vouches` table, `vouch_repository.dart`, `for_you_ranking.dart`,
`vouch_repository_sql_test.dart`, `for_you_ranking_test.dart`, the `suggested` channel
source, and any forward-observation logic in the message repository.

Keep `forwarded_from_chat_id` on `messages` — it is cheap and may be wanted for display
("forwarded from X"), just no longer for ranking.

**Checkpoint:** app builds, Following feed still works, For You is an empty placeholder.

---

## Phase 1 — Schema: two-list membership

`source` as a single enum on `channels` no longer expresses the model. Replace with a
membership table:

`channel_lists(chat_id, list_name, added_at)` where `list_name` is `following` | `for_you`,
primary key on both columns.

- Migrate existing rows: everything currently tracked → `following`.
- Index `channel_lists(list_name)`.
- Channel queries join through this table. A channel with no memberships is orphaned —
  either clean it up or leave it as a cache; decide and document which.
- `seed_channels.dart` entries now declare which list(s) they target.

**Checkpoint:** both lists queryable, existing channels intact in `following`.

---

## Phase 2 — Fix image loading

This is the highest-value phase. Symptom: images stay on the blur placeholder forever.
There are several independent causes; fix all of them, they compound.

**Cause 1 — already-downloaded files emit no update.**
When you request a file TDLib has already fetched, it may emit no `updateFile` at all
because the state is already terminal. A cache that only resolves through the update stream
hangs forever on exactly those files.
→ Inspect the `File` object returned by the download call synchronously. If
`local.isDownloadingCompleted` is true and `local.path` is non-empty, resolve immediately.

**Cause 2 — completer registered after the request.**
If the update arrives before the completer is in the map, the resolution is dropped.
→ Register the pending entry **before** issuing the download call.

**Cause 3 — stall reclaim kills live-but-slow transfers.**
20 s wall-clock is short for a large photo on mobile data. The slot is reclaimed while the
transfer is genuinely progressing, and nothing re-queues it.
→ Reset the timeout on *progress* (`local.downloadedSize` increasing), not on wall clock.
Raise the no-progress threshold to ~45 s. Reclaim must always be paired with re-queue.

**Cause 4 — no retry, no terminal error state.**
→ Track a failure count per file. Retry up to 3 times with backoff. After that, mark the
post's media as failed and render a **tap-to-retry** affordance. A blur placeholder must
never be a permanent state; it either resolves or becomes an explicit error.

**Cause 5 — LIFO starvation.**
Continuous scrolling means older queue entries never get a slot.
→ Keep LIFO, but promote any entry older than ~30 s ahead of new arrivals.

**Cause 6 — unfetchable files.**
→ Check `local.canBeDownloaded`. If false, no download will ever occur; surface it as an
error immediately rather than leaving it pending.

**Cause 7 — path exists but file is gone.**
TDLib (or the OS) may evict cached files. A stored path is not proof of existence.
→ Verify the file exists on disk before rendering; if missing, clear and re-download.

**Also:** raise the concurrency bound from 3 to 4–6, and select photo sizes deliberately —
pick the largest size under a width budget (roughly device width × pixel ratio) rather than
the largest available. Oversized originals are a real cause of transfers that never finish.

**Instrumentation:** add per-file state to the debug screen — requested, queued,
downloading with byte progress, complete, failed with reason. Diagnosing this blind is
what made it hard the first time.

**Checkpoint:** scroll a long feed twice on mobile data. Every image either renders or
shows tap-to-retry. Zero permanent blurs.

---

## Phase 3 — Video and GIF playback

**GIFs** — Telegram animations are silent MP4, not GIF. Autoplay looped and muted whenever
visible. They are small; download eagerly like photos.

**Video** — autoplay muted inline when the post is more than ~50% visible. Tap opens
fullscreen with sound and standard controls.

Constraints that will bite:

- Android has a **small number of hardware video decoders**. Never hold more than 2 players
  alive. Maintain one active player for the most-visible video, dispose off-screen players
  immediately, and recycle rather than recreate.
- Autoplay requires the file downloaded. Set a size threshold — autoplay only under
  ~10 MB; larger videos show thumbnail with tap-to-play. Never eagerly download large video.
- Pause all playback when the app backgrounds or the feed tab loses focus.
- Respect the existing 🖼 cheap-mode toggle: it disables video autoplay too.

**Checkpoint:** scroll through a video-heavy channel. No decoder errors, no audio leaking,
no runaway data use.

---

## Phase 4 — Content filtering

**Store everything, filter in SQL.** Do not filter at insert time — you will want to change
these rules without re-backfilling.

Add a `content_kind` column to `messages` (`text`, `photo`, `video`, `animation`,
`document`, `audio`, `voice`, `poll`, `other`) and a boolean `via_bot`.

Feed queries exclude `content_kind IN ('document','audio','voice')` and `via_bot = 1`.

**Bot posts** are posts sent *through* a bot — the via-bot user field on the message.
That is the auto-poster / RSS / ad pattern. Filter on it.

Also tighten channel tracking: only `chatTypeSupergroup` with `is_channel == true` may
enter `channel_lists`. If non-channel dialogs leaked in during earlier syncs, purge them
in the migration.

**Checkpoint:** a channel that posts PDFs and one that uses an auto-poster both show only
their real content.

---

## Phase 5 — Paging and refresh

Applies to Following, For You, and channel profile screens.

- **First load 100**, subsequent pages **50**, profile screens **50** initially.
- Prefetch the next page when the user is within ~10 items of the end. Never wait for the
  actual bottom.
- **Pull-to-refresh** (`RefreshIndicator`, M3 styling): fetches new posts from the network
  for that feed's channels, then re-queries. Not merely a local re-sort.
- Distinguish three states clearly: loading more, nothing more to load, and load failed
  with retry. A silent stop looks like a bug.
- **Following** keeps keyset pagination on `(date, message_id)`. Unchanged.
- **For You** is ordered by score, so it needs its own keyset on `(score, message_id)`.
  This requires the score to be **stored and stable** — see Phase 6. Never use `OFFSET`.
- Fix the known album-splitting bug here: albums straddling a page boundary must merge, so
  buffer trailing incomplete `grouped_id` runs rather than rendering them as separate cards.
   - also load images smartly so it seems simless like loading 5 photos ahed as i scroll

---

## Phase 6 — For You ranking

**Pool:** channels in the `for_you` list only. Never Following-only channels.

**Window:** posts from the last 7 days. Older posts are excluded outright.

**Score:** likes ÷ views, Bayesian-smoothed toward the global mean:

```
score = (likes + k * m) / (views + k)
```

where `m` is the mean likes/views ratio across the window and `k` is a prior weight in
views (start at 500, make it tunable).

**Why smoothing is mandatory:** a raw ratio lets a post with 2 views and 1 like score 0.5
and beat everything real. Fresh posts are the worst case, since reactions land before views
accumulate. Smoothing pulls low-volume posts toward the mean so an extreme score has to be
earned with volume.

**Also apply a hard minimum view floor** (start at 50). Below it, a post does not rank at
all. Belt and braces with the smoothing — both, not one.

`likes` = total reaction count from `interaction_info`. `views` = view count.

**Storage:** persist `score` as a column on `messages`, indexed. Recompute on
`updateMessageInteractionInfo` and after each backfill pass. `m` is recomputed per pass and
cached. Keyset pagination cannot work against a value computed on the fly.

**Keep the per-channel diversity cap.** The existing
`ROW_NUMBER() OVER (PARTITION BY chat_id)` round-robin stays — without it your most
reaction-heavy channel takes the whole page. Cap at 3 per page, never consecutive.

**Tie-break by date descending** so equal scores are at least fresh.

**Checkpoint:** For You's top posts are things you'd actually want. If it's full of
low-view oddities, the floor or `k` is too low — tune before moving on.

---

## Phase 7 — Cold-start refresh ( skip )

On app launch after process death, For You refreshes automatically: fetch new posts for
`for_you` channels, recompute scores, present from the top.

- Distinguish cold start from tab switches and from returning from background. Only a real
  cold start triggers this.
- Show the refresh indicator so it doesn't look like a hang.
- Cap it — if the last refresh was minutes ago, skip. Sequential fetching with FLOOD_WAIT
  respect still applies; a cold start must not become a thundering backfill.
- Following does **not** auto-refresh. It should restore scroll position and the
  caught-up marker instead.

---

## Phase 8 — Channel management ( skip )

Two clearly separated inputs on the Channels screen, one per list. Both accept `name`,
`@name`, `t.me/name`, or a full URL — reuse the existing normalisation.

- Each channel row shows which list(s) it belongs to, with toggles to add or remove from
  either. Removing from both stops tracking.
- Syncing subscriptions adds to `following` only.
- Adding to a list triggers a backfill for that channel.
- Bulk seeding from `seed_channels.dart` respects each entry's declared list.

---

## Phase 9 — Channel profile screen

Opens with 50 posts, pages 50 more on scroll, pull-to-refresh. Header shows avatar, title,
handle, subscriber count, and list-membership toggles. Same content filters as the feeds.

---

## Phase 10 — Material 3 and motion

- `dynamic_color` for wallpaper-derived palettes on Android 12+, with a seeded
  `ColorScheme.fromSeed` fallback. Light and dark both.
- Migrate to M3 components throughout: `NavigationBar`, `FilledButton`, M3 `Card`,
  `SearchBar` for the channel inputs, M3 `RefreshIndicator`.
- Motion, kept purposeful:
  - Staggered fade-and-slide as feed items enter. Subtle, short — under 200 ms.
  - Shimmer on the blur placeholder while media loads, so pending reads as active.
  - Hero transition from channel avatar into the profile screen.
  - Scale-bounce on reaction tap.
  - `AnimatedSwitcher` between tabs; collapsing `SliverAppBar` on scroll.
  - M3 emphasised easing curves, not linear.
- Respect the OS reduce-motion setting: disable decorative animation when it's on.

**Checkpoint:** feels like a current Android app, and nothing animates during scroll that
costs frames.

---

## Cross-cutting requirements

- **Rate limiting is unchanged and non-negotiable.** Full FLOOD_WAIT sleeps, sequential
  backfill, `openChat`/`closeChat` pairing. More paging and a cold-start refresh mean more
  requests — the discipline matters more now, not less.
- **Tests to replace what Phase 0 deletes:** ranking (smoothing, view floor, window,
  diversity cap), content filtering (documents and via-bot excluded), media cache
  (already-complete resolution, progress-based stall reset, retry exhaustion, LIFO aging),
  keyset pagination on both feeds including album boundaries, and the schema migration.
  Keep the practice of compiling every hand-written SQL string against the real schema.
- **No hardcoded credentials, no logging of api_id/api_hash, TDLib log verbosity stays at 1.**
- Small commits, one phase at a time, stop at each checkpoint and wait for confirmation.
