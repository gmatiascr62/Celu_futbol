// Pruebas del motor del juego: que los partidos den los goles y empates de
// siempre, y que una partida se guarde y se cargue igual.
import 'dart:convert';
import 'dart:io';

import 'package:celu_futbol/motor/azar.dart';
import 'package:celu_futbol/motor/datos.dart';
import 'package:celu_futbol/motor/equipo.dart';
import 'package:celu_futbol/motor/jugadores.dart';
import 'package:celu_futbol/motor/partido.dart';
import 'package:celu_futbol/motor/torneo.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> leer(String n) => jsonDecode(File('../$n').readAsStringSync());

void main() {
  late Modelo modelo;

  setUpAll(() {
    modelo = armarModelo(leer('modelo_poisson.json'), leer('ascenso.json'));
    cargarPlanteles(leer('planteles.json'));
    cargarCerebro(leer('dt_ia.json'));
  });

  test('tres divisiones de 20', () {
    expect(modelo.divisiones.length, 3);
    for (var d = 0; d < 3; d++) {
      expect(modelo.division.values.where((x) => x == d).length, 20);
    }
  });

  test('una liga da unos 2 goles por partido y un tercio de empates', () {
    final clubes = [for (final c in modelo.division.keys) if (modelo.division[c] == 0) c];
    final rng = Azar('prueba');
    var goles = 0, empates = 0, n = 0;
    for (final a in clubes) {
      for (final b in clubes) {
        if (a == b) continue;
        Equipo eq(String c) => Equipo(c, modelo.equipos[c]!.$1, modelo.equipos[c]!.$2)
          ..plantel = copiarPlantel(planteles[c]!)
          ..dt = rng.choice(['equilibrado', 'conservador', 'arriesgado', 'impulsivo']);
        final r = simularPartido(eq(a), eq(b), modelo, semilla: '$a|$b');
        goles += r.gl + r.gv;
        if (r.gl == r.gv) empates++;
        n++;
      }
    }
    expect(goles / n, inInclusiveRange(1.8, 2.4));
    expect(empates / n, inInclusiveRange(0.24, 0.40));
  });

  test('la partida se guarda y se carga igual', () {
    final p = crearPartida(modelo, 'Boca Juniors', 'equilibrado');
    for (var i = 0; i < 3; i++) {
      jugarUnaFecha(p, modelo);
    }
    final texto = jsonEncode(p.toJson());
    final q = Partida.fromJson(jsonDecode(texto))!;
    expect(jsonEncode(q.toJson()), texto);
    expect(q.numero, 3);
  });

  test('una temporada entera con ascensos y descensos', () {
    final p = crearPartida(modelo, 'Temperley', 'arriesgado');
    while (!p.terminada) {
      p.reunion = null;
      if (p.miDt == null) contratar(p, dtsDisponibles(p).first);
      jugarUnaFecha(p, modelo);
    }
    cerrarTemporada(p);
    empezarTemporada(p);
    expect(p.temporada, 2);
    expect(p.historial.single['ascensos'], hasLength(4));
    for (var d = 0; d < 3; d++) {
      expect(p.division.values.where((x) => x == d).length, 20);
    }
  });
}
