// El torneo largo: tres divisiones de 20, ida y vuelta, temporadas
// seguidas, con entrenamiento, mercado, DT, hinchada, club y reserva
// (ver simulador_futbol.py). Acá está solo la lógica: las pantallas
// preguntan y muestran.
import 'dart:math' as math;

import 'azar.dart';
import 'club.dart' as C;
import 'datos.dart';
import 'equipo.dart';
import 'jugadores.dart' as J;
import 'jugadores.dart' show Jugador, Mejora;
import 'mercado.dart' as M;
import 'partido.dart';
import 'tecnicos.dart' as T;
import 'tecnicos.dart' show Tecnico, Reunion;

const versionPartida = 1;
const cambiosDeCategoria = 2; // entre cada par de divisiones bajan 2 y suben 2
const subaDeIngresos = 1.5;
const recuperoFecha = 0.25;
const entradas = 0.10;
const _personalidadAlAzar = {'equilibrado': 40, 'conservador': 25, 'arriesgado': 25, 'impulsivo': 10};
const _intensidadDt = {'equilibrado': 'normal', 'conservador': 'suave', 'arriesgado': 'fuerte'};
const prioridad = {
  'renuncia': 100, 'renovacion': 95, 'promesa': 90, 'lo_quieren': 88, 'ultimatum': 80,
  'venta': 70, 'entrenamiento': 65, 'formacion': 65, 'racha': 60, 'refuerzo': 50, 'regular': 10,
};

final _clasicos = {
  for (final par in const [
    ['Boca Juniors', 'River Plate'], ['Racing Club', 'Independiente'],
    ['Rosario Central', 'Newells Old Boys'], ['Estudiantes L.P.', 'Gimnasia L.P.'],
    ['San Lorenzo', 'Huracan'], ['Colon de Santa Fe', 'Union de Santa Fe'],
    ['Talleres Cordoba', 'Belgrano'], ['Lanus', 'Banfield'], ['Velez Sarsfield', 'Ferro'],
    ['Atl. Tucuman', 'San Martin Tucuman'], ['Godoy Cruz', 'Ind. Rivadavia'],
    ['Chacarita', 'Atlanta'], ['Quilmes', 'Arsenal Sarandi'], ['Los Andes', 'Temperley'],
  ])
    (List.of(par)..sort()).join('|')
};

bool esClasico(String a, String b) => _clasicos.contains(([a, b]..sort()).join('|'));

String cara(double h) => h >= 75
    ? '😍'
    : h >= 55
        ? '🙂'
        : h >= 35
            ? '😐'
            : '😡';

class Fila {
  int pj = 0, g = 0, e = 0, p = 0, gf = 0, gc = 0, pts = 0;
  int get dg => gf - gc;
  List<int> toJson() => [pj, g, e, p, gf, gc, pts];
  static Fila fromJson(List d) => Fila()
    ..pj = d[0]
    ..g = d[1]
    ..e = d[2]
    ..p = d[3]
    ..gf = d[4]
    ..gc = d[5]
    ..pts = d[6];
}

/// Fixture de todos contra todos (método del círculo), ida y vuelta.
List<List<(int, int)>> armarFixture(int cantidad, Azar rng) {
  final orden = <int?>[for (var i = 0; i < cantidad; i++) i];
  rng.shuffle(orden);
  if (orden.length.isOdd) orden.add(null);
  final n = orden.length;
  var o = orden;
  final ida = <List<(int, int)>>[];
  for (var ronda = 0; ronda < n - 1; ronda++) {
    final fecha = <(int, int)>[];
    for (var i = 0; i < n ~/ 2; i++) {
      var a = o[i], b = o[n - 1 - i];
      if (a == null || b == null) continue;
      if ((i == 0 && ronda.isOdd) || (i > 0 && i.isOdd)) {
        final t = a;
        a = b;
        b = t;
      }
      fecha.add((a, b));
    }
    ida.add(fecha);
    o = [o[0], o[n - 1], ...o.sublist(1, n - 1)];
  }
  final vuelta = [for (final f in ida) [for (final (a, b) in f) (b, a)]];
  return [...ida, ...vuelta];
}

/// Lo que pasó en el entrenamiento de tu club.
class Informe {
  final (String, String) plan;
  final List<Mejora> mejoras;
  final List<(Jugador, int)> lesionados;
  final bool delDt;
  Informe(this.plan, this.mejoras, this.lesionados, this.delDt);
}

class MiPartido {
  final String local, visitante;
  final ResultadoPartido r;
  MiPartido(this.local, this.visitante, this.r);
}

class ResultadoFecha {
  final List<(bool, String, int)> resultados; // (es mío, texto, división)
  final Informe? informe;
  final List<String> obras;
  final MiPartido? partido;
  ResultadoFecha(this.resultados, this.informe, this.obras, this.partido);
}

/// Una partida del torneo largo.
class Partida {
  List<Equipo> equipos = [];
  String? mio;
  (String, String)? planMio; // null = lo decide el DT
  int temporada = 0;
  int semilla = 0;
  List<Map<String, dynamic>> historial = [];
  Map<String, int> division = {};
  List<String> divisiones = ['Liga Profesional'];
  List<Jugador> libres = [];
  List<M.Oferta> ofertas = [];
  String? ventana;
  List<String> movimientos = [];
  Map<String, List<(String, double)>> sondeos = {};
  List<List<(int, int)>> fixture = [];
  Map<String, Fila> tabla = {};
  Map<String, int> goleadores = {}; // 'corto|club': goles
  int numero = 0;
  Map<String, Tecnico?> tecnicos = {};
  List<Tecnico> dtsLibres = [];
  bool sinDt = false;
  Reunion? reunion;
  List<String> noticias = [];
  List<List<dynamic>> fichajesVentana = [];
  Map<String, String> ultimos = {};
  int proxReunion = 4;
  Map<String, int> esperado = {};
  Map<String, int> esperadoGlobal = {};
  List<String> pedidosDt = [];
  int derrotasFormacion = 0;
  int quejaEntreno = -99;
  List<String> finContratos = [];
  Map<String, List<Miembro>> staffLibres = {};
  bool conReserva = false;

  Equipo get mi => equipos.firstWhere((e) => e.nombre == mio);
  Equipo equipo(String nombre) => equipos.firstWhere((e) => e.nombre == nombre);
  Tecnico? get miDt => mio == null ? null : tecnicos[mio];
  int divisionDe(String club) => division[club] ?? 0;
  int get divisionAMostrar => mio != null ? divisionDe(mio!) : 0;
  int get totalFechas => fixture.length;
  bool get terminada => numero >= fixture.length;

  Map<String, Fila> tablaDivision(int d) =>
      {for (final x in tabla.entries) if (divisionDe(x.key) == d) x.key: x.value};

  /// Los goleadores de una división: [(jugador, club, goles)], de más a menos.
  List<(String, String, int)> goleadoresDivision(int d) {
    final lista = [
      for (final x in goleadores.entries)
        if (divisionDe(x.key.split('|')[1]) == d)
          (x.key.split('|')[0], x.key.split('|')[1], x.value)
    ];
    lista.sort((a, b) => b.$3.compareTo(a.$3));
    return lista;
  }

  // ---------------------------------------------------------------- guardado
  Map<String, dynamic> toJson() => {
        'version': versionPartida,
        'equipos': [for (final e in equipos) e.toJson()],
        'mio': mio,
        'plan_mio': planMio == null ? null : [planMio!.$1, planMio!.$2],
        'temporada': temporada, 'semilla': semilla, 'historial': historial,
        'division': division, 'divisiones': divisiones,
        'libres': [for (final j in libres) j.toJson()],
        'ofertas': [for (final o in ofertas) [o.club, o.j.completo, o.monto]],
        'ventana': ventana, 'movimientos': movimientos,
        'sondeos': {
          for (final x in sondeos.entries) x.key: [for (final (c, m) in x.value) [c, m]]
        },
        'fixture': [for (final f in fixture) [for (final (a, b) in f) [a, b]]],
        'tabla': {for (final x in tabla.entries) x.key: x.value.toJson()},
        'goleadores': goleadores, 'numero': numero,
        'tecnicos': {for (final x in tecnicos.entries) x.key: x.value?.toJson()},
        'dts_libres': [for (final t in dtsLibres) t.toJson()],
        'sin_dt': sinDt, 'reunion': reunion?.toJson(), 'noticias': noticias,
        'fichajes_ventana': fichajesVentana, 'ultimos': ultimos, 'prox_reunion': proxReunion,
        'esperado': esperado, 'esperado_global': esperadoGlobal, 'pedidos_dt': pedidosDt,
        'derrotas_formacion': derrotasFormacion, 'queja_entreno': quejaEntreno,
        'fin_contratos': finContratos,
        'staff_libres': {
          for (final x in staffLibres.entries) x.key: [for (final m in x.value) m.toJson()]
        },
        'con_reserva': conReserva,
      };

  static Partida? fromJson(Map<String, dynamic> d) {
    if (d['version'] != versionPartida) return null;
    final p = Partida();
    p.equipos = [for (final e in d['equipos']) Equipo.fromJson(Map<String, dynamic>.from(e))];
    p.mio = d['mio'];
    final pm = d['plan_mio'];
    p.planMio = pm == null ? null : (pm[0] as String, pm[1] as String);
    p.temporada = d['temporada'];
    p.semilla = d['semilla'];
    p.historial = [for (final h in d['historial']) Map<String, dynamic>.from(h)];
    p.division = Map<String, int>.from(d['division']);
    p.divisiones = List<String>.from(d['divisiones']);
    p.libres = [for (final j in d['libres']) Jugador.fromJson(Map<String, dynamic>.from(j))];
    final mios = p.mio == null
        ? <String, Jugador>{}
        : {for (final j in [...p.mi.plantel, ...p.mi.reserva]) j.completo: j};
    p.ofertas = [
      for (final o in d['ofertas'])
        if (mios.containsKey(o[1])) M.Oferta(o[0], mios[o[1]]!, (o[2] as num).toDouble())
    ];
    p.ventana = d['ventana'];
    p.movimientos = List<String>.from(d['movimientos']);
    p.sondeos = {
      for (final x in (d['sondeos'] as Map).entries)
        x.key as String: [for (final o in x.value) (o[0] as String, (o[1] as num).toDouble())]
    };
    p.fixture = [
      for (final f in d['fixture']) [for (final x in f) (x[0] as int, x[1] as int)]
    ];
    p.tabla = {for (final x in (d['tabla'] as Map).entries) x.key as String: Fila.fromJson(x.value)};
    p.goleadores = Map<String, int>.from(d['goleadores']);
    p.numero = d['numero'];
    p.tecnicos = {
      for (final x in (d['tecnicos'] as Map).entries)
        x.key as String:
            x.value == null ? null : Tecnico.fromJson(Map<String, dynamic>.from(x.value))
    };
    p.dtsLibres = [for (final t in d['dts_libres']) Tecnico.fromJson(Map<String, dynamic>.from(t))];
    p.sinDt = d['sin_dt'];
    p.reunion = d['reunion'] == null ? null : Reunion.fromJson(Map<String, dynamic>.from(d['reunion']));
    p.noticias = List<String>.from(d['noticias']);
    p.fichajesVentana = [for (final f in d['fichajes_ventana']) List<dynamic>.from(f)];
    p.ultimos = Map<String, String>.from(d['ultimos']);
    p.proxReunion = d['prox_reunion'];
    p.esperado = Map<String, int>.from(d['esperado']);
    p.esperadoGlobal = Map<String, int>.from(d['esperado_global']);
    p.pedidosDt = List<String>.from(d['pedidos_dt']);
    p.derrotasFormacion = d['derrotas_formacion'];
    p.quejaEntreno = d['queja_entreno'];
    p.finContratos = List<String>.from(d['fin_contratos']);
    p.staffLibres = {
      for (final x in (d['staff_libres'] as Map).entries)
        x.key as String: [for (final m in x.value) Miembro.fromJson(Map<String, dynamic>.from(m))]
    };
    p.conReserva = d['con_reserva'];
    return p;
  }
}

// ---------------------------------------------------------------- tabla
List<MapEntry<String, Fila>> ordenarTabla(Map<String, Fila> tabla) {
  final filas = tabla.entries.toList();
  final orden = {for (var i = 0; i < filas.length; i++) filas[i].key: i};
  filas.sort((a, b) {
    for (final c in [
      b.value.pts.compareTo(a.value.pts),
      b.value.dg.compareTo(a.value.dg),
      b.value.gf.compareTo(a.value.gf),
    ]) {
      if (c != 0) return c;
    }
    return orden[a.key]!.compareTo(orden[b.key]!);
  });
  return filas;
}

(int, Fila) posicion(Map<String, Fila> tabla, String nombre) {
  final orden = ordenarTabla(tabla);
  final i = orden.indexWhere((x) => x.key == nombre);
  return (i + 1, orden[i].value);
}

void anotar(Map<String, Fila> tabla, Equipo local, Equipo visitante, int gl, int gv) {
  for (final (eq, gf, gc) in [(local, gl, gv), (visitante, gv, gl)]) {
    final f = tabla[eq.nombre]!;
    f.pj += 1;
    f.gf += gf;
    f.gc += gc;
    if (gf > gc) {
      f.g += 1;
      f.pts += 3;
    } else if (gf == gc) {
      f.e += 1;
      f.pts += 1;
    } else {
      f.p += 1;
    }
  }
}

// ---------------------------------------------------------------- entrenamiento
/// El DT elige el entrenamiento de la semana.
(String, String) planDt(Equipo eq, Azar rng) {
  final sanos = eq.plantel.where((j) => j.lesion == 0).toList();
  final fisico = sanos.fold(0.0, (a, j) => a + j.fisico) / math.max(1, sanos.length);
  if (fisico < 0.85) return ('descanso', 'suave');
  if (eq.dt == 'impulsivo') {
    return (rng.choice(const ['completo', 'ataque', 'defensa', 'fisico']),
        rng.choice(J.intensidades.keys.toList()));
  }
  var intensidad = _intensidadDt[eq.dt] ?? 'normal';
  if (intensidad == 'fuerte' && fisico < 0.92) intensidad = 'normal';
  final fz = J.fuerza(J.armarXi(J.aptos(eq.plantel), J.formacionBase, false));
  final a = fz.ataque, d = fz.defensa;
  if (a < -d - 0.05) return ('ataque', intensidad);
  if (-d < a - 0.05) return ('defensa', intensidad);
  return ('completo', intensidad);
}

// ---------------------------------------------------------------- partida nueva
Partida crearPartida(Modelo modelo, String? mio, [String dtMio = 'equilibrado']) {
  final p = Partida();
  final clubes = (modelo.division.isNotEmpty ? modelo.division.keys : planteles.keys).toList()
    ..sort();
  for (final c in clubes) {
    final (a, d) = modelo.equipos[c]!;
    final e = Equipo(c, a, d)..plantel = J.copiarPlantel(planteles[c]!);
    if (c == mio) {
      e.dt = dtMio;
    } else {
      e.dt = Azar('dt|$c')
          .choices(_personalidadAlAzar.keys.toList(), _personalidadAlAzar.values.toList());
    }
    e.formacion = formacionPreferida(c, e.dt);
    p.equipos.add(e);
  }
  M.iniciarContratos([for (final e in p.equipos) e.plantel], Azar('$mio|contratos'));
  M.iniciarFinanzas(p.equipos);
  p.mio = mio;
  p.semilla = math.Random().nextInt(1 << 30);
  p.division = {for (final c in clubes) c: modelo.division[c] ?? 0};
  p.divisiones = List.of(modelo.divisiones);
  empezarTemporada(p, primera: true);
  iniciarTecnicos(p);
  iniciarClub(p);
  iniciarReserva(p);
  return p;
}

void empezarTemporada(Partida p, {bool primera = false}) {
  p.temporada += 1;
  for (final e in p.equipos) {
    for (final j in e.plantel) {
      j.fisico = 1.0;
    }
  }
  final rng = Azar('${p.semilla}|${p.temporada}');
  p.fixture = [];
  for (var d = 0; d < p.divisiones.length; d++) {
    final indices = [
      for (var i = 0; i < p.equipos.length; i++) if (p.divisionDe(p.equipos[i].nombre) == d) i
    ];
    final fx = armarFixture(indices.length, rng);
    for (var k = 0; k < fx.length; k++) {
      if (k == p.fixture.length) p.fixture.add([]);
      p.fixture[k].addAll([for (final (a, b) in fx[k]) (indices[a], indices[b])]);
    }
  }
  p.tabla = {for (final e in p.equipos) e.nombre: Fila()};
  p.goleadores = {};
  p.numero = 0;
  for (final e in p.equipos) {
    for (final j in e.plantel) {
      j.partidos = 0;
    }
  }
  if (!primera) {
    arrancarTemporadaDt(p);
    renovarStaffLibres(p);
  }
}

/// Quiénes bajan y quiénes suben: [(club, de, a)].
List<(String, int, int)> cambiosDeCategoriaDe(Partida p) {
  final cambios = <(String, int, int)>[];
  for (var d = 0; d < p.divisiones.length - 1; d++) {
    final arriba = [for (final x in ordenarTabla(p.tablaDivision(d))) x.key];
    final abajo = [for (final x in ordenarTabla(p.tablaDivision(d + 1))) x.key];
    cambios.addAll([for (final n in arriba.sublist(arriba.length - cambiosDeCategoria)) (n, d, d + 1)]);
    cambios.addAll([for (final n in abajo.take(cambiosDeCategoria)) (n, d + 1, d)]);
  }
  return cambios;
}

/// Anota los campeones, hace los ascensos y descensos y pasa el año de los
/// planteles. Devuelve, por club, (retirados, juveniles).
Map<String, (List<Jugador>, List<Jugador>)> cerrarTemporada(Partida p) {
  final registro = <String, dynamic>{'temporada': p.temporada, 'campeones': []};
  for (var d = 0; d < p.divisiones.length; d++) {
    final orden = ordenarTabla(p.tablaDivision(d));
    registro['campeones'].add([p.divisiones[d], orden[0].key, orden[0].value.pts]);
    M.premios([for (final e in p.equipos) if (p.divisionDe(e.nombre) == d) e],
        [for (final x in orden) x.key], p.mio);
  }
  registro['campeon'] = registro['campeones'][0][1];
  registro['puntos'] = registro['campeones'][0][2];
  final g = p.goleadoresDivision(0);
  registro['goleador'] = g.isEmpty ? '-' : '${g[0].$1} (${g[0].$2}), ${g[0].$3}';
  if (p.mio != null) {
    final d = p.divisionDe(p.mio!);
    registro['puesto'] = posicion(p.tablaDivision(d), p.mio!).$1;
    registro['division_mio'] = p.divisiones[d];
  }
  registro['ascensos'] = <String>[];
  registro['descensos'] = <String>[];
  balanceDeTemporada(p, registro);
  for (final c in registro['campeones']) {
    final e = p.equipo(c[1]);
    e.hinchada = math.min(100.0, e.hinchada + 15);
  }
  for (final (club, de, a) in cambiosDeCategoriaDe(p)) {
    p.division[club] = a;
    final e = p.equipo(club);
    e.hinchada = math.max(0.0, math.min(100.0, e.hinchada + (a < de ? 15 : -20)));
    if (a < de) {
      e.ingreso = M.r3(e.ingreso * subaDeIngresos);
      registro['ascensos'].add(club);
    } else {
      e.ingreso = M.r3(e.ingreso / subaDeIngresos);
      registro['descensos'].add(club);
    }
  }
  p.historial.add(registro);
  for (final j in p.libres) {
    j.edad += 1;
  }
  final rng = Azar('${p.semilla}|${p.temporada}|retiros');
  final usados = {for (final e in p.equipos) for (final j in e.plantel) j.completo};
  for (final e in p.equipos) {
    for (final j in e.plantel) {
      j.contrato -= 1;
    }
  }
  final cambios = <String, (List<Jugador>, List<Jugador>)>{};
  for (final e in p.equipos) {
    final c = J.pasarTemporada(e.plantel, e.ataque, e.defensa, rng, usados,
        cantera: e.instalaciones.isNotEmpty ? C.cantera(e) : 0.0, reponer: !p.conReserva);
    for (final j in c.$2) {
      M.firmar(j, null, 3);
    }
    cambios[e.nombre] = c;
  }
  p.finContratos = M.vencimientosIa(p.equipos, p.mio, p.libres, rng);
  if (p.conReserva) {
    usados.addAll([for (final e in p.equipos) for (final j in e.reserva) j.completo]);
    for (final e in p.equipos) {
      C.pasarAnioReserva(e, rng);
      if (e.nombre != p.mio) C.reservaIa(e);
      final nuevos = C.lleganPibes(e, rng, usados);
      cambios[e.nombre] = (cambios[e.nombre]!.$1, [...cambios[e.nombre]!.$2, ...nuevos]);
    }
  }
  contratosDt(p);
  return cambios;
}

void balanceDeTemporada(Partida p, Map<String, dynamic> registro) {
  final campeones = {for (final c in registro['campeones']) c[1] as String: c[0] as String};
  final cambios = {for (final (club, de, a) in cambiosDeCategoriaDe(p)) club: (de, a)};
  for (final e in p.equipos) {
    final t = p.tecnicos[e.nombre];
    if (t == null) continue;
    final puesto = posicion(p.tablaDivision(p.divisionDe(e.nombre)), e.nombre).$1;
    T.cambiarPrestigio(t, math.max(-6, math.min(6, 0.6 * (p.esperado[e.nombre]! - puesto))));
    if (campeones.containsKey(e.nombre)) {
      T.cambiarPrestigio(t, 8);
      t.logros.add('🏆 Campeón ${campeones[e.nombre]} T${p.temporada} con ${e.nombre}');
    }
    final c = cambios[e.nombre];
    if (c != null) {
      if (c.$2 < c.$1) {
        T.cambiarPrestigio(t, 6);
        t.logros.add('⬆ Ascendió con ${e.nombre} T${p.temporada}');
      } else {
        T.cambiarPrestigio(t, -6);
        t.logros.add('⬇ Descendió con ${e.nombre} T${p.temporada}');
      }
    }
  }
}

// ---------------------------------------------------------------- hinchada
double pesoMedios(Partida p, String club) {
  if (p.divisionDe(club) > 0) return 0.8;
  return p.esperadoGlobal[club]! <= 6 ? 1.4 : 1.0;
}

void cambiarHinchada(Equipo e, double delta) =>
    e.hinchada = math.max(0.0, math.min(100.0, e.hinchada + delta));

void hinchadaFecha(Partida p, List<(Equipo, Equipo, int, int)> partidos) {
  for (final (local, visitante, gl, gv) in partidos) {
    final clasico = esClasico(local.nombre, visitante.nombre);
    for (final (e, gf, gc) in [(local, gl, gv), (visitante, gv, gl)]) {
      final antes = e.hinchada;
      var cambio = gf > gc
          ? 3.0
          : gf == gc
              ? -0.5
              : -3.0;
      if (clasico) cambio *= 2.5;
      e.hinchada = math.max(0.0, math.min(100.0, e.hinchada + cambio + 0.03 * (60 - e.hinchada)));
      if (e.nombre == p.mio) {
        final t = p.miDt;
        if (antes >= 30 && 30 > e.hinchada && t != null) {
          p.noticias.add('📰 Silbidos en la cancha de ${p.mio}: la hinchada pide la cabeza '
              'de ${t.completo}.');
        } else if (antes <= 85 && 85 < e.hinchada) {
          p.noticias.add('📰 ¡Banderazo! La hinchada de ${p.mio} está de fiesta.');
        }
      }
    }
    if (clasico && p.divisionDe(local.nombre) == p.divisionAMostrar) {
      p.noticias.add('📰 Clásico: ${local.nombre} $gl-$gv ${visitante.nombre}');
    }
  }
  for (final e in p.equipos) {
    e.caja += entradas * e.ingreso * (e.hinchada - 60) / 40 / p.fixture.length;
  }
}

// ---------------------------------------------------------------- una fecha
/// Juega la próxima fecha de todas las divisiones, con el entrenamiento,
/// las finanzas, los DT y la hinchada de la semana. Con relato, guarda el
/// relato de tu partido.
ResultadoFecha jugarUnaFecha(Partida p, Modelo modelo, {bool relato = false}) {
  final equipos = p.equipos, mio = p.mio;
  abrirVentana(p);
  final cierra = ventanaActual(p);
  for (final e in equipos) {
    e.moral = T.moral(p.tecnicos[e.nombre]);
  }
  final marcadores = <String, (int, int)>{};
  final partidos = <(Equipo, Equipo, int, int)>[];
  final fecha = p.fixture[p.numero];
  p.numero += 1;
  final clave = '${p.semilla}|${p.temporada}|${p.numero}';
  final resultados = <(bool, String, int)>[];
  Informe? informe;
  final obras = <String>[];
  MiPartido? miPartido;
  for (final (l, v) in fecha) {
    final local = equipos[l], visitante = equipos[v];
    final esMio = mio == local.nombre || mio == visitante.nombre;
    final r = simularPartido(local, visitante, modelo,
        semilla: '$clave|$l|$v', relato: esMio && relato);
    anotar(p.tabla, local, visitante, r.gl, r.gv);
    marcadores[local.nombre] = (r.gl, r.gv);
    marcadores[visitante.nombre] = (r.gv, r.gl);
    partidos.add((local, visitante, r.gl, r.gv));
    for (final g in r.goles) {
      final k = '${g.autor.corto}|${(g.lado == 0 ? local : visitante).nombre}';
      p.goleadores[k] = (p.goleadores[k] ?? 0) + 1;
    }
    resultados.add((esMio, '${local.nombre} ${r.gl}-${r.gv} ${visitante.nombre}',
        p.divisionDe(local.nombre)));
    if (esMio) miPartido = MiPartido(local.nombre, visitante.nombre, r);
  }
  // Recuperación y entrenamiento de la semana
  final rngEntreno = Azar('$clave|entrenamiento');
  for (final e in equipos) {
    for (final j in e.plantel) {
      j.fisico = math.min(1.0, j.fisico + recuperoFecha + C.recuperoExtra(e));
    }
    final plan = e.nombre == mio && p.planMio != null ? p.planMio! : planDt(e, rngEntreno);
    final (mejoras, lesionados) =
        J.entrenar(e.plantel, plan.$1, plan.$2, rngEntreno, C.multiplicadores(e));
    J.entrenar(e.reserva, 'completo', 'suave', rngEntreno, C.multiplicadores(e));
    if (e.nombre == mio) informe = Informe(plan, mejoras, lesionados, p.planMio == null);
  }
  M.cobrarFecha(equipos, p.fixture.length);
  for (final e in equipos) {
    C.pagarFecha(e, p.fixture.length);
    for (final tipo in C.avanzarObras(e)) {
      if (e.nombre == mio) {
        obras.add('🏗 Terminó la obra: ${C.instalacionesNombres[tipo]} nivel '
            '${e.instalaciones[tipo]}.');
      }
    }
  }
  trasFechaDt(p, marcadores, cierra);
  hinchadaFecha(p, partidos);
  return ResultadoFecha(resultados, informe, obras, miPartido);
}

// ---------------------------------------------------------------- técnicos
double fuerzaTitular(Equipo e) {
  final niveles = [for (final j in e.plantel) J.nivel(j)]..sort((a, b) => b.compareTo(a));
  final top = niveles.take(11).toList();
  return top.reduce((a, b) => a + b) / top.length;
}

void calcularEsperado(Partida p) {
  final fz = {for (final e in p.equipos) e.nombre: fuerzaTitular(e)};
  final orden = List.of(p.equipos)
    ..sort((a, b) {
      final c = p.divisionDe(a.nombre).compareTo(p.divisionDe(b.nombre));
      return c != 0 ? c : fz[b.nombre]!.compareTo(fz[a.nombre]!);
    });
  p.esperadoGlobal = {for (var i = 0; i < orden.length; i++) orden[i].nombre: i + 1};
  p.esperado = {};
  for (var d = 0; d < p.divisiones.length; d++) {
    final enD = [for (final e in orden) if (p.divisionDe(e.nombre) == d) e];
    for (var i = 0; i < enD.length; i++) {
      p.esperado[enD[i].nombre] = i + 1;
    }
  }
}

void iniciarTecnicos(Partida p) {
  final rng = Azar('${p.semilla}|tecnicos');
  calcularEsperado(p);
  final usados = <String>{};
  p.tecnicos = {};
  final total = p.equipos.length;
  for (final e in p.equipos) {
    if (e.dt == null) continue;
    final prestigio = T.prestigioPara(p.esperadoGlobal[e.nombre]!, total, rng);
    final t = T.nuevo(rng, usados, e.dt, prestigio);
    p.tecnicos[e.nombre] = t;
    T.llegaA(t, e.nombre, p.temporada);
    e.ingreso += t.sueldo;
  }
  p.dtsLibres = [];
  T.bolsaLibres(p.dtsLibres, rng, usados);
  p.sinDt = p.mio != null && !p.tecnicos.containsKey(p.mio);
  p.reunion = null;
  p.noticias = [];
  p.fichajesVentana = [];
  p.ultimos = {for (final e in p.equipos) e.nombre: ''};
  p.proxReunion = 4;
}

void arrancarTemporadaDt(Partida p) {
  calcularEsperado(p);
  p.ultimos = {for (final e in p.equipos) e.nombre: ''};
  p.proxReunion = 4;
  for (final t in p.tecnicos.values) {
    if (t != null) t.presion = 40.0;
  }
  final usados = {for (final t in p.tecnicos.values) if (t != null) t.completo};
  T.bolsaLibres(p.dtsLibres, Azar('${p.semilla}|${p.temporada}|dts'), usados);
}

/// Deja una reunión pendiente con tu DT, si es más importante que la que había.
void proponer(Partida p, Reunion reunion, String tema) {
  reunion.prioridad = prioridad[tema]!;
  final actual = p.reunion;
  if (actual == null || reunion.prioridad >= actual.prioridad) p.reunion = reunion;
}

/// El puesto más flojo, el nivel que tiene hoy y la ventana en que se tiene
/// que cumplir si se le promete.
(String, int, String) pedidoDeRefuerzo(Partida p, [String? abierta]) {
  final (pos, actual) = M.necesidad(p.mi);
  final ventana = T.proximaVentana(p.temporada, p.numero, p.fixture.length, abierta);
  return (pos, J.redondear(actual), ventana);
}

/// Lo que le prometiste al DT para la ventana abierta y todavía no llegó.
List<Map<String, dynamic>> promesasPendientes(Partida p) {
  final t = p.miDt, clave = ventanaActual(p);
  if (t == null || clave == null) return [];
  final staff = {for (final r in C.roles.keys) r: p.mi.nivelStaff(r)};
  return [
    for (final pr in t.promesas)
      if (pr['ventana'] == clave && !T.cumple(pr, p.fichajesVentana, staff)) pr
  ];
}

Map<String, int> nivelesStaff(Equipo e) => {for (final r in C.roles.keys) r: e.nivelStaff(r)};

/// Los jugadores que el DT propone para el puesto: [(nombre, línea)].
List<(String, String)> candidatosDelDt(Partida p, Tecnico t, String pos, int nivel, Azar rng) {
  final lista = M.recomendar(
      p.equipos, p.mi, p.libres, pos, nivel + 3.0, t.personalidad, t.prestigio, rng);
  final salida = <(String, String)>[];
  for (var i = 0; i < lista.length; i++) {
    final (j, club, precio) = lista[i];
    final donde = club != null
        ? '${club.nombre}, piden ${M.plata(precio)}'
        : 'libre, pide ${M.plata(M.sueldoPedido(j))}/año';
    final gusta = i == 0 ? ' · ★ mi preferido' : '';
    final puesto = j.pos == pos ? j.pos : '${j.pos}→$pos';
    salida.add((j.completo, '${j.corto} ($puesto, ${j.edad}a, Nv${J.nivel(j)}): $donde$gusta'));
  }
  return salida;
}

double _costoRefuerzo(int nivel) => 1.2 * math.exp(0.13 * (nivel + 3 - 70));

void pedidoDeMercado(Partida p, String clave) {
  final t = p.miDt;
  if (t == null) return;
  final (pos, nivel, ventana) = pedidoDeRefuerzo(p, clave);
  if (t.promesas.any((pr) => pr['ventana'] == clave)) return;
  final rng = Azar('${p.semilla}|$clave|pedido');
  proponer(
      p,
      T.reunionRefuerzo(t, rng, pos, nivel, p.mi.caja, _costoRefuerzo(nivel), ventana, true,
          candidatosDelDt(p, t, pos, nivel, rng)),
      'refuerzo');
}

/// Si vendés a un titular, el DT se entera; si es una figura, la hinchada también.
List<String> avisoVenta(Partida p, Jugador j) {
  final mi = p.mi;
  final textos = <String>[];
  if (M.figuras(mi).contains(j)) {
    cambiarHinchada(mi, -8);
    textos.add('😡 A la hinchada no le gustó que se vaya ${j.corto}.');
  }
  final t = p.miDt;
  if (t == null || !M.titulares(mi).contains(j)) return textos;
  final rng = Azar('${p.semilla}|venta|${j.completo}');
  proponer(p, T.reunionVenta(t, rng, j.corto, j.pos, p.ventana), 'venta');
  return textos;
}

void reemplazarDt(Partida p, Equipo e, Azar rng, String motivo) {
  final viejo = p.tecnicos[e.nombre];
  final buscado = T.prestigioPara(p.esperadoGlobal[e.nombre]!, p.equipos.length, rng);
  final candidatos = [for (final t in p.dtsLibres) if (t.ultimoClub != e.nombre) t];
  final puntos = {for (final t in candidatos) t: (t.prestigio - buscado).abs() + rng.random() * 5};
  final nuevo = candidatos.reduce((a, b) => puntos[b]! < puntos[a]! ? b : a);
  p.dtsLibres.remove(nuevo);
  T.reiniciar(nuevo);
  p.tecnicos[e.nombre] = nuevo;
  T.llegaA(nuevo, e.nombre, p.temporada);
  e.dt = nuevo.personalidad;
  e.formacion = formacionPreferida('${e.nombre}|${nuevo.apellido}', e.dt);
  if (viejo != null) {
    T.reiniciar(viejo);
    T.seVaDe(viejo, p.temporada);
    if (motivo == 'echó') {
      viejo.despidos += 1;
      T.cambiarPrestigio(viejo, -4);
    }
    viejo.ultimoClub = e.nombre;
    p.dtsLibres.add(viejo);
    p.noticias.add('📰 ${e.nombre} $motivo a ${viejo.completo}. Asume ${nuevo.completo} '
        '(${nuevo.personalidad}).');
  }
}

int _finalCon(String s, String letras) {
  var n = 0;
  for (var i = s.length - 1; i >= 0 && letras.contains(s[i]); i--) {
    n++;
  }
  return n;
}

/// Después de cada fecha: ánimo de todos los DT, despidos en los otros
/// clubes, y lo que te quiere plantear el tuyo.
void trasFechaDt(Partida p, Map<String, (int, int)> marcadores, String? cierra) {
  p.noticias = [];
  final rng = Azar('${p.semilla}|${p.temporada}|${p.numero}|dt');
  final jugadas = p.numero;
  for (final e in p.equipos) {
    final (gf, gc) = marcadores[e.nombre] ?? (0, 0);
    final u = (p.ultimos[e.nombre] ?? '') + (gf > gc ? 'G' : gf == gc ? 'E' : 'P');
    p.ultimos[e.nombre] = u.length > 10 ? u.substring(u.length - 10) : u;
    final t = p.tecnicos[e.nombre];
    if (t == null) continue;
    T.trasPartido(t, gf, gc);
    final puesto = posicion(p.tablaDivision(p.divisionDe(e.nombre)), e.nombre).$1;
    T.actualizarPresion(t, puesto, p.esperado[e.nombre]!, p.ultimos[e.nombre]!, jugadas,
        pesoMedios(p, e.nombre), e.hinchada);
    if (e.nombre != p.mio && T.loEchan(t, rng)) reemplazarDt(p, e, rng, 'echó');
  }
  for (final e in p.equipos) {
    final t = p.tecnicos[e.nombre];
    if (t != null) e.caja -= t.sueldo / p.fixture.length;
  }
  final t = p.miDt;
  if (t == null) return;
  final mi = p.mi;
  final (pos, nivel, ventana) = pedidoDeRefuerzo(p);
  if (cierra != null) {
    for (final (promesa, ok, exacto)
        in T.revisarPromesas(t, cierra, p.fichajesVentana, nivelesStaff(mi))) {
      proponer(p, T.reunionPromesa(t, rng, promesa, ok, exacto), 'promesa');
    }
    p.pedidosDt = [];
  }
  if (t.satisfaccion < T.renuncia) {
    proponer(p, T.reunionRenuncia(t, rng), 'renuncia');
    return;
  }
  if (t.satisfaccion < T.ultimatum && !t.avisos.contains('ultimatum')) {
    t.avisos.add('ultimatum');
    proponer(p, T.reunionUltimatum(t, rng, pos, nivel, ventana), 'ultimatum');
    return;
  }
  if (t.satisfaccion > 50) t.avisos.remove('ultimatum');
  final (gf, gc) = marcadores[mi.nombre] ?? (0, 0);
  opinionesTrasFecha(p, t, mi, gf, gc, rng);
  final ultimos = p.ultimos[mi.nombre]!;
  final sinGanar = _finalCon(ultimos, 'EP');
  final sinPerder = _finalCon(ultimos, 'GE');
  if ([3, 5, 7].contains(sinGanar)) {
    proponer(p, T.reunionRacha(t, rng, sinGanar, true, pos, nivel, ventana), 'racha');
  } else if ([5, 8].contains(sinPerder) && ultimos.endsWith('G')) {
    proponer(p, T.reunionRacha(t, rng, sinPerder, false, pos, nivel, ventana), 'racha');
  } else if (jugadas >= p.proxReunion) {
    p.proxReunion = jugadas + rng.randint(3, 5);
    final peor = mi.plantel.map(J.nivel).reduce(math.min);
    final tits = M.titulares(mi);
    final juveniles = [
      for (final j in [...mi.plantel, ...mi.reserva])
        if (j.edad <= 21 &&
            j.potencial - J.nivel(j) >= 8 &&
            (mi.reserva.contains(j) ? J.nivel(j) >= peor : !tits.contains(j)) &&
            !t.avisos.contains('juvenil:${j.completo}'))
          j
    ];
    final prometido = t.promesas.any((pr) => pr['pos'] == pos);
    final vencen = [
      for (final j in mi.plantel)
        if (j.contrato == 1 &&
            tits.contains(j) &&
            jugadas >= p.fixture.length ~/ 2 - 3 &&
            !t.avisos.contains('vence:${j.completo}|${p.temporada}'))
          j
    ];
    final sueldos = [for (final j in mi.plantel) M.sueldo(j)]..sort();
    final noUsa = [
      for (final j in mi.plantel)
        if (jugadas >= 10 &&
            j.partidos <= 0.2 * jugadas &&
            j.edad > 21 &&
            M.sueldo(j) >= sueldos[sueldos.length ~/ 2] &&
            !t.avisos.contains('no_usa:${j.completo}|${p.temporada}'))
          j
    ];
    final sinStaff = mi.instalaciones.isEmpty
        ? <String>[]
        : [
            for (final r in C.roles.keys)
              if (mi.nivelStaff(r) <= 1 && !t.promesas.any((pr) => pr['rol'] == r)) r
          ];
    final opciones = [
      if (juveniles.isNotEmpty) 'juvenil',
      if (!prometido) 'refuerzo',
      if (vencen.isNotEmpty) 'vence',
      if (noUsa.isNotEmpty) 'no_usa',
      if (sinStaff.isNotEmpty) 'staff',
    ];
    final tema = opciones.isNotEmpty && rng.random() < 0.7 ? rng.choice(opciones) : 'general';
    if (tema == 'general' && rng.random() < 0.5) return;
    final Reunion reunion;
    switch (tema) {
      case 'staff':
        final rol = rng.choice(sinStaff);
        reunion = T.reunionStaff(t, rng, rol, C.roles[rol]!, ventana);
      case 'vence':
        final j = vencen.reduce((a, b) => J.nivel(b) > J.nivel(a) ? b : a);
        t.avisos.add('vence:${j.completo}|${p.temporada}');
        reunion = T.reunionVence(t, rng, j);
      case 'no_usa':
        final j = noUsa.reduce((a, b) => M.sueldo(b) > M.sueldo(a) ? b : a);
        t.avisos.add('no_usa:${j.completo}|${p.temporada}');
        reunion = T.reunionNoUsa(t, rng, j, j.partidos);
      case 'juvenil':
        final j = juveniles.reduce((a, b) => b.potencial > a.potencial ? b : a);
        t.avisos.add('juvenil:${j.completo}');
        reunion = T.reunionJuvenil(t, rng, j, mi.reserva.contains(j));
      case 'refuerzo':
        reunion = T.reunionRefuerzo(t, rng, pos, nivel, mi.caja, _costoRefuerzo(nivel), ventana,
            false, candidatosDelDt(p, t, pos, nivel, rng));
      default:
        reunion = T.reunionGeneral(t, rng);
    }
    proponer(p, reunion, 'regular');
  }
}

/// Fin de temporada: un año menos de contrato para los DT.
void contratosDt(Partida p) {
  final rng = Azar('${p.semilla}|${p.temporada}|contratos');
  final cambiaron = <Equipo>[];
  for (final e in p.equipos) {
    final t = p.tecnicos[e.nombre];
    if (t == null) continue;
    t.contrato -= 1;
    if (t.contrato > 0) continue;
    if (e.nombre == p.mio) {
      proponer(p, T.reunionRenovacion(t, rng, M.r3(t.sueldo * 1.1)), 'renovacion');
    } else if (t.presion < 60) {
      t.contrato = 2;
    } else {
      reemplazarDt(p, e, rng, 'no le renovó');
      cambiaron.add(e);
    }
  }
  final t = p.miDt;
  if (t == null) return;
  final masGrandes = [
    for (final e in cambiaron)
      if (p.esperadoGlobal[e.nombre]! < p.esperadoGlobal[p.mio]! &&
          t.prestigio >= p.tecnicos[e.nombre]!.prestigio + 5)
        e
  ];
  if (masGrandes.isNotEmpty && rng.random() < 0.6) {
    final club = masGrandes
        .reduce((a, b) => p.esperadoGlobal[b.nombre]! < p.esperadoGlobal[a.nombre]! ? b : a)
        .nombre;
    proponer(p, T.reunionLoQuieren(t, rng, club), 'lo_quieren');
  }
}

/// Aplica la respuesta n (desde 1; null si la reunión no tenía opciones).
/// Devuelve los textos para mostrar.
List<String> resolverReunion(Partida p, Reunion r, int? n) {
  final t = p.miDt;
  if (t == null) return [];
  if (r.tema == 'renuncia' || r.tema == 'no_renueva') return [seVaMiDt(p)];
  if (n == null) return [];
  final mi = p.mi;
  final (extra, respuesta) = T.aplicar(t, r.opciones[n - 1]);
  final textos = ['«$respuesta»'];
  if (r.candidatos.isNotEmpty && n <= 2) {
    p.pedidosDt = List.of(r.candidatos);
    if (n == 1) textos.add('Lo vas a encontrar en el mercado, en los pedidos del DT.');
  }
  if (extra == null) return textos;
  if (extra.containsKey('renovar')) {
    if (extra['renovar'] > 0) {
      t.contrato = extra['renovar'];
      t.aumento = M.r3(t.aumento * 1.1);
      textos.add('Renovó por ${t.contrato} temporadas.');
    } else {
      textos.add(seVaMiDt(p));
    }
  } else if (extra.containsKey('oferta')) {
    textos.add(seVaAOtroClub(p, t, extra['oferta']));
  } else if (extra.containsKey('aumento')) {
    t.aumento = M.r3(t.aumento * (extra['aumento'] as num));
    textos.add('Ahora cobra ${M.plata(t.sueldo)}/año.');
  } else if (extra.containsKey('plan')) {
    p.planMio = null;
    textos.add('El entrenamiento lo decide el DT.');
  } else if (extra.containsKey('subir')) {
    final pibe = mi.reserva.where((j) => j.completo == extra['subir']).firstOrNull;
    if (pibe != null && mi.plantel.length < M.plantelMax) {
      C.subir(mi, pibe);
      textos.add('⬆ ${pibe.corto} sube a Primera.');
    }
  } else if (extra.containsKey('formacion')) {
    mi.formacionForzada = null;
    p.derrotasFormacion = 0;
    textos.add('Vuelve a jugar con su ${mi.formacion}.');
  }
  return textos;
}

String seVaAOtroClub(Partida p, Tecnico t, String club) {
  final mi = p.mi;
  final otro = p.equipo(club);
  final compensacion = t.sueldo * math.max(t.contrato, 1);
  mi.caja += compensacion;
  final reemplazado = p.tecnicos[club]!;
  T.seVaDe(reemplazado, p.temporada);
  reemplazado.ultimoClub = club;
  p.dtsLibres.add(reemplazado);
  T.seVaDe(t, p.temporada);
  T.reiniciar(t);
  T.llegaA(t, club, p.temporada);
  p.tecnicos[club] = t;
  otro.dt = t.personalidad;
  otro.formacion = formacionPreferida('$club|${t.apellido}', t.personalidad);
  p.tecnicos[p.mio!] = null;
  return '${t.completo} es el nuevo DT de $club. $club paga ${M.plata(compensacion)} de rescisión.';
}

String seVaMiDt(Partida p) {
  final t = p.miDt!;
  T.reiniciar(t);
  T.seVaDe(t, p.temporada);
  t.ultimoClub = p.mio!;
  p.dtsLibres.add(t);
  p.tecnicos[p.mio!] = null;
  return '${t.completo} ya no es el DT de ${p.mio}.';
}

/// Los DT libres que se pueden contratar (los de más prestigio primero).
List<Tecnico> dtsDisponibles(Partida p) {
  final lista = [for (final t in p.dtsLibres) if (t.ultimoClub != p.mio) t]
    ..sort((a, b) => b.prestigio.compareTo(a.prestigio));
  return lista.take(6).toList();
}

String contratar(Partida p, Tecnico t) {
  final mi = p.mi;
  p.dtsLibres.remove(t);
  T.reiniciar(t);
  T.llegaA(t, mi.nombre, p.temporada);
  p.tecnicos[mi.nombre] = t;
  mi.dt = t.personalidad;
  mi.formacion = formacionPreferida('${mi.nombre}|${t.apellido}', t.personalidad);
  mi.formacionForzada = null;
  return '✅ ${t.completo} es el nuevo DT de ${mi.nombre} (${t.personalidad}, prefiere el '
      '${mi.formacion}).';
}

double costoEcharDt(Partida p) {
  final t = p.miDt!;
  return t.sueldo * math.max(t.contrato.toDouble(), 0.5);
}

String echarDt(Partida p) {
  p.mi.caja -= costoEcharDt(p);
  p.reunion = null;
  return seVaMiDt(p);
}

/// Le pedís al DT que juegue con una formación (null = que elija él).
/// Devuelve lo que contesta.
String pedirFormacion(Partida p, String? formacion) {
  final mi = p.mi, t = p.miDt!;
  p.derrotasFormacion = 0;
  if (formacion == null) {
    final habia = mi.formacionForzada != null;
    mi.formacionForzada = null;
    if (habia) T.cambiar(t, sat: 3);
    return 'Gracias, presidente. Usted no se va a arrepentir.';
  }
  if (formacion == mi.formacion) {
    mi.formacionForzada = null;
    return 'Justo lo que pensaba hacer.';
  }
  mi.formacionForzada = formacion;
  T.cambiar(t, sat: -5);
  return 'Usted manda, presidente. Jugamos con el $formacion, aunque yo no lo haría.';
}

/// Elegís el entrenamiento (null = lo decide el DT). Devuelve lo que opina el DT.
String? elegirEntrenamiento(Partida p, (String, String)? plan) {
  p.planMio = plan;
  final t = p.miDt;
  if (plan == null || t == null) return null;
  final suyo = planDt(p.mi, Azar('${p.semilla}|${p.numero}|opinion'));
  if (plan == suyo) return 'Coincido, es lo que yo hubiera hecho.';
  T.cambiar(t, sat: -3);
  return 'Yo hubiera hecho ${suyo.$1} (${suyo.$2}), pero usted manda.';
}

void opinionesTrasFecha(Partida p, Tecnico t, Equipo mi, int gf, int gc, Azar rng) {
  final forzada = mi.formacionForzada;
  if (forzada != null) {
    if (gf > gc) {
      T.cambiar(t, sat: 1);
      if (rng.random() < 0.25) {
        p.noticias.add('🗣 ${t.apellido}: «Lo admito, con el $forzada jugamos bien.»');
      }
    } else if (gf < gc) {
      T.cambiar(t, sat: -2);
      p.derrotasFormacion += 1;
      if (p.derrotasFormacion >= 3 && ['arriesgado', 'impulsivo'].contains(t.personalidad)) {
        proponer(p, T.reunionFormacion(t, rng, forzada, p.derrotasFormacion), 'formacion');
        p.derrotasFormacion = 0;
      }
    }
  }
  final plan = p.planMio;
  if (plan != null) {
    final sanos = mi.plantel.where((j) => j.lesion == 0).toList();
    final cansados = sanos.fold(0.0, (a, j) => a + j.fisico) / math.max(1, sanos.length) < 0.85;
    final queja = (cansados && plan.$2 == 'fuerte') || (gf < gc && rng.random() < 0.15);
    if (queja && p.numero - p.quejaEntreno >= 6) {
      p.quejaEntreno = p.numero;
      proponer(p, T.reunionEntrenamiento(t, rng), 'entrenamiento');
    }
  }
}

// ---------------------------------------------------------------- club
void iniciarClub(Partida p) {
  if (p.esperadoGlobal.isEmpty) calcularEsperado(p);
  C.iniciar(p.equipos, p.esperadoGlobal, Azar('${p.semilla}|club'));
  renovarStaffLibres(p);
}

void iniciarReserva(Partida p) {
  final usados = {for (final e in p.equipos) for (final j in e.plantel) j.completo};
  C.iniciarReserva(p.equipos, Azar('${p.semilla}|reserva'), usados);
  p.conReserva = true;
}

void renovarStaffLibres(Partida p) =>
    p.staffLibres = C.candidatos(Azar('${p.semilla}|${p.temporada}|staff'), {});

/// Por qué no se puede mejorar una instalación (null = se puede).
String? problemaObra(Equipo mi, String tipo) {
  final n = mi.instalaciones[tipo]! + 1;
  if (n > C.nivelMax) return 'Ya está al máximo.';
  if (mi.obras.any((o) => o.tipo == tipo)) return 'Ya hay una obra en marcha.';
  final costo = C.costoObra(tipo, n);
  if (costo > mi.caja) {
    return 'No te alcanza: cuesta ${M.plata(costo)} y tenés ${M.plata(mi.caja)}.';
  }
  return null;
}

/// Cuánto sube el mantenimiento por año si mejorás esa instalación.
double mantenimientoExtra(Equipo mi, String tipo) {
  final antes = C.mantenimiento(mi);
  mi.instalaciones[tipo] = mi.instalaciones[tipo]! + 1;
  final despues = C.mantenimiento(mi);
  mi.instalaciones[tipo] = mi.instalaciones[tipo]! - 1;
  return despues - antes;
}

String contratarStaff(Partida p, String rol, Miembro nuevo) {
  final mi = p.mi;
  final actual = mi.staff[rol];
  p.staffLibres[rol]!.remove(nuevo);
  if (actual != null) mi.caja -= actual.sueldo / 2;
  mi.staff[rol] = nuevo;
  return '✅ ${nuevo.nombre} es el nuevo ${C.roles[rol]!.toLowerCase()}.';
}

String despedirStaff(Partida p, String rol) {
  final mi = p.mi;
  final m = mi.staff.remove(rol)!;
  mi.caja -= m.sueldo / 2;
  return '${m.nombre} ya no trabaja en el club.';
}

// ---------------------------------------------------------------- mercado de pases
/// Clave de la ventana de pases abierta ahora, o null si está cerrado.
String? ventanaActual(Partida p) {
  if (p.numero == 0 || p.numero == p.fixture.length ~/ 2) return '${p.temporada}-${p.numero}';
  return null;
}

/// La primera vez que se llega a una ventana, los otros clubes hacen sus
/// movimientos y le llegan ofertas a tu club. Devuelve true si se abrió recién.
bool abrirVentana(Partida p) {
  final clave = ventanaActual(p);
  if (clave == null || p.ventana == clave) return false;
  p.ventana = clave;
  p.fichajesVentana = [];
  final rng = Azar('${p.semilla}|mercado|$clave');
  final equipos = p.equipos;
  final usados = {for (final e in equipos) for (final j in e.plantel) j.completo}
    ..addAll([for (final j in p.libres) j.completo]);
  final viejos = [for (final j in p.libres) if (j.edad < 35) j]
    ..sort((a, b) => J.nivel(b).compareTo(J.nivel(a)));
  p.libres = [...viejos.take(40), ...M.generarLibres(rng, usados, M.nivelMedio(equipos))];
  p.movimientos = [...p.finContratos, ...M.movimientosIa(equipos, p.mio, p.libres, rng, usados: usados)];
  p.finContratos = [];
  for (final e in equipos) {
    if (e.nombre != p.mio) {
      final noticia = C.invertirIa(e, rng);
      if (noticia != null) p.movimientos.add(noticia);
    }
  }
  p.ofertas = p.mio != null ? M.ofertasPorMios(equipos, p.mio!, rng) : [];
  if (p.mio != null) {
    for (final j in p.mi.reserva) {
      if (j.potEst >= 76 && rng.random() < 0.35) {
        p.ofertas.add(M.Oferta(rng.choice(M.exterior), j, C.ofertaExterior(j, rng)));
      }
    }
  }
  p.sondeos = {};
  pedidoDeMercado(p, clave);
  return true;
}

/// Un refuerzo nuevo: cuenta para las promesas al DT, y si es una de las
/// figuras del plantel, la hinchada se entusiasma.
List<String> llego(Partida p, Jugador j) {
  p.fichajesVentana.add([j.pos, j.pos2, J.nivel(j), j.completo]);
  if (M.figuras(p.mi).contains(j)) {
    cambiarHinchada(p.mi, 5);
    return ['😍 La hinchada festeja la llegada de ${j.corto}.'];
  }
  return [];
}

/// El jugador con ese nombre y el club que lo tiene (null si está libre).
(Jugador?, Equipo?) buscarPorNombre(Partida p, String nombre) {
  for (final e in p.equipos) {
    for (final j in e.plantel) {
      if (j.completo == nombre) return (j, e);
    }
  }
  for (final j in p.libres) {
    if (j.completo == nombre) return (j, null);
  }
  return (null, null);
}

/// Jugadores de otros clubes para comprar (los mejores primero). Con
/// maximo, solo los que piden hasta esa plata.
List<(Jugador, Equipo, double)> buscarJugadores(Partida p, String? pos, {double? maximo}) {
  final mi = p.mi;
  final candidatos = [
    for (final e in p.equipos)
      if (!identical(e, mi))
        for (final j in e.plantel)
          if (pos == null || j.pos == pos) (j, e)
  ]..sort((a, b) => J.nivel(b.$1).compareTo(J.nivel(a.$1)));
  final tits = <String, Set<Jugador>>{};
  final lista = <(Jugador, Equipo, double)>[];
  for (final (j, e) in candidatos) {
    final precio = M.precioPedido(e, j, tits.putIfAbsent(e.nombre, () => M.titulares(e)));
    if (maximo != null && precio > maximo) continue;
    lista.add((j, e, precio));
    if (lista.length >= 30) break;
  }
  return lista;
}

/// Por qué no se puede comprar a un jugador (null = se puede negociar).
String? problemaCompra(Partida p, Jugador j, Equipo vendedor) {
  if (p.mi.plantel.length >= M.plantelMax) {
    return 'Tenés ${M.plantelMax} jugadores: vendé o liberá a alguno antes.';
  }
  if (!M.puedeVender(vendedor, j)) return '${vendedor.nombre} no lo vende: se queda corto en el puesto.';
  return null;
}

/// Lo que pide el jugador para firmar con tu club al comprarlo: (sueldo, años).
(double, int) pedidoDelJugador(Partida p, Jugador j, {bool libre = false}) {
  final rng = Azar('${p.semilla}|${p.ventana}|${j.completo}');
  if (libre) return (M.pretension(j, rng), math.max(1, M.aniosContrato(j) - 1));
  return (M.r3(1.1 * M.pretension(j, rng)), M.aniosContrato(j));
}

/// Cierra una compra ya arreglada con el club y con el jugador.
List<String> concretarCompra(Partida p, Jugador j, Equipo vendedor, double monto, double sueldo,
    int anios) {
  final mi = p.mi;
  M.transferir(j, vendedor, mi, monto, sueldo, anios);
  final textos = llego(p, j);
  p.movimientos.add('${j.corto} (${j.pos}, ${J.nivel(j)}): ${vendedor.nombre} → ${mi.nombre}, '
      '${M.plata(monto)}');
  return ['✅ ¡${j.completo} es nuevo jugador de ${mi.nombre}! (${M.plata(monto)})', ...textos];
}

List<String> concretarLibre(Partida p, Jugador j, double sueldo, int anios) {
  final mi = p.mi;
  M.ficharLibre(j, mi, p.libres, sueldo, anios);
  final textos = llego(p, j);
  p.movimientos.add('${j.corto} (${j.pos}, ${J.nivel(j)}): libre → ${mi.nombre}');
  return ['✅ Firmó ${j.completo}.', ...textos];
}

/// Aviso si los sueldos van a superar los ingresos.
String? avisoSueldos(Equipo mi, double extra) {
  final masa = M.masaSalarial(mi.plantel) + extra;
  if (masa > mi.ingreso) {
    return 'Ojo: los sueldos (${M.plata(masa)}/año) van a superar tus ingresos '
        '(${M.plata(mi.ingreso)}/año).';
  }
  return null;
}

String venderPibe(Partida p, Jugador j, String club, double monto) {
  final mi = p.mi;
  mi.reserva.remove(j);
  mi.caja += monto;
  p.ofertas.removeWhere((o) => identical(o.j, j));
  p.movimientos.add('${j.corto} (${j.pos}, ${j.edad} años, reserva): ${mi.nombre} → $club, '
      '${M.plata(monto)}');
  return '💰 ${j.corto} se va a $club. Entran ${M.plata(monto)}.';
}

/// Vende un jugador del plantel a un club (o al exterior).
List<String> venderJugador(Partida p, Jugador j, String club, double monto) {
  final mi = p.mi;
  final textos = avisoVenta(p, j);
  M.vender(j, mi, club, p.equipos, monto);
  p.movimientos.add('${j.corto} (${j.pos}, ${J.nivel(j)}): ${mi.nombre} → $club, ${M.plata(monto)}');
  p.ofertas.removeWhere((o) => identical(o.j, j));
  return ['Vendido a $club. Entran ${M.plata(monto)}.', ...textos];
}

/// Aceptar una oferta recibida. Devuelve los textos, o un error.
List<String> aceptarOferta(Partida p, M.Oferta o) {
  final mi = p.mi;
  if (mi.reserva.contains(o.j)) return [venderPibe(p, o.j, o.club, o.monto)];
  if (!mi.plantel.contains(o.j) || !M.puedeVender(mi, o.j)) {
    return ['No podés venderlo: te quedás corto de plantel o sin nadie en el puesto.'];
  }
  return venderJugador(p, o.j, o.club, o.monto);
}

/// Ponés a un jugador en venta: quiénes ofrecen (una vez por jugador y ventana).
List<(String, double)> sondearVenta(Partida p, Jugador j) {
  return p.sondeos.putIfAbsent(j.completo, () {
    final rng = Azar('${p.semilla}|${p.ventana}|sondeos|${j.completo}');
    return M.ofertasPorJugador(p.equipos, p.mio!, j, rng);
  });
}

/// Mostrar un pibe de la reserva a clubes de afuera.
List<(String, double)> sondearPibe(Partida p, Jugador j) {
  final clave = 'pibe:${j.completo}';
  return p.sondeos.putIfAbsent(clave, () {
    final rng = Azar('${p.semilla}|${p.ventana}|$clave');
    final pot = j.potEst > 0 ? j.potEst : j.potencial;
    final interesa = rng.random() < 0.25 + 0.12 * (pot - 60) / 8;
    return interesa ? [(rng.choice(M.exterior), C.ofertaExterior(j, rng))] : [];
  });
}

String liberarJugador(Partida p, Jugador j) {
  final mi = p.mi;
  M.liberar(j, mi, p.libres);
  p.ofertas.removeWhere((o) => identical(o.j, j));
  p.movimientos.add('${j.corto} (${j.pos}, ${J.nivel(j)}): ${mi.nombre} lo deja libre');
  return '${j.corto} quedó libre.';
}

/// Lo que pide un jugador tuyo para renovar: (sueldo, años).
(double, int) pedidoRenovacion(Partida p, Jugador j, {bool pretemporada = false}) {
  final rng = pretemporada
      ? Azar('${p.semilla}|${p.temporada}|renueva|${j.completo}')
      : Azar('${p.semilla}|${p.ventana}|renueva|${j.completo}');
  final pide = M.pretension(j, rng);
  return (pretemporada ? pide : math.max(M.sueldo(j), pide), M.aniosContrato(j));
}

/// Pretemporada: un jugador al que se le terminó el contrato se va libre.
void dejarIrVencido(Partida p, Jugador j, bool eraTitular) {
  final mi = p.mi;
  M.liberar(j, mi, p.libres, pagar: false);
  p.finContratos.add('${j.corto} (${j.pos}, ${J.nivel(j)}): termina contrato en ${mi.nombre}, '
      'queda libre');
  final t = p.miDt;
  if (t != null && eraTitular) T.cambiar(t, sat: -4);
}

/// Los pedidos del DT que siguen disponibles: [(jugador, club o null, precio)].
List<(Jugador, Equipo?)> pedidosDelDt(Partida p) {
  return [
    for (final n in p.pedidosDt)
      if (buscarPorNombre(p, n) case (final Jugador j, final Equipo? c)
          when !identical(c, p.mi))
        (j, c)
  ];
}
