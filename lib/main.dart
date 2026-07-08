import 'package:flutter/material.dart';

import 'app/app.dart';

void main() {
  runApp(const MyApp());
}

// import 'package:flutter/material.dart';
 
// import 'model_picker_screen.dart';
 
// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(const ArViewerApp());
// }
 
// class ArViewerApp extends StatelessWidget {
//   const ArViewerApp({super.key});
 
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'AR Viewer',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(
//           seedColor: const Color(0xFF006EFF),
//           brightness: Brightness.light,
//         ),
//         useMaterial3: true,
//       ),
//       home: const ModelPickerScreen(),
//     );
//   }
// }