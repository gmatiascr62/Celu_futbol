// Las posiciones y los goleadores de cada división.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/torneo.dart';
import 'estilo.dart';

class TabTabla extends StatefulWidget {
  const TabTabla({super.key});

  @override
  State<TabTabla> createState() => _TabTablaState();
}

class _TabTablaState extends State<TabTabla> {
  int? division;
  bool goleadores = false;

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final d = division ?? p.divisionAMostrar;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text('Posiciones', style: titulo)),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Tabla')),
              ButtonSegment(value: true, label: Text('Goleadores')),
            ],
            selected: {goleadores},
            onSelectionChanged: (s) => setState(() => goleadores = s.first),
          ),
        ]),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (var i = 0; i < p.divisiones.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(p.divisiones[i]),
                  selected: i == d,
                  onSelected: (_) => setState(() => division = i),
                ),
              ),
          ],
        ),
      ),
      Expanded(child: goleadores ? _goleadores(p, d) : _tabla(p, d)),
    ]);
  }

  Widget _tabla(Partida p, int d) {
    final filas = ordenarTabla(p.tablaDivision(d));
    final n = filas.length;
    const est = TextStyle(fontSize: 13, color: texto2, fontWeight: FontWeight.w600);
    Widget celda(String t, {double w = 30, TextStyle? s}) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: s));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            celda('#', w: 26, s: est),
            const SizedBox(width: 34),
            const Expanded(child: Text('Equipo', style: est)),
            celda('PJ', s: est),
            celda('DG', w: 36, s: est),
            celda('Pts', w: 38, s: est),
          ]),
        ),
        Card(
          child: Column(children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const Divider(height: 1),
              _fila(p, d, i, n, filas[i].key, filas[i].value, celda),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, children: [
          if (d > 0) _referencia(verde, 'Ascenso'),
          if (d < p.divisiones.length - 1) _referencia(rojo, 'Descenso'),
          if (d == 0) _referencia(amarillo, 'Campeón'),
        ]),
      ],
    );
  }

  Widget _referencia(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: chico),
      ]);

  Widget _fila(Partida p, int d, int i, int n, String club, Fila f,
      Widget Function(String, {double w, TextStyle? s}) celda) {
    final esMio = club == p.mio;
    Color? marca;
    if (i == 0) marca = amarillo;
    if (d > 0 && i < cambiosDeCategoria) marca = verde;
    if (d < p.divisiones.length - 1 && i >= n - cambiosDeCategoria) marca = rojo;
    final negrita = TextStyle(fontWeight: esMio ? FontWeight.w700 : FontWeight.w500, fontSize: 14);
    return Container(
      decoration: BoxDecoration(
        color: esMio ? verde.withValues(alpha: 0.12) : null,
        border: Border(left: BorderSide(color: marca ?? Colors.transparent, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(children: [
        celda('${i + 1}', w: 26, s: const TextStyle(fontWeight: FontWeight.w700)),
        Escudo(club, tam: 24),
        const SizedBox(width: 10),
        Expanded(child: Text(club, overflow: TextOverflow.ellipsis, style: negrita)),
        celda('${f.pj}', s: const TextStyle(color: texto2)),
        celda(f.dg > 0 ? '+${f.dg}' : '${f.dg}', w: 36, s: const TextStyle(color: texto2)),
        celda('${f.pts}',
            w: 38,
            s: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 18)),
      ]),
    );
  }

  Widget _goleadores(Partida p, int d) {
    final lista = p.goleadoresDivision(d).take(20).toList();
    if (lista.isEmpty) return const Center(child: Text('Todavía no hay goles.', style: chico));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        Card(
          child: Column(children: [
            for (var i = 0; i < lista.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                dense: true,
                leading: SizedBox(
                    width: 24,
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
                title: Text(lista[i].$1,
                    style: TextStyle(
                        fontWeight: lista[i].$2 == p.mio ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15)),
                subtitle: Row(children: [
                  Escudo(lista[i].$2, tam: 14),
                  const SizedBox(width: 6),
                  Text(lista[i].$2, style: chico),
                ]),
                trailing: Text('${lista[i].$3}',
                    style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 22)),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
