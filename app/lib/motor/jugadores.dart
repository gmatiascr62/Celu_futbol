// Jugadores, posiciones, formaciones y planteles (ver jugadores.py).
//
// Cada club tiene 24 jugadores ficticios. Los planteles vienen de
// planteles.json, generados para que el equipo titular tenga la misma
// fuerza que el modelo aprendió del club real.
import 'dart:math' as math;

import 'azar.dart';
import 'nombres.dart';

// ---------------------------------------------------------------- posiciones
const posiciones = ['ARQ', 'DFC', 'LD', 'LI', 'MCD', 'MC', 'MCO', 'ED', 'EI', 'DC'];
const nombrePos = {
  'ARQ': 'arquero', 'DFC': 'defensor central', 'LD': 'lateral derecho',
  'LI': 'lateral izquierdo', 'MCD': 'volante central', 'MC': 'volante mixto',
  'MCO': 'enganche', 'ED': 'extremo derecho', 'EI': 'extremo izquierdo',
  'DC': 'centrodelantero',
};
const linea = {
  'ARQ': 0, 'DFC': 1, 'LD': 1, 'LI': 1, 'MCD': 2, 'MC': 2, 'MCO': 2,
  'ED': 3, 'EI': 3, 'DC': 3,
};

// Cuánto aporta cada posición al ataque y a la defensa del equipo
const aporte = {
  'ARQ': (0.0, 3.0), 'DFC': (0.2, 1.6), 'LD': (0.6, 1.0), 'LI': (0.6, 1.0),
  'MCD': (0.5, 1.1), 'MC': (1.0, 0.7), 'MCO': (1.4, 0.3),
  'ED': (1.3, 0.4), 'EI': (1.3, 0.4), 'DC': (1.3, 0.15),
};
// Qué parte del rendimiento ofensivo sale del ataque y qué parte de la creación
const mezclaOf = {
  'ARQ': (0.0, 0.0), 'DFC': (0.2, 0.8), 'LD': (0.5, 0.5), 'LI': (0.5, 0.5),
  'MCD': (0.2, 0.8), 'MC': (0.4, 0.6), 'MCO': (0.3, 0.7),
  'ED': (0.6, 0.4), 'EI': (0.6, 0.4), 'DC': (0.85, 0.15),
};

// Rendimiento jugando fuera de su posición
const _cercanas = {
  'LD|LI': 0.90, 'DFC|LD': 0.85, 'DFC|LI': 0.85, 'DFC|MCD': 0.85, 'MCD|MC': 0.93,
  'MC|MCO': 0.92, 'MCO|ED': 0.88, 'MCO|EI': 0.88, 'ED|EI': 0.92, 'ED|DC': 0.88,
  'EI|DC': 0.88, 'MCO|DC': 0.85, 'LD|ED': 0.85, 'LI|EI': 0.85,
};
const secundarias = {
  'DFC': ['MCD', 'LD', 'LI'], 'LD': ['LI', 'ED', 'DFC'], 'LI': ['LD', 'EI', 'DFC'],
  'MCD': ['DFC', 'MC'], 'MC': ['MCD', 'MCO'], 'MCO': ['MC', 'ED', 'EI'],
  'ED': ['EI', 'MCO', 'DC'], 'EI': ['ED', 'MCO', 'DC'], 'DC': ['ED', 'EI', 'MCO'],
};

const formaciones = {
  '4-4-2': [['LD', 'DFC', 'DFC', 'LI'], ['ED', 'MCD', 'MC', 'EI'], ['DC', 'DC']],
  '4-3-3': [['LD', 'DFC', 'DFC', 'LI'], ['MCD', 'MC', 'MC'], ['ED', 'DC', 'EI']],
  '4-2-3-1': [['LD', 'DFC', 'DFC', 'LI'], ['MCD', 'MCD'], ['ED', 'MCO', 'EI'], ['DC']],
  '5-3-2': [['LD', 'DFC', 'DFC', 'DFC', 'LI'], ['MCD', 'MC', 'MC'], ['DC', 'DC']],
  '3-5-2': [['DFC', 'DFC', 'DFC'], ['ED', 'MCD', 'MCO', 'MC', 'EI'], ['DC', 'DC']],
};
const formacionBase = '4-4-2'; // con esta se calibra la fuerza del plantel
// Efecto propio de cada formación (ataque, defensa) en la escala del modelo.
const efectoFormacion = {
  '4-4-2': (0.0, 0.0), '4-3-3': (0.039, 0.034), '4-2-3-1': (-0.006, 0.009),
  '5-3-2': (-0.069, -0.084), '3-5-2': (0.035, 0.058),
};

// Escala: 1 punto de promedio = 2,5% de goles. 65 = equipo promedio.
const k = 0.025;
const promedio = 65.0;

// Composición del plantel: 24 jugadores
const composicion = {
  'ARQ': 3, 'DFC': 4, 'LD': 2, 'LI': 2, 'MCD': 2, 'MC': 3, 'MCO': 2, 'ED': 2, 'EI': 2, 'DC': 2,
};

// Perfil de cada posición: (ataque, creación, defensa) respecto del nivel del club
const _perfil = {
  'ARQ': (-40, -25, -30), 'DFC': (-22, -8, 0), 'LD': (-6, -2, -4), 'LI': (-6, -2, -4),
  'MCD': (-14, -1, -2), 'MC': (-6, 1, -10), 'MCO': (-2, 4, -25),
  'ED': (1, -1, -24), 'EI': (1, -1, -24), 'DC': (3, -12, -30),
};

const maxPorApellido = 3;

/// Nombre y apellido al azar. No repite nombres en toda la liga, ni
/// apellidos dentro del mismo club, ni jugadores famosos reales.
(String, String) generarNombre(Azar rng, Set<String> usados, Set<String> apellidosClub) {
  final pesos = [for (final g in apellidos) g.$1];
  var intentos = 0;
  while (true) {
    intentos++;
    final apellido = rng.choice(rng.choices(apellidos, pesos).$2);
    final nombre = rng.choice(nombres);
    final completo = '$nombre $apellido';
    final repetido = intentos < 60 &&
        usados.where((n) => n.endsWith(' $apellido')).length >= maxPorApellido;
    if (!usados.contains(completo) &&
        !famosos.contains(completo) &&
        !apellidosClub.contains(apellido) &&
        !repetido) {
      usados.add(completo);
      apellidosClub.add(apellido);
      return (nombre, apellido);
    }
  }
}

// ---------------------------------------------------------------- jugador
class Jugador {
  String nombre;
  String apellido;
  String pos;
  int edad;
  double ataque;
  double creacion;
  double defensa;
  double atajada;
  double resistencia;
  int potencial;
  String? pos2;
  double forma;
  double fisico; // cómo llega al partido (1 = descansado)
  double energia; // durante el partido
  int lesion; // fechas que le quedan afuera por lesión
  int contrato; // temporadas de contrato que le quedan (0 = libre o vencido)
  double sueldo; // sueldo anual pactado, millones de dólares (0 = sin pactar)
  int partidos; // partidos jugados en la temporada
  int potEst; // potencial que estima el club (los pibes de la reserva)

  Jugador(this.nombre, this.apellido, this.pos, this.edad, this.ataque, this.creacion,
      this.defensa, this.atajada, this.resistencia,
      {this.potencial = 0,
      this.pos2,
      this.forma = 1.0,
      this.fisico = 1.0,
      this.energia = 1.0,
      this.lesion = 0,
      this.contrato = 0,
      this.sueldo = 0.0,
      this.partidos = 0,
      this.potEst = 0});

  String get completo => '$nombre $apellido';
  String get corto => '${nombre[0]}. $apellido';

  Map<String, dynamic> toJson() => {
        'nombre': nombre, 'apellido': apellido, 'pos': pos, 'edad': edad,
        'ataque': ataque, 'creacion': creacion, 'defensa': defensa, 'atajada': atajada,
        'resistencia': resistencia, 'potencial': potencial, 'pos2': pos2, 'forma': forma,
        'fisico': fisico, 'lesion': lesion, 'contrato': contrato, 'sueldo': sueldo,
        'partidos': partidos, 'pot_est': potEst,
      };

  factory Jugador.fromJson(Map<String, dynamic> d) => Jugador(
        d['nombre'], d['apellido'], d['pos'], d['edad'],
        (d['ataque'] as num).toDouble(), (d['creacion'] as num).toDouble(),
        (d['defensa'] as num).toDouble(), (d['atajada'] as num).toDouble(),
        (d['resistencia'] as num).toDouble(),
        potencial: d['potencial'] ?? 0,
        pos2: d['pos2'],
        forma: (d['forma'] as num? ?? 1.0).toDouble(),
        fisico: (d['fisico'] as num? ?? 1.0).toDouble(),
        lesion: d['lesion'] ?? 0,
        contrato: d['contrato'] ?? 0,
        sueldo: (d['sueldo'] as num? ?? 0).toDouble(),
        partidos: d['partidos'] ?? 0,
        potEst: d['pot_est'] ?? 0,
      );

  Jugador copia() => Jugador.fromJson(toJson());
}

/// Qué porcentaje de su rendimiento da un jugador en esa posición.
double afinidad(Jugador j, String slot) {
  if (j.pos == slot) return 1.0;
  if (slot == j.pos2) return 0.95;
  if (j.pos == 'ARQ' || slot == 'ARQ') return 0.3;
  final f = _cercanas['${j.pos}|$slot'] ?? _cercanas['$slot|${j.pos}'];
  if (f != null) return f;
  return (linea[j.pos]! - linea[slot]!).abs() <= 1 ? 0.8 : 0.65;
}

/// Rendimiento ofensivo y defensivo de un jugador en una posición.
(double, double) valores(Jugador j, String slot) {
  final f = afinidad(j, slot) * j.forma;
  if (slot == 'ARQ') return (0.0, j.atajada * f);
  final (wa, wc) = mezclaOf[slot]!;
  final of = wa * j.ataque + wc * j.creacion;
  final de = slot == 'MCD' ? 0.75 * j.defensa + 0.25 * j.creacion : j.defensa;
  return (of * f, de * f);
}

/// Qué tan bueno es un jugador para esa posición (para elegir titulares).
double puntaje(Jugador j, String slot, [bool conFisico = true]) {
  final (wa, wd) = aporte[slot]!;
  final (of, de) = valores(j, slot);
  final p = (wa * of + wd * de) / (wa + wd);
  return conFisico ? p * (0.7 + 0.3 * j.fisico) : p;
}

/// Nivel general del jugador en su posición.
int nivel(Jugador j) => _round(puntaje(j, j.pos, false));

/// Redondeo como el de Python (al par en los .5).
int _round(double v) {
  final r = v.roundToDouble();
  if ((v - v.truncateToDouble()).abs() == 0.5) {
    final abajo = v.floorToDouble();
    return (abajo % 2 == 0 ? abajo : abajo + 1).toInt();
  }
  return r.toInt();
}

int redondear(double v) => _round(v);

typedef Puesto = (Jugador, String);

class Fuerza {
  final double ataque, defensa, promOf, promDe;
  const Fuerza(this.ataque, this.defensa, this.promOf, this.promDe);
}

/// Fuerza de los 11 en cancha, en la escala del modelo de goles.
Fuerza fuerza(List<Puesto> xi, [String? formacion]) {
  var sa = 0.0, pa = 0.0, sd = 0.0, pd = 0.0;
  for (final (j, s) in xi) {
    final (wa, wd) = aporte[s]!;
    final (of, de) = valores(j, s);
    sa += wa * of;
    pa += wa;
    sd += wd * de;
    pd += wd;
  }
  final promOf = pa > 0 ? sa / pa : 0.0;
  final promDe = pd > 0 ? sd / pd : 0.0;
  var ataque = k * (promOf - promedio);
  var defensa = -k * (promDe - promedio);
  if (formacion != null) {
    final (a, d) = efectoFormacion[formacion]!;
    ataque += a;
    defensa += d;
  }
  return Fuerza(ataque, defensa, promOf, promDe);
}

const _ordenSlots = ['ARQ', 'DC', 'DFC', 'MCD', 'LD', 'LI', 'MCO', 'ED', 'EI', 'MC'];

/// Los que pueden jugar (sin lesión). Si faltan para armar un equipo, juegan todos.
List<Jugador> aptos(List<Jugador> plantel) {
  final sanos = plantel.where((j) => j.lesion == 0).toList();
  return sanos.length >= 16 ? sanos : List.of(plantel);
}

List<String> slotsDe(String formacion) =>
    ['ARQ', for (final l in formaciones[formacion]!) ...l];

/// Elige los 11 mejores para esa formación, puesto por puesto.
List<Puesto> armarXi(List<Jugador> plantel, String formacion, [bool conFisico = true]) {
  final slots = slotsDe(formacion)
    ..sort((a, b) => _ordenSlots.indexOf(a).compareTo(_ordenSlots.indexOf(b)));
  final libres = List<Jugador>.of(plantel);
  final xi = <Puesto>[];
  for (final s in slots) {
    if (libres.isEmpty) break;
    var mejor = libres.first;
    var mp = puntaje(mejor, s, conFisico);
    for (final j in libres.skip(1)) {
      final p = puntaje(j, s, conFisico);
      if (p > mp) {
        mejor = j;
        mp = p;
      }
    }
    libres.remove(mejor);
    xi.add((mejor, s));
  }
  return xi;
}

// ---------------------------------------------------------------- generación
double _clip(double v, [double lo = 20, double hi = 99]) => math.max(lo, math.min(hi, v));

/// Hasta dónde puede llegar: los jóvenes tienen margen.
int potencialDe(Jugador j, Azar rng) {
  final int extra;
  if (j.edad <= 21) {
    extra = rng.randint(6, 22);
  } else if (j.edad <= 25) {
    extra = rng.randint(2, 11);
  } else if (j.edad <= 29) {
    extra = rng.randint(0, 4);
  } else {
    extra = 0;
  }
  return math.min(99, nivel(j) + extra);
}

void redondearAtributos(Jugador j) {
  j.ataque = _round(_clip(j.ataque)).toDouble();
  j.creacion = _round(_clip(j.creacion)).toDouble();
  j.defensa = _round(_clip(j.defensa)).toDouble();
  j.atajada = _round(_clip(j.atajada, 10)).toDouble();
  j.resistencia = _round(j.resistencia).toDouble();
}

/// Un jugador nuevo para un club con ese nivel ofensivo y defensivo.
Jugador generarJugador(String pos, int edad, double metaOf, double metaDe, double calidad,
    Azar rng, Set<String> usados, Set<String> apellidosClub) {
  if (edad <= 21) {
    calidad -= 5;
  } else if (edad >= 33) {
    calidad -= 2;
  }
  final (pa, pc, pd) = _perfil[pos]!;
  final at = metaOf + pa + calidad + rng.gauss(0, 3.5);
  final cr = metaOf + pc + calidad + rng.gauss(0, 3.5);
  final df = metaDe + pd + calidad + rng.gauss(0, 3.5);
  final aj = pos == 'ARQ' ? metaDe + calidad + rng.gauss(0, 3) : rng.uniform(10, 25);
  final res = rng.gauss(68, 9) - (edad >= 33 ? 8 : 0);
  final (nombre, apellido) = generarNombre(rng, usados, apellidosClub);
  final sec = secundarias[pos];
  final pos2 = sec != null && rng.random() < 0.35 ? rng.choice(sec) : null;
  return Jugador(nombre, apellido, pos, edad, at, cr, df, aj, _clip(res, 35, 95), pos2: pos2);
}

/// Nivel ofensivo y defensivo de un club, a partir de su fuerza en el modelo.
(double, double) metas(double ataque, double defensa) =>
    (promedio + ataque / k, promedio - defensa / k);

// ---------------------------------------------------------------- temporadas
// Al terminar una temporada todos cumplen un año. Desde los 31 empiezan a
// bajar, desde los 34 se pueden retirar.
const edadRetiro = 34; // los arqueros duran 2 años más
const edadRetiroSeguro = 40;

/// Envejece el plantel. Devuelve (retirados, juveniles).
(List<Jugador>, List<Jugador>) pasarTemporada(List<Jugador> plantel, double ataque,
    double defensa, Azar rng, Set<String> usados,
    {double cantera = 0.0, bool reponer = true}) {
  final (metaOf, metaDe) = metas(ataque, defensa);
  final retirados = <Jugador>[], juveniles = <Jugador>[];
  for (final j in List.of(plantel)) {
    j.edad += 1;
    j.fisico = 1.0;
    j.lesion = 0;
    final extra = j.pos == 'ARQ' ? 2 : 0;
    if (j.edad >= 31 + extra) {
      final baja = rng.uniform(0.5, 1.5) * (j.edad - 30 - extra);
      j.ataque -= baja;
      j.creacion -= baja;
      j.defensa -= baja;
      j.atajada -= baja;
      j.resistencia -= rng.uniform(1, 3);
      redondearAtributos(j);
      j.potencial = math.min(j.potencial, nivel(j));
    }
    final prob = 0.15 * (j.edad - edadRetiro - extra + 1);
    if (j.edad >= edadRetiroSeguro + extra || (prob > 0 && rng.random() < prob)) {
      plantel.remove(j);
      retirados.add(j);
    }
  }
  final apellidosClub = {for (final j in plantel) j.apellido};
  if (reponer) {
    for (final viejo in retirados) {
      final nuevo = generarJugador(viejo.pos, rng.randint(17, 21), metaOf, metaDe,
          rng.gauss(-6 + cantera, 4), rng, usados, apellidosClub);
      redondearAtributos(nuevo);
      nuevo.potencial = math.min(99, potencialDe(nuevo, rng) + math.max(0, _round(cantera)));
      plantel.add(nuevo);
      juveniles.add(nuevo);
    }
  }
  return (retirados, juveniles);
}

// ---------------------------------------------------------------- entrenamiento
const tiposEntrenamiento = {
  'completo': 'un poco de todo',
  'ataque': 'ataque y creación',
  'defensa': 'defensa y atajada',
  'fisico': 'resistencia',
  'descanso': 'recuperar energía',
};
// progreso, físico que suma o resta, chance de lesión por jugador
const intensidades = {
  'suave': (0.5, 0.06, 0.0),
  'normal': (1.0, 0.0, 0.004),
  'fuerte': (1.7, -0.07, 0.012),
};
const ritmo = 0.008;
const ritmoResistencia = 0.15;
const recuperoDescanso = 0.12;
const _atributos = {
  'completo': ['ataque', 'creacion', 'defensa'],
  'ataque': ['ataque', 'creacion'],
  'defensa': ['defensa'],
};
const enfoque = 1.5;

double ritmoEdad(int edad) =>
    edad <= 21 ? 1.4 : edad <= 25 ? 1.0 : edad <= 29 ? 0.6 : 0.3;

double _get(Jugador j, String a) => switch (a) {
      'ataque' => j.ataque,
      'creacion' => j.creacion,
      'defensa' => j.defensa,
      _ => j.atajada,
    };

void _set(Jugador j, String a, double v) {
  switch (a) {
    case 'ataque':
      j.ataque = v;
    case 'creacion':
      j.creacion = v;
    case 'defensa':
      j.defensa = v;
    default:
      j.atajada = v;
  }
}

class Mejora {
  final Jugador j;
  final int antes, despues;
  Mejora(this.j, this.antes, this.despues);
}

/// Una semana de entrenamiento. Devuelve (mejoras, lesionados).
/// mult: lo que aportan las instalaciones y el cuerpo técnico del club.
(List<Mejora>, List<(Jugador, int)>) entrenar(
    List<Jugador> plantel, String tipo, String intensidad, Azar rng,
    [Map<String, double> mult = const {}]) {
  var (progreso, fisico, riesgo) = intensidades[intensidad]!;
  if (tipo == 'descanso') {
    progreso = 0.0;
    fisico = recuperoDescanso;
    riesgo = 0.0;
  }
  progreso *= mult['progreso'] ?? 1.0;
  riesgo *= mult['lesion'] ?? 1.0;
  final mejoras = <Mejora>[];
  final lesionados = <(Jugador, int)>[];
  for (final j in plantel) {
    if (j.lesion > 0) {
      j.lesion -= 1;
      continue;
    }
    j.fisico = math.max(0.5, math.min(1.0, j.fisico + fisico));
    if (tipo == 'fisico') {
      j.resistencia = math.min(
          95,
          j.resistencia +
              ritmoResistencia *
                  progreso *
                  (mult['resistencia'] ?? 1.0) *
                  ritmoEdad(j.edad) *
                  rng.uniform(0.5, 1.5));
    } else if (progreso > 0) {
      final List<String> attrs;
      if (j.pos == 'ARQ') {
        attrs = tipo != 'ataque' ? ['atajada'] : [];
      } else {
        attrs = _atributos[tipo]!;
      }
      final antes = puntaje(j, j.pos, false);
      final margen = j.potencial - antes;
      if (attrs.isNotEmpty && margen > 0) {
        final paso = ritmo *
            progreso *
            ritmoEdad(j.edad) *
            margen *
            rng.uniform(0.5, 1.5) *
            (tipo == 'completo' ? 1 : enfoque);
        final pasos = {for (final a in attrs) a: paso * (mult[a] ?? 1.0)};
        for (final a in attrs) {
          _set(j, a, math.min(99, _get(j, a) + pasos[a]!));
        }
        // el nivel nunca pasa el potencial
        final subio = puntaje(j, j.pos, false) - antes;
        if (subio > margen) {
          for (final a in attrs) {
            _set(j, a, _get(j, a) - pasos[a]! * (1 - margen / subio));
          }
        }
        if (nivel(j) > _round(antes)) mejoras.add(Mejora(j, _round(antes), nivel(j)));
      }
    }
    if (riesgo > 0 && rng.random() < riesgo) {
      j.lesion = math.max(1, rng.choice(const [1, 1, 2, 2, 3, 4]) - (mult['dur'] ?? 0).toInt());
      lesionados.add((j, j.lesion));
    }
  }
  return (mejoras, lesionados);
}

List<Jugador> copiarPlantel(List<Jugador> plantel) => [for (final j in plantel) j.copia()];

/// Orden para mostrar un plantel: por posición y nivel.
int ordenPlantel(Jugador a, Jugador b) {
  final c = posiciones.indexOf(a.pos).compareTo(posiciones.indexOf(b.pos));
  return c != 0 ? c : nivel(b).compareTo(nivel(a));
}
