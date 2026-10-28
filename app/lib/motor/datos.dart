// Los datos del juego: el modelo de goles, las divisiones, los planteles y
// lo que aprendieron los DT. Son los mismos JSON que usa la versión de
// Python (modelo_poisson.json, ascenso.json, planteles.json, dt_ia.json).
import 'dart:math' as math;

import 'azar.dart';
import 'jugadores.dart';
import 'partido.dart';

/// Planteles de todos los clubes, como vienen en planteles.json.
Map<String, List<Jugador>> planteles = {};

/// La fuerza de los clubes del ascenso se estima con su peso histórico (1 a 5).
(double, double) fuerzaEstimada(String club, num peso, double ajuste) {
  final rng = Azar('ascenso|$club');
  final neto = -1.10 + 0.12 * peso + ajuste + rng.gauss(0, 0.08);
  final sesgo = rng.gauss(0, 0.08);
  return (neto / 2 + sesgo, -neto / 2 + sesgo);
}

/// Arma el modelo con sus tres divisiones.
Modelo armarModelo(Map<String, dynamic> poisson, Map<String, dynamic>? ascenso) {
  final equipos = <String, (double, double)>{
    for (final e in (poisson['equipos'] as Map).entries)
      e.key as String: ((e.value['ataque'] as num).toDouble(), (e.value['defensa'] as num).toDouble())
  };
  final division = <String, int>{for (final c in equipos.keys) c: 0};
  final divisiones = ['Liga Profesional'];
  if (ascenso != null) {
    final primera = [
      for (final c in (ascenso['primera'] as List? ?? equipos.keys.toList()))
        if (equipos.containsKey(c)) c as String
    ];
    final bajan = [for (final c in equipos.keys) if (!primera.contains(c)) c];
    division
      ..clear()
      ..addAll({for (final c in primera) c: 0});
    var d = 0;
    for (final div in ascenso['divisiones'] as List) {
      d++;
      divisiones.add(div['nombre']);
      if (d == 1) division.addAll({for (final c in bajan) c: 1});
      final ajuste = (div['ajuste'] as num? ?? 0).toDouble();
      for (final x in (div['clubes'] as Map).entries) {
        final club = x.key as String;
        equipos.putIfAbsent(club, () => fuerzaEstimada(club, x.value as num, ajuste));
        division[club] = d;
      }
    }
  }
  return Modelo((poisson['base'] as num).toDouble(), (poisson['localia'] as num).toDouble(),
      equipos, division, divisiones);
}

void cargarPlanteles(Map<String, dynamic> datos) {
  planteles = {
    for (final c in (datos['clubes'] as Map).entries)
      c.key as String: [
        for (final j in c.value as List) Jugador.fromJson(Map<String, dynamic>.from(j))
      ]
  };
}

/// Modelo de respaldo si no hubiera datos (no debería pasar en la app).
final modeloVacio =
    Modelo(math.log(1.15), math.log(1.25), {}, {}, ['Liga Profesional']);
