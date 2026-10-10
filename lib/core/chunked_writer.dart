import 'dart:async';

/// Writes a long payload in pieces that fit one Bluetooth LE write.
///
/// A single write carries at most `MTU - 3` bytes. Printers and other devices
/// with small buffers also need a short pause between pieces, or they drop data.
class ChunkedWriter {
  ChunkedWriter({
    required this.write,
    required this.chunkSize,
    this.pause = Duration.zero,
    Future<void> Function(Duration)? sleep,
  })  : assert(chunkSize > 0),
        _sleep = sleep ?? Future<void>.delayed;

  /// Sends one piece.
  final Future<void> Function(List<int> chunk) write;

  final int chunkSize;

  /// Wait between pieces.
  final Duration pause;

  final Future<void> Function(Duration) _sleep;

  /// The largest payload for one write at [mtu], capped at [max].
  static int chunkSizeForMtu(int mtu, {int max = 512}) {
    final size = mtu - 3;
    if (size < 20) return 20; // the minimum every BLE stack supports
    return size > max ? max : size;
  }

  /// Sends [bytes] piece by piece. [onProgress] gets the bytes sent so far and
  /// the total after each piece.
  Future<void> writeAll(
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = bytes.length;
    var sent = 0;
    while (sent < total) {
      final end = sent + chunkSize < total ? sent + chunkSize : total;
      await write(bytes.sublist(sent, end));
      sent = end;
      onProgress?.call(sent, total);
      if (sent < total && pause > Duration.zero) await _sleep(pause);
    }
  }
}
