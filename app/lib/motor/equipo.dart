import 'jugadores.dart';

/// Alguien del cuerpo técnico (ver club.dart).
class Miembro {
  String nombre;
  int nivel;
  double sueldo;
  Miembro(this.nombre, this.nivel, this.sueldo);

  Map<String, dynamic> toJson() => {'nombre': nombre, 'nivel': nivel, 'sueldo': sueldo};
  factory Miembro.fromJson(Map<String, dynamic> d) =>
      Miembro(d['nombre'], d['nivel'], (d['sueldo'] as num).toDouble());
}

/// Una instalación en obra y las fechas que le faltan.
class Obra {
  String tipo;
  int faltan;
  Obra(this.tipo, this.faltan);
}

class Equipo {
  String nombre;
  double ataque; // escala del modelo (log): 0 = promedio de la liga
  double defensa; // escala del modelo (log): negativo = recibe menos
  String tactica = 'equilibrada';
  String tacticaInicial = 'equilibrada';
  String? dt = 'equilibrado'; // personalidad; null = sin DT, táctica fija
  double energia = 1.0; // promedio de los 10 de campo
  List<Jugador> plantel = [];
  String formacion = formacionBase;
  double caja = 0.0; // millones de dólares
  double ingreso = 0.0; // ingreso anual, millones de dólares
  double moral = 1.0; // multiplica los goles: la confianza del DT
  Map<String, int> instalaciones = {};
  Map<String, Miembro> staff = {};
  List<Obra> obras = [];
  double hinchada = 60.0; // humor de la hinchada, de 0 a 100
  String? formacionForzada; // la formación que le pediste al DT
  List<Jugador> reserva = []; // pibes de las inferiores

  Equipo(this.nombre, this.ataque, this.defensa);

  int nivelStaff(String rol) => staff[rol]?.nivel ?? 0;

  Map<String, dynamic> toJson() => {
        'nombre': nombre, 'ataque': ataque, 'defensa': defensa, 'tactica': tactica,
        'tactica_inicial': tacticaInicial, 'dt': dt, 'formacion': formacion, 'caja': caja,
        'ingreso': ingreso, 'moral': moral, 'instalaciones': instalaciones,
        'staff': {for (final e in staff.entries) e.key: e.value.toJson()},
        'obras': [for (final o in obras) [o.tipo, o.faltan]],
        'hinchada': hinchada, 'formacion_forzada': formacionForzada,
        'plantel': [for (final j in plantel) j.toJson()],
        'reserva': [for (final j in reserva) j.toJson()],
      };

  factory Equipo.fromJson(Map<String, dynamic> d) {
    final e = Equipo(d['nombre'], (d['ataque'] as num).toDouble(),
        (d['defensa'] as num).toDouble());
    e.tactica = d['tactica'];
    e.tacticaInicial = d['tactica_inicial'];
    e.dt = d['dt'];
    e.formacion = d['formacion'];
    e.caja = (d['caja'] as num).toDouble();
    e.ingreso = (d['ingreso'] as num).toDouble();
    e.moral = (d['moral'] as num).toDouble();
    e.instalaciones = Map<String, int>.from(d['instalaciones']);
    e.staff = {
      for (final x in (d['staff'] as Map).entries)
        x.key as String: Miembro.fromJson(Map<String, dynamic>.from(x.value))
    };
    e.obras = [for (final o in d['obras']) Obra(o[0], o[1])];
    e.hinchada = (d['hinchada'] as num).toDouble();
    e.formacionForzada = d['formacion_forzada'];
    e.plantel = [for (final j in d['plantel']) Jugador.fromJson(Map<String, dynamic>.from(j))];
    e.reserva = [for (final j in d['reserva']) Jugador.fromJson(Map<String, dynamic>.from(j))];
    return e;
  }
}
