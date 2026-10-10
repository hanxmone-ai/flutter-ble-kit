import 'models.dart';

/// Filters applied to scan results.
class ScanFilter {
  const ScanFilter({this.namedOnly = false, this.minRssi = -100, this.query = ''});

  /// Hide devices that do not advertise a name.
  final bool namedOnly;

  /// Hide devices weaker than this, in dBm.
  final int minRssi;

  /// Case-insensitive match against the name or id.
  final String query;

  bool accepts(DiscoveredDevice d) {
    if (namedOnly && d.name.isEmpty) return false;
    if (d.rssi < minRssi) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return d.name.toLowerCase().contains(q) || d.id.toLowerCase().contains(q);
  }

  ScanFilter copyWith({bool? namedOnly, int? minRssi, String? query}) => ScanFilter(
        namedOnly: namedOnly ?? this.namedOnly,
        minRssi: minRssi ?? this.minRssi,
        query: query ?? this.query,
      );
}

/// Collects advertisements into one entry per device.
///
/// Devices advertise many times a second; this keeps the latest sighting,
/// smooths RSSI so the list does not jump around, and forgets devices that
/// have not been seen for [staleAfter].
class ScanList {
  ScanList({this.staleAfter = const Duration(seconds: 15), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration staleAfter;
  final DateTime Function() _clock;
  final Map<String, _Entry> _entries = {};

  /// Adds one advertisement. Returns true when the list changed.
  bool add(DiscoveredDevice device) {
    final now = _clock();
    final existing = _entries[device.id];
    if (existing == null) {
      _entries[device.id] = _Entry(device, device.rssi.toDouble(), now);
      return true;
    }
    // Exponential moving average: steady ordering, still follows real movement.
    existing.smoothedRssi = existing.smoothedRssi * 0.7 + device.rssi * 0.3;
    final name = device.name.isNotEmpty ? device.name : existing.device.name;
    existing.device = device.copyWith(rssi: existing.smoothedRssi.round(), name: name);
    existing.lastSeen = now;
    return true;
  }

  /// Drops devices not seen for [staleAfter]. Returns true when any were dropped.
  bool prune() {
    final cutoff = _clock().subtract(staleAfter);
    final before = _entries.length;
    _entries.removeWhere((_, e) => e.lastSeen.isBefore(cutoff));
    return _entries.length != before;
  }

  void clear() => _entries.clear();

  int get length => _entries.length;

  DiscoveredDevice? operator [](String id) => _entries[id]?.device;

  /// Devices passing [filter], strongest signal first, ties by name.
  List<DiscoveredDevice> devices([ScanFilter filter = const ScanFilter()]) {
    final list = _entries.values.map((e) => e.device).where(filter.accepts).toList()
      ..sort((a, b) {
        final byRssi = b.rssi.compareTo(a.rssi);
        return byRssi != 0 ? byRssi : a.displayName.compareTo(b.displayName);
      });
    return list;
  }
}

class _Entry {
  _Entry(this.device, this.smoothedRssi, this.lastSeen);

  DiscoveredDevice device;
  double smoothedRssi;
  DateTime lastSeen;
}
