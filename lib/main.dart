import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const IaceApp());
}

class IaceApp extends StatelessWidget {
  const IaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iACE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('iACE')),
      ),
    );
  }
}
