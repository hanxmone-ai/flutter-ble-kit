/// Formats bytes as "0a 1b ff".
String toHex(List<int> bytes) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join(' ');

final RegExp _separators = RegExp(r'[\s,:;-]+');
final RegExp _hexDigits = RegExp(r'^[0-9a-fA-F]*$');

/// Parses hex such as "0a 1b ff", "0x0A,0x1B" or "0a1bff".
///
/// Throws a [FormatException] for anything else.
List<int> parseHex(String input) {
  final cleaned = input
      .split(_separators)
      .where((part) => part.isNotEmpty)
      .map((part) => part.toLowerCase().startsWith('0x') ? part.substring(2) : part)
      .join();
  if (!_hexDigits.hasMatch(cleaned)) {
    throw FormatException('Only 0-9 and a-f are allowed', input);
  }
  if (cleaned.length.isOdd) {
    throw FormatException('Hex needs an even number of digits', input);
  }
  return [
    for (var i = 0; i < cleaned.length; i += 2)
      int.parse(cleaned.substring(i, i + 2), radix: 16),
  ];
}

/// Shows bytes as text when they are printable ASCII, otherwise null.
String? asciiOrNull(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final printable = bytes.every((b) => b == 0x0A || b == 0x0D || (b >= 0x20 && b < 0x7F));
  return printable ? String.fromCharCodes(bytes) : null;
}
