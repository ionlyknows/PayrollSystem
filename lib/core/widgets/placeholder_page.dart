import 'package:flutter/material.dart';

/// Minimal shared page that shows a centered title.
///
/// Used only until real feature pages exist.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(title)));
  }
}
