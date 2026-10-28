// Las ventanas que aparecen entre fecha y fecha: las reuniones con el DT,
// contratar uno nuevo, los contratos que vencen, los pibes que cumplen 21,
// el entrenamiento y la negociación de sueldos.
import 'package:flutter/material.dart';

import '../juego.dart';
import '../motor/club.dart' as C;
import '../motor/jugadores.dart' as J;
import '../motor/jugadores.dart' show Jugador;
import '../motor/mercado.dart' as M;
import '../motor/tecnicos.dart' as T;
import '../motor/tecnicos.dart' show Reunion;
import '../motor/torneo.dart';
import 'estilo.dart';
import 'mercado.dart';

const _estiloTitulo = TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 22);

Widget _avatarDt(String nombre, String apellido, {double radio = 24}) => CircleAvatar(
      radius: radio,
      backgroundColor: verde.withValues(alpha: 0.2),
      child: Text('${nombre[0]}${apellido[0]}',
          style: TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: radio * 0.8)),
    );

/// Una reunión con tu DT: lo que dice y lo que le contestás.
Future<void> reunionDialogo(BuildContext context, Reunion r) async {
  final p = juego.partida!;
  final t = p.miDt;
  if (t == null) return;
  final n = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(children: [
        _avatarDt(t.nombre, t.apellido),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reunión con tu DT', style: chico),
            Text(t.completo, style: _estiloTitulo),
          ]),
        ),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: superficie2,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text('«${r.texto}»', style: const TextStyle(fontSize: 15, height: 1.35)),
          ),
          if (r.lista.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < r.lista.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Expanded(child: Text(r.lista[i], style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
          const SizedBox(height: 16),
          if (r.opciones.isEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Seguir')),
            ),
          for (var i = 0; i < r.opciones.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(c, i + 1),
                  child: Text(r.opciones[i].texto, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ),
        ]),
      ),
    ),
  );
  final textos = resolverReunion(p, r, n == null || n == 0 ? null : n);
  await juego.guardar();
  if (!context.mounted) return;
  final irABuscarlo = r.candidatos.isNotEmpty && n == 1 && ventanaActual(p) != null;
  if (irABuscarlo) {
    textos.removeWhere((t) => t.startsWith('Lo vas a encontrar'));
    await mostrarTextos(context, t.apellido, textos);
    if (context.mounted) await irABuscar(context, r.candidatos.first);
  } else {
    await mostrarTextos(context, t.apellido, textos);
  }
}

/// Elegir un DT nuevo (no se puede seguir sin uno).
Future<void> contratarDtDialogo(BuildContext context) async {
  final p = juego.partida!;
  final libres = dtsDisponibles(p);
  final t = await showDialog<T.Tecnico>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text('${p.mio} necesita DT', style: _estiloTitulo),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          for (final t in libres)
            ListTile(
              leading: _avatarDt(t.nombre, t.apellido, radio: 20),
              title: Text('${t.completo}, ${t.edad}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${t.personalidad} · prestigio ${t.prestigio} · ${M.plata(t.sueldo)}/año\n'
                  '${T.resumenCv(t)}'),
              isThreeLine: true,
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    ),
  );
  if (t == null) return;
  final texto = contratar(p, t);
  await juego.guardar();
  if (context.mounted) avisar(context, texto);
}

/// Negociar el sueldo con un jugador. Devuelve el sueldo acordado o null.
Future<double?> negociarSueldo(BuildContext context, Jugador j, double pedido, int anios,
    {double extraMasa = 0, bool obligado = false}) {
  final mi = juego.partida!.mi;
  final aviso = avisoSueldos(mi, extraMasa);
  var oferta = pedido;
  String? respuesta;
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('Contrato de ${j.corto}', style: _estiloTitulo),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pide ${M.plata(pedido)} por año, por $anios temporada${anios > 1 ? 's' : ''}.'),
          if (aviso != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(aviso, style: const TextStyle(color: amarillo, fontSize: 13)),
          ),
          if (!obligado) ...[
            const SizedBox(height: 18),
            Text('Tu oferta: ${M.plata(oferta)}/año', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: oferta,
              min: pedido * 0.6,
              max: pedido,
              divisions: 40,
              onChanged: (v) => setState(() {
                oferta = M.r3(v);
                respuesta = null;
              }),
            ),
            if (respuesta != null) Text(respuesta!, style: const TextStyle(color: rojo)),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Te quedás sin jugadores si se va: renueva por lo que pide.', style: chico),
            ),
        ]),
        actions: [
          if (!obligado) TextButton(onPressed: () => Navigator.pop(c), child: const Text('No')),
          if (!obligado && oferta < pedido)
            OutlinedButton(
              onPressed: () {
                if (M.acepta(oferta, pedido)) {
                  Navigator.pop(c, oferta);
                } else {
                  setState(() => respuesta = 'No acepta. Quiere ${M.plata(pedido)}/año.');
                }
              },
              child: const Text('Ofrecer'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(c, pedido),
            child: Text(obligado ? 'Renovar' : 'Aceptar lo que pide'),
          ),
        ],
      ),
    ),
  );
}

/// Pretemporada: los contratos que se terminaron.
Future<void> renovacionesDialogo(BuildContext context, List<Jugador> vencidos) async {
  final p = juego.partida!;
  final mi = p.mi;
  final tits = M.titulares(mi);
  for (final j in vencidos) {
    if (!context.mounted) return;
    final (pedido, anios) = pedidoRenovacion(p, j, pretemporada: true);
    final quiere = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('📝 Se terminó un contrato', style: _estiloTitulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          FilaJugador(j, detalle: '${j.edad} años · Pot ${j.potencial} · cobraba ${M.plata(M.sueldo(j))}'),
          const SizedBox(height: 8),
          Text('Para seguir pide ${M.plata(pedido)}/año por $anios temporada${anios > 1 ? 's' : ''}.'),
        ]),
        actions: [
          if (mi.plantel.length > 16)
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Que se vaya')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Negociar')),
        ],
      ),
    );
    if (!context.mounted) return;
    double? sueldo;
    if (quiere == true) {
      sueldo = await negociarSueldo(context, j, pedido, anios,
          extraMasa: pedido - M.sueldo(j), obligado: mi.plantel.length <= 16);
    }
    if (sueldo != null) {
      M.firmar(j, sueldo, anios);
      if (context.mounted) avisar(context, '✅ ${j.corto} renovó por $anios temporada${anios > 1 ? 's' : ''}.');
    } else {
      dejarIrVencido(p, j, tits.contains(j));
      if (context.mounted) avisar(context, '${j.corto} se va libre.');
    }
  }
  if (mi.plantel.length < M.plantelMin && context.mounted) {
    await mostrarTextos(context, 'Plantel corto',
        ['Tenés ${mi.plantel.length} jugadores. Fichá en el mercado o subí pibes de la reserva.']);
  }
}

/// Pretemporada: los pibes de la reserva que cumplen 21.
Future<void> pibesDe21Dialogo(BuildContext context, List<Jugador> grandes) async {
  final mi = juego.partida!.mi;
  grandes.sort((a, b) => J.nivel(b).compareTo(J.nivel(a)));
  for (final j in grandes) {
    if (!context.mounted) return;
    final lleno = mi.plantel.length >= M.plantelMax;
    final sube = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('🌱 ${j.corto} cumple ${C.edadLimite}', style: _estiloTitulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          FilaJugador(j, detalle: '${j.edad} años', derecha: Estrellas(C.estrellasPot(j))),
          const SizedBox(height: 8),
          Text(lleno
              ? 'El plantel está lleno (${M.plantelMax}): deja el club.'
              : 'Sube a Primera o deja el club.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(lleno ? 'Seguir' : 'Dejarlo ir')),
          if (!lleno) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Subirlo')),
        ],
      ),
    );
    if (sube == true) {
      C.subir(mi, j);
    } else {
      mi.reserva.remove(j);
    }
  }
}

/// Elegir el entrenamiento. Devuelve ('dt', '') si lo decide el DT, o null si cancela.
Future<(String, String)?> elegirEntrenamientoDialogo(BuildContext context, (String, String)? actual) {
  var tipo = actual?.$1 ?? 'dt';
  var intensidad = actual?.$2 ?? 'normal';
  const textos = {
    'suave': 'Sube poco, llegan frescos',
    'normal': 'Lo de siempre',
    'fuerte': 'Sube más, cansa y hay riesgo de lesiones',
  };
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Entrenamiento', style: titulo),
            const SizedBox(height: 4),
            const Text('Se repite todas las semanas hasta que lo cambies.', style: chico),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('Que decida el DT'),
                selected: tipo == 'dt',
                onSelected: (_) => setState(() => tipo = 'dt'),
              ),
              for (final x in J.tiposEntrenamiento.entries)
                ChoiceChip(
                  label: Text(x.key[0].toUpperCase() + x.key.substring(1)),
                  selected: tipo == x.key,
                  onSelected: (_) => setState(() => tipo = x.key),
                ),
            ]),
            if (tipo != 'dt') ...[
              const SizedBox(height: 6),
              Text(J.tiposEntrenamiento[tipo]!, style: chico),
            ],
            if (tipo != 'dt' && tipo != 'descanso') ...[
              const SizedBox(height: 16),
              const Text('INTENSIDAD', style: tituloChico),
              const SizedBox(height: 8),
              for (final x in textos.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setState(() => intensidad = x.key),
                  leading: Icon(
                      intensidad == x.key ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: intensidad == x.key ? verde : texto2),
                  title: Text(x.key[0].toUpperCase() + x.key.substring(1)),
                  subtitle: Text(x.value),
                ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                    c, tipo == 'dt' ? ('dt', '') : (tipo, tipo == 'descanso' ? 'suave' : intensidad)),
                child: const Text('Listo'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
