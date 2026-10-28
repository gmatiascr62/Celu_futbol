// Mercado de pases y finanzas de los clubes (ver mercado.py).
//
// La plata está en millones de dólares. Cada jugador tiene un valor de
// mercado según su nivel, su edad y su potencial, y cobra un sueldo anual.
// Cada club tiene una caja y un ingreso anual; los sueldos se pagan fecha a
// fecha y a fin de temporada hay premios según el puesto.
import 'dart:math' as math;

import 'azar.dart';
import 'equipo.dart';
import 'jugadores.dart' as J;
import 'jugadores.dart' show Jugador;

const plantelMin = 20;
const plantelMax = 30;
const sueldoSobreValor = 0.18;
const sueldoMinimo = 0.02;
const parteSueldos = 0.8;
const cajaInicial = 0.35;
const premioCampeon = 0.30;
const cajaMaxima = 2.0;
const indemnizacionParte = 0.5;
const descuentoUltimoAnio = 0.7;
const libresPorPosicion = 3;
const exterior = [
  'un club de Brasil', 'un club de México', 'un club de la MLS',
  'un club de Portugal', 'un club de España', 'un club de Italia',
];
const valorExterior = 1.5;

double r3(double v) => (v * 1000).roundToDouble() / 1000;

/// Monto en millones de dólares, en texto corto.
String plata(double m) {
  if (m.abs() >= 1) return 'US\$ ${m.toStringAsFixed(1).replaceAll('.', ',')}M';
  return 'US\$ ${(m * 1000).round()}K';
}

// ---------------------------------------------------------------- valores
double valor(Jugador j) {
  final n = J.nivel(j);
  final base = math.exp(0.13 * (n - 70));
  final e = j.edad;
  final edad = e <= 21
      ? 1.25
      : e <= 23
          ? 1.15
          : e <= 28
              ? 1.0
              : e <= 30
                  ? 0.8
                  : e <= 32
                      ? 0.55
                      : 0.3;
  final potencial = 1 + 0.04 * math.max(0, j.potencial - n);
  return r3(base * edad * potencial);
}

double sueldoPedido(Jugador j) => math.max(sueldoMinimo, sueldoSobreValor * valor(j));

double sueldo(Jugador j) => j.sueldo > 0 ? j.sueldo : sueldoPedido(j);

int aniosContrato(Jugador j) => j.edad <= 25
    ? 4
    : j.edad <= 29
        ? 3
        : j.edad <= 32
            ? 2
            : 1;

void firmar(Jugador j, [double? sueldoAnual, int? anios]) {
  j.sueldo = r3(sueldoAnual ?? sueldoPedido(j));
  j.contrato = anios ?? aniosContrato(j);
}

void iniciarContratos(Iterable<List<Jugador>> planteles, Azar rng) {
  for (final plantel in planteles) {
    for (final j in plantel) {
      if (j.sueldo == 0) firmar(j, sueldoPedido(j) * rng.uniform(0.85, 1.15), rng.randint(1, 4));
    }
  }
}

/// Lo que pide para renovar: más si está en su mejor momento.
double pretension(Jugador j, Azar rng) {
  final extra = j.edad <= 29 && j.potencial > J.nivel(j) ? 1.25 : 1.1;
  return r3(sueldoPedido(j) * rng.uniform(1.0, extra));
}

/// El jugador acepta si le ofrecen al menos el 90% de lo que pide.
bool acepta(double oferta, double pedido) => oferta >= 0.9 * pedido;

double masaSalarial(List<Jugador> plantel) => plantel.fold(0.0, (a, j) => a + sueldo(j));

void iniciarFinanzas(List<Equipo> equipos) {
  for (final e in equipos) {
    if (e.ingreso == 0) {
      e.ingreso = r3(masaSalarial(e.plantel) / parteSueldos);
      e.caja = r3(e.ingreso * cajaInicial);
    }
  }
}

void cobrarFecha(List<Equipo> equipos, int fechas) {
  for (final e in equipos) {
    e.caja += (e.ingreso - masaSalarial(e.plantel)) / fechas;
  }
}

/// Premios de fin de temporada: más plata cuanto mejor el puesto.
void premios(List<Equipo> equipos, List<String> orden, String? mio) {
  final n = orden.length;
  final porNombre = {for (final e in equipos) e.nombre: e};
  for (var i = 0; i < n; i++) {
    final e = porNombre[orden[i]]!;
    e.caja += e.ingreso * premioCampeon * (1 - i / (n - 1));
    if (orden[i] != mio) e.caja = math.min(e.caja, cajaMaxima * e.ingreso);
  }
}

// ---------------------------------------------------------------- plantel
Set<Jugador> titulares(Equipo e) =>
    {for (final x in J.armarXi(J.aptos(e.plantel), e.formacion, false)) x.$1};

/// El puesto más flojo del equipo titular: (posición, puntaje).
(String, double) necesidad(Equipo e) {
  final xi = J.armarXi(J.aptos(e.plantel), e.formacion, false);
  var peor = xi.first;
  for (final x in xi) {
    if (J.puntaje(x.$1, x.$2, false) < J.puntaje(peor.$1, peor.$2, false)) peor = x;
  }
  return (peor.$2, J.puntaje(peor.$1, peor.$2, false));
}

bool puedeVender(Equipo e, Jugador j) {
  if (e.plantel.length <= plantelMin) return false;
  final mismos = e.plantel.where((x) => x.pos == j.pos).length;
  return mismos > (j.pos == 'ARQ' ? 2 : 1);
}

List<Jugador> figuras(Equipo e) {
  final orden = List.of(e.plantel)..sort((a, b) => J.nivel(a).compareTo(J.nivel(b)));
  return orden.sublist(math.max(0, orden.length - 3));
}

double precioPedido(Equipo e, Jugador j, [Set<Jugador>? tits]) {
  tits ??= titulares(e);
  var factor = figuras(e).contains(j)
      ? 2.0
      : tits.contains(j)
          ? 1.4
          : 1.1;
  if (e.caja < 0) factor -= 0.2;
  if (j.contrato <= 1) factor *= descuentoUltimoAnio;
  return r3(valor(j) * factor);
}

/// Cómo responde un club a una oferta: ('acepta' | 'contraoferta' | 'rechaza', monto).
(String, double) respuesta(Equipo e, Jugador j, double oferta) {
  final pedido = precioPedido(e, j);
  if (oferta >= pedido) return ('acepta', oferta);
  if (oferta >= 0.8 * pedido) return ('contraoferta', pedido);
  return ('rechaza', pedido);
}

void transferir(Jugador j, Equipo vendedor, Equipo comprador, double monto,
    [double? sueldoAnual, int? anios]) {
  vendedor.plantel.remove(j);
  comprador.plantel.add(j);
  vendedor.caja += monto;
  comprador.caja -= monto;
  firmar(j, sueldoAnual ?? 1.1 * sueldoPedido(j), anios);
  j.fisico = math.min(j.fisico, 0.9);
}

bool esExterior(String club) => exterior.contains(club);

void vender(Jugador j, Equipo vendedor, String club, List<Equipo> equipos, double monto) {
  if (esExterior(club)) {
    vendedor.plantel.remove(j);
    vendedor.caja += monto;
    j.contrato = 0;
    j.sueldo = 0;
  } else {
    transferir(j, vendedor, equipos.firstWhere((e) => e.nombre == club), monto);
  }
}

double indemnizacion(Jugador j) => indemnizacionParte * sueldo(j) * math.max(j.contrato, 1);

void liberar(Jugador j, Equipo e, List<Jugador> libres, {bool pagar = true}) {
  e.plantel.remove(j);
  if (pagar) e.caja -= indemnizacion(j);
  j.contrato = 0;
  j.sueldo = 0;
  libres.add(j);
}

void ficharLibre(Jugador j, Equipo e, List<Jugador> libres, [double? sueldoAnual, int? anios]) {
  libres.remove(j);
  e.plantel.add(j);
  firmar(j, sueldoAnual, anios);
}

/// Fin de temporada en los clubes de la computadora: renuevan a los que sirven.
List<String> vencimientosIa(List<Equipo> equipos, String? mio, List<Jugador> libres, Azar rng) {
  final log = <String>[];
  for (final e in equipos) {
    if (e.nombre == mio) continue;
    final orden = List.of(e.plantel)..sort((a, b) => J.nivel(b).compareTo(J.nivel(a)));
    final importantes = orden.take(16).toSet();
    for (final j in [for (final j in e.plantel) if (j.contrato <= 0) j]) {
      final sigue = (importantes.contains(j) && j.edad < 34) || e.plantel.length <= plantelMin;
      if (sigue) {
        firmar(j, pretension(j, rng));
      } else {
        liberar(j, e, libres, pagar: false);
        log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): termina contrato en ${e.nombre}, queda libre');
      }
    }
  }
  return log;
}

// ---------------------------------------------------------------- libres
List<Jugador> generarLibres(Azar rng, Set<String> usados, double nivelMedio) {
  final libres = <Jugador>[];
  for (final pos in J.composicion.keys) {
    for (var i = 0; i < libresPorPosicion; i++) {
      final edad = rng.randint(22, 35);
      final meta = nivelMedio - rng.uniform(10, 22);
      final j = J.generarJugador(pos, edad, meta, meta, 0, rng, usados, {});
      J.redondearAtributos(j);
      j.potencial = J.potencialDe(j, rng);
      libres.add(j);
    }
  }
  return libres;
}

double nivelMedio(List<Equipo> equipos) {
  final niveles = [for (final e in equipos) for (final j in e.plantel) J.nivel(j)];
  return niveles.reduce((a, b) => a + b) / niveles.length;
}

// ---------------------------------------------------------------- la computadora
(Jugador, double)? importar(Equipo c, String pos, double actual, Azar rng, Set<String> usados) {
  final meta = actual + rng.uniform(4, 8);
  final j = J.generarJugador(pos, rng.randint(24, 30), meta, meta, 0, rng, usados,
      {for (final x in c.plantel) x.apellido});
  J.redondearAtributos(j);
  j.potencial = J.potencialDe(j, rng);
  final precio = r3(valor(j) * 1.3);
  if (J.nivel(j) < actual + 3 || precio > 0.6 * c.caja) return null;
  c.plantel.add(j);
  c.caja -= precio;
  firmar(j, 1.1 * sueldoPedido(j));
  return (j, precio);
}

/// Lo que hacen en una ventana los clubes que maneja la computadora.
List<String> movimientosIa(List<Equipo> equipos, String? mio, List<Jugador> libres, Azar rng,
    {double prob = 0.5, Set<String>? usados}) {
  final log = <String>[];
  final movidos = <Jugador>{};
  final tits = {for (final e in equipos) e.nombre: titulares(e)};
  final compradores = [for (final e in equipos) if (e.nombre != mio) e];
  rng.shuffle(compradores);
  compradores.addAll([for (final c in compradores) if (c.caja > c.ingreso) c]);
  for (final c in compradores) {
    final rico = c.caja > c.ingreso;
    if ((!rico && rng.random() > prob) || c.plantel.length >= plantelMax) continue;
    final (pos, actual) = necesidad(c);
    final presupuesto = 0.6 * c.caja;
    final opciones = <(double, Jugador, Equipo, double)>[];
    for (final v in equipos) {
      if (identical(v, c) || v.nombre == mio) continue;
      for (final j in v.plantel) {
        if (j.pos == pos &&
            j.lesion == 0 &&
            J.nivel(j) >= actual + 3 &&
            !movidos.contains(j) &&
            puedeVender(v, j)) {
          final precio = precioPedido(v, j, tits[v.nombre]);
          if (precio <= presupuesto &&
              masaSalarial(c.plantel) + sueldoPedido(j) <= (rico ? 1.3 : 1.05) * c.ingreso) {
            opciones.add((J.nivel(j) - 2 * precio / math.max(c.ingreso, 0.1), j, v, precio));
          }
        }
      }
    }
    if (opciones.isNotEmpty) {
      final (_, j, v, precio) = opciones.reduce((a, b) => b.$1 > a.$1 ? b : a);
      transferir(j, v, c, precio);
      movidos.add(j);
      log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): ${v.nombre} → ${c.nombre}, ${plata(precio)}');
      continue;
    }
    final traido = rico && usados != null ? importar(c, pos, actual, rng, usados) : null;
    if (traido != null) {
      final (j, precio) = traido;
      movidos.add(j);
      log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): del exterior → ${c.nombre}, ${plata(precio)}');
      continue;
    }
    final mejores = [
      for (final j in libres)
        if (j.pos == pos &&
            J.nivel(j) >= actual + 2 &&
            masaSalarial(c.plantel) + sueldoPedido(j) <= c.ingreso)
          j
    ];
    if (mejores.isNotEmpty) {
      final j = mejores.reduce((a, b) => J.nivel(b) > J.nivel(a) ? b : a);
      ficharLibre(j, c, libres);
      movidos.add(j);
      log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): libre → ${c.nombre}');
    }
  }
  for (final e in equipos) {
    if (e.nombre == mio) continue;
    while (e.plantel.length > plantelMax - 2) {
      final cand = [for (final x in e.plantel) if (!movidos.contains(x)) x];
      if (cand.isEmpty) break;
      final j = cand.reduce((a, b) => J.nivel(b) < J.nivel(a) ? b : a);
      if (!puedeVender(e, j)) break;
      liberar(j, e, libres);
      log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): ${e.nombre} lo deja libre');
    }
    while (e.plantel.length < plantelMin + 2 && libres.isNotEmpty) {
      final (pos, _) = necesidad(e);
      var candidatos = [for (final j in libres) if (j.pos == pos) j];
      if (candidatos.isEmpty) candidatos = List.of(libres);
      final margen = e.ingreso - masaSalarial(e.plantel);
      final pagables = [
        for (final j in candidatos) if (sueldoPedido(j) <= math.max(margen, sueldoMinimo)) j
      ];
      final j = pagables.isNotEmpty
          ? pagables.reduce((a, b) => J.nivel(b) > J.nivel(a) ? b : a)
          : candidatos.reduce((a, b) => sueldoPedido(b) < sueldoPedido(a) ? b : a);
      ficharLibre(j, e, libres);
      log.add('${j.corto} (${j.pos}, ${J.nivel(j)}): libre → ${e.nombre}');
    }
  }
  return log;
}

/// Una oferta por un jugador: quién ofrece, por quién y cuánto.
class Oferta {
  final String club;
  final Jugador j;
  final double monto;
  Oferta(this.club, this.j, this.monto);
}

List<Oferta> ofertasPorMios(List<Equipo> equipos, String mio, Azar rng) {
  final mi = equipos.firstWhere((e) => e.nombre == mio);
  final cantidad = rng.choice(const [0, 1, 1, 2, 2, 3]);
  final otros = [for (final e in equipos) if (e.nombre != mio && e.plantel.length < plantelMax) e];
  final tope = otros.isEmpty ? 0.0 : otros.map((e) => 0.6 * e.caja).reduce(math.max);
  final candidatos = [for (final j in mi.plantel) if (valor(j) * 0.9 <= tope) j]
    ..sort((a, b) => valor(b).compareTo(valor(a)));
  final top = candidatos.take(12).toList();
  final ofertas = <Oferta>[];
  for (final j in rng.sample(top, math.min(cantidad, top.length))) {
    var monto = valor(j) * rng.uniform(0.9, 1.5);
    var interesados = [for (final e in otros) if (0.6 * e.caja >= monto) e];
    if (interesados.isEmpty) {
      monto = valor(j) * 0.9;
      interesados = [for (final e in otros) if (0.6 * e.caja >= monto) e];
    }
    if (interesados.isNotEmpty) ofertas.add(Oferta(rng.choice(interesados).nombre, j, r3(monto)));
  }
  final caros = [
    for (final j in mi.plantel)
      if (valor(j) >= valorExterior && ofertas.every((o) => !identical(o.j, j))) j
  ];
  if (caros.isNotEmpty && rng.random() < 0.5) {
    final j = rng.choice(caros);
    ofertas.add(Oferta(rng.choice(exterior), j, r3(valor(j) * rng.uniform(1.0, 1.6))));
  }
  return ofertas;
}

/// Si ponés a un jugador en venta, quiénes ofrecen y cuánto.
List<(String, double)> ofertasPorJugador(List<Equipo> equipos, String mio, Jugador j, Azar rng) {
  final ofertas = <(String, double)>[];
  for (final e in equipos) {
    if (e.nombre == mio || e.plantel.length >= plantelMax) continue;
    final (pos, actual) = necesidad(e);
    var interes = j.pos == pos ? 1.0 : 0.25;
    if (J.nivel(j) < actual - 2) interes *= 0.2;
    final monto = valor(j) * rng.uniform(0.7, 1.2);
    if (rng.random() < interes * 0.5 && 0.6 * e.caja >= monto) ofertas.add((e.nombre, r3(monto)));
  }
  if (valor(j) >= valorExterior && rng.random() < 0.6) {
    ofertas.add((rng.choice(exterior), r3(valor(j) * rng.uniform(0.9, 1.4))));
  }
  ofertas.sort((a, b) => b.$2.compareTo(a.$2));
  return ofertas.take(3).toList();
}

// ---------------------------------------------------------------- lo que propone el DT
/// Jugadores que el DT propone para un puesto: [(jugador, club o null si es libre, precio)].
List<(Jugador, Equipo?, double)> recomendar(List<Equipo> equipos, Equipo mi, List<Jugador> libres,
    String pos, double nivelMin, String personalidad, int prestigio, Azar rng,
    [int cantidad = 3]) {
  final alcance = 0.4 + 0.6 * prestigio / 100;
  final clubes = [for (final e in equipos) if (!identical(e, mi) && rng.random() < alcance) e];
  final margen = 1.1 * mi.ingreso - masaSalarial(mi.plantel);
  final opciones = <(Jugador, Equipo?, double)>[];
  for (final v in clubes) {
    Set<Jugador>? tits;
    for (final j in v.plantel) {
      if ((j.pos != pos && j.pos2 != pos) || J.nivel(j) < nivelMin || !puedeVender(v, j)) continue;
      tits ??= titulares(v);
      final precio = precioPedido(v, j, tits);
      if (precio <= mi.caja && sueldoPedido(j) <= margen) opciones.add((j, v, precio));
    }
  }
  for (final j in libres) {
    if ((j.pos == pos || j.pos2 == pos) && J.nivel(j) >= nivelMin && sueldoPedido(j) <= margen) {
      opciones.add((j, null, 0.0));
    }
  }
  double puntaje((Jugador, Equipo?, double) op) {
    final (j, _, precio) = op;
    final caro = precio / math.max(mi.caja, 0.5);
    final n = J.nivel(j);
    switch (personalidad) {
      case 'conservador':
        return n + (27 <= j.edad && j.edad <= 32 ? 2 : j.edad < 23 ? -2 : 0) - 3 * caro;
      case 'arriesgado':
        return n + 0.5 * (j.potencial - n);
      case 'impulsivo':
        return n + rng.gauss(0, 4) - 4 * caro;
      default:
        return n - 8 * caro;
    }
  }

  final puntos = {for (final o in opciones) o: puntaje(o)};
  opciones.sort((a, b) => puntos[b]!.compareTo(puntos[a]!));
  return opciones.take(cantidad).toList();
}
