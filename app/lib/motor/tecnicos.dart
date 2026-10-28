// Los DT como personas: nombre, prestigio, sueldo, contrato y estado de
// ánimo (ver tecnicos.py).
//
// El ánimo son tres números de 0 a 100: satisfacción (con vos, el dueño),
// confianza (en el plantel) y presión (por resultados). El DT de tu club te
// pide reuniones; las promesas se revisan cuando cierra el mercado. Si la
// satisfacción llega muy abajo, renuncia. A los de los otros clubes los echan.
import 'dart:math' as math;

import 'azar.dart';
import 'jugadores.dart' as J;
import 'jugadores.dart' show Jugador;

const personalidadesDt = ['equilibrado', 'conservador', 'arriesgado', 'impulsivo'];
const efectoMoral = 0.03;
const renuncia = 15;
const ultimatum = 30;
const presionDespido = 80;
const libresDt = 10;
const _paciencia = {
  'equilibrado': 1.0, 'conservador': 0.7, 'arriesgado': 1.2, 'impulsivo': 1.6,
};

class Tecnico {
  String nombre;
  String apellido;
  int edad;
  String personalidad;
  int prestigio;
  int contrato = 2;
  double satisfaccion = 65.0;
  double confianza = 50.0;
  double presion = 40.0;
  int fechas = 0;
  List<Map<String, dynamic>> promesas = [];
  List<String> avisos = [];
  double aumento = 1.0;
  String ultimoClub = '';
  List<List<dynamic>> clubes = []; // [club, desde, hasta o null]
  List<String> logros = [];
  int despidos = 0;

  Tecnico(this.nombre, this.apellido, this.edad, this.personalidad, this.prestigio);

  String get completo => '$nombre $apellido';
  double get sueldo =>
      ((0.05 + 0.006 * prestigio) * aumento * 1000).roundToDouble() / 1000;

  Map<String, dynamic> toJson() => {
        'nombre': nombre, 'apellido': apellido, 'edad': edad, 'personalidad': personalidad,
        'prestigio': prestigio, 'contrato': contrato, 'satisfaccion': satisfaccion,
        'confianza': confianza, 'presion': presion, 'fechas': fechas, 'promesas': promesas,
        'avisos': avisos, 'aumento': aumento, 'ultimo_club': ultimoClub, 'clubes': clubes,
        'logros': logros, 'despidos': despidos,
      };

  factory Tecnico.fromJson(Map<String, dynamic> d) {
    final t = Tecnico(d['nombre'], d['apellido'], d['edad'], d['personalidad'], d['prestigio']);
    t.contrato = d['contrato'];
    t.satisfaccion = (d['satisfaccion'] as num).toDouble();
    t.confianza = (d['confianza'] as num).toDouble();
    t.presion = (d['presion'] as num).toDouble();
    t.fechas = d['fechas'];
    t.promesas = [for (final p in d['promesas']) Map<String, dynamic>.from(p)];
    t.avisos = List<String>.from(d['avisos']);
    t.aumento = (d['aumento'] as num).toDouble();
    t.ultimoClub = d['ultimo_club'];
    t.clubes = [for (final c in d['clubes']) List<dynamic>.from(c)];
    t.logros = List<String>.from(d['logros']);
    t.despidos = d['despidos'];
    return t;
  }
}

String puesto(String pos) => '${J.nombrePos[pos]} ($pos)';

double _clip(double v) => math.max(0.0, math.min(100.0, v));

void cambiar(Tecnico t, {num sat = 0, num conf = 0, num pres = 0}) {
  t.satisfaccion = _clip(t.satisfaccion + sat * _paciencia[t.personalidad]!);
  t.confianza = _clip(t.confianza + conf);
  t.presion = _clip(t.presion + pres);
}

double moral(Tecnico? t) => t == null ? 1.0 : 1 + efectoMoral * (t.confianza - 50) / 50;

Tecnico nuevo(Azar rng, Set<String> usados, [String? personalidad, int? prestigio]) {
  final (nombre, apellido) = J.generarNombre(rng, usados, {});
  return Tecnico(nombre, apellido, rng.randint(36, 68),
      personalidad ?? rng.choice(personalidadesDt), prestigio ?? rng.randint(30, 85));
}

int prestigioPara(int esperado, int total, Azar rng) {
  final base = 90 - 55 * (esperado - 1) / math.max(1, total - 1);
  return math.max(20, math.min(95, base + rng.gauss(0, 7))).toInt();
}

void bolsaLibres(List<Tecnico> libres, Azar rng, Set<String> usados) {
  while (libres.length < libresDt) {
    libres.add(nuevo(rng, usados));
  }
  if (libres.length > libresDt + 4) libres.removeRange(libresDt + 4, libres.length);
}

// ---------------------------------------------------------------- después de cada fecha
void trasPartido(Tecnico t, int gf, int gc) {
  var efecto = gf > gc
      ? 4.0
      : gf == gc
          ? 1.0
          : -4.0;
  if (t.personalidad == 'impulsivo') efecto *= 1.5;
  t.confianza = _clip(t.confianza + efecto + 0.05 * (50 - t.confianza));
  t.fechas += 1;
}

void actualizarPresion(Tecnico t, int puesto, int esperado, String ultimos, int jugadas,
    [double medios = 1.0, double hinchada = 60.0]) {
  final u = ultimos.length > 5 ? ultimos.substring(ultimos.length - 5) : ultimos;
  final racha = 'P'.allMatches(u).length - 'G'.allMatches(u).length;
  var objetivo = 50 + medios * (2.0 * (puesto - esperado) + 6 * racha);
  objetivo = _clip(objetivo + math.max(0.0, 0.4 * (45 - hinchada)));
  final peso = math.min(1.0, jugadas / 10);
  objetivo = peso * objetivo + (1 - peso) * 45;
  t.presion = _clip(t.presion + 0.25 * (objetivo - t.presion));
}

bool loEchan(Tecnico t, Azar rng) =>
    t.presion > presionDespido && t.fechas >= 6 && rng.random() < 0.12;

// ---------------------------------------------------------------- reuniones
/// Una respuesta posible en una reunión.
class Opcion {
  final String texto;
  final num sat, conf, pres;
  final Map<String, dynamic>? extra; // promesa u otra consecuencia
  final String respuesta; // lo que contesta el DT
  Opcion(this.texto, this.sat, this.conf, this.pres, this.extra, this.respuesta);

  Map<String, dynamic> toJson() => {
        'texto': texto, 'cambios': [sat, conf, pres], 'extra': extra, 'respuesta': respuesta,
      };
  factory Opcion.fromJson(Map<String, dynamic> d) => Opcion(d['texto'], d['cambios'][0],
      d['cambios'][1], d['cambios'][2],
      d['extra'] == null ? null : Map<String, dynamic>.from(d['extra']), d['respuesta']);
}

class Reunion {
  final String tema;
  final String texto;
  final List<String> lista; // los jugadores que propone, para mostrar
  final List<String> candidatos; // sus nombres completos
  final List<Opcion> opciones;
  int prioridad = 0;
  Reunion(this.tema, this.texto, this.opciones,
      {this.lista = const [], this.candidatos = const []});

  Map<String, dynamic> toJson() => {
        'tema': tema, 'texto': texto, 'lista': lista, 'candidatos': candidatos,
        'opciones': [for (final o in opciones) o.toJson()], 'prioridad': prioridad,
      };
  factory Reunion.fromJson(Map<String, dynamic> d) => Reunion(
      d['tema'], d['texto'],
      [for (final o in d['opciones']) Opcion.fromJson(Map<String, dynamic>.from(o))],
      lista: List<String>.from(d['lista']), candidatos: List<String>.from(d['candidatos']))
    ..prioridad = d['prioridad'];
}

String _f(Azar rng, String clave, [Map<String, Object> datos = const {}]) {
  var s = rng.choice(_frases[clave]!);
  datos.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

const _frases = {
  'refuerzo': [
    'Presidente, necesito un {pos}. Con lo que tengo en ese puesto no llegamos.',
    'Le soy sincero: nos falta un {pos}. Si no lo traemos, lo vamos a sufrir.',
    'Estuve mirando el plantel. El puesto de {pos} es el que más me preocupa.',
    'Para pelear arriba hace falta un {pos} de jerarquía. ¿Se puede?',
  ],
  'racha_mala': [
    '{n} partidos sin ganar, presidente. Sé que no es fácil, pero necesito su respaldo.',
    'Esto no está saliendo. {n} partidos sin ganar. Yo no me escondo, ¿y usted?',
    'Los muchachos están golpeados: {n} sin ganar. Banquémonos, que vamos a salir.',
  ],
  'buena_racha': [
    'Estamos bárbaro, presidente. {n} partidos sin perder. El grupo está enchufado.',
    '¡Qué momento! {n} sin perder. Esto recién empieza.',
    'El equipo está jugando como yo quiero. {n} partidos sin perder.',
  ],
  'juvenil': [
    'El pibe {jugador} está para jugar en Primera. Tiene un potencial bárbaro.',
    'Le pido algo: déjeme tirar a {jugador} a la cancha. El pibe está listo.',
    '¿Vio a {jugador} en los entrenamientos? Ese pibe va a valer millones.',
  ],
  'venta': [
    '¿Por qué vendieron a {jugador} sin avisarme? Era titular, presidente.',
    'Me enteré por los diarios que se fue {jugador}. Así no se puede trabajar.',
    'Se fue {jugador} y nadie me consultó. Espero que venga un reemplazo.',
  ],
  'promesa_cumplida': [
    'Gracias, presidente. Me prometió un {pos} y llegó. Así da gusto trabajar.',
    'Cumplió con el {pos}. Eso no lo voy a olvidar.',
  ],
  'promesa_rota': [
    'Me prometió un {pos} y cerró el mercado sin nadie. Me siento engañado.',
    'Usted me dijo que venía un {pos}. No vino nadie. ¿Qué quiere que le diga?',
    'Otra vez me quedé sin el {pos} que me prometieron. Así no.',
  ],
  'ultimatum': [
    'Le hablo claro: si las cosas no cambian, me voy.',
    'Presidente, no me siento respaldado. Si sigue así, agarro mis cosas.',
    'Esto es un ultimátum: o me dan lo que necesito, o renuncio.',
  ],
  'general_bien': [
    'Todo en orden, presidente. El grupo trabaja bien.',
    'Venimos bien. Solo le pido que sigamos por este camino.',
    'Los muchachos me están respondiendo. Se entrena con ganas.',
    'Pasaba a saludar, presidente. El clima en el vestuario es bueno.',
    'Me gusta lo que veo en la semana. Hay hambre en este grupo.',
  ],
  'general_mal': [
    'La gente está nerviosa, presidente. Hay que dar vuelta esto.',
    'No le voy a mentir: el vestuario está tocado.',
    'Hay caras largas en el vestuario. Necesito que me ayude a levantarlos.',
    'Los resultados no acompañan y los muchachos lo sienten.',
    'Me están criticando mucho afuera. Necesito saber que usted está conmigo.',
  ],
  'vence': [
    'A {jugador} se le termina el contrato. Es importante, presidente: renuévele.',
    'Ojo con {jugador}: le queda un año. Si no lo renovamos, se va gratis.',
    '{jugador} me preguntó por su contrato. No lo quiero perder.',
  ],
  'no_usa': [
    'A {jugador} no lo estoy usando y cobra bastante. Véndalo o déjelo ir.',
    'Le soy sincero: {jugador} no entra en mis planes. Busquémosle club.',
    '{jugador} jugó {n} partidos. Con esa plata podemos traer a otro.',
  ],
  'staff': [
    'Presidente, necesito un {rol}. Así no puedo trabajar.',
    'Me falta un {rol} de nivel. Con eso el grupo rinde más, se lo aseguro.',
    'Le pido un {rol}. Es una inversión, no un gasto.',
  ],
  'lo_quieren': [
    'Presidente, me llamaron de {club}. Quieren que sea su técnico. Quería que lo sepa por mí.',
    'Le voy a ser sincero: {club} me hizo una oferta. Antes de contestar, quiero escucharlo.',
  ],
  'entrenamiento': [
    'Los muchachos están fundidos y los hace entrenar fuerte. Así se me van a lesionar.',
    'Con este entrenamiento no llegamos, presidente. Déjeme manejarlo a mí.',
    'Le pido que me deje decidir el entrenamiento. Yo los veo todos los días.',
  ],
  'formacion': [
    'No juego más con el {formacion}, presidente. Perdimos {n} partidos así.',
    'El {formacion} no nos sale. Déjeme elegir a mí o esto se complica.',
  ],
  'renuncia': [
    'Presidente, vengo a presentar mi renuncia. No hay más nada que hablar.',
    'Me voy. Le agradezco, pero así no puedo seguir.',
    'Renuncio. Le deseo suerte al club, de corazón.',
  ],
  'renovacion': [
    'Se me termina el contrato, presidente. ¿Seguimos juntos?',
    'Quería hablar de mi contrato. Termina ahora. ¿Qué piensa?',
  ],
  'no_renueva': [
    'Le agradezco, pero no voy a renovar. Necesito otro desafío.',
    'No sigo, presidente. Fue un gusto, pero me voy.',
  ],
};
const _respuestas = {
  'contento': ['Así me gusta, presidente.', 'Gracias por el respaldo.', 'Eso quería escuchar.'],
  'neutro': ['Bueno, veremos.', 'Entendido.', 'Está bien, lo tengo en cuenta.'],
  'enojado': ['No me gusta lo que escucho.', 'Esto no lo voy a olvidar.',
    'Así es difícil, presidente.'],
};

String _resp(Azar rng, String tono) => rng.choice(_respuestas[tono]!);

/// Clave de la ventana en la que se tiene que cumplir una promesa.
String proximaVentana(int temporada, int numero, int total, String? abierta) {
  if (abierta != null) return abierta;
  if (numero < total ~/ 2) return '$temporada-${total ~/ 2}';
  return '${temporada + 1}-0';
}

Reunion reunionRefuerzo(Tecnico t, Azar rng, String pos, int nivel, double caja, double costo,
    String ventana, bool ventanaAbierta, [List<(String, String)> candidatos = const []]) {
  final texto = _f(rng, 'refuerzo', {'pos': puesto(pos)});
  final promesa = {'pos': pos, 'nivel': nivel + 3, 'ventana': ventana};
  final cuando = ventanaAbierta ? 'en este mercado' : 'en el próximo mercado';
  final noHaySat = caja < costo ? -4 : -10;
  final respNoHay =
      caja < costo ? _resp(rng, 'neutro') : '¿No hay plata? Yo veo la caja, presidente.';
  if (candidatos.isNotEmpty) {
    final primero = candidatos.first.$1;
    final apellido = primero.contains(' ') ? primero.substring(primero.indexOf(' ') + 1) : primero;
    return Reunion('refuerzo', '$texto Le traigo nombres:', [
      Opcion(
          ventanaAbierta
              ? 'Andá a buscar a $apellido'
              : 'Traeme a $apellido en el próximo mercado',
          5, 2, 0, {...promesa, 'jugador': primero}, _resp(rng, 'contento')),
      Opcion('Lo voy a pensar', 0, 0, 0, null, 'Bueno, le dejo la lista.'),
      Opcion('No hay plata', noHaySat, 0, 0, null, respNoHay),
      Opcion('Arreglate con lo que tenés', -8, -3, 0, null, _resp(rng, 'enojado')),
    ], lista: [for (final c in candidatos) c.$2], candidatos: [for (final c in candidatos) c.$1]);
  }
  return Reunion('refuerzo', texto, [
    Opcion('Te lo traigo $cuando', 5, 2, 0, promesa, _resp(rng, 'contento')),
    Opcion('No hay plata', noHaySat, 0, 0, null, respNoHay),
    Opcion('Arreglate con lo que tenés', -8, -3, 0, null, _resp(rng, 'enojado')),
  ]);
}

Reunion reunionRacha(Tecnico t, Azar rng, int n, bool mala, String pos, int nivel,
    String ventana) {
  if (mala) {
    return Reunion('racha_mala', _f(rng, 'racha_mala', {'n': n}), [
      Opcion('Te banco, seguimos con vos', 6, 2, -6, null, _resp(rng, 'contento')),
      Opcion('¿Qué necesitás?', 3, 0, 0, {'pos': pos, 'nivel': nivel + 3, 'ventana': ventana},
          'Un ${puesto(pos)}, presidente. Con eso cambiamos.'),
      Opcion('Si no ganás el próximo, te vas', -12, -2, 12, null, _resp(rng, 'enojado')),
    ]);
  }
  return Reunion('buena_racha', _f(rng, 'buena_racha', {'n': n}), [
    Opcion('Seguí así, estamos contentos', 4, 2, -3, null, _resp(rng, 'contento')),
    Opcion('Está bien, pero quiero más', -3, 0, 5, null, _resp(rng, 'neutro')),
  ]);
}

Reunion reunionJuvenil(Tecnico t, Azar rng, Jugador jugador, bool enReserva) {
  final subir = Opcion('Subilo a Primera', 4, 1, 0, {'subir': jugador.completo},
      _resp(rng, 'contento'));
  return Reunion('juvenil', _f(rng, 'juvenil', {'jugador': jugador.corto}), [
    enReserva ? subir : Opcion('Dale, que juegue', 4, 1, 0, null, _resp(rng, 'contento')),
    Opcion('Todavía no, que espere', -3, 0, 0, null, _resp(rng, 'neutro')),
  ]);
}

Reunion reunionVenta(Tecnico t, Azar rng, String jugador, String pos, String? ventana) {
  return Reunion('venta', _f(rng, 'venta', {'jugador': jugador}), [
    Opcion('Era una oferta imposible de rechazar', -2, 0, 0, null, _resp(rng, 'neutro')),
    Opcion('Te traigo un reemplazo', 3, 0, 0, {'pos': pos, 'nivel': 0, 'ventana': ventana},
        _resp(rng, 'contento')),
    Opcion('Es mi club, decido yo', -8, -2, 0, null, _resp(rng, 'enojado')),
  ]);
}

Reunion reunionVence(Tecnico t, Azar rng, Jugador jugador) =>
    Reunion('vence', _f(rng, 'vence', {'jugador': jugador.corto}), [
      Opcion('Lo vamos a renovar', 3, 1, 0, null, _resp(rng, 'contento')),
      Opcion('Si quiere seguir, que baje el sueldo', -1, 0, 0, null, _resp(rng, 'neutro')),
      Opcion('Si se va, se va', -5, -2, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionNoUsa(Tecnico t, Azar rng, Jugador jugador, int partidos) =>
    Reunion('no_usa', _f(rng, 'no_usa', {'jugador': jugador.corto, 'n': partidos}), [
      Opcion('Lo pongo en venta', 3, 0, 0, null, _resp(rng, 'contento')),
      Opcion('Se queda, dale minutos', -3, 0, 0, null, _resp(rng, 'neutro')),
    ]);

Reunion reunionStaff(Tecnico t, Azar rng, String rol, String nombreRol, String ventana) =>
    Reunion('staff', _f(rng, 'staff', {'rol': nombreRol.toLowerCase()}), [
      Opcion('Lo contrato', 4, 1, 0,
          {'rol': rol, 'nivel': 2, 'ventana': ventana, 'nombre': nombreRol},
          _resp(rng, 'contento')),
      Opcion('No hay plata para eso', -3, 0, 0, null, _resp(rng, 'neutro')),
      Opcion('No hace falta', -6, 0, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionLoQuieren(Tecnico t, Azar rng, String club) =>
    Reunion('lo_quieren', _f(rng, 'lo_quieren', {'club': club}), [
      Opcion('Andá, te deseo suerte', 0, 0, 0, {'oferta': club, 'acepta': true},
          'Gracias por todo, presidente. Este club siempre va a ser mío.'),
      Opcion('Te subo el sueldo para que te quedes', 8, 2, 0, {'aumento': 1.25},
          'Me quedo, presidente. Vamos por más.'),
      Opcion('Tenés contrato, te quedás', -12, -2, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionEntrenamiento(Tecnico t, Azar rng) =>
    Reunion('entrenamiento', _f(rng, 'entrenamiento'), [
      Opcion('Tenés razón, decidí vos', 5, 1, 0, {'plan': null}, _resp(rng, 'contento')),
      Opcion('Se entrena como digo yo', -8, -1, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionFormacion(Tecnico t, Azar rng, String formacion, int derrotas) =>
    Reunion('formacion', _f(rng, 'formacion', {'formacion': formacion, 'n': derrotas}), [
      Opcion('Está bien, elegí vos', 5, 1, 0, {'formacion': null}, _resp(rng, 'contento')),
      Opcion('Se juega así', -12, -2, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionUltimatum(Tecnico t, Azar rng, String pos, int nivel, String ventana) =>
    Reunion('ultimatum', _f(rng, 'ultimatum'), [
      Opcion('Quedate, te traigo refuerzos', 10, 0, -3,
          {'pos': pos, 'nivel': nivel + 3, 'ventana': ventana}, _resp(rng, 'neutro')),
      Opcion('Te banco a muerte', 6, 0, -5, null, _resp(rng, 'contento')),
      Opcion('La puerta está abierta', -15, 0, 0, null, _resp(rng, 'enojado')),
    ]);

Reunion reunionGeneral(Tecnico t, Azar rng) {
  final bien = t.confianza >= 50 && t.presion < 60;
  return Reunion('general', _f(rng, bien ? 'general_bien' : 'general_mal'), [
    Opcion('Confío en vos', 3, 0, -2, null, _resp(rng, 'contento')),
    Opcion('Quiero resultados ya', -4, 0, 6, null, _resp(rng, 'enojado')),
  ]);
}

String quePrometio(Map<String, dynamic> promesa) => promesa.containsKey('rol')
    ? (promesa['nombre'] as String).toLowerCase()
    : puesto(promesa['pos']);

Reunion reunionPromesa(Tecnico t, Azar rng, Map<String, dynamic> promesa, bool cumplida,
    bool exacto) {
  if (cumplida) {
    cambiar(t, sat: exacto ? 21 : 15, conf: 4);
    var texto = _f(rng, 'promesa_cumplida', {'pos': quePrometio(promesa)});
    if (exacto) texto += ' ¡Y es ${promesa['jugador']}, el que le pedí!';
    return Reunion('promesa', texto, []);
  }
  cambiar(t, sat: -20, conf: -3);
  return Reunion('promesa', _f(rng, 'promesa_rota', {'pos': quePrometio(promesa)}), [
    Opcion('Tenés razón, perdón', 4, 0, 0, null, _resp(rng, 'neutro')),
    Opcion('No se pudo, hay que bancarse', -3, 0, 0, null, _resp(rng, 'enojado')),
  ]);
}

Reunion reunionRenovacion(Tecnico t, Azar rng, double sueldoNuevo) {
  if (t.satisfaccion < 40) return Reunion('no_renueva', _f(rng, 'no_renueva'), []);
  return Reunion('renovacion', _f(rng, 'renovacion'), [
    Opcion('Renovamos 2 años (US\$ ${(sueldoNuevo * 1000).round()}K/año)', 8, 0, 0,
        {'renovar': 2}, _resp(rng, 'contento')),
    Opcion('No, gracias por todo', 0, 0, 0, {'renovar': 0}, 'Lo entiendo. Suerte.'),
  ]);
}

Reunion reunionRenuncia(Tecnico t, Azar rng) => Reunion('renuncia', _f(rng, 'renuncia'), []);

/// Aplica la respuesta elegida. Devuelve (consecuencia o null, respuesta del DT).
(Map<String, dynamic>?, String) aplicar(Tecnico t, Opcion o) {
  cambiar(t, sat: o.sat, conf: o.conf, pres: o.pres);
  var extra = o.extra;
  if (extra != null && (extra.containsKey('pos') || extra.containsKey('rol'))) {
    t.promesas.add(Map.of(extra));
    extra = null;
  }
  return (extra, o.respuesta);
}

/// Una promesa de refuerzo se cumple si llegó alguien para ese puesto con
/// el nivel prometido; una de cuerpo técnico, si hay alguien de ese nivel.
/// fichajes: [posición, posición secundaria, nivel, nombre].
bool cumple(Map<String, dynamic> promesa, List<List<dynamic>> fichajes, Map<String, int> staff) {
  if (promesa.containsKey('rol')) return (staff[promesa['rol']] ?? 0) >= promesa['nivel'];
  for (final f in fichajes) {
    if ((promesa['pos'] == f[0] || promesa['pos'] == f[1]) && f[2] >= promesa['nivel']) {
      return true;
    }
  }
  return false;
}

/// Al cerrar una ventana: qué promesas se cumplieron. [(promesa, cumplida, exacto)].
List<(Map<String, dynamic>, bool, bool)> revisarPromesas(
    Tecnico t, String ventana, List<List<dynamic>> fichajes, Map<String, int> staff) {
  final resultado = <(Map<String, dynamic>, bool, bool)>[];
  final quedan = <Map<String, dynamic>>[];
  for (final pr in t.promesas) {
    if (pr['ventana'] != ventana) {
      quedan.add(pr);
      continue;
    }
    final ok = cumple(pr, fichajes, staff);
    final exacto = ok && fichajes.any((f) => f.length > 3 && f[3] == pr['jugador']);
    resultado.add((pr, ok, exacto));
  }
  t.promesas = quedan;
  return resultado;
}

// ---------------------------------------------------------------- historial
void llegaA(Tecnico t, String club, int temporada) => t.clubes.add([club, temporada, null]);

void seVaDe(Tecnico t, int temporada) {
  if (t.clubes.isNotEmpty && t.clubes.last[2] == null) t.clubes.last[2] = temporada;
}

void cambiarPrestigio(Tecnico t, num delta) =>
    t.prestigio = math.max(10, math.min(99, J.redondear(t.prestigio + delta.toDouble())));

List<String> curriculum(Tecnico t) {
  final lineas = [...t.logros.skip(math.max(0, t.logros.length - 6))];
  for (final c in t.clubes.skip(math.max(0, t.clubes.length - 5))) {
    lineas.add('${c[0]} (T${c[1]}–${c[2] != null ? 'T${c[2]}' : 'hoy'})');
  }
  if (t.despidos > 0) lineas.add('Lo echaron ${t.despidos} ${t.despidos > 1 ? 'veces' : 'vez'}');
  return lineas.isEmpty ? ['Sin historia en el fútbol argentino'] : lineas;
}

String resumenCv(Tecnico t) {
  final titulos = [for (final l in t.logros) if (l.startsWith('🏆') || l.startsWith('⬆')) l];
  if (titulos.isNotEmpty) return titulos.last;
  if (t.clubes.isNotEmpty) {
    return 'Dirigió ${t.clubes.length} club${t.clubes.length > 1 ? 'es' : ''}';
  }
  return 'Sin historia en el fútbol argentino';
}

void reiniciar(Tecnico t) {
  t.contrato = 2;
  t.satisfaccion = 65.0;
  t.confianza = 50.0;
  t.presion = 40.0;
  t.fechas = 0;
  t.promesas = [];
  t.avisos = [];
}
