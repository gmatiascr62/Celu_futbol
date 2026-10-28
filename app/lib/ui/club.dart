// La pantalla principal de tu club, con sus pestañas, y el ritmo del juego:
// lo que hay que resolver antes de cada fecha, jugarla y ver qué pasó.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/equipo.dart';
import '../motor/jugadores.dart' as J;
import '../motor/mercado.dart' as M;
import '../motor/tecnicos.dart' as T;
import '../motor/torneo.dart';
import 'dialogos.dart';
import 'estilo.dart';
import 'fin_temporada.dart';
import 'mas.dart';
import 'mercado.dart';
import 'pantalla_partido.dart';
import 'plantel.dart';
import 'tabla.dart';
import 'tab_dt.dart';

class PantallaClub extends StatefulWidget {
  const PantallaClub({super.key});

  @override
  State<PantallaClub> createState() => _PantallaClubState();
}

class _PantallaClubState extends State<PantallaClub> {
  int tab = 0;
  bool ocupado = false;
  ResultadoFecha? ultima;
  String? progreso;

  Partida get p => juego.partida!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => pendientes());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: juego,
      builder: (context, _) {
        if (juego.partida == null) return const Scaffold();
        final paginas = [
          _tabInicio(),
          const TabTabla(),
          const TabPlantel(),
          TabDt(alCambiar: pendientes),
          const TabMas(),
        ];
        return PopScope(
          canPop: !ocupado,
          child: Scaffold(
            body: SafeArea(child: paginas[tab]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Inicio'),
                NavigationDestination(icon: Icon(Icons.leaderboard_rounded), label: 'Tabla'),
                NavigationDestination(icon: Icon(Icons.groups_rounded), label: 'Plantel'),
                NavigationDestination(icon: Icon(Icons.sports_rounded), label: 'DT'),
                NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'Más'),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- inicio
  Widget _tabInicio() {
    final mi = p.mi;
    final d = p.divisionDe(mi.nombre);
    final (pos, f) = posicion(p.tablaDivision(d), mi.nombre);
    final t = p.miDt;
    final abierto = ventanaActual(p) != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          IconButton(
            onPressed: ocupado ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(child: Text('Temporada ${p.temporada}', style: titulo)),
          Text(p.divisiones[d], style: chico),
        ]),
        const SizedBox(height: 8),
        _encabezado(pos, f),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _chip(Icons.account_balance_wallet_rounded, M.plata(mi.caja),
              mi.caja < 0 ? rojo : null)),
          const SizedBox(width: 8),
          Expanded(child: _chip(null, '${cara(mi.hinchada)} ${mi.hinchada.round()}', null,
              textoIcono: 'Hinchada')),
          const SizedBox(width: 8),
          Expanded(
              child: _chip(Icons.sentiment_satisfied_rounded,
                  t == null ? 'Sin DT' : 'DT ${t.satisfaccion.round()}',
                  t != null && t.satisfaccion < 35 ? rojo : null)),
        ]),
        const SizedBox(height: 16),
        if (!p.terminada) _proximo() else _terminada(),
        if (abierto && !p.terminada) ...[
          const SizedBox(height: 12),
          Tarjeta(
            color: verde.withValues(alpha: 0.12),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const PantallaMercado())),
            child: Row(children: [
              const Icon(Icons.swap_horiz_rounded, color: verde, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Mercado de pases abierto',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(
                      'Cierra al jugar la próxima fecha'
                      '${p.ofertas.isEmpty ? '' : p.ofertas.length == 1 ? ' · 1 oferta por tus jugadores' : ' · ${p.ofertas.length} ofertas por tus jugadores'}',
                      style: chico),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ],
        if (ultima != null && p.numero > 0) ..._resultados(),
        if (p.noticias.isNotEmpty) ...[
          const Seccion('Noticias'),
          Tarjeta(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              for (final n in p.noticias)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Align(alignment: Alignment.centerLeft, child: Text(n))),
            ]),
          ),
        ],
        const Seccion('Entrenamiento'),
        Tarjeta(
          onTap: _entrenamiento,
          child: Row(children: [
            const Icon(Icons.fitness_center_rounded, color: texto2),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                p.planMio == null
                    ? 'Lo decide el DT cada semana'
                    : '${_mayus(p.planMio!.$1)}${p.planMio!.$1 == 'descanso' ? '' : ' · ${p.planMio!.$2}'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Text('Cambiar', style: TextStyle(color: verde, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }

  Widget _chip(IconData? icono, String texto, Color? color, {String? textoIcono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
            color: superficie, borderRadius: BorderRadius.circular(12), border: Border.all(color: borde)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icono != null) ...[Icon(icono, size: 16, color: color ?? texto2), const SizedBox(width: 6)],
          Flexible(
            child: Text(texto,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ),
        ]),
      );

  Widget _encabezado(int pos, Fila f) {
    final mi = p.mi;
    final (c1, _) = coloresDe(mi.nombre);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Color.lerp(superficie, c1, 0.45)!, superficie],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borde),
      ),
      child: Row(children: [
        Escudo(mi.nombre, tam: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mi.nombre, style: titulo.copyWith(fontSize: 26)),
            const SizedBox(height: 2),
            Text('${f.g}G ${f.e}E ${f.p}P · ${f.gf}-${f.gc}', style: chico),
          ]),
        ),
        Column(children: [
          Text(f.pj == 0 ? '-' : '$pos°', style: titulo.copyWith(fontSize: 34)),
          Text('${f.pts} pts', style: chico),
        ]),
      ]),
    );
  }

  (Equipo, Equipo)? _proximoPartido() {
    if (p.terminada) return null;
    final yo = p.equipos.indexOf(p.mi);
    for (final (l, v) in p.fixture[p.numero]) {
      if (l == yo || v == yo) return (p.equipos[l], p.equipos[v]);
    }
    return null;
  }

  Widget _proximo() {
    final par = _proximoPartido();
    final d = p.divisionDe(p.mio!);
    Widget lado(Equipo e) {
      final (pos, _) = posicion(p.tablaDivision(d), e.nombre);
      return Expanded(
        child: Column(children: [
          Escudo(e.nombre, tam: 52),
          const SizedBox(height: 8),
          Text(e.nombre,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: e.nombre == p.mio ? Colors.white : const Color(0xFFDDE5E0))),
          Text(p.numero == 0 ? '' : '$pos°', style: chico),
        ]),
      );
    }

    return Tarjeta(
      child: Column(children: [
        Text('FECHA ${p.numero + 1} DE ${p.totalFechas}', style: tituloChico),
        const SizedBox(height: 14),
        if (par != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            lado(par.$1),
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('VS', style: TextStyle(fontFamily: 'Barlow', fontSize: 22, color: texto2)),
            ),
            lado(par.$2),
          ]),
        if (par != null && esClasico(par.$1.nombre, par.$2.nombre))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('🔥 CLÁSICO', style: TextStyle(color: amarillo, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        if (ocupado)
          Column(children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(progreso ?? 'Jugando...', style: chico),
          ])
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => jugar(1),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Jugar partido'),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: OutlinedButton(onPressed: () => jugar(5), child: const Text('Simular 5'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    onPressed: () => jugar(p.totalFechas - p.numero),
                    child: const Text('Hasta el final'))),
          ]),
        ],
      ]),
    );
  }

  Widget _terminada() => Tarjeta(
        child: Column(children: [
          const Text('TERMINÓ LA TEMPORADA', style: tituloChico),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => pendientes(),
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('Ver el cierre'),
            ),
          ),
        ]),
      );

  List<Widget> _resultados() {
    final r = ultima!;
    final d = p.divisionAMostrar;
    return [
      Seccion('Fecha ${p.numero} · ${p.divisiones[d]}'),
      Tarjeta(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (esMio, texto, div) in r.resultados)
            if (div == d) _filaResultado(texto, esMio),
        ]),
      ),
      if (r.informe != null) ...[
        const Seccion('Entrenamiento de la semana'),
        Tarjeta(child: _informe(r.informe!)),
      ],
    ];
  }

  Widget _filaResultado(String texto, bool esMio) {
    final m = RegExp(r'^(.*) (\d+)-(\d+) (.*)$').firstMatch(texto)!;
    final style = TextStyle(fontWeight: esMio ? FontWeight.w700 : FontWeight.w400, fontSize: 14);
    return Container(
      color: esMio ? verde.withValues(alpha: 0.10) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(children: [
        Expanded(child: Text(m[1]!, textAlign: TextAlign.right, style: style, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Escudo(m[1]!, tam: 20),
        Container(
          width: 52,
          alignment: Alignment.center,
          child: Text('${m[2]} - ${m[3]}',
              style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 17)),
        ),
        Escudo(m[4]!, tam: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(m[4]!, style: style, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _informe(Informe inf) {
    final (tipo, intensidad) = inf.plan;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_mayus(tipo)}${tipo == 'descanso' ? '' : ' ($intensidad)'} · '
          '${inf.delDt ? 'lo eligió el DT' : 'lo elegiste vos'}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      if (inf.mejoras.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in inf.mejoras)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.arrow_upward_rounded, size: 16, color: verde),
              label: Text('${m.j.corto} ${m.antes}→${m.despues}'),
            ),
        ]),
      ],
      for (final (j, n) in inf.lesionados)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('🚑 Se lesionó ${j.corto}: $n fecha${n > 1 ? 's' : ''} afuera',
              style: const TextStyle(color: rojo)),
        ),
      if (inf.mejoras.isEmpty && inf.lesionados.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Nadie subió de nivel esta semana.', style: chico)),
    ]);
  }

  String _mayus(String s) => s[0].toUpperCase() + s.substring(1);

  Future<void> _entrenamiento() async {
    final plan = await elegirEntrenamientoDialogo(context, p.planMio);
    if (plan == null || !mounted) return;
    final opinion = elegirEntrenamiento(p, plan.$1 == 'dt' ? null : plan);
    await juego.guardar();
    if (opinion != null && mounted) avisar(context, '🗣 ${p.miDt!.apellido}: «$opinion»');
  }

  // ---------------------------------------------------------------- el ritmo del juego
  /// Lo que hay que resolver antes de jugar: el fin de temporada, los
  /// contratos que vencen, los pibes que cumplen 21, el mercado y el DT.
  Future<void> pendientes() async {
    if (!mounted || juego.partida == null) return;
    if (p.terminada) {
      final siguio = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const FinTemporada()));
      if (siguio != true || !mounted) return;
      setState(() => ultima = null);
    }
    final mi = p.mi;
    final vencidos = [for (final j in mi.plantel) if (j.contrato <= 0) j]
      ..sort((a, b) => J.nivel(b).compareTo(J.nivel(a)));
    if (vencidos.isNotEmpty) {
      await renovacionesDialogo(context, vencidos);
      await juego.guardar();
      if (!mounted) return;
    }
    final grandes = [for (final j in mi.reserva) if (j.edad >= 21) j];
    if (grandes.isNotEmpty) {
      await pibesDe21Dialogo(context, grandes);
      await juego.guardar();
      if (!mounted) return;
    }
    if (abrirVentana(p)) {
      await juego.guardar();
      if (!mounted) return;
      avisar(context,
          '🔁 Se abrió el mercado de pases: ${p.movimientos.length} movimientos'
          '${p.ofertas.isEmpty ? '' : p.ofertas.length == 1 ? ', 1 oferta por tus jugadores' : ', ${p.ofertas.length} ofertas por tus jugadores'}.');
    }
    if (!p.sinDt) {
      final r = p.reunion;
      if (r != null) {
        p.reunion = null;
        await reunionDialogo(context, r);
        await juego.guardar();
        if (!mounted) return;
      }
      if (p.tecnicos[p.mio] == null) {
        await contratarDtDialogo(context);
        await juego.guardar();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> jugar(int cuantas) async {
    if (ocupado) return;
    final pend = promesasPendientes(p);
    if (pend.isNotEmpty) {
      final seguir = await confirmar(
          context,
          'Promesa sin cumplir',
          'Le prometiste al DT ${pend.map(T.quePrometio).join(', ')} y el plazo vence con '
              'esta fecha. ¿Jugar igual?',
          si: 'Jugar igual');
      if (!seguir || !mounted) return;
    }
    setState(() => ocupado = true);
    final modelo = juego.modelo;
    try {
      if (cuantas == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final r = jugarUnaFecha(p, modelo, relato: true);
        ultima = r;
        await juego.guardar();
        if (!mounted) return;
        if (r.partido != null) {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => PantallaPartido(partido: r.partido!)));
        }
        if (mounted && r.obras.isNotEmpty) await mostrarTextos(context, 'Obras', r.obras);
      } else {
        final hasta = p.numero + cuantas;
        final mios = <String>[];
        while (p.numero < hasta && !p.terminada) {
          setState(() => progreso = 'Fecha ${p.numero + 1} de ${p.totalFechas}...');
          await Future<void>.delayed(const Duration(milliseconds: 16));
          final r = jugarUnaFecha(p, modelo);
          ultima = r;
          mios.addAll([for (final (esMio, t, _) in r.resultados) if (esMio) 'Fecha ${p.numero}: $t']);
          if (p.numero % 5 == 0) await juego.guardar();
          final reunion = p.reunion;
          if (reunion != null && reunion.prioridad >= 80) {
            mios.add('📣 Tu DT pidió una reunión urgente.');
            break;
          }
          if (!mounted) return;
        }
        await juego.guardar();
        if (mounted) await mostrarTextos(context, 'Resultados', mios);
      }
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
    await pendientes();
  }
}
