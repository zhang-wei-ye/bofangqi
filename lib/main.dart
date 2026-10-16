import 'dart:io';

import 'package:flutter/material.dart';

import 'net.dart';
import 'pages/search_page.dart';

void main() {
  HttpOverrides.global = AppHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '播放一烨',
      theme: ThemeData.dark(),
      home: const SearchPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
