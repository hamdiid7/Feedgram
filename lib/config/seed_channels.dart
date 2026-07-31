import '../data/app_database.dart';

/// Default membership for a seed entry: the reverse-chronological timeline.
const defaultSeedLists = <ChannelList>{ChannelList.following};

/// One hand-picked public channel.
class SeedChannel {
  const SeedChannel(
    this.username, {
    this.source = ChannelSource.curated,
    this.lists = defaultSeedLists,
  });

  /// `@name`, `name`, or a `t.me/name` link — all are normalised.
  final String username;

  /// Provenance. Always [ChannelSource.curated] for a hand entry; adding a
  /// channel never joins it.
  final ChannelSource source;

  /// Which feed(s) this channel feeds. Both is allowed.
  ///
  /// * `{ChannelList.following}` — the reverse-chronological timeline.
  /// * `{ChannelList.forYou}` — the ranked feed only.
  /// * both — appears in each.
  final Set<ChannelList> lists;
}

/// **Edit this list.** The seed list for the whole app.
///
/// This exists because the Telegram API has no way to enumerate or crawl public
/// channels — `searchPublicChat` is a username lookup, not discovery. There is no
/// automatic discovery of any kind, so this list and the Channels screen are the
/// only ways a channel enters the app.
///
/// Nothing here is joined: `searchPublicChat` resolves the handle and registers
/// it locally, which is what lets the feed track channels the account does not
/// follow.
///
/// Run it from **Channels → Add seed channels**. It is idempotent, so re-running
/// after editing only adds what is new, and it never downgrades a channel you
/// actually subscribe to.
const seedChannels = <SeedChannel>[
  // --- Replace these with the channels you care about ---------------------
  SeedChannel('bbcworld'),
  SeedChannel('telegram'),
  SeedChannel('TelegramTips'),
  SeedChannel('durov'),

  // Feed the ranked list instead of, or as well as, the timeline:
  //   SeedChannel('somechannel', lists: {ChannelList.forYou}),
  //   SeedChannel('other', lists: {ChannelList.following, ChannelList.forYou}),
];
