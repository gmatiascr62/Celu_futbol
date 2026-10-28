// Tu DT: quién es, cómo está de ánimo, lo que le prometiste y su historia.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/jugadores.dart' as J;
import '../motor/mercado.dart' as M;
import '../motor/partido.dart';
import '../motor/tecnicos.dart' as T;
import '../motor/torneo.dart';
import 'dialogos.dart';
import 'estilo.dart';

class TabDt extends StatelessWidget {
  final Future<void> Function() alCambiar;
  const TabDt({super.key, required this.alCambiar});

  @override
  Widget build(BuildContext context) {
    final p = juego.partida!;
    final t = p.miDt;
    final mi = p.mi;
    if (t == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('El club no tiene DT', style: titulo),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await contratarDtDialogo(context);
                await juego.guardar();
              },
              child: const Text('Contratar uno'),
            ),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Tu DT', style: titulo),
        const SizedBox(height: 12),
        Tarjeta(
          child: Column(children: [
            Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: verde.withValues(alpha: 0.2),
                child: Text('${t.nombre[0]}${t.apellido[0]}',
                    style: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 24)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.completo, style: titulo),
                  Text('${t.edad} años · ${t.personalidad}', style: chico),
                  Text(personalidades[t.personalidad]!.desc, style: chico),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Dato('${t.prestigio}', 'Prestigio'),
              Dato(M.plata(t.sueldo), 'Sueldo/año'),
              Dato('${t.contrato}', t.contrato == 1 ? 'Temporada' : 'Temporadas'),
            ]),
          ]),
        ),
        const Seccion('Ánimo'),
        Tarjeta(
          child: Column(children: [
            BarraConNombre('Con vos', t.satisfaccion),
            BarraConNombre('Confianza', t.confianza),
            BarraConNombre('Presión', t.presion, alReves: true),
            const SizedBox(height: 6),
            Text(
              t.satisfaccion < T.ultimatum
                  ? 'Está a punto de irse. Si baja más, renuncia.'
                  : t.satisfaccion < 45
                      ? 'No está contento con vos.'
                      : 'La relación está bien.',
              style: chico,
            ),
          ]),
        ),
        const Seccion('Cómo juega'),
        Tarjeta(
          onTap: () async {
            final f = await elegirFormacionDialogo(context, mi.formacion, mi.formacionForzada);
            if (f == null) return;
            final dice = pedirFormacion(p, f == 'dt' ? null : f);
            await juego.guardar();
            if (context.mounted) avisar(context, '🗣 ${t.apellido}: «$dice»');
          },
          child: Row(children: [
            const Icon(Icons.grid_view_rounded, color: texto2),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mi.formacionForzada ?? mi.formacion,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                    mi.formacionForzada != null
                        ? 'Se lo pediste vos (él prefiere el ${mi.formacion})'
                        : 'La elige él según el rival; prefiere el ${mi.formacion}',
                    style: chico),
              ]),
            ),
            const Text('Cambiar', style: TextStyle(color: verde, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (t.promesas.isNotEmpty) ...[
          const Seccion('Lo que le prometiste'),
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final pr in t.promesas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      '📌 ${T.quePrometio(pr)}, '
                      '${pr.containsKey('rol') ? '${pr['nivel']} estrellas' : 'nivel ${pr['nivel']}'} o más '
                      '(${_ventana(p, pr['ventana'])})'),
                ),
            ]),
          ),
        ],
        const Seccion('Historia'),
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in T.curriculum(t))
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l)),
          ]),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: rojo, side: const BorderSide(color: rojo)),
          onPressed: () async {
            final costo = costoEcharDt(p);
            if (!await confirmar(context, '¿Echar a ${t.apellido}?',
                'Rescindir el contrato cuesta ${M.plata(costo)}.', si: 'Echarlo')) {
              return;
            }
            final texto = echarDt(p);
            await juego.guardar();
            if (!context.mounted) return;
            avisar(context, texto);
            await alCambiar();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Echarlo'),
        ),
      ],
    );
  }

  String _ventana(Partida p, String? clave) {
    if (clave == null) return '';
    final partes = clave.split('-');
    final temporada = int.parse(partes[0]);
    final abre = partes[1] == '0' ? 'en la pretemporada' : 'a mitad de temporada';
    return temporada == p.temporada ? 'mercado $abre' : 'mercado $abre de la temporada $temporada';
  }
}

/// Elegir la formación para pedirle al DT. Devuelve la formación, 'dt' o null.
Future<String?> elegirFormacionDialogo(BuildContext context, String prefiere, String? forzada) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('¿Con qué formación jugamos?', style: titulo),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.psychology_rounded),
          title: const Text('Que elija él'),
          trailing: forzada == null ? const Icon(Icons.check_rounded, color: verde) : null,
          onTap: () => Navigator.pop(c, 'dt'),
        ),
        for (final f in J.formaciones.keys)
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: Text(f),
            subtitle: f == prefiere ? const Text('La que prefiere') : null,
            trailing: forzada == f ? const Icon(Icons.check_rounded, color: verde) : null,
            onTap: () => Navigator.pop(c, f),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}
