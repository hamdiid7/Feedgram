import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/message_mapping.dart';

td.File _file([int id = 1]) => td.File(
      id: id,
      size: 1000,
      expectedSize: 1000,
      local: const td.LocalFile(
        path: '',
        canBeDownloaded: true,
        canBeDeleted: false,
        isDownloadingActive: false,
        isDownloadingCompleted: false,
        downloadOffset: 0,
        downloadedPrefixSize: 0,
        downloadedSize: 0,
      ),
      remote: const td.RemoteFile(
        id: 'remote-1',
        uniqueId: 'unique-1',
        isUploadingActive: false,
        isUploadingCompleted: true,
        uploadedSize: 1000,
      ),
    );

td.MessageDocument _document({required String mime, required String name}) =>
    td.MessageDocument(
      document: td.Document(
        fileName: name,
        mimeType: mime,
        document: _file(),
      ),
      caption: const td.FormattedText(text: '', entities: []),
    );

const _emptyText = td.FormattedText(text: '', entities: []);

void main() {
  group('straightforward kinds', () {
    test('map to themselves', () {
      expect(contentKindOf(const td.MessageText(text: _emptyText)),
          ContentKind.text);
      expect(
        contentKindOf(td.MessagePhoto(
          photo: const td.Photo(hasStickers: false, sizes: []),
          caption: _emptyText,
          showCaptionAboveMedia: false,
          hasSpoiler: false,
          isSecret: false,
        )),
        ContentKind.photo,
      );
    });
  });

  // The reason this phase needed care. A real @gifs6 post arrived as
  // `messageDocument` named "855334_0.gif" and rendered as a filename row; the
  // document filter would then have hidden it entirely.
  group('documents that are not really documents', () {
    test('a GIF sent as a document is an animation', () {
      expect(
        contentKindOf(_document(mime: 'image/gif', name: '855334_0.gif')),
        ContentKind.animation,
      );
    });

    test('an mp4 sent as a document is a video', () {
      expect(
        contentKindOf(_document(mime: 'video/mp4', name: 'clip.mp4')),
        ContentKind.video,
      );
    });

    test('the filename rescues a mislabelled mime type', () {
      // Plenty of servers send application/octet-stream for everything.
      expect(
        contentKindOf(
            _document(mime: 'application/octet-stream', name: 'funny.gif')),
        ContentKind.animation,
      );
    });

    test('audio sent as a document is still hidden', () {
      expect(
        contentKindOf(_document(mime: 'audio/mpeg', name: 'song.mp3')),
        ContentKind.audio,
      );
    });

    test('an actual document stays a document', () {
      expect(
        contentKindOf(_document(mime: 'application/pdf', name: 'report.pdf')),
        ContentKind.document,
      );
      expect(hiddenContentKinds, contains(ContentKind.document));
    });

    test('a document-wrapped GIF is encoded as playable media', () {
      // Not just classified — it has to reach the video pipeline, which means
      // media_json must say `animation`, not `document`.
      final fields =
          contentFieldsOf(_document(mime: 'image/gif', name: 'x.gif'));
      expect(fields.kind, ContentKind.animation);
      expect(fields.mediaJson, contains('"type":"animation"'));
    });
  });
}
