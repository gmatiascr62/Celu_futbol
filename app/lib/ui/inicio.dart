// Pantalla de inicio: seguir la partida guardada o empezar una nueva.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/partido.dart';
import 'estilo.dart';
import 'club.dart';
import 'nueva.dart';
import 'amistoso.dart';

class Inicio extends StatelessWidget {
  const Inicio({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: juego,
        builder: (context, _) {
          if (!juego.listo) return const Center(child: CircularProgressIndicator());
          final p = juego.partida;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [verdeOscuro, fondo],
                stops: [0, 0.6],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                children: [
                  const _Logo(),
                  const SizedBox(height: 40),
                  if (p != null && p.mio != null) ...[
                    Tarjeta(
                      onTap: () => _abrir(context),
                      child: Row(children: [
                        Escudo(p.mio!, tam: 52),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('SEGUIR PARTIDA', style: tituloChico),
                            const SizedBox(height: 4),
                            Text(p.mio!, style: titulo),
                            Text(
                                'Temporada ${p.temporada} · Fecha ${p.numero} de ${p.totalFechas}'
                                ' · ${p.divisiones[p.divisionAMostrar]}',
                                style: chico),
                          ]),
                        ),
                        const Icon(Icons.play_circle_fill_rounded, color: verde, size: 44),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    onPressed: () async {
                      if (p != null &&
                          !await confirmar(context, '¿Empezar de nuevo?',
                              'Se borra la partida de ${p.mio} (temporada ${p.temporada}).',
                              si: 'Empezar')) {
                        return;
                      }
                      if (!context.mounted) return;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NuevaPartida()));
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva partida'),
                    style: p != null
                        ? FilledButton.styleFrom(
                            backgroundColor: superficie2, foregroundColor: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const Amistoso())),
                    icon: const Icon(Icons.sports_soccer_rounded),
                    label: const Text('Partido amistoso'),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    cerebro != null
                        ? 'Los DT juegan con lo que aprendieron en 12 millones de partidos.'
                        : 'Los DT deciden con el cálculo de probabilidades.',
                    textAlign: TextAlign.center,
                    style: chico,
                  ),
                  const SizedBox(height: 6),
                  const Text('Versión 2.0', textAlign: TextAlign.center, style: chico),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _abrir(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaClub()));
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: verde.withValues(alpha: 0.15),
            border: Border.all(color: verde, width: 3),
          ),
          child: const Icon(Icons.sports_soccer_rounded, size: 60, color: Colors.white),
        ),
        const SizedBox(height: 18),
        const Text('CELU FÚTBOL',
            style: TextStyle(
                fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 44, letterSpacing: 2)),
        const Text('El fútbol argentino en tu mano',
            style: TextStyle(color: texto2, fontSize: 15)),
      ]);
}
