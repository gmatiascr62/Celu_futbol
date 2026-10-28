// El cierre de la temporada: campeones, ascensos y descensos, y la
// pretemporada de tu club.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/club.dart' as C;
import '../motor/jugadores.dart' show Jugador;
import '../motor/mercado.dart' as M;
import '../motor/torneo.dart';
import 'estilo.dart';

class FinTemporada extends StatefulWidget {
  const FinTemporada({super.key});

  @override
  State<FinTemporada> createState() => _FinTemporadaState();
}

class _FinTemporadaState extends State<FinTemporada> {
  bool cerrando = false;

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final mio = p.mio!;
    final d = p.divisionDe(mio);
    final (pos, f) = posicion(p.tablaDivision(d), mio);
    final cambios = cambiosDeCategoriaDe(p);
    final mioCambia = cambios.where((c) => c.$1 == mio).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('Fin de la temporada ${p.temporada}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: [
                Color.lerp(superficie, coloresDe(mio).$1, 0.4)!,
                superficie,
              ]),
              border: Border.all(color: borde),
            ),
            child: Column(children: [
              Escudo(mio, tam: 70),
              const SizedBox(height: 10),
              Text(mio, style: titulo),
              Text('$pos° en la ${p.divisiones[d]}',
                  style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 30)),
              Text('${f.pts} puntos · ${f.g}G ${f.e}E ${f.p}P · ${f.gf}-${f.gc}', style: chico),
              if (pos == 1) ...[
                const SizedBox(height: 10),
                const Text('🏆 ¡CAMPEÓN!',
                    style: TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 28, color: amarillo)),
              ],
              if (mioCambia != null) ...[
                const SizedBox(height: 10),
                Text(mioCambia.$3 < mioCambia.$2 ? '🎉 ¡ASCENDISTE!' : '😢 Descendiste',
                    style: TextStyle(
                        fontFamily: 'Barlow',
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                        color: mioCambia.$3 < mioCambia.$2 ? verde : rojo)),
              ],
            ]),
          ),
          const Seccion('Campeones'),
          for (var i = 0; i < p.divisiones.length; i++) _campeon(p, i),
          const Seccion('Ascensos y descensos'),
          Tarjeta(
            child: Column(children: [
              for (final (club, de, a) in cambios)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(a < de ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: a < de ? verde : rojo, size: 18),
                    const SizedBox(width: 8),
                    Escudo(club, tam: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(club,
                          style: TextStyle(fontWeight: club == mio ? FontWeight.w700 : FontWeight.w400)),
                    ),
                    Text(p.divisiones[a], style: chico),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: cerrando ? null : _siguiente,
            child: cerrando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text('Empezar la temporada ${p.temporada + 1}'),
          ),
        ],
      ),
    );
  }

  Widget _campeon(Partida p, int d) {
    final orden = ordenarTabla(p.tablaDivision(d));
    final g = p.goleadoresDivision(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tarjeta(
        child: Row(children: [
          Escudo(orden.first.key, tam: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.divisiones[d].toUpperCase(), style: tituloChico),
              Text(orden.first.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text('${orden.first.value.pts} pts', style: chico),
              if (g.isNotEmpty) Text('⚽ ${g.first.$1} (${g.first.$2}), ${g.first.$3} goles', style: chico),
            ]),
          ),
          const Text('🏆', style: TextStyle(fontSize: 28)),
        ]),
      ),
    );
  }

  Future<void> _siguiente() async {
    setState(() => cerrando = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final p = juego.partida!;
    final mio = p.mio!;
    final antes = p.divisionDe(mio);
    final cambios = cerrarTemporada(p);
    empezarTemporada(p);
    await juego.guardar();
    if (!mounted) return;
    final ahora = p.divisionDe(mio);
    final (retirados, juveniles) = cambios[mio]!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('Pretemporada ${p.temporada}',
            style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (ahora < antes) Text('🎉 ¡$mio jugará en la ${p.divisiones[ahora]}! Los ingresos suben un 50%.'),
            if (ahora > antes) Text('😢 $mio jugará en la ${p.divisiones[ahora]}. Los ingresos bajan.'),
            const SizedBox(height: 8),
            Text(retirados.isEmpty ? 'No se retira nadie.' : 'Se retiran:',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final j in retirados) Text('  ${j.corto} (${j.pos}, ${j.edad} años)'),
            if (juveniles.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('🌱 Llegan a la reserva:', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final j in juveniles) _pibe(j),
            ],
            if (p.mi.plantel.length < M.plantelMin) ...[
              const SizedBox(height: 10),
              Text('⚠ Quedan ${p.mi.plantel.length} jugadores: subí pibes de la reserva o fichá en el mercado.',
                  style: const TextStyle(color: amarillo)),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('A jugar'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _pibe(Jugador j) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text('  ${j.corto} (${j.pos}, ${j.edad})')),
          Estrellas(C.estrellasPot(j), tam: 12),
        ]),
      );
}
