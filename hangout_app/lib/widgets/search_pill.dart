import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pill-shaped search field (report §6.4: "white field with light teal border
/// + magnifier"). Local filtering is done by the caller.
class SearchPill extends StatefulWidget {
  const SearchPill({
    super.key,
    required this.controller,
    this.hint = 'Search',
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.cancel_rounded, size: 19),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                  },
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
    );
  }
}
