import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'app_database.dart';
import 'text_segments.dart';

/// The renderable part of a post: everything derived purely from its content.
///
/// Split out from [messageToRow] because an edit arrives as a bare
/// `MessageContent` with no surrounding `Message`, and both paths must produce
/// spans identically — otherwise edited posts would render differently from
/// fresh ones.
class MessageContentFields {
  const MessageContentFields({
    required this.text,
    required this.entitiesJson,
    required this.spansJson,
    required this.mediaJson,
    required this.kind,
  });

  final String text;
  final String? entitiesJson;
  final String? spansJson;
  final String? mediaJson;

  /// Recomputed on edit: an edit can change what a post *is* (text becomes a
  /// photo), and a stale kind would leave it filtered wrongly.
  final ContentKind kind;
}

MessageContentFields contentFieldsOf(td.MessageContent content) {
  final formatted = _formattedTextOf(content);
  final text = formatted?.text ?? '';
  final entities = formatted?.entities ?? const <td.TextEntity>[];

  return MessageContentFields(
    text: text,
    entitiesJson: entities.isEmpty
        ? null
        : jsonEncode([for (final e in entities) e.toJson()]),
    // Precomputed here, once, so scrolling never parses entities.
    spansJson:
        text.isEmpty ? null : encodeSegments(buildTextSegments(text, entities)),
    mediaJson: _encodeMedia(content),
    kind: contentKindOf(content),
  );
}

/// Converts a TDLib `Message` into a row. The last place TDLib types appear on
/// the write path.
MessagesCompanion messageToRow(td.Message message) {
  final fields = contentFieldsOf(message.content);
  final info = message.interactionInfo;

  return MessagesCompanion.insert(
    chatId: message.chatId,
    messageId: message.id,
    date: message.date,
    // TDLib uses 0 for "not in an album"; null models that honestly.
    groupedId: Value(message.mediaAlbumId == 0 ? null : message.mediaAlbumId),
    body: Value(fields.text),
    entitiesJson: Value(fields.entitiesJson),
    spansJson: Value(fields.spansJson),
    mediaJson: Value(fields.mediaJson),
    viewCount: Value(info?.viewCount ?? 0),
    reactionCount: Value(_reactionCount(info)),
    forwardCount: Value(info?.forwardCount ?? 0),
    forwardedFromChatId: Value(_forwardedFromChatId(message.forwardInfo)),
    editDate: Value(message.editDate == 0 ? null : message.editDate),
    // Thread id comes off the message, not off reply_info — TDLib 1.8.36 has no
    // message_thread_id on MessageReplyInfo.
    threadId: Value(message.messageThreadId == 0 ? null : message.messageThreadId),
    replyCount: Value(info?.replyInfo?.replyCount ?? 0),
    chosenReaction: Value(chosenReactionOf(info)),
    contentKind: Value(contentKindOf(message.content)),
    // Non-zero means an inline bot sent it — auto-posters, RSS bridges, ads.
    viaBot: Value(message.viaBotUserId != 0),
  );
}

/// Classifies a post for the feed filters.
///
/// The document case is the interesting one. Telegram routinely delivers GIFs and
/// short clips as `messageDocument` rather than `messageAnimation`/`messageVideo`,
/// so classifying purely on the TDLib content type would file real content as
/// "document" and the feed filter would then hide it. The mime type is the
/// reliable signal, with the filename as a fallback for the servers that send
/// `application/octet-stream`.
ContentKind contentKindOf(td.MessageContent content) => switch (content) {
      td.MessageText() => ContentKind.text,
      td.MessagePhoto() => ContentKind.photo,
      td.MessageVideo() => ContentKind.video,
      td.MessageAnimation() => ContentKind.animation,
      td.MessageAudio() => ContentKind.audio,
      td.MessageVoiceNote() => ContentKind.voice,
      td.MessagePoll() => ContentKind.poll,
      td.MessageDocument(:final document) => _documentKind(document),
      _ => ContentKind.other,
    };

ContentKind _documentKind(td.Document document) {
  final mime = document.mimeType.toLowerCase();
  final name = document.fileName.toLowerCase();

  if (mime == 'image/gif' || name.endsWith('.gif')) return ContentKind.animation;
  if (mime.startsWith('video/') || name.endsWith('.mp4')) {
    return ContentKind.video;
  }
  if (mime.startsWith('audio/')) return ContentKind.audio;
  return ContentKind.document;
}

/// Text and caption live on different content types; both are the same thing to
/// the feed.
td.FormattedText? _formattedTextOf(td.MessageContent content) =>
    switch (content) {
      td.MessageText(:final text) => text,
      td.MessagePhoto(:final caption) => caption,
      td.MessageVideo(:final caption) => caption,
      td.MessageAnimation(:final caption) => caption,
      td.MessageDocument(:final caption) => caption,
      td.MessageAudio(:final caption) => caption,
      td.MessageVoiceNote(:final caption) => caption,
      _ => null,
    };

/// The emoji this account reacted with, if any.
///
/// Only plain emoji reactions are represented; custom and paid reactions have no
/// emoji string to store, so they read as "not reacted" rather than showing
/// something wrong.
String? chosenReactionOf(td.MessageInteractionInfo? info) {
  final reactions = info?.reactions?.reactions;
  if (reactions == null) return null;
  for (final reaction in reactions) {
    if (!reaction.isChosen) continue;
    final type = reaction.type;
    if (type is td.ReactionTypeEmoji) return type.emoji;
  }
  return null;
}

int _reactionCount(td.MessageInteractionInfo? info) {
  final reactions = info?.reactions?.reactions;
  if (reactions == null) return 0;
  return reactions.fold(0, (sum, r) => sum + r.totalCount);
}

/// Only forwards *from a channel* are recorded. Kept for display
/// ("forwarded from X") — it no longer feeds any ranking.
int? _forwardedFromChatId(td.MessageForwardInfo? info) => switch (info?.origin) {
      td.MessageOriginChannel(:final chatId) => chatId,
      _ => null,
    };

/// Media descriptor with the `minithumbnail` inlined.
///
/// The thumbnail is a few hundred bytes of JPEG that TDLib already handed us, so
/// storing it costs nothing and gives the feed an instant blurred placeholder
/// with no file download at all.
///
/// **Two identifiers are stored per file, and the difference matters.** `fileId`
/// is TDLib's *local* handle — fast to use, but only meaningful to the TDLib
/// instance that issued it. Rows written by an earlier run hold stale ones, and
/// `downloadFile` answers `400: Invalid file identifier`, which presents as an
/// image stuck on its placeholder forever. `remote` is the persistent id, good
/// across restarts, resolved back to a live local id via `getRemoteFile`.
String? _encodeMedia(td.MessageContent content) {
  Map<String, dynamic>? media;

  switch (content) {
    case td.MessagePhoto(:final photo):
      final largest = _largestPhotoSize(photo.sizes);
      media = {
        'type': 'photo',
        if (photo.minithumbnail != null) ...{
          'thumb': photo.minithumbnail!.data,
          'tw': photo.minithumbnail!.width,
          'th': photo.minithumbnail!.height,
        },
        if (largest != null) ...{
          'fileId': largest.photo.id,
          'remote': largest.photo.remote.id,
          'w': largest.width,
          'h': largest.height,
        },
        // Every available size, so the renderer can pick the smallest one that
        // still fills the screen. Choosing here would bake in one device's pixel
        // ratio and could never be revised without re-backfilling — and fetching
        // a 2560px original to draw it 400px wide is a real cause of transfers
        // that never finish.
        'sizes': [
          for (final size in photo.sizes)
            {
              'id': size.photo.id,
              'remote': size.photo.remote.id,
              'w': size.width,
              'h': size.height,
            },
        ],
      };

    case td.MessageVideo(:final video):
      media = {
        'type': 'video',
        if (video.minithumbnail != null) ...{
          'thumb': video.minithumbnail!.data,
          'tw': video.minithumbnail!.width,
          'th': video.minithumbnail!.height,
        },
        'fileId': video.video.id,
        'remote': video.video.remote.id,
        'w': video.width,
        'h': video.height,
        'duration': video.duration,
        // A real JPEG poster, not the 32px minithumbnail. Shown instead of a blur
        // whenever the video is not playing.
        if (video.thumbnail != null) ...{
          'posterId': video.thumbnail!.file.id,
          'posterRemote': video.thumbnail!.file.remote.id,
        },
        // Telegram marks files whose moov atom is at the front. Those can be
        // played from a partial prefix; the rest need the whole file.
        'streamable': video.supportsStreaming,
        // Drives the autoplay threshold. `expectedSize` is what TDLib knows
        // before a byte is fetched, which is exactly when the decision is made.
        'bytes': video.video.size > 0
            ? video.video.size
            : video.video.expectedSize,
      };

    case td.MessageAnimation(:final animation):
      media = {
        'type': 'animation',
        if (animation.minithumbnail != null) ...{
          'thumb': animation.minithumbnail!.data,
          'tw': animation.minithumbnail!.width,
          'th': animation.minithumbnail!.height,
        },
        'fileId': animation.animation.id,
        'remote': animation.animation.remote.id,
        if (animation.thumbnail != null) ...{
          'posterId': animation.thumbnail!.file.id,
          'posterRemote': animation.thumbnail!.file.remote.id,
        },
        'w': animation.width,
        'h': animation.height,
        'bytes': animation.animation.size > 0
            ? animation.animation.size
            : animation.animation.expectedSize,
      };

    case td.MessageDocument(:final document):
      final kind = _documentKind(document);
      media = {
        // A document that is really a GIF or clip must present as playable, or it
        // would render as a filename row and never reach the video pipeline.
        'type': switch (kind) {
          ContentKind.animation => 'animation',
          ContentKind.video => 'video',
          _ => 'document',
        },
        'name': document.fileName,
        if (document.minithumbnail != null) ...{
          'thumb': document.minithumbnail!.data,
          'tw': document.minithumbnail!.width,
          'th': document.minithumbnail!.height,
        },
        'bytes': document.document.size > 0
            ? document.document.size
            : document.document.expectedSize,
        'remote': document.document.remote.id,
        'fileId': document.document.id,
      };

    case td.MessageSticker(:final sticker):
      media = {'type': 'sticker', 'emoji': sticker.emoji};

    case td.MessagePoll(:final poll):
      media = {'type': 'poll', 'question': poll.question.text};

    default:
      // Unhandled content still gets a row so the feed stays
      // reverse-chronological without holes; it just renders as a placeholder.
      final id = content.currentObjectId;
      if (content is td.MessageText) return null;
      media = {'type': 'unsupported', 'kind': id};
  }

  return jsonEncode(media);
}

td.PhotoSize? _largestPhotoSize(List<td.PhotoSize> sizes) {
  if (sizes.isEmpty) return null;
  return sizes.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
}
