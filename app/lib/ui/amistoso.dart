// Partido amistoso entre dos clubes cualquiera, con el DT que quieras, y
// la prueba de muchos partidos seguidos.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/datos.dart';
import '../motor/equipo.dart';
import '../motor/jugadores.dart' as J;
import '../motor/partido.dart';
import '../motor/torneo.dart';
import 'estilo.dart';
import 'pantalla_partido.dart';

class Amistoso extends StatefulWidget {
  const Amistoso({super.key});

  @override
  State<Amistoso> createState() => _AmistosoState();
}

class _AmistosoState extends State<Amistoso> {
  String local = 'Boca Juniors';
  String visitante = 'River Plate';
  String dtLocal = 'equilibrado';
  String dtVisitante = 'equilibrado';
  bool ocupado = false;

  Equipo _equipo(String club, String dt) {
    final (a, d) = juego.modelo.equipos[club]!;
    return Equipo(club, a, d)
      ..plantel = J.copiarPlantel(planteles[club]!)
      ..dt = dt
      ..formacion = formacionPreferida(club, dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partido amistoso')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _lado('Local', local, dtLocal, (c) => setState(() => local = c), (d) => setState(() => dtLocal = d)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: Text('VS', style: TextStyle(fontFamily: 'Barlow', fontSize: 24, color: texto2))),
          ),
          _lado('Visitante', visitante, dtVisitante, (c) => setState(() => visitante = c),
              (d) => setState(() => dtVisitante = d)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: ocupado || local == visitante ? null : _jugar,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(local == visitante ? 'Elegí dos clubes distintos' : 'Jugar'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: ocupado || local == visitante ? null : _muchos,
            icon: ocupado
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bar_chart_rounded),
            label: const Text('Simular 500 partidos'),
          ),
        ],
      ),
    );
  }

  Widget _lado(String etiqueta, String club, String dt, ValueChanged<String> club2, ValueChanged<String> dt2) {
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiqueta.toUpperCase(), style: tituloChico),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final c = await elegirClub(context);
            if (c != null) club2(c);
          },
          child: Row(children: [
            Escudo(club, tam: 44),
            const SizedBox(width: 14),
            Expanded(child: Text(club, style: titulo)),
            const Icon(Icons.edit_rounded, color: texto2),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final p in personalidades.keys)
            ChoiceChip(label: Text(p), selected: dt == p, onSelected: (_) => dt2(p)),
        ]),
      ]),
    );
  }

  Future<void> _jugar() async {
    final l = _equipo(local, dtLocal), v = _equipo(visitante, dtVisitante);
    final r = simularPartido(l, v, juego.modelo, relato: true);
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PantallaPartido(partido: MiPartido(local, visitante, r), titulo: 'Amistoso')),
    );
  }

  Future<void> _muchos() async {
    setState(() => ocupado = true);
    var gl = 0, gv = 0, goles = 0;
    final marcadores = <String, int>{};
    const n = 500;
    for (var i = 0; i < n; i++) {
      if (i % 25 == 0) await Future<void>.delayed(const Duration(milliseconds: 1));
      final l = _equipo(local, dtLocal), v = _equipo(visitante, dtVisitante);
      final r = simularPartido(l, v, juego.modelo, semilla: 'amistoso|$i');
      if (r.gl > r.gv) gl++;
      if (r.gv > r.gl) gv++;
      goles += r.gl + r.gv;
      marcadores['${r.gl}-${r.gv}'] = (marcadores['${r.gl}-${r.gv}'] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() => ocupado = false);
    final comunes = marcadores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    String pc(int x) => '${(100 * x / n).toStringAsFixed(1)}%';
    await mostrarTextos(context, '$n partidos', [
      '$local: ${pc(gl)}',
      'Empate: ${pc(n - gl - gv)}',
      '$visitante: ${pc(gv)}',
      'Goles por partido: ${(goles / n).toStringAsFixed(2)}',
      'Más comunes: ${comunes.take(4).map((e) => '${e.key} (${pc(e.value)})').join(', ')}',
    ]);
  }
}

/// Elegir un club de cualquier división.
Future<String?> elegirClub(BuildContext context) {
  final m = juego.modelo;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (c, scroll) => ListView(
        controller: scroll,
        children: [
          for (var d = 0; d < m.divisiones.length; d++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(m.divisiones[d].toUpperCase(), style: tituloChico),
            ),
            for (final club in [for (final c in m.division.keys) if (m.division[c] == d) c]..sort())
              ListTile(
                leading: Escudo(club, tam: 30),
                title: Text(club),
                onTap: () => Navigator.pop(c, club),
              ),
          ],
        ],
      ),
    ),
  );
}
