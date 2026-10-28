// El mercado de pases: comprar, fichar libres, las ofertas por tus
// jugadores, vender, liberar, renovar y lo que te pidió el DT.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/equipo.dart';
import '../motor/jugadores.dart' as J;
import '../motor/jugadores.dart' show Jugador;
import '../motor/mercado.dart' as M;
import '../motor/tecnicos.dart' as T;
import '../motor/torneo.dart';
import 'dialogos.dart';
import 'estilo.dart';
import 'plantel.dart';

class PantallaMercado extends StatefulWidget {
  const PantallaMercado({super.key});

  @override
  State<PantallaMercado> createState() => _PantallaMercadoState();
}

class _PantallaMercadoState extends State<PantallaMercado> {
  String? posBuscar;
  String? posLibres;
  bool alcanza = true; // solo los que el club puede pagar

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: juego,
      builder: (context, _) {
        final p = juego.partida!;
        final abierto = ventanaActual(p) != null;
        if (!abierto) {
          return Scaffold(
            appBar: AppBar(title: const Text('Mercado de pases')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Tarjeta(
                child: Text(
                    'El mercado está cerrado. Abre en la pretemporada y antes de la fecha '
                    '${p.totalFechas ~/ 2 + 1}.\nCaja: ${M.plata(p.mi.caja)}'),
              ),
              const Seccion('Últimos movimientos'),
              _movimientos(p),
            ]),
          );
        }
        final pedidos = pedidosDelDt(p);
        return DefaultTabController(
          length: pedidos.isEmpty ? 5 : 6,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Mercado de pases'),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: [
                  if (pedidos.isNotEmpty) Tab(text: 'Pedidos DT (${pedidos.length})'),
                  const Tab(text: 'Comprar'),
                  const Tab(text: 'Libres'),
                  Tab(text: 'Ofertas (${p.ofertas.length})'),
                  const Tab(text: 'Mi plantel'),
                  const Tab(text: 'Movimientos'),
                ],
              ),
            ),
            body: Column(children: [
              _resumen(p),
              Expanded(
                child: TabBarView(children: [
                  if (pedidos.isNotEmpty) _pedidos(p, pedidos),
                  _comprar(p),
                  _libres(p),
                  _ofertas(p),
                  _miPlantel(p),
                  ListView(padding: const EdgeInsets.all(12), children: [_movimientos(p)]),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _resumen(Partida p) {
    final mi = p.mi;
    final pend = promesasPendientes(p);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: superficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: borde)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Dato(M.plata(mi.caja), 'Caja', color: mi.caja < 0 ? rojo : null),
          Dato('${mi.plantel.length}', 'Jugadores'),
          Dato(M.plata(M.masaSalarial(mi.plantel)), 'Sueldos/año'),
          Dato(M.plata(mi.ingreso), 'Ingresos/año'),
        ]),
        for (final pr in pend)
          if (pr.containsKey('pos'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('📌 Le prometiste al DT: ${T.puesto(pr['pos'])}, nivel ${pr['nivel']} o más',
                  style: const TextStyle(color: amarillo, fontSize: 13)),
            ),
      ]),
    );
  }

  Widget _filtro(String? actual, ValueChanged<String?> cambiar) => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(label: const Text('Todos'), selected: actual == null, onSelected: (_) => cambiar(null)),
            ),
            for (final pos in J.posiciones)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(label: Text(pos), selected: actual == pos, onSelected: (_) => cambiar(pos)),
              ),
          ],
        ),
      );

  Widget _comprar(Partida p) {
    final lista = buscarJugadores(p, posBuscar, maximo: alcanza ? p.mi.caja : null);
    return Column(children: [
      _filtro(posBuscar, (v) => setState(() => posBuscar = v)),
      SwitchListTile(
        dense: true,
        title: const Text('Solo los que puedo pagar'),
        value: alcanza,
        onChanged: (v) => setState(() => alcanza = v),
      ),
      if (lista.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay jugadores que te alcance para pagar en ese puesto.', style: chico),
        ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const Divider(indent: 68),
          itemBuilder: (context, i) {
            final (j, e, precio) = lista[i];
            return FilaJugador(j,
                detalle: '${j.edad}a · ${e.nombre} · piden ${M.plata(precio)}',
                onTap: () => negociarCompra(context, j, e));
          },
        ),
      ),
    ]);
  }

  Widget _libres(Partida p) {
    final lista = [for (final j in p.libres) if (posLibres == null || j.pos == posLibres) j]
      ..sort((a, b) => J.nivel(b).compareTo(J.nivel(a)));
    return Column(children: [
      _filtro(posLibres, (v) => setState(() => posLibres = v)),
      Expanded(
        child: lista.isEmpty
            ? const Center(child: Text('No hay libres en ese puesto.', style: chico))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: lista.length > 30 ? 30 : lista.length,
                separatorBuilder: (_, __) => const Divider(indent: 68),
                itemBuilder: (context, i) {
                  final j = lista[i];
                  return FilaJugador(j,
                      detalle: '${j.edad}a · libre · pide ${M.plata(M.sueldoPedido(j))}/año',
                      onTap: () => negociarLibre(context, j));
                },
              ),
      ),
    ]);
  }

  Widget _ofertas(Partida p) {
    if (p.ofertas.isEmpty) {
      return const Center(child: Text('No hay ofertas por tus jugadores.', style: chico));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final o in List.of(p.ofertas))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tarjeta(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
              child: Column(children: [
                FilaJugador(o.j, detalle: '${o.j.edad}a · valor ${M.plata(M.valor(o.j))}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    Expanded(
                      child: Text('${o.club} ofrece ${M.plata(o.monto)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: () async {
                        p.ofertas.remove(o);
                        await juego.guardar();
                      },
                      child: const Text('Rechazar'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final textos = aceptarOferta(p, o);
                        await juego.guardar();
                        if (mounted) await mostrarTextos(context, 'Venta', textos);
                      },
                      child: const Text('Aceptar'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _miPlantel(Partida p) {
    final plantel = List.of(p.mi.plantel)..sort(J.ordenPlantel);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: plantel.length,
      separatorBuilder: (_, __) => const Divider(indent: 68),
      itemBuilder: (context, i) {
        final j = plantel[i];
        return FilaJugador(j,
            detalle: 'valor ${M.plata(M.valor(j))} · ${M.plata(M.sueldo(j))}/año · ${j.contrato}a',
            onTap: () => fichaJugador(context, j));
      },
    );
  }

  Widget _pedidos(Partida p, List<(Jugador, Equipo?)> pedidos) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Los jugadores que te pidió el DT. El primero es su preferido.', style: chico),
        ),
        Card(
          child: Column(children: [
            for (final (j, c) in pedidos)
              FilaJugador(j,
                  detalle: c != null
                      ? '${c.nombre} · piden ${M.plata(M.precioPedido(c, j))}'
                      : 'libre · pide ${M.plata(M.sueldoPedido(j))}/año',
                  onTap: () => irABuscar(context, j.completo)),
          ]),
        ),
      ],
    );
  }

  Widget _movimientos(Partida p) {
    if (p.movimientos.isEmpty) return const Text('Ninguno.', style: chico);
    return Card(
      child: Column(children: [
        for (final m in p.movimientos.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(m, style: const TextStyle(fontSize: 13))),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- negociaciones
/// Desde una reunión o desde los pedidos: negociar por un jugador.
Future<void> irABuscar(BuildContext context, String nombre) async {
  final p = juego.partida!;
  final (j, club) = buscarPorNombre(p, nombre);
  if (j == null || identical(club, p.mi)) {
    avisar(context, 'Ese jugador ya no está disponible.');
  } else if (club == null) {
    await negociarLibre(context, j);
  } else {
    await negociarCompra(context, j, club);
  }
}

/// Negociación con el club y después con el jugador.
Future<void> negociarCompra(BuildContext context, Jugador j, Equipo vendedor) async {
  final p = juego.partida!;
  final mi = p.mi;
  final problema = problemaCompra(p, j, vendedor);
  if (problema != null) {
    avisar(context, problema);
    return;
  }
  final pedido = M.precioPedido(vendedor, j);
  var oferta = pedido;
  final monto = await showDialog<double>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(j.completo, style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Posicion(j.pos),
            const SizedBox(width: 10),
            Text('${j.edad} años · Pot ${j.potencial}', style: chico),
            const Spacer(),
            Nivel(J.nivel(j)),
          ]),
          const SizedBox(height: 12),
          Text('Valor: ${M.plata(M.valor(j))} · Contrato: ${j.contrato} año${j.contrato > 1 ? 's' : ''}'),
          Text('${vendedor.nombre} pide ${M.plata(pedido)}.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Tu caja: ${M.plata(mi.caja)}', style: chico),
          const SizedBox(height: 16),
          Text('Tu oferta: ${M.plata(oferta)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Slider(
            value: oferta,
            min: pedido * 0.5,
            max: pedido * 1.2,
            divisions: 35,
            onChanged: (v) => setState(() => oferta = M.r3(v)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: oferta > mi.caja ? null : () => Navigator.pop(c, oferta),
            child: Text(oferta > mi.caja ? 'No te alcanza' : 'Ofertar'),
          ),
        ],
      ),
    ),
  );
  if (monto == null || !context.mounted) return;
  final (resp, cuanto) = M.respuesta(vendedor, j, monto);
  var acordado = monto;
  if (resp == 'rechaza') {
    await mostrarTextos(context, 'Rechazada', ['${vendedor.nombre} rechaza la oferta. Pide ${M.plata(cuanto)}.']);
    return;
  }
  if (resp == 'contraoferta') {
    final ok = await confirmar(context, 'Contraoferta', '${vendedor.nombre} quiere ${M.plata(cuanto)}. ¿Aceptás?',
        si: 'Aceptar', no: 'No');
    if (!ok || !context.mounted) return;
    if (cuanto > mi.caja) {
      avisar(context, 'No te alcanza: tenés ${M.plata(mi.caja)}.');
      return;
    }
    acordado = cuanto;
  }
  if (!context.mounted) return;
  avisar(context, '${vendedor.nombre} acepta. Falta arreglar con el jugador.');
  final (sueldoPide, anios) = pedidoDelJugador(p, j);
  final sueldo = await negociarSueldo(context, j, sueldoPide, anios, extraMasa: sueldoPide);
  if (!context.mounted) return;
  if (sueldo == null) {
    avisar(context, 'Se cayó el pase.');
    return;
  }
  final textos = concretarCompra(p, j, vendedor, acordado, sueldo, anios);
  await juego.guardar();
  if (context.mounted) await mostrarTextos(context, '¡Refuerzo!', textos);
}

Future<void> negociarLibre(BuildContext context, Jugador j) async {
  final p = juego.partida!;
  if (p.mi.plantel.length >= M.plantelMax) {
    avisar(context, 'Tenés ${M.plantelMax} jugadores: vendé o liberá a alguno antes.');
    return;
  }
  final (pide, anios) = pedidoDelJugador(p, j, libre: true);
  final sueldo = await negociarSueldo(context, j, pide, anios, extraMasa: pide);
  if (sueldo == null || !context.mounted) return;
  final textos = concretarLibre(p, j, sueldo, anios);
  await juego.guardar();
  if (context.mounted) await mostrarTextos(context, '¡Refuerzo!', textos);
}

/// Ponés a un jugador en venta y ves quiénes ofrecen.
Future<void> venderDialogo(BuildContext context, Jugador j) async {
  final p = juego.partida!;
  if (!M.puedeVender(p.mi, j)) {
    avisar(context, 'No podés venderlo: te quedás corto de plantel o sin nadie en el puesto.');
    return;
  }
  final ofertas = sondearVenta(p, j);
  await juego.guardar();
  if (!context.mounted) return;
  if (ofertas.isEmpty) {
    await mostrarTextos(context, 'Sin ofertas', ['Nadie ofertó por ${j.corto} en esta ventana.']);
    return;
  }
  final elegida = await showDialog<(String, double)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Ofertas por ${j.corto}', style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final o in ofertas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(o.$1),
            trailing: Text(M.plata(o.$2), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(c, o),
          ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Ninguna'))],
    ),
  );
  if (elegida == null || !context.mounted) return;
  final textos = venderJugador(p, j, elegida.$1, elegida.$2);
  await juego.guardar();
  if (context.mounted) await mostrarTextos(context, 'Venta', textos);
}

Future<bool> liberarDialogo(BuildContext context, Jugador j) async {
  final p = juego.partida!;
  if (!M.puedeVender(p.mi, j)) {
    avisar(context, 'No podés: te quedás corto de plantel o sin nadie en el puesto.');
    return false;
  }
  final ok = await confirmar(
      context,
      '¿Liberar a ${j.corto}?',
      'Cuesta ${M.plata(M.indemnizacion(j))} de indemnización '
          '(le quedan ${j.contrato} año${j.contrato > 1 ? 's' : ''}).',
      si: 'Liberar');
  if (!ok) return false;
  final texto = liberarJugador(p, j);
  await juego.guardar();
  if (context.mounted) avisar(context, texto);
  return true;
}

Future<void> renovarDialogo(BuildContext context, Jugador j) async {
  final p = juego.partida!;
  final (pide, anios) = pedidoRenovacion(p, j);
  final sueldo = await negociarSueldo(context, j, pide, anios, extraMasa: pide - M.sueldo(j));
  if (sueldo == null) return;
  M.firmar(j, sueldo, anios);
  await juego.guardar();
  if (context.mounted) {
    avisar(context, '✅ ${j.corto} renovó hasta dentro de $anios temporada${anios > 1 ? 's' : ''}.');
  }
}

/// Mostrar un pibe de la reserva a clubes de afuera.
Future<void> ofrecerPibeDialogo(BuildContext context, Jugador j) async {
  final p = juego.partida!;
  final ofertas = sondearPibe(p, j);
  await juego.guardar();
  if (!context.mounted) return;
  if (ofertas.isEmpty) {
    await mostrarTextos(context, 'Sin interés', ['Afuera nadie se interesó por ${j.corto} en esta ventana.']);
    return;
  }
  final (club, monto) = ofertas.first;
  if (!await confirmar(context, 'Oferta de afuera', '$club ofrece ${M.plata(monto)} por ${j.corto}. ¿Aceptás?',
      si: 'Aceptar', no: 'No')) {
    return;
  }
  final texto = venderPibe(p, j, club, monto);
  await juego.guardar();
  if (context.mounted) avisar(context, texto);
}
