// Tu plantel y la reserva, y la ficha de cada jugador.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/club.dart' as C;
import '../motor/jugadores.dart' as J;
import '../motor/jugadores.dart' show Jugador;
import '../motor/mercado.dart' as M;
import '../motor/torneo.dart';
import 'estilo.dart';
import 'mercado.dart';

class TabPlantel extends StatefulWidget {
  const TabPlantel({super.key});

  @override
  State<TabPlantel> createState() => _TabPlantelState();
}

class _TabPlantelState extends State<TabPlantel> {
  bool reserva = false;

  static const grupos = [
    ('Arqueros', [0]),
    ('Defensores', [1]),
    ('Mediocampistas', [2]),
    ('Delanteros', [3]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final mi = p.mi;
    final tits = M.titulares(mi);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Expanded(child: Text('Plantel', style: titulo)),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text('Primera (${mi.plantel.length})')),
              ButtonSegment(value: true, label: Text('Reserva (${mi.reserva.length})')),
            ],
            selected: {reserva},
            onSelectionChanged: (s) => setState(() => reserva = s.first),
          ),
        ]),
      ),
      Expanded(child: reserva ? _reserva(p) : _primera(p, tits)),
    ]);
  }

  Widget _primera(Partida p, Set<Jugador> tits) {
    final mi = p.mi;
    final masa = M.masaSalarial(mi.plantel);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
              'Juega con ${mi.formacionForzada ?? mi.formacion} · Sueldos ${M.plata(masa)}/año · '
              '★ titular',
              style: chico),
        ),
        for (final (nombre, lineas) in grupos) ...[
          Seccion(nombre),
          Card(
            child: Column(children: [
              for (final j in (mi.plantel.where((j) => lineas.contains(J.linea[j.pos])).toList()
                ..sort(J.ordenPlantel)))
                FilaJugador(
                  j,
                  detalle: '${j.edad} años · Pot ${j.potencial} · '
                      '${j.contrato <= 0 ? 'sin contrato' : '${j.contrato} año${j.contrato > 1 ? 's' : ''}'}'
                      '${j.lesion > 0 ? ' · lesionado ${j.lesion}f' : ''}',
                  derecha: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (tits.contains(j)) const Icon(Icons.star_rounded, size: 16, color: amarillo),
                    const SizedBox(width: 6),
                    SizedBox(width: 34, child: Barra(j.fisico)),
                  ]),
                  onTap: () => fichaJugador(context, j).then((_) => setState(() {})),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _reserva(Partida p) {
    final mi = p.mi;
    final pibes = List.of(mi.reserva)
      ..sort((a, b) {
        final c = (b.potEst > 0 ? b.potEst : b.potencial).compareTo(a.potEst > 0 ? a.potEst : a.potencial);
        return c != 0 ? c : J.nivel(b).compareTo(J.nivel(a));
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        Tarjeta(
          child: Row(children: [
            const Icon(Icons.child_care_rounded, color: texto2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Los pibes de las inferiores entrenan acá. A los ${C.edadLimite} suben a Primera o '
                'se van. Las estrellas son el potencial que estima el club: con mejor coordinador '
                'de inferiores, se equivoca menos.',
                style: chico,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (pibes.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No hay pibes en la reserva.', style: chico)),
        Card(
          child: Column(children: [
            for (final j in pibes)
              FilaJugador(
                j,
                detalle: '${j.edad} años',
                derecha: Estrellas(C.estrellasPot(j)),
                onTap: () => fichaJugador(context, j).then((_) => setState(() {})),
              ),
          ]),
        ),
      ],
    );
  }
}

/// La ficha de un jugador de tu club, con lo que se puede hacer con él.
Future<void> fichaJugador(BuildContext context, Jugador j) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _Ficha(j),
  );
}

class _Ficha extends StatefulWidget {
  final Jugador j;
  const _Ficha(this.j);

  @override
  State<_Ficha> createState() => _FichaState();
}

class _FichaState extends State<_Ficha> {
  @override
  Widget build(BuildContext context) {
    final j = widget.j;
    final p = juego.partida!;
    final mi = p.mi;
    final enReserva = mi.reserva.contains(j);
    final abierto = ventanaActual(p) != null;
    final arquero = j.pos == 'ARQ';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(children: [
            Nivel(J.nivel(j), tam: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(j.completo, style: titulo),
                Text('${J.nombrePos[j.pos]}${j.pos2 != null ? ' · también ${j.pos2}' : ''}', style: chico),
                Text('${j.edad} años', style: chico),
              ]),
            ),
            Column(children: [
              if (enReserva) Estrellas(C.estrellasPot(j), tam: 16) else Dato('${j.potencial}', 'Potencial'),
            ]),
          ]),
          const SizedBox(height: 16),
          _atributo('Ataque', j.ataque),
          _atributo('Creación', j.creacion),
          _atributo(arquero ? 'Atajada' : 'Defensa', arquero ? j.atajada : j.defensa),
          _atributo('Resistencia', j.resistencia),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 100, child: Text('Físico', style: chico)),
            Expanded(child: Barra(j.fisico, alto: 8)),
            SizedBox(width: 44, child: Text('${(j.fisico * 100).round()}%', textAlign: TextAlign.right)),
          ]),
          const SizedBox(height: 16),
          Tarjeta(
            color: superficie2,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Dato(M.plata(M.valor(j)), 'Valor'),
              if (!enReserva) Dato(M.plata(M.sueldo(j)), 'Sueldo/año'),
              if (!enReserva) Dato(j.contrato <= 0 ? '-' : '${j.contrato}', 'Años contrato'),
              if (!enReserva) Dato('${j.partidos}', 'Partidos'),
            ]),
          ),
          if (j.lesion > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('🚑 Lesionado: ${j.lesion} fecha${j.lesion > 1 ? 's' : ''} afuera',
                  style: const TextStyle(color: rojo)),
            ),
          const SizedBox(height: 18),
          if (enReserva) ..._accionesReserva(j, abierto) else ..._accionesPlantel(j, abierto),
        ],
      ),
    );
  }

  Widget _atributo(String nombre, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 100, child: Text(nombre, style: chico)),
          Expanded(child: Barra(v / 99, alto: 8, color: colorNivel(v.round()))),
          SizedBox(
              width: 44,
              child: Text('${v.round()}',
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  List<Widget> _accionesPlantel(Jugador j, bool abierto) {
    if (!abierto) {
      return [
        const Text('El mercado está cerrado: abre en la pretemporada y a mitad del torneo. '
            'Ahí podés venderlo, renovarle o liberarlo.', style: chico),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: () async {
          await venderDialogo(context, j);
          if (mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.sell_rounded),
        label: const Text('Ponerlo en venta'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              await renovarDialogo(context, j);
              if (mounted) setState(() {});
            },
            child: const Text('Renovar'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              if (await liberarDialogo(context, j) && mounted) Navigator.pop(context);
            },
            child: const Text('Liberar'),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _accionesReserva(Jugador j, bool abierto) {
    final p = juego.partida!;
    final mi = p.mi;
    return [
      FilledButton.icon(
        onPressed: mi.plantel.length >= M.plantelMax
            ? null
            : () async {
                C.subir(mi, j);
                await juego.guardar();
                if (!mounted) return;
                avisar(context, '⬆ ${j.corto} sube a Primera con contrato por 3 temporadas.');
                Navigator.pop(context);
              },
        icon: const Icon(Icons.arrow_upward_rounded),
        label: Text(mi.plantel.length >= M.plantelMax
            ? 'Plantel lleno (${M.plantelMax})'
            : 'Subir a Primera'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: !abierto
                ? null
                : () async {
                    await ofrecerPibeDialogo(context, j);
                    if (mounted && !mi.reserva.contains(j)) Navigator.pop(context);
                  },
            child: const Text('Ofrecerlo afuera'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              if (!await confirmar(context, '¿Dejarlo ir?', '${j.corto} deja el club.', si: 'Dejarlo ir')) {
                return;
              }
              mi.reserva.remove(j);
              await juego.guardar();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Dejarlo ir'),
          ),
        ),
      ]),
      if (!abierto)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Para ofrecerlo afuera tiene que estar abierto el mercado.', style: chico),
        ),
    ];
  }
}
