import 'package:flutter/material.dart';

/// Search box shown under a list screen's app bar (AppBar.bottom). Filtering
/// happens on the screen, via [matchesSearch].
class ListSearchBar extends StatelessWidget implements PreferredSizeWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const ListSearchBar({super.key, required this.hint, required this.onChanged});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: TextField(
        onChanged: (value) => onChanged(value.trim().toLowerCase()),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.search),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

/// True when every word of [query] (already lower-cased) appears in at least
/// one of [values] — so "old full" finds an Old Monk Full 750 ml bottle.
bool matchesSearch(String query, Iterable<Object?> values) {
  if (query.isEmpty) return true;
  final haystack = values.whereType<Object>().map((v) => v.toString().toLowerCase()).join(' ');
  return query.split(RegExp(r'\s+')).every(haystack.contains);
}
