# Project: Unofficial Telegram Channel Feed Client

## What we're building

A Flutter app that turns Telegram channels into a single scrolling social feed (Twitter-like)
instead of a list of chats. Each user logs in with their own Telegram account via TDLib.
Posts from subscribed channels **and** arbitrary public channels added by username are pulled
into a local SQLite database. The feed is that database sorted newest-first.

Two feeds:
- **Following** — strict reverse-chronological, all tracked channels merged.
- **For You** — posts from channels the user does *not* follow, surfaced via the forward graph.

## Decisions already made — do not revisit

- **TDLib via the `handy_tdlib` package.** Do NOT compile TDLib from source and do NOT
  hand-write FFI bindings. The package ships prebuilt native libraries and generated typed
  Dart classes for the full TDLib API. Import its `lib/api.dart` **with a prefix** (e.g.
  `as td`) — several of its object names collide with `dart:io` and Flutter.
- **Android only.** Target is a sideloaded APK, not the Play Store. `handy_tdlib` supports
  Android exclusively, so there is no desktop build. `minSdk` per the package requirement;
  build `arm64-v8a` only unless there's a reason not to.
- **Local SQLite** via `drift`. All feed logic is SQL, not Dart list manipulation.
- **Auth stays on-device.** No backend of any kind. Phone codes and 2FA passwords never
  leave the machine.

## Hard constraints

- `api_id` / `api_hash` load from a gitignored local config file or env vars.
  **Never hardcode them, never commit them, never log them.** Never use the sample
  api_id shipped with TDLib source — it triggers `API_ID_PUBLISHED_FLOOD`.
- Respect `FLOOD_WAIT` / TDLib error 429 by sleeping the **full** returned duration.
  Backfill sequentially, one channel at a time. Do not parallelize history pulls —
  that pattern gets accounts flagged.
- Handle deletion and edit updates so the cache never serves removed posts.

---

## Build in phases. Stop at each checkpoint and confirm before continuing.

### Phase 1 — Package setup + isolate architecture
Add `handy_tdlib` to `pubspec.yaml`. Confirm the app builds and installs on a real device
before writing any logic.

The package handles the native layer, but the threading model is still on you and it is the
one thing that must be right from the start:

- **Never touch TDLib from the UI isolate.** Both `tdSend` and `tdReceive` plus all
  JSON/object conversion must run off the main thread or the feed will visibly stutter.
- Get the client ID once via the plugin's create-client-id call, on the invokes isolate.
- Run two isolates: one looping on receive and forwarding results to subscribers, one
  handling outgoing invokes. Pass the client ID between them. Wire them with
  `SendPort`/`ReceivePort` pairs.
- Do object conversion (`convertJsonToObject`) on the worker isolate, never on main.
- Attach a unique `@extra` value to every outgoing request. TDLib echoes it back on the
  matching response. Keep a `Map<String, Completer>` so callers get normal `Future`s over
  what is really a fire-and-forget stream.
- Responses arriving **without** `@extra` are unsolicited updates → push to a broadcast
  `Stream` that repositories subscribe to.

Wrap all of this behind one `TelegramClient` class exposing `Future`-returning methods and
an update `Stream`. Nothing outside that class should know isolates exist.

**Checkpoint:** on a real device, request the TDLib version option and display it in the UI.
Nothing else until this works.

### Phase 2 — Auth
State machine driven purely by `updateAuthorizationState`:

`waitTdlibParameters` → `setTdlibParameters` (api_id, api_hash, database dir, files dir,
`use_message_database: true`, `use_secret_chats: false`) → `waitPhoneNumber` →
`setAuthenticationPhoneNumber` → `waitCode` → `checkAuthenticationCode` →
`waitPassword` (only if 2FA enabled) → `checkAuthenticationPassword` → `ready`.

Notes:
- Session persists in the database dir. Restarts land directly on `ready`.
- Older TDLib versions add a separate `checkDatabaseEncryptionKey` step — handle if present.
- For dev resets, delete the local database dir. Do **not** call `logOut` (invalidates
  the session server-side and burns a fresh login code).

**Checkpoint:** log in, restart the app, confirm it resumes without asking for a code.

### Phase 3 — Channel discovery and tracking
Schema: `channels(id, username, title, subscriber_count, last_synced_message_id, source)`
where `source` is `subscribed` | `curated` | `suggested`.

Two paths in:
- **Subscribed:** `loadChats(chatList: main, limit: 100)` in a loop until it returns
  error 404, which means end of list. **Chats arrive as `updateNewChat` updates, not as a
  return value** — this is the single most common mistake. Filter to `chatTypeSupergroup`
  with `is_channel == true`.
- **Curated:** `searchPublicChat(username)` resolves any public channel and registers it
  locally **without joining**. Handle not-found and private-channel errors per channel so
  one dead username never kills the whole sync pass.

### Phase 4 — Backfill and live sync
`getChatHistory(chat_id, from_message_id, offset, limit, only_local: false)`.

- The first call on a fresh channel returns few or zero rows because TDLib checks local
  cache first. **Call again.** Never treat a short result as end-of-history.
- `openChat(chat_id)` subscribes to live `updateNewMessage` for that chat. Pair with
  `closeChat` — do not leave hundreds open. Open only what's actively syncing.
- Persist to `messages(chat_id, message_id, date, grouped_id, text, entities_json,
  media_json, view_count, reaction_count, forward_count, forwarded_from_chat_id)`.
  Index on `date DESC` and on `(chat_id, message_id)`.
- Subscribe to `updateNewMessage`, `updateMessageEdited`, `updateDeleteMessages`,
  `updateMessageInteractionInfo` and apply each to the local store.

### Phase 5 — Following feed UI
Virtualized list over `SELECT ... ORDER BY date DESC` with keyset pagination on `date`.

- Render Telegram message `entities` into `TextSpan`. Offsets are UTF-16 code units and
  Dart strings are UTF-16, so they map directly — no conversion needed.
  **Precompute spans at insert time and cache them.** Never parse entities during scroll.
- Images: decode the `minithumbnail` base64 as an instant blur placeholder, then
  `downloadFile` and watch `updateFile` for `local.path` once `is_downloading_completed`.
- TDLib refreshes `file_reference` internally, so expiry is not your problem.

**Checkpoint:** a scrolling merged timeline with text and single photos. This is the MVP.

### Phase 6 — Albums, reactions, threads
- Group consecutive messages sharing a non-zero `grouped_id` into one carousel card.
- `addMessageReaction` for likes; reaction counts come from `interaction_info`.
- Comment threads: `interaction_info.reply_info.message_thread_id` →
  `getMessageThreadHistory`. This is the linked discussion group and the closest thing
  Telegram has to replies.

### Phase 7 — For You feed
Build the forward graph. Every post with `forwarded_from_chat_id` pointing at a channel
not in `channels` is a **vouch** from a channel the user trusts.

Table: `vouches(source_chat_id, target_chat_id, first_seen, last_seen, count)`.

Rank candidate posts by: number of distinct vouching channels, recency of those vouches,
and engagement relative to channel size.

Two things that must be right or the feed degrades:
- **Normalize engagement by subscriber count**, or large channels dominate permanently.
- **Decay old vouches**, or the feed calcifies around whatever was popular at seed time.

Surface unfollowed channels with repeated vouches as `suggested` in the channel list.

---

## Android specifics

- **Database location.** Keep the TDLib database and files directories inside the app's own
  private storage (`getApplicationDocumentsDirectory` / app support dir). Only if you place
  them elsewhere do you need external-storage permissions — avoid that entirely.
- **Background sync.** Android dozes the device and kills the process, so the feed goes
  stale unless sync is scheduled as periodic background work (WorkManager via a Flutter
  wrapper). Expect the OS to ignore short intervals; ~15 minutes is the realistic floor.
  On cold start, always run a foreground catch-up sync rather than trusting background runs.
- **Battery optimization** will suppress background sync on many Ethiopian-market devices
  with aggressive OEM battery managers. Surface a one-time prompt asking the user to exempt
  the app, and treat background sync as best-effort, never as guaranteed.
- **Bandwidth matters.** On first backfill, fetch text and `minithumbnail` only. Download
  full-size media strictly on tap. This also makes FLOOD_WAIT throttling cheap.
- **APK output:** `flutter build apk --release --target-platform android-arm64`.
  Install via `adb install` or copy the file to the device and allow unknown sources.
  No signing key beyond the debug/local keystore is needed for personal sideloading.
- **Debugging loss.** Without a desktop target you lose fast iteration, so lean harder on
  logging every TDLib update to a file you can pull off the device with `adb`. Build a
  hidden debug screen that dumps recent raw updates — it will save hours.

## Known limits — build around them, don't try to solve them

- There is **no way to enumerate or crawl public channels.** `searchPublicChat` and
  `searchPublicChats` are username/title lookups, not discovery. The channel list is
  always seeded by hand and grown via the forward graph. Cold start is unavoidable.
- Private channels require a real invite, same as normal Telegram.
- Un-joined channels still deliver live updates via `openChat`, but if that proves
  unreliable, fall back to polling with `last_synced_message_id` as the delta marker.

## If this is ever published (not needed for personal use)

Telegram's API ToS requires third-party clients to make all basic features of the official
apps work correctly. A feed-only reader does not qualify — publishing means adding real
messaging (chats, sending, replies). Also required: app name must not contain "Telegram"
unless prefixed with "Unofficial", no official logo, prominent disclosure that the app uses
the Telegram API, and in-app report/block/mute for user-generated content.

## Working agreement

- Small commits, one phase at a time. Stop at each checkpoint and wait for confirmation.
- Repository layout: `telegram/` (client wrapper + isolates), `data/` (drift schema + repos),
  `domain/` (feed ranking), `ui/` (feeds + auth flow). Keep TDLib objects out of the UI layer —
  map them to your own models at the repository boundary.
- When a TDLib call behaves unexpectedly, check the typed classes in the installed
  `handy_tdlib` version rather than guessing field names. The package tracks a specific
  TDLib version; if a method or field you expect is missing, that version is the reason.
  Check the package's changelog and GitHub before assuming your usage is wrong.
- `handy_tdlib` is a community package with a small maintainer base. If it turns out to be
  blocking (stale TDLib version, unfixed bug), the fallback is `libtdjson` — which needs
  `GITHUB_ACTOR` and `GITHUB_TOKEN` env vars to fetch prebuilt Android libraries from its
  GitHub Maven repo. Isolating everything behind the `TelegramClient` wrapper is what makes
  that swap cheap, so do not leak package types past it.
