// Partida nueva: elegir el club y la personalidad del DT.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/datos.dart';
import '../motor/equipo.dart';
import '../motor/partido.dart';
import '../motor/torneo.dart';
import 'club.dart';
import 'estilo.dart';

/// Nivel del equipo titular de un club (promedio de sus 11 mejores).
int nivelClub(String club) {
  final e = Equipo(club, 0, 0)..plantel = planteles[club] ?? [];
  return e.plantel.isEmpty ? 0 : fuerzaTitular(e).round();
}

class NuevaPartida extends StatefulWidget {
  const NuevaPartida({super.key});

  @override
  State<NuevaPartida> createState() => _NuevaPartidaState();
}

class _NuevaPartidaState extends State<NuevaPartida> {
  @override
  Widget build(BuildContext context) {
    final m = juego.modelo;
    return DefaultTabController(
      length: m.divisiones.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elegí tu club'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: [for (final d in m.divisiones) Tab(text: d)],
          ),
        ),
        body: TabBarView(children: [
          for (var d = 0; d < m.divisiones.length; d++) _lista(d),
        ]),
      ),
    );
  }

  Widget _lista(int d) {
    final clubes = [for (final c in juego.modelo.division.keys) if (juego.modelo.division[c] == d) c];
    final niveles = {for (final c in clubes) c: nivelClub(c)};
    clubes.sort((a, b) => niveles[b]!.compareTo(niveles[a]!));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: clubes.length,
      separatorBuilder: (_, __) => const Divider(indent: 72),
      itemBuilder: (context, i) {
        final c = clubes[i];
        return ListTile(
          leading: Escudo(c, tam: 38),
          title: Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(d == 0 && i < 5
              ? 'Candidato al título'
              : d > 0 && i < 4
                  ? 'Candidato al ascenso'
                  : d == 0 && i >= clubes.length - 4
                      ? 'Pelea por no descender'
                      : 'Mitad de tabla', style: chico),
          trailing: Nivel(niveles[c]!),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => ElegirDt(club: c))),
        );
      },
    );
  }
}

class ElegirDt extends StatefulWidget {
  final String club;
  const ElegirDt({super.key, required this.club});

  @override
  State<ElegirDt> createState() => _ElegirDtState();
}

class _ElegirDtState extends State<ElegirDt> {
  String elegido = 'equilibrado';
  bool creando = false;

  static const iconos = {
    'equilibrado': Icons.balance_rounded,
    'conservador': Icons.shield_rounded,
    'arriesgado': Icons.local_fire_department_rounded,
    'impulsivo': Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final (c1, _) = coloresDe(widget.club);
    return Scaffold(
      appBar: AppBar(title: const Text('Tu DT')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Tarjeta(
            color: Color.lerp(superficie, c1, 0.18),
            child: Row(children: [
              Escudo(widget.club, tam: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.club, style: titulo),
                  Text(juego.modelo.divisiones[juego.modelo.division[widget.club] ?? 0],
                      style: chico),
                ]),
              ),
              Nivel(nivelClub(widget.club), tam: 42),
            ]),
          ),
          const Seccion('¿Qué DT contratás?'),
          for (final x in personalidades.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Tarjeta(
                onTap: () => setState(() => elegido = x.key),
                color: elegido == x.key ? verde.withValues(alpha: 0.14) : null,
                child: Row(children: [
                  Icon(iconos[x.key], color: elegido == x.key ? verde : texto2, size: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.key[0].toUpperCase() + x.key.substring(1),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(x.value.desc, style: chico),
                    ]),
                  ),
                  Icon(elegido == x.key ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: elegido == x.key ? verde : texto2),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'El DT elige la formación, los titulares y los cambios, y te va a pedir '
            'reuniones. Prefiere jugar con su formación, pero le podés pedir otra.',
            style: chico,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: creando ? null : _empezar,
            child: creando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Empezar'),
          ),
        ],
      ),
    );
  }

  Future<void> _empezar() async {
    setState(() => creando = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await juego.nueva(widget.club, elegido);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaClub()));
  }
}
