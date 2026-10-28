import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'juego.dart';
import 'ui/estilo.dart';
import 'ui/inicio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  juego.cargar();
  runApp(const CeluFutbol());
}

class CeluFutbol extends StatelessWidget {
  const CeluFutbol({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Celu Fútbol',
        debugShowCheckedModeBanner: false,
        theme: tema(),
        home: const Inicio(),
      );
}
