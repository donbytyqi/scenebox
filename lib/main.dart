import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SceneBoxApp());
}

class SceneBoxApp extends StatelessWidget {
  const SceneBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SceneBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const PortHomePage(),
    );
  }
}

class PortHomePage extends StatelessWidget {
  const PortHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SceneBox')),
      body: const Center(
        child: Text('Flutter Android port initialized'),
      ),
    );
  }
}
