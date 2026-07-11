/// Raspberry Pi camera (rpicam/libcamera) live feed.
///
/// Conditional facade: the real implementation on dart:io platforms, an inert
/// stub on the web where `Process`/`Platform` don't exist.
library;

export 'rpicam_io.dart' if (dart.library.js_interop) 'rpicam_stub.dart';
