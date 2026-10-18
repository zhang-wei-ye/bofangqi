import 'dart:io';

import 'package:flutter/material.dart';

import 'downloads.dart';
import 'net.dart';
import 'pages/home_shell.dart';

void main() {
  HttpOverrides.global = AppHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  // 读出缓存任务，上次没下完的接着下。
  DownloadManager.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '播放一烨',
      theme: ThemeData.dark(),
      home: const HomeShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
