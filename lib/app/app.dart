import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/network/presentation_web_server.dart';
import '../editor/edit_models.dart';
import '../features/pptx_viewer/pages/pptx_viewer_page.dart';
import '../ar_core/pptx_parser.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PresentationEditModel? editModel;
  PresentationWebServer? _webServer;
  String? _serverUrl;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await rootBundle.load('assets/test.pptx');
    final bytes = data.buffer.asUint8List();
    final result = await parsePptxFile(bytes);
    final model = PresentationEditModel.fromPresentation(result);

    final server = PresentationWebServer(presentation: model);
    final uri = await server.start();
    setState(() {
      editModel = model;
      _webServer = server;
      _serverUrl = uri.toString();
      print("$_serverUrl - сервер");
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading || editModel == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ChangeNotifierProvider.value(
      value: editModel!,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PptxViewerPage(webServer: _webServer!),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_webServer?.stop());
    super.dispose();
  }
}
