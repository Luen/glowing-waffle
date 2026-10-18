import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/model_store.dart';

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

  Uri get uri => Uri.parse('http://127.0.0.1:${_http.port}/model.tar.bz2');

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    if (status != HttpStatus.ok) {
      response.statusCode = status;
      await response.close();
      return;
    }
    response.headers.contentLength = body.length;
    response.add(body);
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

  KokoroModelStore storeFor({String sha256 = ''}) => KokoroModelStore(
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
    expect(File('${modelDir.path}/lexicon-us-en.txt').readAsStringSync(),
        'hello');
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
    expect(File('${modelDir.path}.part').existsSync(), isFalse);
    expect(File('${modelDir.path}.tar.bz2').existsSync(), isFalse);
  });

  test('fails on a truncated download and leaves no partial file', () async {
    final archive = _buildArchive();
    // The announced checksum is of the full archive, so a short body is caught
    // either by the HTTP stack or by the checksum below it.
    final url = await _TruncatedServer.start(archive, 32);
    final store = KokoroModelStore(
      modelDir: modelDir,
      archiveUrl: url,
      sha256: crypto.sha256.convert(archive).toString(),
    );

    await expectLater(store.ensure(), throwsA(isA<Exception>()));

    expect(await store.isReady(), isFalse);
    expect(File('${modelDir.path}.part').existsSync(), isFalse);
  });

  test('keeps the archive when extraction fails, so a retry is cheap',
      () async {
    server.body = List<int>.generate(4096, (i) => i % 256); // not bzip2

    await expectLater(storeFor().ensure(), throwsA(isA<Exception>()));

    expect(File('${modelDir.path}.tar.bz2').existsSync(), isTrue);
    expect(await storeFor().isReady(), isFalse);
  });
}
