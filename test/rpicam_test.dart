import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdstest/rpicam.dart';

/// 8x8 solid-color JPEG (no ICC/EXIF bloat) used as an MJPEG frame payload.
const _tinyJpegBase64 =
    '/9j/4AAQSkZJRgABAQAASABIAAD/4QBARXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAA'
    'AAAAAqACAAQAAAABAAAACKADAAQAAAABAAAACAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklN'
    'BAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgACAAIAwEiAAIRAQMR'
    'Af/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAAB'
    'fQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2'
    'Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqi'
    'o6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5'
    '+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAEC'
    'dwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1'
    'Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZ'
    'mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5'
    '+v/bAEMACQkJCQkJEAkJEBYQEBAWHhYWFhYeJh4eHh4eJi4mJiYmJiYuLi4uLi4uLjc3Nzc3'
    'N0BAQEBASEhISEhISEhISP/bAEMBCwwMEhESHxERH0szKjNLS0tLS0tLS0tLS0tLS0tLS0tL'
    'S0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS//dAAQAAf/aAAwDAQACEQMRAD8Ap0UU'
    'V9OfPH//2Q==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MjpegSplitter', () {
    Uint8List jpeg(List<int> payload) =>
        Uint8List.fromList([0xFF, 0xD8, ...payload, 0xFF, 0xD9]);

    test('emits back-to-back frames from a single chunk', () {
      final frames = <Uint8List>[];
      final splitter = MjpegSplitter(frames.add);
      final a = jpeg([1, 2, 3]);
      final b = jpeg([4, 5, 6, 7]);

      splitter.add([...a, ...b]);

      expect(frames, [a, b]);
    });

    test('reassembles a frame delivered byte by byte', () {
      final frames = <Uint8List>[];
      final splitter = MjpegSplitter(frames.add);
      final frame = jpeg(List.generate(64, (i) => i));

      for (final byte in frame) {
        splitter.add([byte]);
      }

      expect(frames, [frame]);
    });

    test('finds markers split across chunk boundaries', () {
      final frames = <Uint8List>[];
      final splitter = MjpegSplitter(frames.add);
      final frame = jpeg([9, 8, 7]);

      // Split inside both the SOI and EOI markers.
      splitter.add(frame.sublist(0, 1)); // FF
      splitter.add(frame.sublist(1, frame.length - 1)); // D8 ... FF
      splitter.add(frame.sublist(frame.length - 1)); // D9

      expect(frames, [frame]);
    });

    test('discards garbage before the first frame', () {
      final frames = <Uint8List>[];
      final splitter = MjpegSplitter(frames.add);
      final frame = jpeg([1, 2]);

      splitter.add([0x00, 0x42, 0x13]);
      splitter.add(frame);

      expect(frames, [frame]);
    });

    test('escaped 0xFF and restart markers do not end a frame early', () {
      final frames = <Uint8List>[];
      final splitter = MjpegSplitter(frames.add);
      // Entropy-coded data escapes 0xFF as FF 00; restart markers are
      // FF D0..D7. Neither may be mistaken for EOI.
      final frame = jpeg([0xFF, 0x00, 0x55, 0xFF, 0xD0, 0x66]);

      splitter.add(frame);

      expect(frames, [frame]);
    });
  });

  group('parseRpicamCameraList', () {
    test('parses rpicam-vid --list-cameras output', () {
      const output = '''
Available cameras
-----------------
0 : imx708 [4608x2592 10-bit RGGB] (/base/soc/i2c0mux/i2c@0/imx708@1a)
    Modes: 'SRGGB10_CSI2P' : 1536x864 [120.13 fps - (768, 432)/3072x1728 crop]
                             2304x1296 [56.03 fps - (0, 0)/4608x2592 crop]
                             4608x2592 [14.35 fps - (0, 0)/4608x2592 crop]
1 : ov5647 [2592x1944 10-bit GBRG] (/base/soc/i2c0mux/i2c@1/ov5647@36)
    Modes: 'SGBRG10_CSI2P' : 640x480 [58.92 fps - (16, 0)/2560x1920 crop]
''';

      final cameras = parseRpicamCameraList(output);

      expect(cameras, hasLength(2));
      expect(cameras[0].index, 0);
      expect(cameras[0].name, 'imx708');
      expect(cameras[1].index, 1);
      expect(cameras[1].name, 'ov5647');
    });

    test('returns no cameras for an empty listing', () {
      expect(parseRpicamCameraList('No cameras available!'), isEmpty);
      expect(parseRpicamCameraList(''), isEmpty);
    });
  });

  group('RpicamFeed', () {
    test('decodes frames streamed by the spawned process', () async {
      final dir = await Directory.systemTemp.createTemp('rpicam_feed_test');
      addTearDown(() => dir.delete(recursive: true));

      // Fake rpicam-vid: writes two MJPEG frames to stdout, then stays alive
      // like the real tool would until the feed kills it.
      final jpeg = base64Decode(_tinyJpegBase64);
      final stream = File('${dir.path}/stream.mjpeg');
      await stream.writeAsBytes([...jpeg, ...jpeg]);
      final script = File('${dir.path}/fake-rpicam-vid');
      await script.writeAsString('#!/bin/sh\ncat "${stream.path}"\nsleep 30\n');
      await Process.run('chmod', ['+x', script.path]);

      final feed = RpicamFeed(
        binary: script.path,
        camera: const RpicamCamera(index: 0, name: 'fake'),
      );
      addTearDown(feed.stop);
      final firstFrame = Completer<void>();
      feed.addListener(() {
        if (firstFrame.isCompleted) return;
        final error = feed.error;
        if (error != null) {
          firstFrame.completeError(StateError(error));
        } else if (feed.image != null) {
          firstFrame.complete();
        }
      });

      await feed.start();
      await firstFrame.future.timeout(const Duration(seconds: 15));

      expect(feed.error, isNull);
      expect(feed.image, isNotNull);
      expect(feed.image!.width, 8);
      expect(feed.image!.height, 8);
    });

    test('reports an error when the binary is missing', () async {
      final feed = RpicamFeed(
        binary: '/nonexistent/rpicam-vid',
        camera: const RpicamCamera(index: 0, name: 'fake'),
      );
      addTearDown(feed.stop);
      final failed = Completer<void>();
      feed.addListener(() {
        if (feed.error != null && !failed.isCompleted) failed.complete();
      });

      await feed.start();
      await failed.future.timeout(const Duration(seconds: 5));

      expect(feed.error, contains('Could not start'));
      expect(feed.image, isNull);
    });
  });
}
