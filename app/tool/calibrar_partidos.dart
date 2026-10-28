// Juega muchas ligas de partidos sueltos y muestra goles, empates y
// localía, para comparar con la versión de Python.
// Uso (desde app/): dart run tool/calibrar_partidos.dart
import 'dart:convert';
import 'dart:io';

import 'package:celu_futbol/motor/azar.dart';
import 'package:celu_futbol/motor/datos.dart';
import 'package:celu_futbol/motor/equipo.dart';
import 'package:celu_futbol/motor/jugadores.dart';
import 'package:celu_futbol/motor/partido.dart';

Map<String, dynamic> leer(String n) => jsonDecode(File('../$n').readAsStringSync());

void main(List<String> args) {
  final modelo = armarModelo(leer('modelo_poisson.json'), leer('ascenso.json'));
  cargarPlanteles(leer('planteles.json'));
  cargarCerebro(leer('dt_ia.json'));
  final rng = Azar('calibrar');
  for (var d = 0; d < modelo.divisiones.length; d++) {
    final clubes = [for (final c in modelo.division.keys) if (modelo.division[c] == d) c];
    var goles = 0, empates = 0, locales = 0, n = 0;
    for (var r = 0; r < 4; r++) {
      for (final a in clubes) {
        for (final b in clubes) {
          if (a == b) continue;
          final ea = Equipo(a, modelo.equipos[a]!.$1, modelo.equipos[a]!.$2)
            ..plantel = copiarPlantel(planteles[a]!)
            ..dt = rng.choice(['equilibrado', 'conservador', 'arriesgado', 'impulsivo']);
          final eb = Equipo(b, modelo.equipos[b]!.$1, modelo.equipos[b]!.$2)
            ..plantel = copiarPlantel(planteles[b]!)
            ..dt = rng.choice(['equilibrado', 'conservador', 'arriesgado', 'impulsivo']);
          ea.formacion = formacionPreferida(a, ea.dt);
          eb.formacion = formacionPreferida(b, eb.dt);
          final res = simularPartido(ea, eb, modelo, semilla: '$r|$a|$b');
          goles += res.gl + res.gv;
          if (res.gl == res.gv) empates++;
          if (res.gl > res.gv) locales++;
          n++;
        }
      }
    }
    print('${modelo.divisiones[d]} (${clubes.length}): $n partidos, '
        '${(goles / n).toStringAsFixed(2)} goles, '
        '${(100 * empates / n).toStringAsFixed(1)}% empates, '
        '${(100 * locales / n).toStringAsFixed(1)}% local');
  }
}
