/// Hex helpers for showing and entering raw characteristic values.
library;

/// `[0x01, 0xAB]` → `01 AB`.
String toHex(List<int> bytes) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

/// Parses `01 ab`, `01AB`, `0x01,0xAB` and similar. Throws [FormatException].
List<int> parseHex(String text) {
  final cleaned = text.replaceAll(RegExp(r'0x', caseSensitive: false), '').replaceAll(RegExp(r'[\s,:;-]'), '');
  if (cleaned.isEmpty) return const [];
  if (cleaned.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
    throw FormatException('Enter pairs of hex digits, like 01 A0 FF', text);
  }
  return [
    for (var i = 0; i < cleaned.length; i += 2) int.parse(cleaned.substring(i, i + 2), radix: 16),
  ];
}

/// The bytes as text when they are printable UTF-8 / ASCII, otherwise null.
String? asPrintableText(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final printable = bytes.every((b) => b == 0x0A || b == 0x0D || b == 0x09 || (b >= 0x20 && b < 0x7F));
  return printable ? String.fromCharCodes(bytes) : null;
}
