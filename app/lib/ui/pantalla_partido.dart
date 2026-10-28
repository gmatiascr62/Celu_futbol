// Tu partido, minuto a minuto: el marcador, el relato, las estadísticas y
// las formaciones.
import 'dart:async';

import 'package:flutter/material.dart';

import '../motor/jugadores.dart' as J;
import '../motor/partido.dart';
import '../motor/torneo.dart';
import 'estilo.dart';

class PantallaPartido extends StatefulWidget {
  final MiPartido partido;
  final String titulo;
  const PantallaPartido({super.key, required this.partido, this.titulo = ''});

  @override
  State<PantallaPartido> createState() => _PantallaPartidoState();
}

class _PantallaPartidoState extends State<PantallaPartido> with SingleTickerProviderStateMixin {
  int minuto = 0;
  int velocidad = 1;
  Timer? reloj;
  late final TabController tabs = TabController(length: 3, vsync: this);

  ResultadoPartido get r => widget.partido.r;
  bool get termino => minuto >= 90;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  void _arrancar() {
    reloj?.cancel();
    reloj = Timer.periodic(Duration(milliseconds: 220 ~/ velocidad), (_) {
      if (!mounted) return;
      setState(() => minuto++);
      if (termino) reloj?.cancel();
    });
  }

  @override
  void dispose() {
    reloj?.cancel();
    tabs.dispose();
    super.dispose();
  }

  List<Evento> get visibles => [for (final e in r.eventos) if (e.minuto <= minuto) e];

  (int, int) get marcador {
    final v = visibles;
    return v.isEmpty ? (0, 0) : (v.last.gl, v.last.gv);
  }

  @override
  Widget build(BuildContext context) {
    final (gl, gv) = marcador;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo.isEmpty ? 'Partido' : widget.titulo),
        automaticallyImplyLeading: false,
        actions: [
          if (!termino)
            TextButton.icon(
              onPressed: () {
                setState(() => velocidad = velocidad == 1 ? 4 : 1);
                _arrancar();
              },
              icon: Icon(velocidad == 1 ? Icons.fast_forward_rounded : Icons.play_arrow_rounded),
              label: Text(velocidad == 1 ? 'x4' : 'x1'),
            ),
          if (!termino)
            TextButton(
              onPressed: () {
                reloj?.cancel();
                setState(() => minuto = 90);
              },
              child: const Text('Final'),
            ),
        ],
      ),
      body: Column(children: [
        _marcador(gl, gv),
        TabBar(
          controller: tabs,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Relato'), Tab(text: 'Estadísticas'), Tab(text: 'Formaciones')],
        ),
        Expanded(
          child: TabBarView(controller: tabs, children: [
            _relato(),
            _estadisticas(),
            _formaciones(),
          ]),
        ),
        if (termino)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Seguir')),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _marcador(int gl, int gv) {
    final local = widget.partido.local, visitante = widget.partido.visitante;
    Widget equipo(String nombre) => Expanded(
          child: Column(children: [
            Escudo(nombre, tam: 54),
            const SizedBox(height: 8),
            Text(nombre,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [verdeOscuro, superficie], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: Border.all(color: borde),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          equipo(local),
          Column(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text('$gl - $gv',
                  key: ValueKey('$gl-$gv'),
                  style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 48)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: termino ? Colors.white12 : verde.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                termino ? 'FINAL' : minuto == 45 ? 'ENTRETIEMPO' : "$minuto'",
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: termino ? Colors.white : verde, fontSize: 13),
              ),
            ),
          ]),
          equipo(visitante),
        ]),
        const SizedBox(height: 12),
        Barra(minuto / 90, color: verde, alto: 4),
        if (termino) ...[
          const SizedBox(height: 10),
          _goleadores(),
        ],
      ]),
    );
  }

  Widget _goleadores() {
    String de(int lado) {
      final porJugador = <String, List<String>>{};
      for (final g in r.goles) {
        if (g.lado == lado) porJugador.putIfAbsent(g.autor.corto, () => []).add("${g.minuto}'");
      }
      return porJugador.entries.map((e) => '${e.key} ${e.value.join(' ')}').join('\n');
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(de(0), textAlign: TextAlign.center, style: chico)),
      const SizedBox(width: 60, child: Icon(Icons.sports_soccer_rounded, size: 14, color: texto2)),
      Expanded(child: Text(de(1), textAlign: TextAlign.center, style: chico)),
    ]);
  }

  static const _iconos = {
    'gol': (Icons.sports_soccer_rounded, verde),
    'atajada': (Icons.back_hand_rounded, celeste),
    'desviado': (Icons.call_missed_outgoing_rounded, texto2),
    'amarilla': (Icons.style_rounded, amarillo),
    'cambio': (Icons.swap_vert_rounded, Color(0xFF8BC34A)),
    'tactica': (Icons.psychology_rounded, Color(0xFFB39DDB)),
    'entretiempo': (Icons.timer_rounded, texto2),
  };

  Widget _relato() {
    final eventos = visibles.reversed.toList();
    if (eventos.isEmpty) {
      return const Center(child: Text('Arranca el partido...', style: chico));
    }
    final nombres = [widget.partido.local, widget.partido.visitante];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: eventos.length,
      itemBuilder: (context, i) {
        final e = eventos[i];
        final (icono, color) = _iconos[e.tipo]!;
        if (e.tipo == 'entretiempo') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(e.texto.toUpperCase(), style: tituloChico),
              ),
              const Expanded(child: Divider()),
            ]),
          );
        }
        final gol = e.tipo == 'gol';
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: gol ? verde.withValues(alpha: 0.16) : superficie,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gol ? verde.withValues(alpha: 0.5) : borde),
          ),
          child: Row(children: [
            SizedBox(
                width: 34,
                child: Text("${e.minuto}'",
                    style: const TextStyle(fontWeight: FontWeight.w700, color: texto2))),
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_sinMinuto(e.texto),
                    style: TextStyle(fontWeight: gol ? FontWeight.w700 : FontWeight.w500)),
                if (e.lado >= 0 && !gol)
                  Text(nombres[e.lado], style: const TextStyle(fontSize: 12, color: texto2)),
              ]),
            ),
            if (gol)
              Text('${e.gl}-${e.gv}',
                  style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 18)),
          ]),
        );
      },
    );
  }

  String _sinMinuto(String t) => t.replaceFirst(RegExp(r"^\d+(\+\d)?' "), '');

  Widget _estadisticas() {
    if (!termino) {
      return const Center(child: Text('Las estadísticas, al final del partido.', style: chico));
    }
    final l = r.stats[0], v = r.stats[1];
    final filas = [
      ('Posesión', '${r.posesion.round()}%', '${100 - r.posesion.round()}%', r.posesion, 100 - r.posesion),
      ('Tiros', '${r.gl + l.atajados + l.desviados}', '${r.gv + v.atajados + v.desviados}',
          (r.gl + l.atajados + l.desviados).toDouble(), (r.gv + v.atajados + v.desviados).toDouble()),
      ('Al arco', '${r.gl + l.atajados}', '${r.gv + v.atajados}', (r.gl + l.atajados).toDouble(),
          (r.gv + v.atajados).toDouble()),
      ('Atajadas', '${v.atajados}', '${l.atajados}', v.atajados.toDouble(), l.atajados.toDouble()),
      ('Amarillas', '${l.amarillas}', '${v.amarillas}', l.amarillas.toDouble(), v.amarillas.toDouble()),
      ('Cambios', '${l.sustituciones}', '${v.sustituciones}', l.sustituciones.toDouble(),
          v.sustituciones.toDouble()),
      ('Cambios tácticos', '${l.cambios}', '${v.cambios}', l.cambios.toDouble(), v.cambios.toDouble()),
      ('Energía final', '${(r.energia[0] * 100).round()}%', '${(r.energia[1] * 100).round()}%',
          r.energia[0], r.energia[1]),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (nombre, a, b, x, y) in filas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Row(children: [
                SizedBox(width: 48, child: Text(a, style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: Text(nombre, textAlign: TextAlign.center, style: chico)),
                SizedBox(
                    width: 48,
                    child: Text(b, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Barra(x + y == 0 ? 0 : x / (x + y), color: verde),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: Barra(x + y == 0 ? 0 : y / (x + y), color: celeste)),
              ]),
            ]),
          ),
      ],
    );
  }

  Widget _formaciones() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var k = 0; k < 2; k++) ...[
          Row(children: [
            Escudo(k == 0 ? widget.partido.local : widget.partido.visitante, tam: 24),
            const SizedBox(width: 8),
            Expanded(
                child: Text(k == 0 ? widget.partido.local : widget.partido.visitante,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${r.formacion[k]} · ${nombreTactica[r.tacticasIniciales[k]]}', style: chico),
          ]),
          const SizedBox(height: 8),
          Cancha(formacion: r.formacion[k], xi: r.titulares[k],
              color: coloresDe(k == 0 ? widget.partido.local : widget.partido.visitante).$1),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// Una cancha con los 11 ubicados según la formación.
class Cancha extends StatelessWidget {
  final String formacion;
  final List<J.Puesto> xi;
  final Color color;
  const Cancha({super.key, required this.formacion, required this.xi, required this.color});

  @override
  Widget build(BuildContext context) {
    final restantes = List.of(xi);
    J.Jugador? sacar(String slot) {
      final i = restantes.indexWhere((x) => x.$2 == slot);
      if (i < 0) return null;
      return restantes.removeAt(i).$1;
    }

    final lineas = [
      ['ARQ'],
      ...J.formaciones[formacion]!,
    ];
    final filas = [for (final l in lineas) [for (final s in l) (s, sacar(s))]];
    return AspectRatio(
      aspectRatio: 0.78,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E6B3A), Color(0xFF1A5E33)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomPaint(
          painter: _Lineas(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final fila in filas.reversed)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final (slot, j) in fila) _ficha(slot, j),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ficha(String slot, J.Jugador? j) {
    final claro = color.computeLuminance() > 0.5;
    return SizedBox(
      width: 66,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: slot == 'ARQ' ? amarillo : color,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text(j == null ? '' : '${J.nivel(j)}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: slot == 'ARQ' || claro ? Colors.black : Colors.white)),
        ),
        const SizedBox(height: 3),
        Text(j?.apellido ?? '?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, shadows: [
              Shadow(blurRadius: 3, color: Colors.black54),
            ])),
      ]),
    );
  }
}

class _Lineas extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = size.width, h = size.height;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(8, 8, w - 16, h - 16), const Radius.circular(10)), p);
    canvas.drawLine(Offset(8, h / 2), Offset(w - 8, h / 2), p);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.14, p);
    canvas.drawRect(Rect.fromLTWH(w * 0.25, h - 8 - h * 0.15, w * 0.5, h * 0.15), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.25, 8, w * 0.5, h * 0.15), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
