// The store is dart:io only (real HttpClient, real files) and the fixture
// archive is served from a real HttpServer, so this file cannot run on the web.
@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/model_store.dart';
import 'package:glowing_waffle/tts/tts_models.dart';

/// Serves the archive bytes over loopback so the store's real HTTP path runs.
class _FixtureServer {
  _FixtureServer._(this._http) {
    _http.listen(_handle);
  }

  static Future<_FixtureServer> start() async =>
      _FixtureServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _http;

  /// Bytes to serve; replaced before the store runs in each test.
  List<int> body = const [1, 2, 3];

  /// Status code to answer with, for failure cases.
  int status = HttpStatus.ok;

  int requests = 0;

  /// When set, the next response announces the full length but sends only this
  /// many bytes, then drops the connection: a phone losing Wi-Fi mid-download.
  int? dropAfter;

  /// Whether a `Range` request is honoured with a 206. Set false to model a
  /// server/CDN that ignores ranges and sends the whole body again.
  bool supportsRange = true;

  /// The `Range` header of every request, in order.
  final List<String?> ranges = [];

  Uri get uri => Uri.parse('http://127.0.0.1:${_http.port}/model.tar.bz2');

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    if (status != HttpStatus.ok) {
      response.statusCode = status;
      await response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    var start = 0;
    if (range != null && supportsRange) {
      start = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
      );
      response.statusCode = HttpStatus.partialContent;
    }
    response.headers.contentLength = body.length - start;

    final dropAfter = this.dropAfter;
    if (dropAfter != null) {
      this.dropAfter = null;
      final socket = await response.detachSocket();
      socket.add(body.sublist(start, dropAfter));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.add(body.sublist(start));
    await response.close();
  }

  Future<void> close() => _http.close(force: true);
}

/// Answers with an announced length but a short body, then hangs up: a raw
/// socket because an [HttpServer] refuses to under-send.
class _TruncatedServer {
  static Future<Uri> start(List<int> body, int sendBytes) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    server.listen((socket) async {
      socket.write('HTTP/1.1 200 OK\r\n'
          'Content-Type: application/octet-stream\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: close\r\n\r\n');
      socket.add(body.sublist(0, sendBytes));
      await socket.flush();
      socket.destroy();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/model.tar.bz2');
  }
}

/// Builds an archive shaped like the real one: a top-level directory holding
/// the English files, plus files the engine does not need.
List<int> _buildArchive() {
  final archive = Archive();
  const prefix = 'kokoro-multi-lang-v1_0/';
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile('$prefix$name', bytes.length, bytes));

  add('model.onnx', List<int>.generate(1024, (i) => i % 251));
  add('tokens.txt', 'a b c'.codeUnits);
  add('voices.bin', List<int>.generate(64, (i) => 255 - i));
  add('lexicon-us-en.txt', 'hello'.codeUnits);
  add('lexicon-zh-en.txt', 'ni hao'.codeUnits);
  add('espeak-ng-data/en_dict', 'en'.codeUnits);
  add('espeak-ng-data/zh_dict', 'zh'.codeUnits);
  add('README.md', 'not for the engine'.codeUnits);
  return BZip2Encoder().encode(TarEncoder().encode(archive));
}

/// Builds Kitten's archive shape: same layout, its own file names, no lexicon.
List<int> _buildKittenArchive() {
  final archive = Archive();
  const prefix = 'kitten-nano-en-v0_2-fp16/';
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile('$prefix$name', bytes.length, bytes));

  add('model.fp16.onnx', List<int>.generate(512, (i) => (i * 7) % 251));
  add('tokens.txt', 'x y z'.codeUnits);
  add('voices.bin', List<int>.generate(32, (i) => i));
  // Kokoro's lexicon is not part of Kitten; a mirror shipping it must not make
  // the store believe the model is something else.
  add('lexicon-us-en.txt', 'ignored'.codeUnits);
  add('espeak-ng-data/en_dict', 'en'.codeUnits);
  add('LICENSE', 'licence text'.codeUnits);
  return BZip2Encoder().encode(TarEncoder().encode(archive));
}

void main() {
  late Directory tempDir;
  late Directory modelDir;
  late _FixtureServer server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('model_store_test');
    modelDir = Directory('${tempDir.path}/tts_model');
    server = await _FixtureServer.start();
  });

  tearDown(() async {
    await server.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final progress = <double>[];

  ModelStore storeFor({TtsModel model = TtsModel.kokoro, String sha256 = ''}) =>
      ModelStore(
        model: model,
        modelDir: modelDir,
        archiveUrl: server.uri,
        sha256: sha256,
        onProgress: progress.add,
      );

  test('downloads and extracts only what the engine reads', () async {
    final archive = _buildArchive();
    server.body = archive;
    progress.clear();

    await storeFor(sha256: crypto.sha256.convert(archive).toString()).ensure();

    final store = storeFor();
    expect(await store.isReady(), isTrue);
    expect(File('${modelDir.path}/model.onnx').readAsBytesSync(),
        List<int>.generate(1024, (i) => i % 251));
    expect(File('${modelDir.path}/tokens.txt').readAsStringSync(), 'a b c');
    expect(File('${modelDir.path}/voices.bin').readAsBytesSync(),
        List<int>.generate(64, (i) => 255 - i));
    expect(
        File('${modelDir.path}/lexicon-us-en.txt').readAsStringSync(), 'hello');
    expect(File('${modelDir.path}/espeak-ng-data/en_dict').readAsStringSync(),
        'en');

    // The top-level directory is stripped and unneeded files are not written.
    expect(File('${modelDir.path}/lexicon-zh-en.txt').existsSync(), isFalse);
    expect(File('${modelDir.path}/README.md').existsSync(), isFalse);
    expect(Directory('${modelDir.path}/kokoro-multi-lang-v1_0').existsSync(),
        isFalse);

    // Archive and intermediate tar are cleaned up; only the model remains.
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);
    expect(File('${modelDir.path}.tar').existsSync(), isFalse);
    expect(server.requests, 1);

    // Progress covers the download and the extraction, ending at 1.0.
    expect(progress, isNotEmpty);
    expect(progress.first, greaterThan(0));
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('skips the download when the model is already installed', () async {
    server.body = _buildArchive();
    await storeFor().ensure();
    final requests = server.requests;
    progress.clear();

    await storeFor().ensure();

    expect(server.requests, requests);
    expect(progress, [1.0]);
  });

  test('rejects an archive whose checksum does not match', () async {
    server.body = _buildArchive();

    await expectLater(
      storeFor(sha256: 'not-the-real-hash').ensure(),
      throwsA(isA<StateError>()),
    );

    expect(await storeFor().isReady(), isFalse);
    expect(File('${modelDir.path}/model.onnx').existsSync(), isFalse);
    // The bad archive is dropped so a retry downloads it again.
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);
  });

  test('fails on an HTTP error and leaves no partial download', () async {
    server.status = HttpStatus.notFound;

    await expectLater(
      storeFor().ensure(),
      throwsA(isA<HttpException>()),
    );

    expect(await storeFor().isReady(), isFalse);
    expect(File('${modelDir.path}.tar.bz2.part').existsSync(), isFalse);
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);
  });

  test('resumes a dropped download instead of starting over', () async {
    final archive = _buildArchive();
    server.body = archive;
    server.dropAfter = 32; // the first attempt dies after 32 bytes
    final store = storeFor(sha256: crypto.sha256.convert(archive).toString());

    await store.ensure();

    expect(server.requests, 2);
    // The retry asked for the rest, not for the whole 350 MB again.
    expect(server.ranges, [isNull, 'bytes=32-']);
    expect(await store.isReady(), isTrue);
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);
    expect(File('${modelDir.path}.tar.bz2.part').existsSync(), isFalse);
  });

  test('restarts when the server ignores Range', () async {
    final archive = _buildArchive();
    server.body = archive;
    server.supportsRange = false; // a CDN that always sends the whole body
    await modelDir.create(recursive: true);
    await File('${modelDir.path}.tar.bz2.part').writeAsBytes([9, 9, 9, 9]);
    final store = storeFor(sha256: crypto.sha256.convert(archive).toString());

    await store.ensure();

    expect(server.ranges, ['bytes=4-']);
    // A 200 body must truncate the part file: appending would corrupt the
    // archive and fail the checksum.
    expect(await store.isReady(), isTrue);
    expect(File('${modelDir.path}.tar.bz2.part').existsSync(), isFalse);
  });

  test('gives up after a few attempts and keeps the bytes for a retry',
      () async {
    final archive = _buildArchive();
    final url = await _TruncatedServer.start(archive, 32);
    final store = ModelStore(
      model: TtsModel.kokoro,
      modelDir: modelDir,
      archiveUrl: url,
      sha256: crypto.sha256.convert(archive).toString(),
    );

    await expectLater(store.ensure(), throwsA(isA<HttpException>()));

    expect(await store.isReady(), isFalse);
    // Keeping the partial file is what makes the next run resume.
    final part = File('${modelDir.path}.tar.bz2.part');
    expect(part.existsSync(), isTrue);
    expect(await part.length(), 32);
  });

  test('keeps the archive when extraction fails, so a retry is cheap',
      () async {
    server.body = List<int>.generate(4096, (i) => i % 256); // not bzip2

    await expectLater(storeFor().ensure(), throwsA(isA<Exception>()));

    expect(File('${modelDir.path}.tar.bz2').existsSync(), isTrue);
    expect(await storeFor().isReady(), isFalse);
  });

  test(
      'drops the archive once the tar exists, so a failed extraction re-downloads',
      () async {
    final archive = _buildArchive();
    server.body = archive;
    final checksum = crypto.sha256.convert(archive).toString();
    // A file where the extraction needs a directory makes the write fail after
    // the archive has already been dropped.
    Directory(modelDir.path).createSync(recursive: true);
    final blocker = File('${modelDir.path}/espeak-ng-data')
      ..writeAsStringSync('in the way');

    await expectLater(
      storeFor(sha256: checksum).ensure(),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);

    // With the blocker gone the retry works, but it has to download again.
    blocker.deleteSync();
    final requests = server.requests;
    await storeFor(sha256: checksum).ensure();
    expect(server.requests, greaterThan(requests));
    expect(await storeFor().isReady(), isTrue);
  });

  test('installs Kitten: its own file names, no lexicon', () async {
    final archive = _buildKittenArchive();
    server.body = archive;
    progress.clear();
    final store = storeFor(
      model: TtsModel.kitten,
      sha256: crypto.sha256.convert(archive).toString(),
    );

    await store.ensure();

    expect(await store.isReady(), isTrue);
    expect(File('${modelDir.path}/model.fp16.onnx').readAsBytesSync(),
        List<int>.generate(512, (i) => (i * 7) % 251));
    expect(File('${modelDir.path}/tokens.txt').readAsStringSync(), 'x y z');
    expect(File('${modelDir.path}/voices.bin').lengthSync(), 32);
    expect(File('${modelDir.path}/espeak-ng-data/en_dict').readAsStringSync(),
        'en');
    // Neither the Kokoro lexicon nor the licence is written.
    expect(File('${modelDir.path}/lexicon-us-en.txt').existsSync(), isFalse);
    expect(File('${modelDir.path}/LICENSE').existsSync(), isFalse);
    expect(progress.last, 1.0);
  });

  test("one model's files do not satisfy the other", () async {
    // Both stores are pointed at the same directory: Kokoro's files are there,
    // Kitten's are not, so only Kokoro reports ready.
    server.body = _buildArchive();
    await storeFor().ensure();

    expect(await storeFor(model: TtsModel.kokoro).isReady(), isTrue);
    expect(await storeFor(model: TtsModel.kitten).isReady(), isFalse);
  });

  test('each model pins the archive it downloads', () {
    for (final model in TtsModel.values) {
      expect(model.archiveUrl.scheme, 'https');
      expect(model.archiveUrl.path, endsWith('.tar.bz2'));
      expect(model.archiveSha256, hasLength(64));
      expect(model.files, contains(model.onnxFile));
      expect(model.voices, isNotEmpty);
      expect(model.voices, contains(model.defaultVoice));
    }

    // The pinned release assets, and the names the smoke test stages with.
    expect(TtsModel.kokoro.archiveUrl.path,
        contains('kokoro-multi-lang-v1_0.tar.bz2'));
    expect(TtsModel.kitten.archiveUrl.path,
        contains('kitten-nano-en-v0_2-fp16.tar.bz2'));
    expect(
        TtsModel.values.map((model) => model.wireName), ['kokoro', 'kitten']);
  });
}
