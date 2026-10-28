// La pestaña "Más": el club (instalaciones y cuerpo técnico), el mercado,
// el historial y las finanzas.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/club.dart' as C;
import '../motor/mercado.dart' as M;
import '../motor/torneo.dart';
import 'estilo.dart';
import 'mercado.dart';

class TabMas extends StatelessWidget {
  const TabMas({super.key});

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final mi = p.mi;
    final abierto = ventanaActual(p) != null;
    Widget opcion(IconData icono, String nombre, String detalle, Widget Function() pantalla) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tarjeta(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla())),
            child: Row(children: [
              Icon(icono, color: verde, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(detalle, style: chico),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: texto2),
            ]),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Más', style: titulo),
        const SizedBox(height: 12),
        opcion(Icons.swap_horiz_rounded, 'Mercado de pases',
            abierto ? 'Abierto · ${p.ofertas.length} ofertas' : 'Cerrado · ver movimientos',
            () => const PantallaMercado()),
        opcion(Icons.stadium_rounded, 'Club', 'Instalaciones y cuerpo técnico', () => const PantallaInstalaciones()),
        opcion(Icons.account_balance_rounded, 'Finanzas', 'Caja ${M.plata(mi.caja)}', () => const PantallaFinanzas()),
        opcion(Icons.history_rounded, 'Historial', '${p.historial.length} temporadas terminadas',
            () => const PantallaHistorial()),
      ],
    );
  }
}

// ---------------------------------------------------------------- club
class PantallaInstalaciones extends StatelessWidget {
  const PantallaInstalaciones({super.key});

  static const iconos = {
    'predio': Icons.grass_rounded,
    'medico': Icons.local_hospital_rounded,
    'estadio': Icons.stadium_rounded,
    'inferiores': Icons.child_care_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: juego,
      builder: (context, _) {
        final p = juego.partida!;
        final mi = p.mi;
        return Scaffold(
          appBar: AppBar(title: Text(mi.nombre)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text('Caja: ${M.plata(mi.caja)} · Mantenimiento ${M.plata(C.mantenimiento(mi))}/año', style: chico),
              const Seccion('Instalaciones'),
              for (final x in C.instalacionesNombres.entries) _instalacion(context, p, x.key, x.value),
              const Seccion('Cuerpo técnico'),
              Card(
                child: Column(children: [
                  for (final x in C.roles.entries) _rol(context, p, x.key, x.value),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _instalacion(BuildContext context, Partida p, String tipo, String nombre) {
    final mi = p.mi;
    final n = mi.instalaciones[tipo]!;
    final obra = mi.obras.where((o) => o.tipo == tipo).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(iconos[tipo], color: verde),
            const SizedBox(width: 12),
            Expanded(child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Text('Nivel $n', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 1; i <= C.nivelMax; i++)
              Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i <= n
                        ? verde
                        : obra != null && i == n + 1
                            ? amarillo.withValues(alpha: 0.6)
                            : Colors.white12,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text(C.efectoInstalacion[tipo]!, style: chico),
          const SizedBox(height: 8),
          if (obra != null)
            Text('🏗 En obra → nivel ${n + 1}, faltan ${obra.faltan} fechas',
                style: const TextStyle(color: amarillo))
          else if (n < C.nivelMax)
            Row(children: [
              Expanded(
                child: Text('→ ${n + 1}: ${M.plata(C.costoObra(tipo, n + 1))}, ${C.duracionObra(n + 1)} fechas',
                    style: const TextStyle(fontSize: 13)),
              ),
              FilledButton.tonal(onPressed: () => _mejorar(context, p, tipo), child: const Text('Mejorar')),
            ])
          else
            const Text('Nivel máximo', style: chico),
        ]),
      ),
    );
  }

  Future<void> _mejorar(BuildContext context, Partida p, String tipo) async {
    final mi = p.mi;
    final problema = problemaObra(mi, tipo);
    if (problema != null) {
      avisar(context, problema);
      return;
    }
    final n = mi.instalaciones[tipo]! + 1;
    final ok = await confirmar(
        context,
        '${C.instalacionesNombres[tipo]} a nivel $n',
        'Cuesta ${M.plata(C.costoObra(tipo, n))} y la obra tarda ${C.duracionObra(n)} fechas. '
            'El mantenimiento sube ${M.plata(mantenimientoExtra(mi, tipo))}/año.',
        si: 'Arrancar la obra');
    if (!ok) return;
    C.empezarObra(mi, tipo);
    await juego.guardar();
    if (context.mounted) avisar(context, '🏗 Arrancó la obra. Termina en ${C.duracionObra(n)} fechas.');
  }

  Widget _rol(BuildContext context, Partida p, String rol, String nombre) {
    final m = p.mi.staff[rol];
    return ListTile(
      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: m == null
          ? const Text('No hay', style: chico)
          : Row(children: [
              Text('${m.nombre} · ${M.plata(m.sueldo)}/año  ', style: chico),
              Estrellas(m.nivel, tam: 12),
            ]),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _staff(context, p, rol, nombre),
    );
  }

  Future<void> _staff(BuildContext context, Partida p, String rol, String nombre) async {
    final mi = p.mi;
    final actual = mi.staff[rol];
    final lista = p.staffLibres[rol] ?? [];
    final elegido = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(nombre, style: titulo),
          const SizedBox(height: 4),
          Text(
              actual == null
                  ? 'No hay nadie en el puesto.'
                  : 'Hoy: ${actual.nombre} (${actual.nivel} estrellas). Si contratás a otro, '
                      'se va y cuesta ${M.plata(actual.sueldo / 2)}.',
              style: chico),
          const SizedBox(height: 8),
          if (lista.isEmpty) const Text('No hay nadie disponible hasta la próxima temporada.'),
          for (final m in lista)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.nombre),
              subtitle: Text('${M.plata(m.sueldo)}/año'),
              trailing: Estrellas(m.nivel),
              onTap: () => Navigator.pop(c, m),
            ),
          if (actual != null) ...[
            const Divider(),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: rojo),
              onPressed: () => Navigator.pop(c, 'despedir'),
              icon: const Icon(Icons.person_remove_rounded),
              label: Text('Despedir a ${actual.nombre} (${M.plata(actual.sueldo / 2)})'),
            ),
          ],
        ]),
      ),
    );
    if (elegido == null) return;
    final texto = elegido == 'despedir' ? despedirStaff(p, rol) : contratarStaff(p, rol, elegido as dynamic);
    await juego.guardar();
    if (context.mounted) avisar(context, texto);
  }
}

// ---------------------------------------------------------------- finanzas
class PantallaFinanzas extends StatelessWidget {
  const PantallaFinanzas({super.key});

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final mi = p.mi;
    final sueldos = M.masaSalarial(mi.plantel);
    final dt = p.miDt?.sueldo ?? 0;
    final gastos = C.gastosAnuales(mi);
    final saldo = mi.ingreso - sueldos - dt - gastos;
    Widget fila(String nombre, double v, {bool negrita = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(nombre, style: TextStyle(fontWeight: negrita ? FontWeight.w700 : FontWeight.w400))),
            Text(M.plata(v),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: v < 0 ? rojo : (negrita ? verde : null))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Finanzas')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Tarjeta(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            Dato(M.plata(mi.caja), 'Caja', color: mi.caja < 0 ? rojo : null),
            Dato('${cara(mi.hinchada)} ${mi.hinchada.round()}', 'Hinchada'),
          ]),
        ),
        const Seccion('Por año'),
        Tarjeta(
          child: Column(children: [
            fila('Ingresos (socios, TV, sponsors)', mi.ingreso),
            fila('Sueldos del plantel', -sueldos),
            fila('Sueldo del DT', -dt),
            fila('Instalaciones y cuerpo técnico', -gastos),
            const Divider(),
            fila('Queda', saldo, negrita: true),
          ]),
        ),
        const SizedBox(height: 12),
        const Text(
          'Además entran premios a fin de temporada según el puesto, y la hinchada mueve hasta un 10% '
          'de los ingresos: contenta llena la cancha, enojada la vacía.',
          style: chico,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- historial
class PantallaHistorial extends StatelessWidget {
  const PantallaHistorial({super.key});

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: p.historial.isEmpty
          ? const Center(child: Text('Todavía no terminó ninguna temporada.', style: chico))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final r in p.historial.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Tarjeta(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Temporada ${r['temporada']}', style: titulo),
                        if (r['puesto'] != null)
                          Text('${p.mio}: ${r['puesto']}° en la ${r['division_mio']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: verde)),
                        const SizedBox(height: 8),
                        for (final c in r['campeones'])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              const Text('🏆 '),
                              Escudo(c[1], tam: 18),
                              const SizedBox(width: 6),
                              Expanded(child: Text('${c[1]} (${c[2]} pts) · ${c[0]}')),
                            ]),
                          ),
                        Text('⚽ Goleador: ${r['goleador']}', style: chico),
                        if ((r['ascensos'] as List).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('⬆ Suben: ${(r['ascensos'] as List).join(', ')}', style: chico),
                          Text('⬇ Bajan: ${(r['descensos'] as List).join(', ')}', style: chico),
                        ],
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
