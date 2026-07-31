# Feedgram

Unofficial Telegram **channel feed** client. Turns Telegram channels into one
scrolling social feed instead of a list of chats, backed by a local SQLite cache.
Android only, sideloaded. Built to [SPEC (1).md](<SPEC (1).md>).

Not affiliated with Telegram. Uses the Telegram API via TDLib.

Two feeds:

- **Following** — strict reverse-chronological, every tracked channel merged.
- **For You** — posts from channels you *don't* follow, surfaced via the forward
  graph.

---

## Quick start

```bash
cp td_credentials.example.json td_credentials.json   # gitignored
# fill in TG_API_ID / TG_API_HASH from https://my.telegram.org

flutter run --dart-define-from-file=td_credentials.json
```

Then, in the app: **Channels → ⟳** (sync your subscriptions) → **⬇ Backfill** on
the home screen (pull their posts). The feed is the local database, so it renders
before any network round trip on subsequent starts.

---

## What's built

All seven phases of the spec.

| Phase | | Where |
| --- | --- | --- |
| 1 | Two-isolate TDLib bridge | [lib/telegram/](lib/telegram/) |
| 2 | Auth state machine | [lib/telegram/auth/](lib/telegram/auth/) |
| 3 | Channel discovery + tracking | [channel_repository.dart](lib/data/channel_repository.dart) |
| 4 | Backfill + live sync | [message_repository.dart](lib/data/message_repository.dart) |
| 5 | Following feed | [lib/ui/feed/](lib/ui/feed/) |
| 6 | Albums, reactions, threads | [feed_grouping.dart](lib/domain/feed_grouping.dart), [thread_sheet.dart](lib/ui/feed/thread_sheet.dart) |
| 7 | For You / forward graph | [vouch_repository.dart](lib/data/vouch_repository.dart), [for_you_ranking.dart](lib/domain/for_you_ranking.dart) |

### Layout

| Path | Role |
| --- | --- |
| [lib/telegram/](lib/telegram/) | `TelegramClient` + the two TDLib worker isolates |
| [lib/data/](lib/data/) | drift schema, repositories, TDLib→row mapping |
| [lib/domain/](lib/domain/) | album grouping, For You ranking |
| [lib/ui/](lib/ui/) | feeds, auth flow, channels, debug |
| [lib/config/](lib/config/) | credentials, seed channel list, app identity |

TDLib objects stop at the repository boundary — nothing in `ui/` imports
`handy_tdlib`. That isolation is what would make swapping `handy_tdlib` for
`libtdjson` a contained change.

---

## Architecture notes

### The TDLib bridge

`tdSend` and `tdReceive` both block, so neither ever runs on the UI isolate:

- **invoke isolate** — creates the one client ID, owns every `tdSend`, does all
  `jsonEncode`.
- **receive isolate** — loops on `tdReceive`, does all `convertJsonToObject`, and
  ships finished typed objects to main.

A unique `@extra` on every request, matched against a `Map<String, Completer>`,
turns a fire-and-forget stream into normal `Future`s. Responses arriving *without*
`@extra` are unsolicited updates and go to a broadcast `Stream`.

Both spawns pass `onError`/`onExit` ports plus a 15 s startup deadline — without
them a dead worker is indistinguishable from a hung one, which cost real
debugging time early on.

### Auth

Driven purely by `updateAuthorizationState`; no submit method advances a stage
itself. A restart on a live session lands on `authorizationStateReady` through the
identical code path as a fresh login.

`_apply` is idempotent because TDLib delivers `waitTdlibParameters` **twice** —
once as an update, once as the `getAuthorizationState` response. See
[auth_controller.dart](lib/telegram/auth/auth_controller.dart).

### Schema (v4)

`channels`, `messages`, `vouches` — see [app_database.dart](lib/data/app_database.dart).

Indexes: `channels(source)`, `messages(date, message_id)`,
`messages(chat_id, grouped_id)`, `vouches(target_chat_id)`.

Two things worth knowing:

- **Text spans are precomputed at insert time** into `messages.spans_json`.
  Entity offsets are UTF-16 code units and Dart strings are UTF-16, so they map
  directly. Scrolling never parses entities. See
  [text_segments.dart](lib/data/text_segments.dart).
- **`minithumbnail` is stored inline** in `media_json` — a few hundred bytes TDLib
  already handed over, giving an instant blur placeholder with no file download.

Migrations create their indexes explicitly. `createTable` does *not* create a
table's `@TableIndex` entities, which is why schema v3 exists purely to repair v2.

### Feed queries

Keyset pagination on `(date, message_id)`, never `OFFSET`. All ranking is SQL —
loading candidates into Dart to sort them would defeat the point of the local
database.

For You ranking = vouch strength × subscriber-normalised engagement × post
freshness, with a `ROW_NUMBER() OVER (PARTITION BY chat_id)` round-robin so no
single channel can flood a page. Both of the spec's must-haves are load-bearing
and tested: engagement is normalised by subscriber count (or large channels
dominate permanently) and vouches decay with age (or the feed calcifies around
whatever was popular at seed time).

---

## Adding channels

Three ways in, none of which join the channel:

1. **Your subscriptions** — Channels → ⟳. Uses `loadChats` in a loop; chats
   arrive as `updateNewChat` updates, *not* as a return value, and error 404 is
   the end-of-list signal.
2. **One at a time** — the text field on the Channels screen. Accepts `name`,
   `@name`, `t.me/name`, or a full URL.
3. **In bulk, from code** — edit
   **[lib/config/seed_channels.dart](lib/config/seed_channels.dart)**, then
   Channels → ☰+. It resolves each handle and backfills its posts.

```dart
const seedChannels = <SeedChannel>[
  SeedChannel('bbcworld'),                                     // → Following
  SeedChannel('somechannel', source: ChannelSource.suggested),  // → For You
];
```

`curated` (the default) puts a channel in Following. `suggested` treats it as a
discovery candidate ranked into For You. Seeding also grows For You *indirectly*:
more tracked channels means more forwards observed, and the forward graph is the
only mechanism that discovers new channels at all.

Tap any channel row to see just that channel's posts, with a per-channel history
pull.

---

## Rate limiting

`FLOOD_WAIT` / error 429 sleeps the **full** returned duration, parsed into
`TdException.floodWait`. Backfill is strictly sequential, one channel at a time —
parallel history pulls are the fastest way to get an account flagged. `openChat`
is paired with `closeChat` and capped at 20 concurrent.

Retry policy deliberately lives in the repositories, not in `TelegramClient`: the
wrapper surfaces the wait, the caller decides what is safe to replay.

---

## Bandwidth

The spec calls for text + `minithumbnail` only, with full media strictly on tap.
That default was **changed on request**: feed photos now auto-load as you scroll.

- Photos only. Video and animation stay tap-to-open — they are orders of
  magnitude larger.
- Bounded to 3 concurrent transfers, LIFO so whatever just scrolled into view is
  served first ([media_cache.dart](lib/data/media_cache.dart)).
- Stalled transfers are reclaimed after 20 s, or they would hold a slot forever
  and starve every later image.
- The 🖼 toggle in the home app bar returns to the cheap placeholder-until-tapped
  behaviour. Session-only, not persisted.

---

## Codegen

After changing anything under [lib/data/](lib/data/):

```bash
dart run build_runner build --force-jit --delete-conflicting-outputs
```

**`--force-jit` is required, not optional.** build_runner AOT-compiles its build
script by default, and `dart compile` refuses any dependency graph containing Dart
build hooks — which `sqlite3` 3.x uses to bundle SQLite:

```
'dart compile' does not support build hooks, use 'dart build' instead.
```

JIT mode runs the hooks fine.

### Version pins

These are load-bearing, not tidiness:

| Package | Constraint | Why |
| --- | --- | --- |
| `drift_dev` | `>=2.34.0 <2.35.0` | earlier pins analyzer 7.x, which cannot parse Dart 3.10 (`visitDotShorthandInvocation`) |
| `build_runner` | `>=2.5.0 <2.15.0` | needs `build >=3.0.0` for drift_dev, below the AOT-only versions |

`sqlite3_flutter_libs` is deliberately **absent** — at 0.6.0 it is an empty
deprecated stub, and `sqlite3` 3.x bundles the native library itself via hooks.
Verified present as `lib/<abi>/libsqlite3.so` in both debug and release APKs.

---

## Build

```bash
flutter build apk --release --target-platform android-arm64 \
    --dart-define-from-file=td_credentials.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release is arm64-v8a only; the other ABIs `handy_tdlib` ships are stripped in
[android/app/build.gradle.kts](android/app/build.gradle.kts), halving the APK
(74 MB → 37 MB). `--target-platform` alone does not do this — it filters Flutter's
own libs but not a plugin's prebuilt `jniLibs`, and
`defaultConfig.ndk.abiFilters` loses to the Flutter Gradle plugin.

**Debug keeps every ABI on purpose.** The exclusion pattern also matches Flutter's
own `libflutter.so`, so stripping x86_64 globally leaves an x86_64 emulator with
no engine at all — not just no TDLib.

### Emulator

TDLib and SQLite both run fine on an x86_64 AVD, which claws back the fast
iteration the spec notes you lose without a desktop target:

```bash
flutter emulators --launch <avd-name>
flutter run --dart-define-from-file=td_credentials.json
```

Use a **debug** build; a release build will not start on x86_64.

---

## Credentials

`api_id` / `api_hash` load from `td_credentials.json` (gitignored) via
`--dart-define-from-file`. There is no hardcoded fallback and no logging of
either value; TDLib's own log verbosity is pinned to 1 because higher levels log
request contents, which would put phone numbers and login codes in logcat.

Never commit them, and never use the sample `api_id` from the TDLib source tree —
it triggers `API_ID_PUBLISHED_FLOOD`. `TG_API_ID` must be `> 0`, so the example
file's `"0"` produces a clear "fill in your credentials" screen rather than a
confusing `API_ID_INVALID` from Telegram.

## Dev reset

**Reset local session** on the home screen closes TDLib, deletes its database and
files directories, and asks for a restart. It deliberately does *not* call
`logOut` — that invalidates the session server-side and burns a fresh login code
every time.

The feed cache is a separate database (`files/feed/feed.sqlite`) so it is
independently disposable.

## Debugging

The 🐛 icon opens a raw TDLib update dump with copy-to-clipboard, reachable from
the home screen **and from the auth failure screens** — diagnostics are most
needed when you cannot get past login. Raw capture is off by default so normal
operation does not ship every update across the port twice.

The same screen reports the linked TDLib version and whether SQLite opened, since
the two arrive through completely different mechanisms and can fail
independently.

---

## Tests

62 tests, no device required:

```bash
flutter test
```

| File | Covers |
| --- | --- |
| [vouch_repository_sql_test.dart](test/vouch_repository_sql_test.dart) | compiles + runs **every hand-written SQL string** against the real schema |
| [for_you_ranking_test.dart](test/for_you_ranking_test.dart) | normalisation, decay, diversity cap |
| [text_segments_test.dart](test/text_segments_test.dart) | entity→span mapping, emoji/UTF-16 offsets, nesting |
| [feed_grouping_test.dart](test/feed_grouping_test.dart) | album collapsing |
| [media_cache_test.dart](test/media_cache_test.dart) | dedup, concurrency bound, stall recovery |
| [auth_controller_test.dart](test/auth_controller_test.dart) | duplicate-state idempotency, error retention |
| [auth_mapping_test.dart](test/auth_mapping_test.dart) | code delivery/length, FLOOD_WAIT precedence |
| [channel_username_test.dart](test/channel_username_test.dart) | handle/link normalisation |

The SQL test exists because raw SQL has no type checking — a missing comma
between CTEs is invisible until the feed is opened on a device. That happened
once; the test now catches it.

---

## Known gaps

- **Reactions are wired but unexercised.** Tapping like posts a real, publicly
  visible reaction from your account, so it was never triggered during testing.
  The optimistic write + rollback path is implemented and reviewed, not proven.
- **`messages.thread_id` is vestigial.** `Message.messageThreadId` is populated on
  messages *inside* a discussion group, not on the channel post itself. TDLib
  1.8.36 also has no `message_thread_id` on `MessageReplyInfo`, contrary to the
  spec. The comment button correctly keys off `reply_count` and passes the post's
  own id to `getMessageThreadHistory`.
- **No background sync.** WorkManager is not implemented; cold start runs a
  foreground catch-up, which the spec calls the reliable path anyway. The
  battery-optimisation exemption prompt is also not built.
- **Albums split across a pagination boundary** render as two cards.
- **For You depth is limited by what is readable.** Channels found via forwards
  are often inaccessible (`400: Can't access the chat`) — normal, and skipped
  per-channel.
