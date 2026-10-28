// Instalaciones, cuerpo técnico y reserva de los clubes (ver club.py).
//
// Instalaciones de nivel 1 a 5 (predio, centro médico, estadio,
// inferiores) y cuerpo técnico de nivel 0 (no hay) a 5. Los efectos se
// miden contra un club promedio (nivel 2,5).
import 'dart:math' as math;

import 'azar.dart';
import 'equipo.dart';
import 'jugadores.dart' as J;
import 'jugadores.dart' show Jugador;
import 'mercado.dart' as M;

const instalacionesNombres = {
  'predio': 'Predio', 'medico': 'Centro médico', 'estadio': 'Estadio',
  'inferiores': 'Inferiores',
};
const efectoInstalacion = {
  'predio': 'los jugadores mejoran más rápido',
  'medico': 'menos lesiones y más cortas',
  'estadio': 'un 10% más de ingresos',
  'inferiores': 'mejores juveniles',
};
const roles = {
  'preparador': 'Preparador físico', 'ataque': 'Ayudante de ataque',
  'defensa': 'Ayudante de defensa', 'arqueros': 'Entrenador de arqueros',
  'inferiores': 'Coordinador de inferiores',
};
const nivelMax = 5;
const _promedio = 2.5;
const subaEstadio = 0.10;
const candidatosPorRol = 4;

// ---------------------------------------------------------------- costos
double costoObra(String tipo, int nivelNuevo) =>
    M.r3(0.6 * math.pow(2, nivelNuevo - 2) * (tipo == 'estadio' ? 2 : 1));

int duracionObra(int nivelNuevo) => 4 * nivelNuevo;

double mantenimiento(Equipo e) =>
    M.r3(e.instalaciones.values.fold(0.0, (a, n) => a + 0.04 * math.pow(n, 1.5)));

double sueldoStaff(int nivel) => nivel > 0 ? M.r3(0.03 * math.pow(nivel, 1.6)) : 0.0;

double gastosAnuales(Equipo e) =>
    mantenimiento(e) + e.staff.values.fold(0.0, (a, m) => a + m.sueldo);

// ---------------------------------------------------------------- efectos
double _f(num nivel, double k) => 1 + k * (nivel - _promedio);

Map<String, double> multiplicadores(Equipo e) {
  final inst = e.instalaciones;
  return {
    'progreso': _f(inst['predio'] ?? 2, 0.15),
    'ataque': _f(e.nivelStaff('ataque'), 0.12),
    'creacion': _f(e.nivelStaff('ataque'), 0.12),
    'defensa': _f(e.nivelStaff('defensa'), 0.12),
    'atajada': _f(e.nivelStaff('arqueros'), 0.12),
    'resistencia': _f(e.nivelStaff('preparador'), 0.15),
    'lesion': math.max(0.4, _f(inst['medico'] ?? 2, -0.15)),
    'dur': (inst['medico'] ?? 2) >= 4 ? 1.0 : 0.0,
  };
}

double recuperoExtra(Equipo e) => 0.015 * (e.nivelStaff('preparador') - _promedio);

double cantera(Equipo e) =>
    1.2 * ((e.instalaciones['inferiores'] ?? 2) - _promedio) +
    0.8 * (e.nivelStaff('inferiores') - _promedio);

// ---------------------------------------------------------------- arranque
Miembro nuevoStaff(Azar rng, int nivel, Set<String> usados) {
  final (nombre, apellido) = J.generarNombre(rng, usados, {});
  return Miembro('${nombre[0]}. $apellido', nivel, sueldoStaff(nivel));
}

/// Instalaciones y cuerpo técnico según el tamaño del club (ranking: 1 = el más grande).
void iniciar(List<Equipo> equipos, Map<String, int> ranking, Azar rng) {
  final usados = <String>{};
  final total = equipos.length;
  for (final e in equipos) {
    if (e.instalaciones.isNotEmpty) continue;
    final grande = 1 - (ranking[e.nombre]! - 1) / math.max(1, total - 1);
    final base = 1 + 3 * grande;
    e.instalaciones = {
      for (final t in instalacionesNombres.keys)
        t: math.max(1, math.min(4, J.redondear(base + rng.uniform(-0.6, 0.6))))
    };
    e.staff = {};
    for (final rol in roles.keys) {
      final nivel = math.max(0, math.min(5, J.redondear(base + rng.uniform(-1.2, 0.8))));
      if (nivel > 0) e.staff[rol] = nuevoStaff(rng, nivel, usados);
    }
    e.obras = [];
    e.ingreso = M.r3(e.ingreso + gastosAnuales(e));
  }
}

/// Cuerpo técnico sin club: algunos de cada rol, de distintos niveles.
Map<String, List<Miembro>> candidatos(Azar rng, Set<String> usados) => {
      for (final rol in roles.keys)
        rol: [
          for (var i = 0; i < candidatosPorRol; i++)
            nuevoStaff(rng, rng.choice(const [1, 2, 2, 3, 3, 4, 5]), usados)
        ]..sort((a, b) => b.nivel.compareTo(a.nivel))
    };

// ---------------------------------------------------------------- obras
double? empezarObra(Equipo e, String tipo) {
  final nivel = e.instalaciones[tipo]! + 1;
  if (nivel > nivelMax || e.obras.any((o) => o.tipo == tipo)) return null;
  final costo = costoObra(tipo, nivel);
  e.caja -= costo;
  e.obras.add(Obra(tipo, duracionObra(nivel)));
  return costo;
}

/// Una fecha de obra. Devuelve las instalaciones que se terminaron.
List<String> avanzarObras(Equipo e) {
  final listas = <String>[];
  for (final obra in List.of(e.obras)) {
    obra.faltan -= 1;
    if (obra.faltan <= 0) {
      e.instalaciones[obra.tipo] = e.instalaciones[obra.tipo]! + 1;
      if (obra.tipo == 'estadio') e.ingreso = M.r3(e.ingreso * (1 + subaEstadio));
      e.obras.remove(obra);
      listas.add(obra.tipo);
    }
  }
  return listas;
}

void pagarFecha(Equipo e, int fechas) => e.caja -= gastosAnuales(e) / fechas;

// ---------------------------------------------------------------- la computadora
const _prioridadIa = ['predio', 'inferiores', 'medico', 'estadio'];

String? invertirIa(Equipo e, Azar rng) {
  if (e.caja < 1.2 * e.ingreso || e.obras.isNotEmpty) return null;
  final orden = List.of(_prioridadIa)
    ..sort((a, b) {
      final c = e.instalaciones[a]!.compareTo(e.instalaciones[b]!);
      return c != 0 ? c : _prioridadIa.indexOf(a).compareTo(_prioridadIa.indexOf(b));
    });
  for (final tipo in orden) {
    final nivel = e.instalaciones[tipo]! + 1;
    if (nivel <= nivelMax && costoObra(tipo, nivel) <= 0.5 * e.caja) {
      empezarObra(e, tipo);
      return '🏗 ${e.nombre} mejora: ${instalacionesNombres[tipo]}, nivel $nivel.';
    }
  }
  var rol = roles.keys.first;
  for (final r in roles.keys) {
    if (e.nivelStaff(r) < e.nivelStaff(rol)) rol = r;
  }
  final nivel = e.nivelStaff(rol) + 1;
  if (nivel <= nivelMax && sueldoStaff(nivel) <= 0.05 * e.ingreso) {
    e.staff[rol] = nuevoStaff(rng, nivel, {});
  }
  return null;
}

// ---------------------------------------------------------------- reserva
const reservaMax = 12;
const edadLimite = 21;
const pibesAlArrancar = 5;
const plantelIdeal = 24;

int cuantosLlegan(Equipo e) => 2 + (e.instalaciones['inferiores'] ?? 2) ~/ 2;

/// El potencial que ve el club, con un error que achica el coordinador.
void estimar(Jugador j, Equipo e, Azar rng) {
  final coord = e.nivelStaff('inferiores');
  j.potEst = J.redondear(j.potencial + rng.gauss(0, math.max(1.0, 7 - 1.2 * coord)));
}

int estrellasPot(Jugador j) {
  final pe = j.potEst > 0 ? j.potEst : j.potencial;
  return pe < 60
      ? 1
      : pe < 68
          ? 2
          : pe < 76
              ? 3
              : pe < 84
                  ? 4
                  : 5;
}

Jugador nuevoPibe(Equipo e, int edad, Azar rng, Set<String> usados) {
  final (metaOf, metaDe) = J.metas(e.ataque, e.defensa);
  final pos = rng.choices(J.composicion.keys.toList(), J.composicion.values.toList());
  final bonus = e.instalaciones.isNotEmpty ? cantera(e) : 0.0;
  final j = J.generarJugador(pos, edad, metaOf, metaDe,
      rng.gauss(-14 + 0.5 * bonus + 2 * (edad - 16), 4), rng, usados,
      {for (final x in [...e.plantel, ...e.reserva]) x.apellido});
  J.redondearAtributos(j);
  final crack = rng.random() < 0.10 ? rng.randint(5, 15) : 0;
  j.potencial = math.min(99, J.potencialDe(j, rng) + crack + math.max(0, J.redondear(0.6 * bonus)));
  estimar(j, e, rng);
  return j;
}

void iniciarReserva(List<Equipo> equipos, Azar rng, Set<String> usados) {
  for (final e in equipos) {
    if (e.reserva.isEmpty) {
      e.reserva = [
        for (var i = 0; i < pibesAlArrancar; i++) nuevoPibe(e, rng.randint(16, 20), rng, usados)
      ];
    }
  }
}

List<Jugador> lleganPibes(Equipo e, Azar rng, Set<String> usados) {
  final nuevos = <Jugador>[];
  for (var i = 0; i < cuantosLlegan(e); i++) {
    if (e.reserva.length >= reservaMax) break;
    final j = nuevoPibe(e, rng.randint(16, 17), rng, usados);
    e.reserva.add(j);
    nuevos.add(j);
  }
  return nuevos;
}

void pasarAnioReserva(Equipo e, Azar rng) {
  for (final j in e.reserva) {
    j.edad += 1;
    j.fisico = 1.0;
    j.lesion = 0;
    estimar(j, e, rng);
  }
}

void subir(Equipo e, Jugador j) {
  e.reserva.remove(j);
  e.plantel.add(j);
  M.firmar(j, null, 3);
}

void reservaIa(Equipo e) {
  while (e.plantel.length < plantelIdeal && e.reserva.isNotEmpty) {
    subir(e, e.reserva.reduce((a, b) => J.nivel(b) > J.nivel(a) ? b : a));
  }
  final peor = e.plantel.map(J.nivel).reduce(math.min);
  for (final j in [for (final j in e.reserva) if (j.edad >= edadLimite) j]) {
    if (J.nivel(j) > peor && e.plantel.length < 30) {
      subir(e, j);
    } else {
      e.reserva.remove(j);
    }
  }
}

double ofertaExterior(Jugador j, Azar rng) =>
    M.r3(M.valor(j) * rng.uniform(1.5, 3.0) * (1 + math.max(0, j.potencial - 75) / 15));
