/// "Brand · Size" for a bottle (e.g. "Old Monk · Half 375 ml"), or null when
/// the bottle record carries neither. Works on any backend map that has
/// `brand_name` / `bottle_size` keys — returns, verify responses, bottles.
String? bottleLabel(Map<String, dynamic>? data) => bottleLabelOf(
      data?['brand_name'] as String?,
      data?['bottle_size'] as String?,
    );

String? bottleLabelOf(String? brand, String? size) {
  final parts = [brand, size].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
  return parts.isEmpty ? null : parts.join(' · ');
}
