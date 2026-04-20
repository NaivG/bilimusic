import 'package:flutter/material.dart';
import 'package:bilimusic/pages/home_content.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeContent(showAppBar: true);
  }
}
