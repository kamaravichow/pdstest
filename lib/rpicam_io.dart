import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Live camera feed backed by the Raspberry Pi rpicam/libcamera stack.
///
/// The `camera_desktop` Linux backend captures through GStreamer's `v4l2src`,
/// which works for USB webcams but not for Pi CSI camera modules: their
/// /dev/video* nodes are the raw unicam/ISP interfaces that only the libcamera
/// pipeline can drive, so a `v4l2src` pipeline starts but never delivers a
/// frame. `rpicam-vid` speaks libcamera natively, so [RpicamFeed] spawns it
/// streaming MJPEG to stdout and decodes the frames in Dart.

int _envInt(String name, int fallback) {
  final value = int.tryParse(Platform.environment[name] ?? '');
  return (value == null || value <= 0) ? fallback : value;
}

/// Capture size/rate, overridable per install since this runs on kiosks with
/// very different CPU budgets (HAVEN_CAMERA_WIDTH / _HEIGHT / _FPS).
final int _feedWidth = _envInt('HAVEN_CAMERA_WIDTH', 1280);
final int _feedHeight = _envInt('HAVEN_CAMERA_HEIGHT', 720);
final int _feedFps = _envInt('HAVEN_CAMERA_FPS', 15);

/// libcamera is chatty on stderr at INFO level; keep only errors so the
/// stderr tail we surface on failure stays readable.
const _rpicamEnv = {'LIBCAMERA_LOG_LEVELS': '*:ERROR'};

/// A CSI camera reported by `rpicam-vid --list-cameras`.
class RpicamCamera {
  const RpicamCamera({required this.index, required this.name});

  /// Index passed to `rpicam-vid --camera`.
  final int index;

  /// Sensor name, e.g. `imx708`.
  final String name;
}

/// A working rpicam installation: which binary to spawn and the CSI cameras
/// it can see.
class RpicamStack {
  const RpicamStack({required this.binary, required this.cameras});

  final String binary;
  final List<RpicamCamera> cameras;
}

/// Probes for a usable rpicam/libcamera stack.
///
/// Returns null when it should not be used: non-Linux platforms, disabled via
/// `HAVEN_RPICAM=0`, no rpicam binary installed, or no CSI camera attached
/// (USB webcams are served by the camera plugin's V4L2 path instead).
Future<RpicamStack?> detectRpicam() async {
  if (!Platform.isLinux) return null;
  if (Platform.environment['HAVEN_RPICAM'] == '0') return null;

  final override = Platform.environment['HAVEN_RPICAM_BIN'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    'rpicam-vid',
    // Pre-Bookworm (Bullseye) name of the same tool.
    'libcamera-vid',
  ];
  for (final binary in candidates) {
    final listing = await _listCameras(binary);
    if (listing == null) continue; // Binary missing or unresponsive.
    final cameras = parseRpicamCameraList(listing);
    if (cameras.isEmpty) return null;
    return RpicamStack(binary: binary, cameras: cameras);
  }
  return null;
}

Future<String?> _listCameras(String binary) async {
  try {
    // On timeout the listing process is abandoned rather than killed; it does
    // not hold the camera, so that is harmless.
    final result = await Process.run(
      binary,
      const ['--list-cameras'],
      environment: _rpicamEnv,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 10));
    return '${result.stdout}\n${result.stderr}';
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
}

/// Parses `rpicam-vid --list-cameras` output. Camera entries look like
/// `0 : imx708 [4608x2592 10-bit RGGB] (/base/soc/i2c0mux/i2c@1/imx708@1a)`;
/// the indented `Modes:` lines below each entry don't match the pattern.
@visibleForTesting
List<RpicamCamera> parseRpicamCameraList(String output) {
  final entry = RegExp(r'^\s*(\d+)\s*:\s*(\S+)\s*\[\d+x\d+', multiLine: true);
  final seen = <int>{};
  final cameras = <RpicamCamera>[];
  for (final match in entry.allMatches(output)) {
    final index = int.parse(match.group(1)!);
    if (!seen.add(index)) continue;
    cameras.add(RpicamCamera(index: index, name: match.group(2)!));
  }
  cameras.sort((a, b) => a.index.compareTo(b.index));
  return cameras;
}

/// Splits a raw MJPEG byte stream into individual JPEG frames.
///
/// `rpicam-vid --codec mjpeg -o -` writes complete JPEGs back-to-back with no
/// container, so frames are delimited by the SOI (FF D8) and EOI (FF D9)
/// markers. JPEG escapes 0xFF bytes inside entropy-coded data (as FF 00) and
/// restart markers are FF D0–D7, so EOI cannot appear inside a frame.
class MjpegSplitter {
  MjpegSplitter(this.onFrame);

  final void Function(Uint8List frame) onFrame;

  final List<int> _buffer = [];
  bool _inFrame = false;
  int _scanFrom = 0;

  void add(List<int> chunk) {
    _buffer.addAll(chunk);
    while (true) {
      if (!_inFrame) {
        final soi = _find(0xD8);
        if (soi < 0) {
          // Drop garbage before any SOI, keeping a trailing 0xFF that may
          // complete a marker with the next chunk.
          if (_buffer.length > 1) {
            _buffer.removeRange(0, _buffer.length - 1);
          }
          _scanFrom = 0;
          return;
        }
        if (soi > 0) _buffer.removeRange(0, soi);
        _inFrame = true;
        _scanFrom = 2;
      } else {
        final eoi = _find(0xD9);
        if (eoi < 0) {
          // Resume scanning at the last byte so a marker split across chunks
          // is still found.
          _scanFrom = _buffer.length > 1 ? _buffer.length - 1 : _scanFrom;
          return;
        }
        onFrame(Uint8List.fromList(_buffer.sublist(0, eoi + 2)));
        _buffer.removeRange(0, eoi + 2);
        _inFrame = false;
        _scanFrom = 0;
      }
    }
  }

  int _find(int second) {
    for (var i = _scanFrom; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 0xFF && _buffer[i + 1] == second) return i;
    }
    return -1;
  }
}

/// Streams frames from one CSI camera by running `rpicam-vid` and decoding
/// its MJPEG output. Notifies listeners on every decoded [image] and when
/// [error] changes.
///
/// Call [stop] to release the camera as soon as the feed is no longer needed,
/// then [dispose] once listening widgets have unsubscribed (e.g. in a
/// post-frame callback after rebuilding without the preview).
class RpicamFeed extends ChangeNotifier {
  RpicamFeed({required this.binary, required this.camera});

  final String binary;
  final RpicamCamera camera;

  Process? _process;
  Timer? _firstFrameTimeout;
  final List<String> _stderrTail = [];
  bool _stopped = false;

  Uint8List? _pendingJpeg;
  bool _decoding = false;

  ui.Image? _image;
  String? _error;

  /// Latest decoded frame. Owned by the feed; valid until [dispose].
  ui.Image? get image => _image;

  String? get error => _error;

  double get aspectRatio {
    final image = _image;
    if (image != null && image.height != 0) {
      return image.width / image.height;
    }
    return _feedWidth / _feedHeight;
  }

  Future<void> start() async {
    assert(_process == null && !_stopped);
    final args = <String>[
      '--camera', '${camera.index}',
      '--timeout', '0', // Stream until killed.
      '--codec', 'mjpeg',
      '--quality', '80',
      '--width', '$_feedWidth',
      '--height', '$_feedHeight',
      '--framerate', '$_feedFps',
      '--nopreview', // No DRM/EGL preview window; frames go to stdout only.
      '--flush', // Write each frame as soon as it's encoded.
      '--output', '-',
    ];
    try {
      final process = await Process.start(
        binary,
        args,
        environment: _rpicamEnv,
      );
      _process = process;
      final splitter = MjpegSplitter(_onFrame);
      process.stdout.listen(splitter.add);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine);
      unawaited(process.exitCode.then(_onExit));
      _firstFrameTimeout = Timer(const Duration(seconds: 12), () {
        if (_image == null) {
          _fail(
            'Camera initialization timed out ($binary produced no '
            'frames).',
          );
        }
      });
    } on ProcessException catch (e) {
      _fail('Could not start $binary: ${e.message}');
    }
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _stderrTail.add(line);
    if (_stderrTail.length > 6) _stderrTail.removeAt(0);
  }

  void _onExit(int code) {
    _process = null;
    if (_stopped || _error != null) return;
    final detail = _stderrTail.isEmpty ? '' : '\n${_stderrTail.join('\n')}';
    _fail('$binary exited unexpectedly (code $code).$detail');
  }

  void _onFrame(Uint8List jpeg) {
    if (_stopped) return;
    _firstFrameTimeout?.cancel();
    // Keep only the newest undecoded frame: if decoding is slower than the
    // camera's frame rate, frames are dropped instead of queueing up.
    _pendingJpeg = jpeg;
    if (!_decoding) unawaited(_decodePending());
  }

  Future<void> _decodePending() async {
    _decoding = true;
    try {
      while (!_stopped) {
        final jpeg = _pendingJpeg;
        if (jpeg == null) break;
        _pendingJpeg = null;
        try {
          final buffer = await ui.ImmutableBuffer.fromUint8List(jpeg);
          final codec = await ui.instantiateImageCodecFromBuffer(buffer);
          final frame = await codec.getNextFrame();
          codec.dispose();
          if (_stopped) {
            frame.image.dispose();
            break;
          }
          final previous = _image;
          _image = frame.image;
          _error = null;
          notifyListeners();
          if (previous != null) _disposeImageAfterFrame(previous);
        } catch (_) {
          // Truncated/corrupt frame (e.g. mid-stream shutdown) — skip it.
        }
      }
    } finally {
      _decoding = false;
    }
  }

  void _fail(String message) {
    if (_stopped) return;
    _stopProcess();
    _error = message;
    notifyListeners();
  }

  /// Kills the rpicam process and halts decoding. Idempotent; safe to call
  /// before [dispose] so the camera is released immediately.
  void stop() {
    _stopped = true;
    _stopProcess();
  }

  void _stopProcess() {
    _firstFrameTimeout?.cancel();
    _firstFrameTimeout = null;
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill();
    // Escalate if SIGTERM is ignored so a wedged encoder can't keep holding
    // the camera.
    unawaited(
      process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      ),
    );
  }

  @override
  void dispose() {
    stop();
    final image = _image;
    _image = null;
    if (image != null) _disposeImageAfterFrame(image);
    super.dispose();
  }
}

/// Disposes [image] after the next frame completes, when no [RawImage] that
/// painted it can still be in the tree.
void _disposeImageAfterFrame(ui.Image image) {
  SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
  SchedulerBinding.instance.scheduleFrame();
}

/// Paints the feed's latest frame, repainting on every decoded frame without
/// rebuilding the surrounding page.
class RpicamPreview extends StatelessWidget {
  const RpicamPreview(this.feed, {super.key});

  final RpicamFeed feed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feed,
    builder: (context, _) => RawImage(image: feed.image, fit: BoxFit.cover),
  );
}
