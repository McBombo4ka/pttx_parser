import 'package:flutter/material.dart';
import 'screens/hello_world.dart';
import 'screens/auto_detect_plane.dart';
import 'screens/remote_object.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ArCore Plus Demo'),
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (context) => HelloWorld()));
            },
            title: Text("Hello World (Shapes)"),
          ),
          ListTile(
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => AutoDetectPlane()));
            },
            title: Text("Plane Detection"),
          ),
          ListTile(
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => RemoteObject()));
            },
            title: Text("Remote Object (GLTF/GLB)"),
          ),
        ],
      ),
    );
  }
}
