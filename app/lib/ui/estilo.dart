// Colores, letras y piezas que se repiten en todas las pantallas.
import 'package:flutter/material.dart';

import '../motor/jugadores.dart' as J;
import '../motor/jugadores.dart' show Jugador;

const verde = Color(0xFF1DB954);
const verdeOscuro = Color(0xFF0B3D2E);
const fondo = Color(0xFF0E1512);
const superficie = Color(0xFF17211C);
const superficie2 = Color(0xFF1F2B25);
const borde = Color(0xFF2B3A32);
const texto2 = Color(0xFF9DB0A5);
const amarillo = Color(0xFFF5C518);
const rojo = Color(0xFFE5484D);
const celeste = Color(0xFF4CC2FF);

ThemeData tema() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: verde,
      brightness: Brightness.dark,
      primary: verde,
      surface: superficie,
    ),
    scaffoldBackgroundColor: fondo,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: fondo,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle:
          TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: superficie,
      indicatorColor: verde.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    cardTheme: CardThemeData(
      color: superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: borde)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: verde,
        foregroundColor: Colors.black,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 46),
        side: const BorderSide(color: borde),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: borde, space: 1, thickness: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: superficie,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

const titulo = TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 22);
const tituloChico = TextStyle(
    fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.8, color: texto2);
const chico = TextStyle(fontSize: 13, color: texto2);

// ---------------------------------------------------------------- clubes
/// Colores de cada club (camiseta principal y secundaria).
const _colores = {
  'Boca Juniors': (Color(0xFF103F8F), Color(0xFFF5C518)),
  'River Plate': (Color(0xFFF2F2F2), Color(0xFFD7262B)),
  'Racing Club': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'Independiente': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'San Lorenzo': (Color(0xFF1B2A6B), Color(0xFFD01F2E)),
  'Huracan': (Color(0xFFF2F2F2), Color(0xFFD01F2E)),
  'Velez Sarsfield': (Color(0xFFF2F2F2), Color(0xFF1B4FA0)),
  'Estudiantes L.P.': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Gimnasia L.P.': (Color(0xFFF2F2F2), Color(0xFF1B2A6B)),
  'Rosario Central': (Color(0xFF1B4FA0), Color(0xFFF5C518)),
  'Newells Old Boys': (Color(0xFFD01F2E), Color(0xFF141414)),
  'Lanus': (Color(0xFF7A1E2E), Color(0xFFF2F2F2)),
  'Banfield': (Color(0xFF1E7A3C), Color(0xFFF2F2F2)),
  'Argentinos Jrs': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Talleres Cordoba': (Color(0xFF1B2A6B), Color(0xFFF2F2F2)),
  'Belgrano': (Color(0xFF6CC4F0), Color(0xFF1B2A6B)),
  'Instituto': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Union de Santa Fe': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Colon de Santa Fe': (Color(0xFFD01F2E), Color(0xFF141414)),
  'Tigre': (Color(0xFF1B2A6B), Color(0xFFD01F2E)),
  'Defensa y Justicia': (Color(0xFFF5C518), Color(0xFF1E7A3C)),
  'Barracas Central': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Ind. Rivadavia': (Color(0xFF1B2A6B), Color(0xFFF2F2F2)),
  'Godoy Cruz': (Color(0xFF1B2A6B), Color(0xFFF2F2F2)),
  'Platense': (Color(0xFF6B4226), Color(0xFFF2F2F2)),
  'Atl. Tucuman': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'San Martin Tucuman': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Aldosivi': (Color(0xFF1E7A3C), Color(0xFFF5C518)),
  'Sarmiento Junin': (Color(0xFF1E7A3C), Color(0xFFF2F2F2)),
  'Central Cordoba': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Dep. Riestra': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Estudiantes Rio Cuarto': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Gimnasia Mendoza': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'San Martin S.J.': (Color(0xFF1E7A3C), Color(0xFF141414)),
  'Quilmes': (Color(0xFFF2F2F2), Color(0xFF1B2A6B)),
  'Chacarita': (Color(0xFF141414), Color(0xFFD01F2E)),
  'Ferro': (Color(0xFF1E7A3C), Color(0xFFF2F2F2)),
  'Nueva Chicago': (Color(0xFF1E7A3C), Color(0xFF141414)),
  'All Boys': (Color(0xFFF2F2F2), Color(0xFF141414)),
  'Atlanta': (Color(0xFF1B4FA0), Color(0xFFF5C518)),
  'Gimnasia Jujuy': (Color(0xFF1B4FA0), Color(0xFFF2F2F2)),
  'Patronato': (Color(0xFFD01F2E), Color(0xFF141414)),
  'Temperley': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'Almirante Brown': (Color(0xFFF5C518), Color(0xFF141414)),
  'Arsenal Sarandi': (Color(0xFF6CC4F0), Color(0xFFD01F2E)),
  'Atl. Rafaela': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'Agropecuario': (Color(0xFF1E7A3C), Color(0xFFF2F2F2)),
  'Dep. Moron': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Dep. Maipu': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Dep. Madryn': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Racing Cordoba': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'Los Andes': (Color(0xFFD01F2E), Color(0xFFF2F2F2)),
  'Brown Adrogue': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
  'Almagro': (Color(0xFF1B2A6B), Color(0xFFF2F2F2)),
  'Chaco For Ever': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Def. de Belgrano': (Color(0xFFD01F2E), Color(0xFF141414)),
  'Tristan Suarez': (Color(0xFF6CC4F0), Color(0xFF1B2A6B)),
  'Estudiantes BA': (Color(0xFF141414), Color(0xFFF2F2F2)),
  'Mitre SdE': (Color(0xFFF5C518), Color(0xFF141414)),
  'San Telmo': (Color(0xFF6CC4F0), Color(0xFFF2F2F2)),
};

(Color, Color) coloresDe(String club) {
  final c = _colores[club];
  if (c != null) return c;
  final h = club.codeUnits.fold(7, (a, b) => (a * 31 + b) & 0xffffff);
  return (HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.45).toColor(), Colors.white);
}

String sigla(String club) {
  const fijas = {
    'Boca Juniors': 'CABJ',
    'River Plate': 'CARP',
    'Racing Club': 'RAC',
    'Independiente': 'CAI',
    'San Lorenzo': 'CASLA',
    'Velez Sarsfield': 'VEL',
    'Estudiantes L.P.': 'EDLP',
    'Gimnasia L.P.': 'GELP',
    'Newells Old Boys': 'NOB',
    'Rosario Central': 'CARC',
  };
  if (fijas.containsKey(club)) return fijas[club]!;
  final palabras = club.replaceAll('.', ' ').split(' ').where((p) => p.isNotEmpty).toList();
  if (palabras.length == 1) return palabras[0].substring(0, 3).toUpperCase();
  return palabras.take(3).map((p) => p[0]).join().toUpperCase();
}

/// Un escudo simple con los colores del club.
class Escudo extends StatelessWidget {
  final String club;
  final double tam;
  const Escudo(this.club, {super.key, this.tam = 36});

  @override
  Widget build(BuildContext context) {
    final (c1, c2) = coloresDe(club);
    final s = sigla(club);
    return SizedBox(
      width: tam,
      height: tam * 1.12,
      child: CustomPaint(
        painter: _PintaEscudo(c1, c2),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: tam * 0.12),
            child: Text(
              s,
              style: TextStyle(
                fontFamily: 'Barlow',
                fontWeight: FontWeight.w700,
                fontSize: tam * (s.length > 3 ? 0.27 : 0.33),
                color: c1.computeLuminance() > 0.5 ? const Color(0xFF141414) : Colors.white,
                shadows: const [Shadow(blurRadius: 2, color: Colors.black26)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintaEscudo extends CustomPainter {
  final Color c1, c2;
  _PintaEscudo(this.c1, this.c2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.06)
      ..quadraticBezierTo(w * 0.5, -h * 0.02, w * 0.92, h * 0.06)
      ..lineTo(w * 0.92, h * 0.5)
      ..quadraticBezierTo(w * 0.9, h * 0.82, w * 0.5, h * 0.98)
      ..quadraticBezierTo(w * 0.1, h * 0.82, w * 0.08, h * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = c1);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.70, w, h * 0.12), Paint()..color = c2);
    canvas.restore();
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.06
          ..color = c2);
  }

  @override
  bool shouldRepaint(covariant _PintaEscudo old) => old.c1 != c1 || old.c2 != c2;
}

// ---------------------------------------------------------------- piezas
Color colorNivel(int n) => n >= 80
    ? const Color(0xFF2ECC71)
    : n >= 70
        ? const Color(0xFF9BE15D)
        : n >= 60
            ? amarillo
            : n >= 50
                ? const Color(0xFFF39C12)
                : rojo;

/// El nivel de un jugador en un cuadradito de color.
class Nivel extends StatelessWidget {
  final int n;
  final double tam;
  const Nivel(this.n, {super.key, this.tam = 34});

  @override
  Widget build(BuildContext context) => Container(
        width: tam,
        height: tam,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorNivel(n).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(tam * 0.3),
          border: Border.all(color: colorNivel(n).withValues(alpha: 0.7)),
        ),
        child: Text('$n',
            style: TextStyle(
                fontFamily: 'Barlow',
                fontWeight: FontWeight.w700,
                fontSize: tam * 0.5,
                color: colorNivel(n))),
      );
}

Color colorPos(String pos) => switch (J.linea[pos]) {
      0 => const Color(0xFFF5A623),
      1 => const Color(0xFF4CC2FF),
      2 => const Color(0xFF2ECC71),
      _ => const Color(0xFFE5484D),
    };

class Posicion extends StatelessWidget {
  final String pos;
  const Posicion(this.pos, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        padding: const EdgeInsets.symmetric(vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: colorPos(pos).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
        child: Text(pos,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: colorPos(pos), letterSpacing: 0.5)),
      );
}

/// Barra de 0 a 1 con color.
class Barra extends StatelessWidget {
  final double valor;
  final Color? color;
  final double alto;
  const Barra(this.valor, {super.key, this.color, this.alto = 6});

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (valor >= 0.75
            ? verde
            : valor >= 0.5
                ? amarillo
                : rojo);
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: LinearProgressIndicator(
        value: valor.clamp(0, 1).toDouble(),
        minHeight: alto,
        backgroundColor: Colors.white10,
        valueColor: AlwaysStoppedAnimation(c),
      ),
    );
  }
}

/// Barra con nombre y número (para el ánimo del DT y cosas así).
class BarraConNombre extends StatelessWidget {
  final String nombre;
  final double valor; // 0 a 100
  final bool alReves; // true: alto es malo (la presión)
  const BarraConNombre(this.nombre, this.valor, {super.key, this.alReves = false});

  @override
  Widget build(BuildContext context) {
    final v = alReves ? 1 - valor / 100 : valor / 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 100, child: Text(nombre, style: chico)),
        Expanded(
            child: Barra(valor / 100,
                alto: 8,
                color: v >= 0.6
                    ? verde
                    : v >= 0.35
                        ? amarillo
                        : rojo)),
        SizedBox(
            width: 36,
            child: Text('${valor.round()}',
                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class Estrellas extends StatelessWidget {
  final int n;
  final double tam;
  const Estrellas(this.n, {super.key, this.tam = 14});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 5; i++)
          Icon(i < n ? Icons.star_rounded : Icons.star_outline_rounded,
              size: tam, color: i < n ? amarillo : Colors.white24),
      ]);
}

/// Encabezado de una sección.
class Seccion extends StatelessWidget {
  final String texto;
  final Widget? accion;
  const Seccion(this.texto, {super.key, this.accion});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Expanded(child: Text(texto.toUpperCase(), style: tituloChico)),
          if (accion != null) accion!,
        ]),
      );
}

/// Tarjeta con relleno.
class Tarjeta extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const Tarjeta(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class Dato extends StatelessWidget {
  final String valor, nombre;
  final Color? color;
  const Dato(this.valor, this.nombre, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(valor,
            style: TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 24, color: color)),
        Text(nombre, style: chico),
      ]);
}

/// Una fila de jugador para las listas.
class FilaJugador extends StatelessWidget {
  final Jugador j;
  final String? detalle;
  final Widget? derecha;
  final VoidCallback? onTap;
  const FilaJugador(this.j, {super.key, this.detalle, this.derecha, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Posicion(j.pos),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                      child: Text(j.corto,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                  if (j.lesion > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.healing_rounded, size: 15, color: rojo),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(detalle ?? '${j.edad} años · Pot ${j.potencial}',
                    style: chico, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (derecha != null) ...[derecha!, const SizedBox(width: 10)],
            Nivel(J.nivel(j)),
          ]),
        ),
      ),
    );
  }
}

void avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Pregunta sí o no. Devuelve true si confirma.
Future<bool> confirmar(BuildContext context, String titulo, String texto,
    {String si = 'Sí', String no = 'Cancelar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo, style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(si)),
      ],
    ),
  );
  return r ?? false;
}

/// Muestra textos (lo que pasó) en una ventanita.
Future<void> mostrarTextos(BuildContext context, String titulo, List<String> textos) async {
  if (textos.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo, style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in textos) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t)),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Seguir'))],
    ),
  );
}
