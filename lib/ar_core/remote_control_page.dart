import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  WebSocket? socket;

  Future<void> connect() async {
    socket = await WebSocket.connect(
      'ws://192.168.0.106:8080/ws',
    );
  }

  @override
  void initState() {
    super.initState();
    connect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пульт')),
      body: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                socket?.add(jsonEncode({
                  'type': 'prev',
                }));
              },
              child: const Text('Назад'),
            ),
          ),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                socket?.add(jsonEncode({
                  'type': 'next',
                }));
              },
              child: const Text('Вперёд'),
            ),
          ),
        ],
      ),
    );
  }
}