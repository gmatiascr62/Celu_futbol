// El partido minuto a minuto (ver simulador_futbol.py).
//
// Los goles salen de un modelo de Poisson entrenado con partidos reales.
// Cada equipo tiene un DT que elige formación y titulares, cambia la
// táctica según el resultado (con lo que aprendió jugando millones de
// partidos, en dt_ia.json) y hace los cambios según el cansancio.
import 'dart:math' as math;

import 'azar.dart';
import 'equipo.dart';
import 'jugadores.dart' as J;
import 'jugadores.dart' show Jugador, Puesto;

// ---------------------------------------------------------------- modelo
class Modelo {
  final double base;
  final double localia;
  final Map<String, (double, double)> equipos; // club: (ataque, defensa)
  final Map<String, int> division; // club: división (0 = Liga Profesional)
  final List<String> divisiones;
  Modelo(this.base, this.localia, this.equipos, this.division, this.divisiones);
}

// ---------------------------------------------------------------- tácticas
class Tactica {
  final double propio, rival, posesion;
  const Tactica(this.propio, this.rival, this.posesion);
}

const tacticas = {
  'equilibrada': Tactica(1.00, 1.00, 0),
  'ofensiva': Tactica(1.15, 1.08, 4),
  'defensiva': Tactica(0.85, 0.85, -6),
  'contraataque': Tactica(0.95, 0.93, -8),
  'presion': Tactica(1.10, 1.03, 6),
  'todo_al_ataque': Tactica(1.40, 1.35, 8),
};
const nombreTactica = {
  'equilibrada': 'Equilibrada', 'ofensiva': 'Ofensiva', 'defensiva': 'Defensiva',
  'contraataque': 'Contraataque', 'presion': 'Presión', 'todo_al_ataque': 'Todo al ataque',
};
const bonusContra = 1.15;
const tacticasAdelantadas = ['ofensiva', 'presion', 'todo_al_ataque'];
final tacticasIniciales = [for (final t in tacticas.keys) if (t != 'todo_al_ataque') t];
const minutoTodoAlAtaque = 70;

List<String> disponibles(int minuto) =>
    minuto >= minutoTodoAlAtaque ? tacticas.keys.toList() : tacticasIniciales;

// ---------------------------------------------------------------- DTs
class Personalidad {
  final double ganar, empatar, umbral, error;
  final String desc;
  const Personalidad(this.ganar, this.empatar, this.umbral, this.error, this.desc);
}

const personalidades = {
  'equilibrado': Personalidad(3.0, 1.0, 0.04, 0.15, 'decide con la cabeza fría'),
  'conservador': Personalidad(3.0, 1.6, 0.06, 0.15, 'un punto siempre suma'),
  'arriesgado': Personalidad(3.6, 0.6, 0.03, 0.25, 'sale a ganar siempre'),
  'impulsivo': Personalidad(3.0, 1.0, 0.02, 0.80, 'cambia mucho y a veces se equivoca'),
};

const tramos = [1, 15, 30, 46, 60, 70, 78, 85];
final momentosDecision = tramos.sublist(1);
const minEntreCambios = 8;
const factorEmpate = 0.80;
const escala = 1.06;
const maxCambiosTacticos = 5;

// ---------------------------------------------------------------- energía
const desgaste = {
  'equilibrada': 0.0045, 'ofensiva': 0.0055, 'defensiva': 0.0035,
  'contraataque': 0.0042, 'presion': 0.0072, 'todo_al_ataque': 0.0085,
};
const recuperoEntretiempo = 0.05;
const energiaMinima = 0.30;
const cambiosPermitidos = 5;
const ventanasCambio = 3;
const metaCambios = [(60, 1), (70, 3), (78, 4), (85, 5)];
const _umbralCambio = {
  'equilibrado': 0.78, 'conservador': 0.74, 'arriesgado': 0.82, 'impulsivo': 0.80,
};

double efectoEnergia(double propia, double rival) =>
    (0.75 + 0.25 * propia) * (1 + 0.25 * (1 - rival));

/// Cuántos cambios hace el DT en este momento.
int decidirCambios(String? personalidad, int minuto, double energia, int restantes,
    int ventanas, int gf, int gc, Azar? rng) {
  if (restantes == 0 || minuto < 46) return 0;
  final entretiempo = minuto == 46;
  if (!entretiempo && ventanas == 0) return 0;
  if (!entretiempo && ventanas == 1 && minuto >= 70) return restantes;
  var umbral = _umbralCambio[personalidad] ?? 0.76;
  if (gf < gc) umbral += 0.03;
  if (personalidad == 'impulsivo' && rng != null) umbral += rng.uniform(-0.08, 0.08);
  final porEnergia = energia < umbral ? math.min(2, restantes) : 0;
  final usados = cambiosPermitidos - restantes;
  var meta = 0;
  for (final (m, n) in metaCambios) {
    if (minuto >= m) meta = math.max(meta, n);
  }
  return math.min(restantes, math.max(porEnergia, meta - usados));
}

// Formación preferida de cada DT
const _preferencias = {'4-4-2': 25, '4-3-3': 25, '4-2-3-1': 25, '3-5-2': 12, '5-3-2': 13};
const apegoFormacion = 0.04;

String formacionPreferida(String club, String? dt) {
  final rng = Azar('$club|$dt');
  return rng.choices(_preferencias.keys.toList(), _preferencias.values.toList());
}

// ---------------------------------------------------------------- probabilidades
double multiplicador(String propia, String rival) {
  var m = tacticas[propia]!.propio * tacticas[rival]!.rival;
  if (propia == 'contraataque' && tacticasAdelantadas.contains(rival)) m *= bonusContra;
  return m;
}

// Peso de cada minuto: los goles son algo más frecuentes al final.
final List<double> peso = () {
  final pesos = [for (var m = 1; m <= 90; m++) 1 + 0.006 * m];
  final suma = pesos.reduce((a, b) => a + b);
  return [0.0, for (final p in pesos) p * 90 / suma];
}();
final List<double> _acum = () {
  final a = [0.0];
  for (final p in peso.skip(1)) {
    a.add(a.last + p);
  }
  return a;
}();

double pesoTramo(int desde, int hasta) =>
    desde > hasta ? 0.0 : (_acum[hasta] - _acum[desde - 1]) / 90;

double golesRestantes(double base, String propia, String rival, int minuto) =>
    base * pesoTramo(minuto, 90) * multiplicador(propia, rival);

double _poisson(int k, double mu) {
  var f = 1.0;
  for (var i = 2; i <= k; i++) {
    f *= i;
  }
  return math.exp(-mu) * math.pow(mu, k) / f;
}

/// Probabilidad de ganar, empatar y perder, dado el marcador y los goles que faltan.
(double, double, double) probResultado(int gf, int gc, double muF, double muC,
    [int maximo = 8]) {
  final pf = [for (var k = 0; k <= maximo; k++) _poisson(k, muF)];
  final pc = [for (var k = 0; k <= maximo; k++) _poisson(k, muC)];
  var gana = 0.0, empata = 0.0;
  for (var i = 0; i <= maximo; i++) {
    for (var j = 0; j <= maximo; j++) {
      final diff = gf + i - gc - j;
      if (diff > 0) {
        gana += pf[i] * pc[j];
      } else if (diff == 0) {
        empata += pf[i] * pc[j];
      }
    }
  }
  return (gana, empata, 1 - gana - empata);
}

// ---------------------------------------------------------------- DT calculador
String? decidirCalculado(Equipo eq, Equipo rival, double baseEq, double baseRival, int gf,
    int gc, int minuto, Azar rng) {
  final p = personalidades[eq.dt]!;
  final opciones = disponibles(minuto);
  final puntajes = <String, double>{};
  for (final t in {...opciones, eq.tactica}) {
    final muF = golesRestantes(baseEq, t, rival.tactica, minuto);
    final muC = golesRestantes(baseRival, rival.tactica, t, minuto);
    final (gana, empata, _) = probResultado(gf, gc, muF, muC);
    puntajes[t] = p.ganar * gana + p.empatar * empata;
  }
  final diferencia = puntajes.values.reduce(math.max) - puntajes.values.reduce(math.min);
  if (diferencia < p.umbral) return null;
  for (final t in puntajes.keys.toList()) {
    puntajes[t] = puntajes[t]! + rng.gauss(0, p.error * diferencia);
  }
  String? mejor;
  for (final t in puntajes.keys) {
    if (opciones.contains(t) && (mejor == null || puntajes[t]! > puntajes[mejor]!)) mejor = t;
  }
  if (mejor != eq.tactica && puntajes[mejor]! - puntajes[eq.tactica]! > p.umbral) return mejor;
  return null;
}

// ---------------------------------------------------------------- DT con IA
final acciones = tacticas.keys.toList();
const _tipoRival = {
  'defensiva': 0, 'contraataque': 0, 'equilibrada': 1,
  'ofensiva': 2, 'presion': 2, 'todo_al_ataque': 2,
};
const _cortesFuerza = [-0.8, -0.4, -0.15, 0.15, 0.4, 0.8];
const _tablaDe = {
  'equilibrado': 'equilibrado', 'conservador': 'conservador',
  'arriesgado': 'arriesgado', 'impulsivo': 'equilibrado',
};
const versionCerebro = 2;

/// Lo que aprendieron los DT (dt_ia.json): para cada situación, cuántos
/// puntos esperan sacar con cada táctica.
Map<String, Map<String, List<double>>>? cerebro;

String estadoDt(int minuto, int gf, int gc, double baseEq, double baseRival, String tRival,
    double energia) {
  final tramo = tramos.where((t) => t <= minuto).length - 1;
  final dif = math.max(-2, math.min(2, gf - gc));
  final r = math.log(baseEq / baseRival);
  final fuerza = _cortesFuerza.where((c) => r > c).length;
  final cansancio = energia >= 0.8 ? 0 : energia >= 0.65 ? 1 : 2;
  return '$tramo|$dif|$fuerza|${_tipoRival[tRival]}|$cansancio';
}

String? decidirIa(Equipo eq, Equipo rival, double baseEq, double baseRival, int gf, int gc,
    int minuto, Azar rng) {
  final tabla = cerebro![_tablaDe[eq.dt]]!;
  final q = tabla[estadoDt(minuto, gf, gc, baseEq, baseRival, rival.tactica, eq.energia)];
  if (q == null) return null;
  final validas = [for (final t in disponibles(minuto)) acciones.indexOf(t)];
  if (eq.dt == 'impulsivo' && rng.random() < 0.25) return acciones[rng.choice(validas)];
  var mejor = validas.first;
  for (final i in validas) {
    if (q[i] > q[mejor]) mejor = i;
  }
  final actual = acciones.indexOf(eq.tactica);
  if (mejor != actual && q[mejor] - q[actual] > 0.02) return acciones[mejor];
  return null;
}

void cargarCerebro(Map<String, dynamic> datos) {
  if (datos['version'] != versionCerebro) return;
  cerebro = {
    for (final t in (datos['tablas'] as Map).entries)
      t.key as String: {
        for (final s in (t.value as Map).entries)
          s.key as String: [for (final v in s.value as List) (v as num).toDouble()]
      }
  };
}

String motivo(int gf, int gc) => gf > gc
    ? 'gana $gf-$gc'
    : gf < gc
        ? 'pierde $gf-$gc'
        : 'empata $gf-$gc';

// ---------------------------------------------------------------- partido
const _ofensivos = ['DC', 'ED', 'EI', 'MCO'];
const _defensivos = ['DFC', 'MCD'];
const _pesoGol = {
  'DC': 5.0, 'ED': 2.6, 'EI': 2.6, 'MCO': 2.3, 'MC': 1.4, 'MCD': 0.8,
  'LD': 0.7, 'LI': 0.7, 'DFC': 1.1, 'ARQ': 0.0,
};
const _pesoTarjeta = {
  'DFC': 1.5, 'MCD': 1.6, 'LD': 1.2, 'LI': 1.2, 'MC': 1.1, 'MCO': 0.8,
  'ED': 0.8, 'EI': 0.8, 'DC': 0.9, 'ARQ': 0.3,
};
const efectoAliento = 0.02; // la hinchada mueve hasta un 2% los goles del local

/// El DT prueba cada formación con sus mejores 11 contra el rival y se
/// queda con la que más puntos le da, según su personalidad.
(String, List<Puesto>) elegirAlineacion(
    Equipo eq, Equipo rival, Modelo modelo, bool esLocal, Azar rng) {
  if (eq.dt == null) return (eq.formacion, J.armarXi(J.aptos(eq.plantel), eq.formacion));
  final forzada = eq.formacionForzada;
  if (forzada != null) return (forzada, J.armarXi(J.aptos(eq.plantel), forzada));
  final fRival = rival.dt == null ? rival.formacion : J.formacionBase;
  final fr = J.fuerza(J.armarXi(J.aptos(rival.plantel), fRival), fRival);
  final p = personalidades[eq.dt]!;
  final opciones = <(double, String, List<Puesto>)>[];
  for (final f in J.formaciones.keys) {
    final xi = J.armarXi(J.aptos(eq.plantel), f);
    final fz = J.fuerza(xi, f);
    final muF = math.exp(modelo.base + (esLocal ? modelo.localia : 0) + fz.ataque + fr.defensa) *
        escala;
    final muC = math.exp(modelo.base + (esLocal ? 0 : modelo.localia) + fr.ataque + fz.defensa) *
        escala;
    final (gana, empata, _) = probResultado(0, 0, muF, muC);
    var puntos = p.ganar * gana + p.empatar * empata;
    if (f == eq.formacion) puntos += apegoFormacion;
    opciones.add((puntos, f, xi));
  }
  final (double, String, List<Puesto>) elegida;
  if (eq.dt == 'impulsivo' && rng.random() < 0.3) {
    elegida = rng.choice(opciones);
  } else {
    elegida = opciones.reduce((a, b) => b.$1 > a.$1 ? b : a);
  }
  return (elegida.$2, elegida.$3);
}

T _maxPor<T>(Iterable<T> xs, double Function(T) f) =>
    xs.reduce((a, b) => f(b) > f(a) ? b : a);
T _minPor<T>(Iterable<T> xs, double Function(T) f) =>
    xs.reduce((a, b) => f(b) < f(a) ? b : a);

/// A quién saca y a quién mete el DT. Devuelve (índice, entra, posición).
(int, Jugador, String) elegirCambio(
    List<Puesto> cancha, List<Jugador> banco, int minuto, int gf, int gc) {
  final campo = [for (var i = 0; i < cancha.length; i++) if (cancha[i].$2 != 'ARQ') i];
  final nOf = cancha.where((x) => _ofensivos.contains(x.$2)).length;
  final nDef = cancha.where((x) => _defensivos.contains(x.$2)).length;
  if (gf < gc && minuto >= 60 && nOf < 5) {
    final salen = campo.where((i) => const ['MCD', 'MC', 'LD', 'LI'].contains(cancha[i].$2));
    final entran = banco.where((j) => _ofensivos.contains(j.pos));
    if (salen.isNotEmpty && entran.isNotEmpty) {
      final i = _minPor(salen, (i) => cancha[i].$1.energia);
      final entra = _maxPor(entran, (j) => J.puntaje(j, j.pos));
      return (i, entra, entra.pos);
    }
  }
  if (gf > gc && minuto >= 70 && nDef < 5) {
    final salen = campo.where((i) => _ofensivos.contains(cancha[i].$2));
    final entran = banco.where((j) => _defensivos.contains(j.pos));
    if (salen.isNotEmpty && entran.isNotEmpty) {
      final i = _minPor(salen, (i) => cancha[i].$1.energia);
      final entra = _maxPor(entran, (j) => J.puntaje(j, j.pos));
      return (i, entra, entra.pos);
    }
  }
  final i = _minPor(campo, (i) => cancha[i].$1.energia);
  final slot = cancha[i].$2;
  final entra = _maxPor(banco, (j) => J.puntaje(j, slot));
  return (i, entra, slot);
}

Jugador? _elegirJugador(List<Puesto> cancha, bool goleador, Azar rng,
    [Set<Jugador> excluir = const {}]) {
  final candidatos = [for (final x in cancha) if (!excluir.contains(x.$1)) x];
  if (candidatos.isEmpty) return null;
  final w = [
    for (final (j, s) in candidatos)
      goleador ? _pesoGol[s]! * math.pow(j.ataque / 65, 2) : _pesoTarjeta[s]!
  ];
  if (w.fold<double>(0, (a, b) => a + b) <= 0) return null;
  return rng.choices([for (final x in candidatos) x.$1], w);
}

String _minutoTexto(Azar rng, int m) =>
    (m == 45 || m == 90) && rng.random() < 0.5 ? "$m+${rng.randint(1, 4)}'" : "$m'";

bool _sucede(Azar rng, double tasa) => rng.random() < 1 - math.exp(-tasa);

/// Algo que pasó en el partido, para el relato.
class Evento {
  final int minuto;
  final String tipo; // gol, atajada, desviado, amarilla, cambio, tactica, entretiempo
  final int lado; // 0 local, 1 visitante, -1 ninguno
  final String texto;
  final int gl, gv; // marcador después del evento
  Evento(this.minuto, this.tipo, this.lado, this.texto, this.gl, this.gv);
}

class Estadisticas {
  int atajados = 0, desviados = 0, amarillas = 0, sustituciones = 0, cambios = 0;
}

class Gol {
  final int lado;
  final Jugador autor;
  final int minuto;
  Gol(this.lado, this.autor, this.minuto);
}

class ResultadoPartido {
  final int gl, gv;
  final List<Gol> goles;
  final List<Estadisticas> stats;
  final List<String> formacion;
  final List<Evento> eventos;
  final double posesion; // del local
  final List<List<Puesto>> titulares;
  final List<String> tacticasIniciales;
  final List<double> energia;
  ResultadoPartido(this.gl, this.gv, this.goles, this.stats, this.formacion, this.eventos,
      this.posesion, this.titulares, this.tacticasIniciales, this.energia);
}

typedef Decisor = String? Function(Equipo eq, Equipo rival, double baseEq, double baseRival,
    int gf, int gc, int minuto, Azar rng);

/// Juega un partido entero. Si relato es true, guarda los eventos.
ResultadoPartido simularPartido(Equipo local, Equipo visitante, Modelo modelo,
    {Object? semilla, bool relato = false, Decisor? decisor}) {
  decisor ??= cerebro != null ? decidirIa : decidirCalculado;
  final rng = Azar(semilla);
  final eq = [local, visitante];
  final formacion = <String>['', ''];
  final cancha = <List<Puesto>>[[], []];
  final banco = <List<Jugador>>[[], []];
  final jugaron = <List<Jugador>>[[], []];
  for (var k = 0; k < 2; k++) {
    final (f, xi) = elegirAlineacion(eq[k], eq[1 - k], modelo, k == 0, rng);
    formacion[k] = f;
    cancha[k] = List.of(xi);
    final enCancha = {for (final x in xi) x.$1};
    banco[k] = [for (final j in J.aptos(eq[k].plantel)) if (!enCancha.contains(j)) j];
    jugaron[k] = [for (final x in xi) x.$1];
    for (final j in eq[k].plantel) {
      j.energia = j.fisico;
    }
  }
  final titulares = [List.of(cancha[0]), List.of(cancha[1])];
  final goles = [0, 0];
  final stats = [Estadisticas(), Estadisticas()];
  final autores = <Gol>[];
  final amonestados = <Jugador>{};
  final ultimoCambio = [-99, -99];
  final cambiosRest = [cambiosPermitidos, cambiosPermitidos];
  final ventanas = [ventanasCambio, ventanasCambio];
  var ultimoGol = -99;
  final eventos = <Evento>[];
  var posesionTotal = 0.0;

  void log(int minuto, String tipo, int lado, String texto) {
    if (relato) eventos.add(Evento(minuto, tipo, lado, texto, goles[0], goles[1]));
  }

  double energiaEquipo(int k) {
    final campo = [for (final (j, s) in cancha[k]) if (s != 'ARQ') j.energia];
    return campo.reduce((a, b) => a + b) / campo.length;
  }

  List<double> calcularBases() {
    final fz = [for (var k = 0; k < 2; k++) J.fuerza(cancha[k], formacion[k])];
    final muL = math.exp(modelo.base + modelo.localia + fz[0].ataque + fz[1].defensa);
    final muV = math.exp(modelo.base + fz[1].ataque + fz[0].defensa);
    final aliento = 1 + efectoAliento * (local.hinchada - 60) / 40;
    return [muL * local.moral * aliento, muV * visitante.moral];
  }

  double creacion(int k) {
    final campo = [for (final (j, s) in cancha[k]) if (s != 'ARQ') j.creacion * j.energia];
    return campo.reduce((a, b) => a + b) / campo.length;
  }

  var base = calcularBases();

  for (var k = 0; k < 2; k++) {
    eq[k].tactica = eq[k].tacticaInicial;
    eq[k].energia = energiaEquipo(k);
  }
  for (var k = 0; k < 2; k++) {
    if (eq[k].dt != null) {
      final nueva = decisor(eq[k], eq[1 - k], base[k], base[1 - k], 0, 0, 1, rng);
      if (nueva != null) eq[k].tactica = nueva;
    }
  }
  final tacticasIni = [eq[0].tactica, eq[1].tactica];

  for (var minuto = 1; minuto <= 90; minuto++) {
    final mt = _minutoTexto(rng, minuto);
    if (minuto == 46) {
      for (var k = 0; k < 2; k++) {
        for (final (j, _) in cancha[k]) {
          j.energia = math.min(1.0, j.energia + recuperoEntretiempo);
        }
      }
    }

    // Cambios de jugadores
    if (momentosDecision.contains(minuto)) {
      var hubo = false;
      for (var k = 0; k < 2; k++) {
        final e = eq[k];
        e.energia = energiaEquipo(k);
        var n = decidirCambios(e.dt, minuto, e.energia, cambiosRest[k], ventanas[k], goles[k],
            goles[1 - k], rng);
        n = math.min(n, banco[k].length);
        if (n == 0) continue;
        for (var c = 0; c < n; c++) {
          final (i, entra, slot) =
              elegirCambio(cancha[k], banco[k], minuto, goles[k], goles[1 - k]);
          final sale = cancha[k][i].$1;
          cancha[k][i] = (entra, slot);
          banco[k].remove(entra);
          jugaron[k].add(entra);
          log(minuto, 'cambio', k,
              'Sale ${sale.corto} (${(sale.energia * 100).round()}%), entra ${entra.corto} ($slot)');
        }
        cambiosRest[k] -= n;
        if (minuto != 46) ventanas[k] -= 1;
        stats[k].sustituciones += n;
        hubo = true;
      }
      if (hubo) base = calcularBases();
    }
    for (var k = 0; k < 2; k++) {
      eq[k].energia = energiaEquipo(k);
    }

    // Decisiones tácticas de los DT
    if (momentosDecision.contains(minuto) || minuto == ultimoGol + 2) {
      for (var k = 0; k < 2; k++) {
        final e = eq[k];
        if (e.dt == null ||
            stats[k].cambios >= maxCambiosTacticos ||
            minuto - ultimoCambio[k] < minEntreCambios) {
          continue;
        }
        final nueva =
            decisor(e, eq[1 - k], base[k], base[1 - k], goles[k], goles[1 - k], minuto, rng);
        if (nueva != null) {
          e.tactica = nueva;
          ultimoCambio[k] = minuto;
          stats[k].cambios += 1;
          log(minuto, 'tactica', k,
              'El DT pasa a ${nombreTactica[nueva]!.toLowerCase()} (${motivo(goles[k], goles[1 - k])})');
        }
      }
    }

    // Lo que pasa en el minuto
    final empate = goles[0] == goles[1];
    for (var k = 0; k < 2; k++) {
      final e = eq[k], r = eq[1 - k];
      var tasa = base[k] *
          escala *
          peso[minuto] /
          90 *
          multiplicador(e.tactica, r.tactica) *
          efectoEnergia(e.energia, r.energia);
      if (empate) tasa *= factorEmpate;
      if (_sucede(rng, tasa)) {
        goles[k] += 1;
        ultimoGol = minuto;
        final autor = _elegirJugador(cancha[k], true, rng)!;
        autores.add(Gol(k, autor, minuto));
        log(minuto, 'gol', k, '$mt ¡GOL de ${e.nombre}! ${autor.corto}');
      } else if (_sucede(rng, 2.4 * tasa)) {
        stats[k].atajados += 1;
        final arq = cancha[1 - k].firstWhere((x) => x.$2 == 'ARQ', orElse: () => cancha[1 - k][0]);
        log(minuto, 'atajada', k, '$mt Ataja ${arq.$1.corto} (${r.nombre})');
      } else if (_sucede(rng, 5.5 * tasa + 1.5 / 90)) {
        stats[k].desviados += 1;
        if (rng.random() < 0.3) {
          final tirador = _elegirJugador(cancha[k], true, rng)!;
          log(minuto, 'desviado', k, '$mt Desviado: ${tirador.corto}');
        }
      }
      if (_sucede(rng, 2.2 / 90)) {
        final j = _elegirJugador(cancha[k], false, rng, amonestados);
        if (j != null) {
          amonestados.add(j);
          stats[k].amarillas += 1;
          log(minuto, 'amarilla', k, '$mt Amarilla: ${j.corto}');
        }
      }
    }

    // Desgaste: depende de la táctica y de la resistencia de cada uno
    for (var k = 0; k < 2; k++) {
      final d = desgaste[eq[k].tactica]!;
      for (final (j, s) in cancha[k]) {
        final factor = s == 'ARQ' ? 0.4 : 1 + (65 - j.resistencia) * 0.012;
        j.energia = math.max(energiaMinima, j.energia - d * factor);
      }
    }

    posesionTotal += 50 +
        (creacion(0) - creacion(1)) * 0.6 +
        tacticas[local.tactica]!.posesion -
        tacticas[visitante.tactica]!.posesion;
    if (minuto == 45) log(45, 'entretiempo', -1, 'Entretiempo ${goles[0]}-${goles[1]}');
  }

  for (var k = 0; k < 2; k++) {
    for (final j in jugaron[k]) {
      j.fisico = j.energia;
      j.partidos += 1;
    }
    eq[k].energia = energiaEquipo(k);
  }
  final posesion = math.max(25.0, math.min(75.0, posesionTotal / 90 + rng.gauss(0, 3)));
  return ResultadoPartido(goles[0], goles[1], autores, stats, formacion, eventos, posesion,
      titulares, tacticasIni, [local.energia, visitante.energia]);
}
