import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _archivo() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/partida.json');
}

Future<String?> leerPartida() async {
  final f = await _archivo();
  return await f.exists() ? f.readAsString() : null;
}

/// Escribe primero a un temporal: si se corta a la mitad, queda la anterior.
Future<void> escribirPartida(String datos) async {
  final f = await _archivo();
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(datos, flush: true);
  await tmp.rename(f.path);
}

Future<void> borrarPartida() async {
  final f = await _archivo();
  if (await f.exists()) await f.delete();
}
