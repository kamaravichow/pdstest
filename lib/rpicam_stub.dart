import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Web build of the rpicam feed. `detectRpicam` always returns null, so none
/// of these members ever run; they exist only to satisfy the compiler on
/// platforms without dart:io.

Never _unsupported() =>
    throw UnsupportedError('rpicam is only available on Linux');

Future<RpicamStack?> detectRpicam() async => null;

class RpicamCamera {
  RpicamCamera._();

  int get index => _unsupported();
  String get name => _unsupported();
}

class RpicamStack {
  RpicamStack._();

  String get binary => _unsupported();
  List<RpicamCamera> get cameras => _unsupported();
}

class RpicamFeed extends ChangeNotifier {
  RpicamFeed({required String binary, required RpicamCamera camera}) {
    _unsupported();
  }

  ui.Image? get image => _unsupported();
  String? get error => _unsupported();
  double get aspectRatio => _unsupported();

  Future<void> start() => _unsupported();
  void stop() => _unsupported();
}

class RpicamPreview extends StatelessWidget {
  const RpicamPreview(this.feed, {super.key});

  final RpicamFeed feed;

  @override
  Widget build(BuildContext context) => _unsupported();
}
