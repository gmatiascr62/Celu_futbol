String? _guardada;

Future<String?> leerPartida() async => _guardada;

Future<void> escribirPartida(String datos) async => _guardada = datos;

Future<void> borrarPartida() async => _guardada = null;
