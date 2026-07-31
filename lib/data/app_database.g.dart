// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChannelsTable extends Channels with TableInfo<$ChannelsTable, Channel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _subscriberCountMeta = const VerificationMeta(
    'subscriberCount',
  );
  @override
  late final GeneratedColumn<int> subscriberCount = GeneratedColumn<int>(
    'subscriber_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSyncedMessageIdMeta =
      const VerificationMeta('lastSyncedMessageId');
  @override
  late final GeneratedColumn<int> lastSyncedMessageId = GeneratedColumn<int>(
    'last_synced_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChannelSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ChannelSource>($ChannelsTable.$convertersource);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    username,
    title,
    subscriberCount,
    lastSyncedMessageId,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<Channel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('subscriber_count')) {
      context.handle(
        _subscriberCountMeta,
        subscriberCount.isAcceptableOrUnknown(
          data['subscriber_count']!,
          _subscriberCountMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_message_id')) {
      context.handle(
        _lastSyncedMessageIdMeta,
        lastSyncedMessageId.isAcceptableOrUnknown(
          data['last_synced_message_id']!,
          _lastSyncedMessageIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Channel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Channel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subscriberCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subscriber_count'],
      )!,
      lastSyncedMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_synced_message_id'],
      ),
      source: $ChannelsTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChannelSource, String, String> $convertersource =
      const EnumNameConverter<ChannelSource>(ChannelSource.values);
}

class Channel extends DataClass implements Insertable<Channel> {
  /// TDLib chat ID. Channels get large negative IDs (-100…), which is why this
  /// is a 64-bit integer and not an unsigned anything.
  final int id;

  /// Public @username, absent for private channels reached via invite.
  final String? username;
  final String title;
  final int subscriberCount;

  /// Backfill cursor for Phase 4 — the newest message already persisted.
  /// Deliberately preserved across re-syncs; see `ChannelRepository`.
  final int? lastSyncedMessageId;
  final ChannelSource source;
  const Channel({
    required this.id,
    this.username,
    required this.title,
    required this.subscriberCount,
    this.lastSyncedMessageId,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['title'] = Variable<String>(title);
    map['subscriber_count'] = Variable<int>(subscriberCount);
    if (!nullToAbsent || lastSyncedMessageId != null) {
      map['last_synced_message_id'] = Variable<int>(lastSyncedMessageId);
    }
    {
      map['source'] = Variable<String>(
        $ChannelsTable.$convertersource.toSql(source),
      );
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      id: Value(id),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      title: Value(title),
      subscriberCount: Value(subscriberCount),
      lastSyncedMessageId: lastSyncedMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedMessageId),
      source: Value(source),
    );
  }

  factory Channel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Channel(
      id: serializer.fromJson<int>(json['id']),
      username: serializer.fromJson<String?>(json['username']),
      title: serializer.fromJson<String>(json['title']),
      subscriberCount: serializer.fromJson<int>(json['subscriberCount']),
      lastSyncedMessageId: serializer.fromJson<int?>(
        json['lastSyncedMessageId'],
      ),
      source: $ChannelsTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'username': serializer.toJson<String?>(username),
      'title': serializer.toJson<String>(title),
      'subscriberCount': serializer.toJson<int>(subscriberCount),
      'lastSyncedMessageId': serializer.toJson<int?>(lastSyncedMessageId),
      'source': serializer.toJson<String>(
        $ChannelsTable.$convertersource.toJson(source),
      ),
    };
  }

  Channel copyWith({
    int? id,
    Value<String?> username = const Value.absent(),
    String? title,
    int? subscriberCount,
    Value<int?> lastSyncedMessageId = const Value.absent(),
    ChannelSource? source,
  }) => Channel(
    id: id ?? this.id,
    username: username.present ? username.value : this.username,
    title: title ?? this.title,
    subscriberCount: subscriberCount ?? this.subscriberCount,
    lastSyncedMessageId: lastSyncedMessageId.present
        ? lastSyncedMessageId.value
        : this.lastSyncedMessageId,
    source: source ?? this.source,
  );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      title: data.title.present ? data.title.value : this.title,
      subscriberCount: data.subscriberCount.present
          ? data.subscriberCount.value
          : this.subscriberCount,
      lastSyncedMessageId: data.lastSyncedMessageId.present
          ? data.lastSyncedMessageId.value
          : this.lastSyncedMessageId,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('title: $title, ')
          ..write('subscriberCount: $subscriberCount, ')
          ..write('lastSyncedMessageId: $lastSyncedMessageId, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    username,
    title,
    subscriberCount,
    lastSyncedMessageId,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.id == this.id &&
          other.username == this.username &&
          other.title == this.title &&
          other.subscriberCount == this.subscriberCount &&
          other.lastSyncedMessageId == this.lastSyncedMessageId &&
          other.source == this.source);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<int> id;
  final Value<String?> username;
  final Value<String> title;
  final Value<int> subscriberCount;
  final Value<int?> lastSyncedMessageId;
  final Value<ChannelSource> source;
  const ChannelsCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.title = const Value.absent(),
    this.subscriberCount = const Value.absent(),
    this.lastSyncedMessageId = const Value.absent(),
    this.source = const Value.absent(),
  });
  ChannelsCompanion.insert({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.title = const Value.absent(),
    this.subscriberCount = const Value.absent(),
    this.lastSyncedMessageId = const Value.absent(),
    required ChannelSource source,
  }) : source = Value(source);
  static Insertable<Channel> custom({
    Expression<int>? id,
    Expression<String>? username,
    Expression<String>? title,
    Expression<int>? subscriberCount,
    Expression<int>? lastSyncedMessageId,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (title != null) 'title': title,
      if (subscriberCount != null) 'subscriber_count': subscriberCount,
      if (lastSyncedMessageId != null)
        'last_synced_message_id': lastSyncedMessageId,
      if (source != null) 'source': source,
    });
  }

  ChannelsCompanion copyWith({
    Value<int>? id,
    Value<String?>? username,
    Value<String>? title,
    Value<int>? subscriberCount,
    Value<int?>? lastSyncedMessageId,
    Value<ChannelSource>? source,
  }) {
    return ChannelsCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      title: title ?? this.title,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      lastSyncedMessageId: lastSyncedMessageId ?? this.lastSyncedMessageId,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subscriberCount.present) {
      map['subscriber_count'] = Variable<int>(subscriberCount.value);
    }
    if (lastSyncedMessageId.present) {
      map['last_synced_message_id'] = Variable<int>(lastSyncedMessageId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $ChannelsTable.$convertersource.toSql(source.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('title: $title, ')
          ..write('subscriberCount: $subscriberCount, ')
          ..write('lastSyncedMessageId: $lastSyncedMessageId, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channels (id)',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupedIdMeta = const VerificationMeta(
    'groupedId',
  );
  @override
  late final GeneratedColumn<int> groupedId = GeneratedColumn<int>(
    'grouped_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _entitiesJsonMeta = const VerificationMeta(
    'entitiesJson',
  );
  @override
  late final GeneratedColumn<String> entitiesJson = GeneratedColumn<String>(
    'entities_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _spansJsonMeta = const VerificationMeta(
    'spansJson',
  );
  @override
  late final GeneratedColumn<String> spansJson = GeneratedColumn<String>(
    'spans_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaJsonMeta = const VerificationMeta(
    'mediaJson',
  );
  @override
  late final GeneratedColumn<String> mediaJson = GeneratedColumn<String>(
    'media_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _viewCountMeta = const VerificationMeta(
    'viewCount',
  );
  @override
  late final GeneratedColumn<int> viewCount = GeneratedColumn<int>(
    'view_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reactionCountMeta = const VerificationMeta(
    'reactionCount',
  );
  @override
  late final GeneratedColumn<int> reactionCount = GeneratedColumn<int>(
    'reaction_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _forwardCountMeta = const VerificationMeta(
    'forwardCount',
  );
  @override
  late final GeneratedColumn<int> forwardCount = GeneratedColumn<int>(
    'forward_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _forwardedFromChatIdMeta =
      const VerificationMeta('forwardedFromChatId');
  @override
  late final GeneratedColumn<int> forwardedFromChatId = GeneratedColumn<int>(
    'forwarded_from_chat_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _editDateMeta = const VerificationMeta(
    'editDate',
  );
  @override
  late final GeneratedColumn<int> editDate = GeneratedColumn<int>(
    'edit_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<int> threadId = GeneratedColumn<int>(
    'thread_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyCountMeta = const VerificationMeta(
    'replyCount',
  );
  @override
  late final GeneratedColumn<int> replyCount = GeneratedColumn<int>(
    'reply_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chosenReactionMeta = const VerificationMeta(
    'chosenReaction',
  );
  @override
  late final GeneratedColumn<String> chosenReaction = GeneratedColumn<String>(
    'chosen_reaction',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    chatId,
    messageId,
    date,
    groupedId,
    body,
    entitiesJson,
    spansJson,
    mediaJson,
    viewCount,
    reactionCount,
    forwardCount,
    forwardedFromChatId,
    editDate,
    threadId,
    replyCount,
    chosenReaction,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('grouped_id')) {
      context.handle(
        _groupedIdMeta,
        groupedId.isAcceptableOrUnknown(data['grouped_id']!, _groupedIdMeta),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['text']!, _bodyMeta),
      );
    }
    if (data.containsKey('entities_json')) {
      context.handle(
        _entitiesJsonMeta,
        entitiesJson.isAcceptableOrUnknown(
          data['entities_json']!,
          _entitiesJsonMeta,
        ),
      );
    }
    if (data.containsKey('spans_json')) {
      context.handle(
        _spansJsonMeta,
        spansJson.isAcceptableOrUnknown(data['spans_json']!, _spansJsonMeta),
      );
    }
    if (data.containsKey('media_json')) {
      context.handle(
        _mediaJsonMeta,
        mediaJson.isAcceptableOrUnknown(data['media_json']!, _mediaJsonMeta),
      );
    }
    if (data.containsKey('view_count')) {
      context.handle(
        _viewCountMeta,
        viewCount.isAcceptableOrUnknown(data['view_count']!, _viewCountMeta),
      );
    }
    if (data.containsKey('reaction_count')) {
      context.handle(
        _reactionCountMeta,
        reactionCount.isAcceptableOrUnknown(
          data['reaction_count']!,
          _reactionCountMeta,
        ),
      );
    }
    if (data.containsKey('forward_count')) {
      context.handle(
        _forwardCountMeta,
        forwardCount.isAcceptableOrUnknown(
          data['forward_count']!,
          _forwardCountMeta,
        ),
      );
    }
    if (data.containsKey('forwarded_from_chat_id')) {
      context.handle(
        _forwardedFromChatIdMeta,
        forwardedFromChatId.isAcceptableOrUnknown(
          data['forwarded_from_chat_id']!,
          _forwardedFromChatIdMeta,
        ),
      );
    }
    if (data.containsKey('edit_date')) {
      context.handle(
        _editDateMeta,
        editDate.isAcceptableOrUnknown(data['edit_date']!, _editDateMeta),
      );
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    }
    if (data.containsKey('reply_count')) {
      context.handle(
        _replyCountMeta,
        replyCount.isAcceptableOrUnknown(data['reply_count']!, _replyCountMeta),
      );
    }
    if (data.containsKey('chosen_reaction')) {
      context.handle(
        _chosenReactionMeta,
        chosenReaction.isAcceptableOrUnknown(
          data['chosen_reaction']!,
          _chosenReactionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chatId, messageId};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chat_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      groupedId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}grouped_id'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      entitiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entities_json'],
      ),
      spansJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spans_json'],
      ),
      mediaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_json'],
      ),
      viewCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}view_count'],
      )!,
      reactionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reaction_count'],
      )!,
      forwardCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}forward_count'],
      )!,
      forwardedFromChatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}forwarded_from_chat_id'],
      ),
      editDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}edit_date'],
      ),
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}thread_id'],
      ),
      replyCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reply_count'],
      )!,
      chosenReaction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chosen_reaction'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int chatId;
  final int messageId;

  /// Unix seconds. The feed's sort key.
  final int date;

  /// TDLib's `media_album_id`, null when the post is not part of an album.
  /// Phase 6 groups consecutive posts sharing one of these into a carousel.
  final int? groupedId;

  /// Plain text with no markup, for previews and future search.
  ///
  /// The Dart getter is `body` but the SQL column stays `text`: a getter named
  /// `text` would shadow drift's own `text()` column builder inside this class,
  /// and drift then fails to resolve the table at all.
  final String body;

  /// Raw TDLib entities, kept so spans can be rebuilt if the renderer changes.
  final String? entitiesJson;

  /// **Precomputed** render segments — flattened, non-overlapping, ready to map
  /// straight onto `TextSpan`s. Built once at insert time precisely so that
  /// nothing parses entities during scroll.
  final String? spansJson;

  /// Media descriptor including the inline `minithumbnail`. Full-size files are
  /// only ever downloaded on tap, which keeps backfill cheap on mobile data.
  final String? mediaJson;
  final int viewCount;
  final int reactionCount;
  final int forwardCount;

  /// Set when this post is a forward from another channel. The Phase 7 forward
  /// graph is built entirely from this column.
  final int? forwardedFromChatId;

  /// Non-null once TDLib reports the post was edited.
  final int? editDate;

  /// Linked-discussion thread, when the channel has comments enabled.
  ///
  /// Comes from `Message.messageThreadId`, **not** from
  /// `interaction_info.reply_info` — TDLib 1.8.36 has no `message_thread_id` on
  /// `MessageReplyInfo`.
  final int? threadId;

  /// Comment count, from `interaction_info.reply_info.reply_count`.
  final int replyCount;

  /// The emoji this account reacted with, if any. Drives the like toggle.
  final String? chosenReaction;
  const Message({
    required this.chatId,
    required this.messageId,
    required this.date,
    this.groupedId,
    required this.body,
    this.entitiesJson,
    this.spansJson,
    this.mediaJson,
    required this.viewCount,
    required this.reactionCount,
    required this.forwardCount,
    this.forwardedFromChatId,
    this.editDate,
    this.threadId,
    required this.replyCount,
    this.chosenReaction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chat_id'] = Variable<int>(chatId);
    map['message_id'] = Variable<int>(messageId);
    map['date'] = Variable<int>(date);
    if (!nullToAbsent || groupedId != null) {
      map['grouped_id'] = Variable<int>(groupedId);
    }
    map['text'] = Variable<String>(body);
    if (!nullToAbsent || entitiesJson != null) {
      map['entities_json'] = Variable<String>(entitiesJson);
    }
    if (!nullToAbsent || spansJson != null) {
      map['spans_json'] = Variable<String>(spansJson);
    }
    if (!nullToAbsent || mediaJson != null) {
      map['media_json'] = Variable<String>(mediaJson);
    }
    map['view_count'] = Variable<int>(viewCount);
    map['reaction_count'] = Variable<int>(reactionCount);
    map['forward_count'] = Variable<int>(forwardCount);
    if (!nullToAbsent || forwardedFromChatId != null) {
      map['forwarded_from_chat_id'] = Variable<int>(forwardedFromChatId);
    }
    if (!nullToAbsent || editDate != null) {
      map['edit_date'] = Variable<int>(editDate);
    }
    if (!nullToAbsent || threadId != null) {
      map['thread_id'] = Variable<int>(threadId);
    }
    map['reply_count'] = Variable<int>(replyCount);
    if (!nullToAbsent || chosenReaction != null) {
      map['chosen_reaction'] = Variable<String>(chosenReaction);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      chatId: Value(chatId),
      messageId: Value(messageId),
      date: Value(date),
      groupedId: groupedId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupedId),
      body: Value(body),
      entitiesJson: entitiesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(entitiesJson),
      spansJson: spansJson == null && nullToAbsent
          ? const Value.absent()
          : Value(spansJson),
      mediaJson: mediaJson == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaJson),
      viewCount: Value(viewCount),
      reactionCount: Value(reactionCount),
      forwardCount: Value(forwardCount),
      forwardedFromChatId: forwardedFromChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(forwardedFromChatId),
      editDate: editDate == null && nullToAbsent
          ? const Value.absent()
          : Value(editDate),
      threadId: threadId == null && nullToAbsent
          ? const Value.absent()
          : Value(threadId),
      replyCount: Value(replyCount),
      chosenReaction: chosenReaction == null && nullToAbsent
          ? const Value.absent()
          : Value(chosenReaction),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      chatId: serializer.fromJson<int>(json['chatId']),
      messageId: serializer.fromJson<int>(json['messageId']),
      date: serializer.fromJson<int>(json['date']),
      groupedId: serializer.fromJson<int?>(json['groupedId']),
      body: serializer.fromJson<String>(json['body']),
      entitiesJson: serializer.fromJson<String?>(json['entitiesJson']),
      spansJson: serializer.fromJson<String?>(json['spansJson']),
      mediaJson: serializer.fromJson<String?>(json['mediaJson']),
      viewCount: serializer.fromJson<int>(json['viewCount']),
      reactionCount: serializer.fromJson<int>(json['reactionCount']),
      forwardCount: serializer.fromJson<int>(json['forwardCount']),
      forwardedFromChatId: serializer.fromJson<int?>(
        json['forwardedFromChatId'],
      ),
      editDate: serializer.fromJson<int?>(json['editDate']),
      threadId: serializer.fromJson<int?>(json['threadId']),
      replyCount: serializer.fromJson<int>(json['replyCount']),
      chosenReaction: serializer.fromJson<String?>(json['chosenReaction']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chatId': serializer.toJson<int>(chatId),
      'messageId': serializer.toJson<int>(messageId),
      'date': serializer.toJson<int>(date),
      'groupedId': serializer.toJson<int?>(groupedId),
      'body': serializer.toJson<String>(body),
      'entitiesJson': serializer.toJson<String?>(entitiesJson),
      'spansJson': serializer.toJson<String?>(spansJson),
      'mediaJson': serializer.toJson<String?>(mediaJson),
      'viewCount': serializer.toJson<int>(viewCount),
      'reactionCount': serializer.toJson<int>(reactionCount),
      'forwardCount': serializer.toJson<int>(forwardCount),
      'forwardedFromChatId': serializer.toJson<int?>(forwardedFromChatId),
      'editDate': serializer.toJson<int?>(editDate),
      'threadId': serializer.toJson<int?>(threadId),
      'replyCount': serializer.toJson<int>(replyCount),
      'chosenReaction': serializer.toJson<String?>(chosenReaction),
    };
  }

  Message copyWith({
    int? chatId,
    int? messageId,
    int? date,
    Value<int?> groupedId = const Value.absent(),
    String? body,
    Value<String?> entitiesJson = const Value.absent(),
    Value<String?> spansJson = const Value.absent(),
    Value<String?> mediaJson = const Value.absent(),
    int? viewCount,
    int? reactionCount,
    int? forwardCount,
    Value<int?> forwardedFromChatId = const Value.absent(),
    Value<int?> editDate = const Value.absent(),
    Value<int?> threadId = const Value.absent(),
    int? replyCount,
    Value<String?> chosenReaction = const Value.absent(),
  }) => Message(
    chatId: chatId ?? this.chatId,
    messageId: messageId ?? this.messageId,
    date: date ?? this.date,
    groupedId: groupedId.present ? groupedId.value : this.groupedId,
    body: body ?? this.body,
    entitiesJson: entitiesJson.present ? entitiesJson.value : this.entitiesJson,
    spansJson: spansJson.present ? spansJson.value : this.spansJson,
    mediaJson: mediaJson.present ? mediaJson.value : this.mediaJson,
    viewCount: viewCount ?? this.viewCount,
    reactionCount: reactionCount ?? this.reactionCount,
    forwardCount: forwardCount ?? this.forwardCount,
    forwardedFromChatId: forwardedFromChatId.present
        ? forwardedFromChatId.value
        : this.forwardedFromChatId,
    editDate: editDate.present ? editDate.value : this.editDate,
    threadId: threadId.present ? threadId.value : this.threadId,
    replyCount: replyCount ?? this.replyCount,
    chosenReaction: chosenReaction.present
        ? chosenReaction.value
        : this.chosenReaction,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      date: data.date.present ? data.date.value : this.date,
      groupedId: data.groupedId.present ? data.groupedId.value : this.groupedId,
      body: data.body.present ? data.body.value : this.body,
      entitiesJson: data.entitiesJson.present
          ? data.entitiesJson.value
          : this.entitiesJson,
      spansJson: data.spansJson.present ? data.spansJson.value : this.spansJson,
      mediaJson: data.mediaJson.present ? data.mediaJson.value : this.mediaJson,
      viewCount: data.viewCount.present ? data.viewCount.value : this.viewCount,
      reactionCount: data.reactionCount.present
          ? data.reactionCount.value
          : this.reactionCount,
      forwardCount: data.forwardCount.present
          ? data.forwardCount.value
          : this.forwardCount,
      forwardedFromChatId: data.forwardedFromChatId.present
          ? data.forwardedFromChatId.value
          : this.forwardedFromChatId,
      editDate: data.editDate.present ? data.editDate.value : this.editDate,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      replyCount: data.replyCount.present
          ? data.replyCount.value
          : this.replyCount,
      chosenReaction: data.chosenReaction.present
          ? data.chosenReaction.value
          : this.chosenReaction,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('chatId: $chatId, ')
          ..write('messageId: $messageId, ')
          ..write('date: $date, ')
          ..write('groupedId: $groupedId, ')
          ..write('body: $body, ')
          ..write('entitiesJson: $entitiesJson, ')
          ..write('spansJson: $spansJson, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('viewCount: $viewCount, ')
          ..write('reactionCount: $reactionCount, ')
          ..write('forwardCount: $forwardCount, ')
          ..write('forwardedFromChatId: $forwardedFromChatId, ')
          ..write('editDate: $editDate, ')
          ..write('threadId: $threadId, ')
          ..write('replyCount: $replyCount, ')
          ..write('chosenReaction: $chosenReaction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    chatId,
    messageId,
    date,
    groupedId,
    body,
    entitiesJson,
    spansJson,
    mediaJson,
    viewCount,
    reactionCount,
    forwardCount,
    forwardedFromChatId,
    editDate,
    threadId,
    replyCount,
    chosenReaction,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.chatId == this.chatId &&
          other.messageId == this.messageId &&
          other.date == this.date &&
          other.groupedId == this.groupedId &&
          other.body == this.body &&
          other.entitiesJson == this.entitiesJson &&
          other.spansJson == this.spansJson &&
          other.mediaJson == this.mediaJson &&
          other.viewCount == this.viewCount &&
          other.reactionCount == this.reactionCount &&
          other.forwardCount == this.forwardCount &&
          other.forwardedFromChatId == this.forwardedFromChatId &&
          other.editDate == this.editDate &&
          other.threadId == this.threadId &&
          other.replyCount == this.replyCount &&
          other.chosenReaction == this.chosenReaction);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> chatId;
  final Value<int> messageId;
  final Value<int> date;
  final Value<int?> groupedId;
  final Value<String> body;
  final Value<String?> entitiesJson;
  final Value<String?> spansJson;
  final Value<String?> mediaJson;
  final Value<int> viewCount;
  final Value<int> reactionCount;
  final Value<int> forwardCount;
  final Value<int?> forwardedFromChatId;
  final Value<int?> editDate;
  final Value<int?> threadId;
  final Value<int> replyCount;
  final Value<String?> chosenReaction;
  final Value<int> rowid;
  const MessagesCompanion({
    this.chatId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.date = const Value.absent(),
    this.groupedId = const Value.absent(),
    this.body = const Value.absent(),
    this.entitiesJson = const Value.absent(),
    this.spansJson = const Value.absent(),
    this.mediaJson = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.reactionCount = const Value.absent(),
    this.forwardCount = const Value.absent(),
    this.forwardedFromChatId = const Value.absent(),
    this.editDate = const Value.absent(),
    this.threadId = const Value.absent(),
    this.replyCount = const Value.absent(),
    this.chosenReaction = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required int chatId,
    required int messageId,
    required int date,
    this.groupedId = const Value.absent(),
    this.body = const Value.absent(),
    this.entitiesJson = const Value.absent(),
    this.spansJson = const Value.absent(),
    this.mediaJson = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.reactionCount = const Value.absent(),
    this.forwardCount = const Value.absent(),
    this.forwardedFromChatId = const Value.absent(),
    this.editDate = const Value.absent(),
    this.threadId = const Value.absent(),
    this.replyCount = const Value.absent(),
    this.chosenReaction = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : chatId = Value(chatId),
       messageId = Value(messageId),
       date = Value(date);
  static Insertable<Message> custom({
    Expression<int>? chatId,
    Expression<int>? messageId,
    Expression<int>? date,
    Expression<int>? groupedId,
    Expression<String>? body,
    Expression<String>? entitiesJson,
    Expression<String>? spansJson,
    Expression<String>? mediaJson,
    Expression<int>? viewCount,
    Expression<int>? reactionCount,
    Expression<int>? forwardCount,
    Expression<int>? forwardedFromChatId,
    Expression<int>? editDate,
    Expression<int>? threadId,
    Expression<int>? replyCount,
    Expression<String>? chosenReaction,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chatId != null) 'chat_id': chatId,
      if (messageId != null) 'message_id': messageId,
      if (date != null) 'date': date,
      if (groupedId != null) 'grouped_id': groupedId,
      if (body != null) 'text': body,
      if (entitiesJson != null) 'entities_json': entitiesJson,
      if (spansJson != null) 'spans_json': spansJson,
      if (mediaJson != null) 'media_json': mediaJson,
      if (viewCount != null) 'view_count': viewCount,
      if (reactionCount != null) 'reaction_count': reactionCount,
      if (forwardCount != null) 'forward_count': forwardCount,
      if (forwardedFromChatId != null)
        'forwarded_from_chat_id': forwardedFromChatId,
      if (editDate != null) 'edit_date': editDate,
      if (threadId != null) 'thread_id': threadId,
      if (replyCount != null) 'reply_count': replyCount,
      if (chosenReaction != null) 'chosen_reaction': chosenReaction,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? chatId,
    Value<int>? messageId,
    Value<int>? date,
    Value<int?>? groupedId,
    Value<String>? body,
    Value<String?>? entitiesJson,
    Value<String?>? spansJson,
    Value<String?>? mediaJson,
    Value<int>? viewCount,
    Value<int>? reactionCount,
    Value<int>? forwardCount,
    Value<int?>? forwardedFromChatId,
    Value<int?>? editDate,
    Value<int?>? threadId,
    Value<int>? replyCount,
    Value<String?>? chosenReaction,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      date: date ?? this.date,
      groupedId: groupedId ?? this.groupedId,
      body: body ?? this.body,
      entitiesJson: entitiesJson ?? this.entitiesJson,
      spansJson: spansJson ?? this.spansJson,
      mediaJson: mediaJson ?? this.mediaJson,
      viewCount: viewCount ?? this.viewCount,
      reactionCount: reactionCount ?? this.reactionCount,
      forwardCount: forwardCount ?? this.forwardCount,
      forwardedFromChatId: forwardedFromChatId ?? this.forwardedFromChatId,
      editDate: editDate ?? this.editDate,
      threadId: threadId ?? this.threadId,
      replyCount: replyCount ?? this.replyCount,
      chosenReaction: chosenReaction ?? this.chosenReaction,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (groupedId.present) {
      map['grouped_id'] = Variable<int>(groupedId.value);
    }
    if (body.present) {
      map['text'] = Variable<String>(body.value);
    }
    if (entitiesJson.present) {
      map['entities_json'] = Variable<String>(entitiesJson.value);
    }
    if (spansJson.present) {
      map['spans_json'] = Variable<String>(spansJson.value);
    }
    if (mediaJson.present) {
      map['media_json'] = Variable<String>(mediaJson.value);
    }
    if (viewCount.present) {
      map['view_count'] = Variable<int>(viewCount.value);
    }
    if (reactionCount.present) {
      map['reaction_count'] = Variable<int>(reactionCount.value);
    }
    if (forwardCount.present) {
      map['forward_count'] = Variable<int>(forwardCount.value);
    }
    if (forwardedFromChatId.present) {
      map['forwarded_from_chat_id'] = Variable<int>(forwardedFromChatId.value);
    }
    if (editDate.present) {
      map['edit_date'] = Variable<int>(editDate.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<int>(threadId.value);
    }
    if (replyCount.present) {
      map['reply_count'] = Variable<int>(replyCount.value);
    }
    if (chosenReaction.present) {
      map['chosen_reaction'] = Variable<String>(chosenReaction.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('chatId: $chatId, ')
          ..write('messageId: $messageId, ')
          ..write('date: $date, ')
          ..write('groupedId: $groupedId, ')
          ..write('body: $body, ')
          ..write('entitiesJson: $entitiesJson, ')
          ..write('spansJson: $spansJson, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('viewCount: $viewCount, ')
          ..write('reactionCount: $reactionCount, ')
          ..write('forwardCount: $forwardCount, ')
          ..write('forwardedFromChatId: $forwardedFromChatId, ')
          ..write('editDate: $editDate, ')
          ..write('threadId: $threadId, ')
          ..write('replyCount: $replyCount, ')
          ..write('chosenReaction: $chosenReaction, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelListsTable extends ChannelLists
    with TableInfo<$ChannelListsTable, ChannelMembership> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channels (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChannelList, String> listName =
      GeneratedColumn<String>(
        'list_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ChannelList>($ChannelListsTable.$converterlistName);
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [chatId, listName, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChannelMembership> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chatId, listName};
  @override
  ChannelMembership map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelMembership(
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chat_id'],
      )!,
      listName: $ChannelListsTable.$converterlistName.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}list_name'],
        )!,
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $ChannelListsTable createAlias(String alias) {
    return $ChannelListsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChannelList, String, String> $converterlistName =
      const ChannelListConverter();
}

class ChannelMembership extends DataClass
    implements Insertable<ChannelMembership> {
  final int chatId;
  final ChannelList listName;

  /// When it joined this list. Lets a future "recently added" view exist, and
  /// makes a migrated row distinguishable from a deliberate one by timestamp.
  final int addedAt;
  const ChannelMembership({
    required this.chatId,
    required this.listName,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chat_id'] = Variable<int>(chatId);
    {
      map['list_name'] = Variable<String>(
        $ChannelListsTable.$converterlistName.toSql(listName),
      );
    }
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  ChannelListsCompanion toCompanion(bool nullToAbsent) {
    return ChannelListsCompanion(
      chatId: Value(chatId),
      listName: Value(listName),
      addedAt: Value(addedAt),
    );
  }

  factory ChannelMembership.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelMembership(
      chatId: serializer.fromJson<int>(json['chatId']),
      listName: $ChannelListsTable.$converterlistName.fromJson(
        serializer.fromJson<String>(json['listName']),
      ),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chatId': serializer.toJson<int>(chatId),
      'listName': serializer.toJson<String>(
        $ChannelListsTable.$converterlistName.toJson(listName),
      ),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  ChannelMembership copyWith({
    int? chatId,
    ChannelList? listName,
    int? addedAt,
  }) => ChannelMembership(
    chatId: chatId ?? this.chatId,
    listName: listName ?? this.listName,
    addedAt: addedAt ?? this.addedAt,
  );
  ChannelMembership copyWithCompanion(ChannelListsCompanion data) {
    return ChannelMembership(
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      listName: data.listName.present ? data.listName.value : this.listName,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelMembership(')
          ..write('chatId: $chatId, ')
          ..write('listName: $listName, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(chatId, listName, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelMembership &&
          other.chatId == this.chatId &&
          other.listName == this.listName &&
          other.addedAt == this.addedAt);
}

class ChannelListsCompanion extends UpdateCompanion<ChannelMembership> {
  final Value<int> chatId;
  final Value<ChannelList> listName;
  final Value<int> addedAt;
  final Value<int> rowid;
  const ChannelListsCompanion({
    this.chatId = const Value.absent(),
    this.listName = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelListsCompanion.insert({
    required int chatId,
    required ChannelList listName,
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : chatId = Value(chatId),
       listName = Value(listName),
       addedAt = Value(addedAt);
  static Insertable<ChannelMembership> custom({
    Expression<int>? chatId,
    Expression<String>? listName,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chatId != null) 'chat_id': chatId,
      if (listName != null) 'list_name': listName,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelListsCompanion copyWith({
    Value<int>? chatId,
    Value<ChannelList>? listName,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return ChannelListsCompanion(
      chatId: chatId ?? this.chatId,
      listName: listName ?? this.listName,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (listName.present) {
      map['list_name'] = Variable<String>(
        $ChannelListsTable.$converterlistName.toSql(listName.value),
      );
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelListsCompanion(')
          ..write('chatId: $chatId, ')
          ..write('listName: $listName, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $ChannelListsTable channelLists = $ChannelListsTable(this);
  late final Index channelsSource = Index(
    'channels_source',
    'CREATE INDEX channels_source ON channels (source)',
  );
  late final Index messagesDate = Index(
    'messages_date',
    'CREATE INDEX messages_date ON messages (date, message_id)',
  );
  late final Index messagesGrouped = Index(
    'messages_grouped',
    'CREATE INDEX messages_grouped ON messages (chat_id, grouped_id)',
  );
  late final Index channelListsName = Index(
    'channel_lists_name',
    'CREATE INDEX channel_lists_name ON channel_lists (list_name)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    channels,
    messages,
    channelLists,
    channelsSource,
    messagesDate,
    messagesGrouped,
    channelListsName,
  ];
}

typedef $$ChannelsTableCreateCompanionBuilder =
    ChannelsCompanion Function({
      Value<int> id,
      Value<String?> username,
      Value<String> title,
      Value<int> subscriberCount,
      Value<int?> lastSyncedMessageId,
      required ChannelSource source,
    });
typedef $$ChannelsTableUpdateCompanionBuilder =
    ChannelsCompanion Function({
      Value<int> id,
      Value<String?> username,
      Value<String> title,
      Value<int> subscriberCount,
      Value<int?> lastSyncedMessageId,
      Value<ChannelSource> source,
    });

final class $$ChannelsTableReferences
    extends BaseReferences<_$AppDatabase, $ChannelsTable, Channel> {
  $$ChannelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'channels__id__messages__chat_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.chatId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChannelListsTable, List<ChannelMembership>>
  _channelListsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.channelLists,
    aliasName: 'channels__id__channel_lists__chat_id',
  );

  $$ChannelListsTableProcessedTableManager get channelListsRefs {
    final manager = $$ChannelListsTableTableManager(
      $_db,
      $_db.channelLists,
    ).filter((f) => f.chatId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_channelListsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subscriberCount => $composableBuilder(
    column: $table.subscriberCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncedMessageId => $composableBuilder(
    column: $table.lastSyncedMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChannelSource, ChannelSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> channelListsRefs(
    Expression<bool> Function($$ChannelListsTableFilterComposer f) f,
  ) {
    final $$ChannelListsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.channelLists,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelListsTableFilterComposer(
            $db: $db,
            $table: $db.channelLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subscriberCount => $composableBuilder(
    column: $table.subscriberCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncedMessageId => $composableBuilder(
    column: $table.lastSyncedMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get subscriberCount => $composableBuilder(
    column: $table.subscriberCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncedMessageId => $composableBuilder(
    column: $table.lastSyncedMessageId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ChannelSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> channelListsRefs<T extends Object>(
    Expression<T> Function($$ChannelListsTableAnnotationComposer a) f,
  ) {
    final $$ChannelListsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.channelLists,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelListsTableAnnotationComposer(
            $db: $db,
            $table: $db.channelLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChannelsTable,
          Channel,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (Channel, $$ChannelsTableReferences),
          Channel,
          PrefetchHooks Function({bool messagesRefs, bool channelListsRefs})
        > {
  $$ChannelsTableTableManager(_$AppDatabase db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> subscriberCount = const Value.absent(),
                Value<int?> lastSyncedMessageId = const Value.absent(),
                Value<ChannelSource> source = const Value.absent(),
              }) => ChannelsCompanion(
                id: id,
                username: username,
                title: title,
                subscriberCount: subscriberCount,
                lastSyncedMessageId: lastSyncedMessageId,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> subscriberCount = const Value.absent(),
                Value<int?> lastSyncedMessageId = const Value.absent(),
                required ChannelSource source,
              }) => ChannelsCompanion.insert(
                id: id,
                username: username,
                title: title,
                subscriberCount: subscriberCount,
                lastSyncedMessageId: lastSyncedMessageId,
                source: source,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChannelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({messagesRefs = false, channelListsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messagesRefs) db.messages,
                    if (channelListsRefs) db.channelLists,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          Channel,
                          $ChannelsTable,
                          Message
                        >(
                          currentTable: table,
                          referencedTable: $$ChannelsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.chatId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (channelListsRefs)
                        await $_getPrefetchedData<
                          Channel,
                          $ChannelsTable,
                          ChannelMembership
                        >(
                          currentTable: table,
                          referencedTable: $$ChannelsTableReferences
                              ._channelListsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).channelListsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.chatId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChannelsTable,
      Channel,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (Channel, $$ChannelsTableReferences),
      Channel,
      PrefetchHooks Function({bool messagesRefs, bool channelListsRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required int chatId,
      required int messageId,
      required int date,
      Value<int?> groupedId,
      Value<String> body,
      Value<String?> entitiesJson,
      Value<String?> spansJson,
      Value<String?> mediaJson,
      Value<int> viewCount,
      Value<int> reactionCount,
      Value<int> forwardCount,
      Value<int?> forwardedFromChatId,
      Value<int?> editDate,
      Value<int?> threadId,
      Value<int> replyCount,
      Value<String?> chosenReaction,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> chatId,
      Value<int> messageId,
      Value<int> date,
      Value<int?> groupedId,
      Value<String> body,
      Value<String?> entitiesJson,
      Value<String?> spansJson,
      Value<String?> mediaJson,
      Value<int> viewCount,
      Value<int> reactionCount,
      Value<int> forwardCount,
      Value<int?> forwardedFromChatId,
      Value<int?> editDate,
      Value<int?> threadId,
      Value<int> replyCount,
      Value<String?> chosenReaction,
      Value<int> rowid,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _chatIdTable(_$AppDatabase db) =>
      db.channels.createAlias('messages__chat_id__channels__id');

  $$ChannelsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<int>('chat_id')!;

    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get groupedId => $composableBuilder(
    column: $table.groupedId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entitiesJson => $composableBuilder(
    column: $table.entitiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spansJson => $composableBuilder(
    column: $table.spansJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reactionCount => $composableBuilder(
    column: $table.reactionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get forwardCount => $composableBuilder(
    column: $table.forwardCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get forwardedFromChatId => $composableBuilder(
    column: $table.forwardedFromChatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get editDate => $composableBuilder(
    column: $table.editDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chosenReaction => $composableBuilder(
    column: $table.chosenReaction,
    builder: (column) => ColumnFilters(column),
  );

  $$ChannelsTableFilterComposer get chatId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get groupedId => $composableBuilder(
    column: $table.groupedId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entitiesJson => $composableBuilder(
    column: $table.entitiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spansJson => $composableBuilder(
    column: $table.spansJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reactionCount => $composableBuilder(
    column: $table.reactionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get forwardCount => $composableBuilder(
    column: $table.forwardCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get forwardedFromChatId => $composableBuilder(
    column: $table.forwardedFromChatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get editDate => $composableBuilder(
    column: $table.editDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chosenReaction => $composableBuilder(
    column: $table.chosenReaction,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChannelsTableOrderingComposer get chatId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get groupedId =>
      $composableBuilder(column: $table.groupedId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get entitiesJson => $composableBuilder(
    column: $table.entitiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get spansJson =>
      $composableBuilder(column: $table.spansJson, builder: (column) => column);

  GeneratedColumn<String> get mediaJson =>
      $composableBuilder(column: $table.mediaJson, builder: (column) => column);

  GeneratedColumn<int> get viewCount =>
      $composableBuilder(column: $table.viewCount, builder: (column) => column);

  GeneratedColumn<int> get reactionCount => $composableBuilder(
    column: $table.reactionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get forwardCount => $composableBuilder(
    column: $table.forwardCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get forwardedFromChatId => $composableBuilder(
    column: $table.forwardedFromChatId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get editDate =>
      $composableBuilder(column: $table.editDate, builder: (column) => column);

  GeneratedColumn<int> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chosenReaction => $composableBuilder(
    column: $table.chosenReaction,
    builder: (column) => column,
  );

  $$ChannelsTableAnnotationComposer get chatId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool chatId})
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> chatId = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<int?> groupedId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> entitiesJson = const Value.absent(),
                Value<String?> spansJson = const Value.absent(),
                Value<String?> mediaJson = const Value.absent(),
                Value<int> viewCount = const Value.absent(),
                Value<int> reactionCount = const Value.absent(),
                Value<int> forwardCount = const Value.absent(),
                Value<int?> forwardedFromChatId = const Value.absent(),
                Value<int?> editDate = const Value.absent(),
                Value<int?> threadId = const Value.absent(),
                Value<int> replyCount = const Value.absent(),
                Value<String?> chosenReaction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                chatId: chatId,
                messageId: messageId,
                date: date,
                groupedId: groupedId,
                body: body,
                entitiesJson: entitiesJson,
                spansJson: spansJson,
                mediaJson: mediaJson,
                viewCount: viewCount,
                reactionCount: reactionCount,
                forwardCount: forwardCount,
                forwardedFromChatId: forwardedFromChatId,
                editDate: editDate,
                threadId: threadId,
                replyCount: replyCount,
                chosenReaction: chosenReaction,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int chatId,
                required int messageId,
                required int date,
                Value<int?> groupedId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> entitiesJson = const Value.absent(),
                Value<String?> spansJson = const Value.absent(),
                Value<String?> mediaJson = const Value.absent(),
                Value<int> viewCount = const Value.absent(),
                Value<int> reactionCount = const Value.absent(),
                Value<int> forwardCount = const Value.absent(),
                Value<int?> forwardedFromChatId = const Value.absent(),
                Value<int?> editDate = const Value.absent(),
                Value<int?> threadId = const Value.absent(),
                Value<int> replyCount = const Value.absent(),
                Value<String?> chosenReaction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                chatId: chatId,
                messageId: messageId,
                date: date,
                groupedId: groupedId,
                body: body,
                entitiesJson: entitiesJson,
                spansJson: spansJson,
                mediaJson: mediaJson,
                viewCount: viewCount,
                reactionCount: reactionCount,
                forwardCount: forwardCount,
                forwardedFromChatId: forwardedFromChatId,
                editDate: editDate,
                threadId: threadId,
                replyCount: replyCount,
                chosenReaction: chosenReaction,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chatId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chatId,
                                referencedTable: $$MessagesTableReferences
                                    ._chatIdTable(db),
                                referencedColumn: $$MessagesTableReferences
                                    ._chatIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool chatId})
    >;
typedef $$ChannelListsTableCreateCompanionBuilder =
    ChannelListsCompanion Function({
      required int chatId,
      required ChannelList listName,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$ChannelListsTableUpdateCompanionBuilder =
    ChannelListsCompanion Function({
      Value<int> chatId,
      Value<ChannelList> listName,
      Value<int> addedAt,
      Value<int> rowid,
    });

final class $$ChannelListsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ChannelListsTable, ChannelMembership> {
  $$ChannelListsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _chatIdTable(_$AppDatabase db) =>
      db.channels.createAlias('channel_lists__chat_id__channels__id');

  $$ChannelsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<int>('chat_id')!;

    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChannelListsTableFilterComposer
    extends Composer<_$AppDatabase, $ChannelListsTable> {
  $$ChannelListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<ChannelList, ChannelList, String>
  get listName => $composableBuilder(
    column: $table.listName,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChannelsTableFilterComposer get chatId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChannelListsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChannelListsTable> {
  $$ChannelListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get listName => $composableBuilder(
    column: $table.listName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChannelsTableOrderingComposer get chatId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChannelListsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChannelListsTable> {
  $$ChannelListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<ChannelList, String> get listName =>
      $composableBuilder(column: $table.listName, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$ChannelsTableAnnotationComposer get chatId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChannelListsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChannelListsTable,
          ChannelMembership,
          $$ChannelListsTableFilterComposer,
          $$ChannelListsTableOrderingComposer,
          $$ChannelListsTableAnnotationComposer,
          $$ChannelListsTableCreateCompanionBuilder,
          $$ChannelListsTableUpdateCompanionBuilder,
          (ChannelMembership, $$ChannelListsTableReferences),
          ChannelMembership,
          PrefetchHooks Function({bool chatId})
        > {
  $$ChannelListsTableTableManager(_$AppDatabase db, $ChannelListsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> chatId = const Value.absent(),
                Value<ChannelList> listName = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelListsCompanion(
                chatId: chatId,
                listName: listName,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int chatId,
                required ChannelList listName,
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChannelListsCompanion.insert(
                chatId: chatId,
                listName: listName,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChannelListsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chatId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chatId,
                                referencedTable: $$ChannelListsTableReferences
                                    ._chatIdTable(db),
                                referencedColumn: $$ChannelListsTableReferences
                                    ._chatIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChannelListsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChannelListsTable,
      ChannelMembership,
      $$ChannelListsTableFilterComposer,
      $$ChannelListsTableOrderingComposer,
      $$ChannelListsTableAnnotationComposer,
      $$ChannelListsTableCreateCompanionBuilder,
      $$ChannelListsTableUpdateCompanionBuilder,
      (ChannelMembership, $$ChannelListsTableReferences),
      ChannelMembership,
      PrefetchHooks Function({bool chatId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$ChannelListsTableTableManager get channelLists =>
      $$ChannelListsTableTableManager(_db, _db.channelLists);
}
