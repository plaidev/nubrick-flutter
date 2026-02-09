import 'package:flutter/material.dart';
import 'package:nubrick_flutter/nubrick_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final nubrick = NubrickFlutter("ckto7v223akg00ag3jsg");
  String _message = "Not Found";

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    if (!mounted) return;

    var config = NubrickRemoteConfig("REMOTE_CONFIG_FOR_E2E");
    var variant = await config.fetch();
    var message = await variant.get("message");

    setState(() {
      _message = message ?? "Not Found";
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: NubrickProvider(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('app for e2e '),
          ),
          body: Column(
            children: [
              const NubrickEmbedding("EMBEDDING_FOR_E2E", height: 270),
              Text(_message),
            ],
          ),
        ),
      ),
    );
  }
}
