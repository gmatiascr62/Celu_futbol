// Juega varias temporadas seguidas siguiendo a un club, contestando las
// reuniones al azar, y muestra cómo queda la liga. Sirve para ver que la
// economía, los planteles y los goles se mantengan razonables.
// Uso (desde app/): dart run tool/temporadas.dart [temporadas] [club]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:celu_futbol/motor/datos.dart';
import 'package:celu_futbol/motor/jugadores.dart' as J;
import 'package:celu_futbol/motor/mercado.dart' as M;
import 'package:celu_futbol/motor/partido.dart';
import 'package:celu_futbol/motor/torneo.dart';

Map<String, dynamic> leer(String n) => jsonDecode(File('../$n').readAsStringSync());

void main(List<String> args) {
  final temporadas = args.isNotEmpty ? int.parse(args[0]) : 3;
  final club = args.length > 1 ? args[1] : 'Boca Juniors';
  final modelo = armarModelo(leer('modelo_poisson.json'), leer('ascenso.json'));
  cargarPlanteles(leer('planteles.json'));
  cargarCerebro(leer('dt_ia.json'));
  var p = crearPartida(modelo, club, 'equilibrado');
  final azar = math.Random(1);
  var reuniones = 0;
  for (var t = 0; t < temporadas; t++) {
    final goles = List.filled(3, 0), partidos = List.filled(3, 0), empates = List.filled(3, 0);
    while (!p.terminada) {
      // pretemporada: renovar a todos los vencidos y subir a los pibes de 21
      for (final j in [for (final j in p.mi.plantel) if (j.contrato <= 0) j]) {
        final (s, a) = pedidoRenovacion(p, j, pretemporada: true);
        M.firmar(j, s, a);
      }
      if (p.miDt == null) contratar(p, dtsDisponibles(p).first);
      final r = p.reunion;
      if (r != null) {
        p.reunion = null;
        reuniones++;
        resolverReunion(p, r, r.opciones.isEmpty ? null : azar.nextInt(r.opciones.length) + 1);
        if (p.miDt == null) contratar(p, dtsDisponibles(p).first);
      }
      final res = jugarUnaFecha(p, modelo);
      for (final (_, texto, d) in res.resultados) {
        final m = RegExp(r' (\d+)-(\d+) ').firstMatch(texto)!;
        final gl = int.parse(m[1]!), gv = int.parse(m[2]!);
        goles[d] += gl + gv;
        partidos[d]++;
        if (gl == gv) empates[d]++;
      }
      // guardar y volver a cargar, como la app
      p = Partida.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
    }
    final d = p.divisionDe(club);
    final (pos, f) = posicion(p.tablaDivision(d), club);
    print('--- Temporada ${p.temporada}: $club $pos° en ${p.divisiones[d]} (${f.pts} pts)');
    for (var i = 0; i < 3; i++) {
      print('  ${p.divisiones[i]}: ${(goles[i] / partidos[i]).toStringAsFixed(2)} goles, '
          '${(100 * empates[i] / partidos[i]).toStringAsFixed(0)}% empates, '
          'campeón ${ordenarTabla(p.tablaDivision(i)).first.key}');
    }
    final g = p.goleadoresDivision(0).first;
    print('  Goleador: ${g.$1} (${g.$2}) ${g.$3}');
    print('  Noticias de la última fecha: ${p.noticias.length}, reuniones: $reuniones');
    final cambios = cerrarTemporada(p);
    print('  Suben: ${p.historial.last['ascensos']} · Bajan: ${p.historial.last['descensos']}');
    print('  $club: se retiran ${cambios[club]!.$1.length}, llegan ${cambios[club]!.$2.length}');
    empezarTemporada(p);
  }
  final cajas = [for (final e in p.equipos) e.caja / e.ingreso]..sort();
  final tam = [for (final e in p.equipos) e.plantel.length]..sort();
  final niveles = [for (final e in p.equipos) fuerzaTitular(e)]..sort();
  print('Caja/ingreso: min ${cajas.first.toStringAsFixed(2)} mediana '
      '${cajas[30].toStringAsFixed(2)} max ${cajas.last.toStringAsFixed(2)}');
  print('Planteles: ${tam.first} a ${tam.last} · Titulares: '
      '${niveles.first.toStringAsFixed(1)} a ${niveles.last.toStringAsFixed(1)}');
  print('Mi caja: ${M.plata(p.mi.caja)} · Mi DT: ${p.miDt?.completo} '
      '(sat ${p.miDt?.satisfaccion.round()}) · Libres: ${p.libres.length}');
  print('Nivel medio: ${M.nivelMedio(p.equipos).toStringAsFixed(1)} · '
      'Mejor jugador: ${[for (final e in p.equipos) ...e.plantel].map(J.nivel).reduce(math.max)}');
  print('Tamaño del guardado: ${(jsonEncode(p.toJson()).length / 1024).round()} KB');
}
