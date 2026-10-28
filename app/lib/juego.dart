// El estado de la app: los datos del juego y la partida en curso.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'almacen/almacen.dart';
import 'motor/datos.dart';
import 'motor/partido.dart';
import 'motor/torneo.dart';

class Juego extends ChangeNotifier {
  Modelo modelo = modeloVacio;
  Partida? partida;
  bool listo = false;

  Future<Map<String, dynamic>> _json(String nombre) async =>
      jsonDecode(await rootBundle.loadString('assets/datos/$nombre'));

  Future<void> cargar() async {
    modelo = armarModelo(await _json('modelo_poisson.json'), await _json('ascenso.json'));
    cargarPlanteles(await _json('planteles.json'));
    cargarCerebro(await _json('dt_ia.json'));
    try {
      final guardada = await leerPartida();
      if (guardada != null) partida = Partida.fromJson(jsonDecode(guardada));
    } catch (e) {
      debugPrint('No se pudo leer la partida guardada: $e');
    }
    listo = true;
    notifyListeners();
  }

  Future<void> nueva(String club, String dt) async {
    partida = crearPartida(modelo, club, dt);
    await guardar();
  }

  Future<void> guardar() async {
    final p = partida;
    if (p != null) await escribirPartida(jsonEncode(p.toJson()));
    notifyListeners();
  }

  Future<void> borrar() async {
    partida = null;
    await borrarPartida();
    notifyListeners();
  }

  /// Avisa a las pantallas que algo cambió (sin guardar).
  void cambio() => notifyListeners();
}

final juego = Juego();
