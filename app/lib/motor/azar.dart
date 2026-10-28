// Generador de números al azar con semilla de texto, como random.Random
// de Python: la misma semilla da siempre los mismos números (así una
// partida guardada sigue igual al volver a abrirla).
import 'dart:math' as math;

class Azar {
  final math.Random _r;
  double? _gaussGuardado;

  Azar([Object? semilla])
      : _r = semilla == null ? math.Random() : math.Random(_hash('$semilla'));

  /// Hash de un texto en un entero de 31 bits (anda igual en web y en el celu).
  static int _hash(String s) {
    var h = 5381;
    var g = 7;
    for (final c in s.codeUnits) {
      h = (h * 33 + c) % 2147483647;
      g = (g * 131 + c) % 2147483629;
    }
    return (h ^ (g << 3)) & 0x7fffffff;
  }

  double random() => _r.nextDouble();

  /// Entero entre a y b, los dos incluidos.
  int randint(int a, int b) => a + _r.nextInt(b - a + 1);

  double uniform(double a, double b) => a + (b - a) * _r.nextDouble();

  double gauss(double media, double desvio) {
    var z = _gaussGuardado;
    _gaussGuardado = null;
    if (z == null) {
      final u1 = 1 - _r.nextDouble();
      final u2 = _r.nextDouble();
      final rad = math.sqrt(-2 * math.log(u1));
      z = rad * math.cos(2 * math.pi * u2);
      _gaussGuardado = rad * math.sin(2 * math.pi * u2);
    }
    return media + desvio * z;
  }

  double triangular(double bajo, double alto, double moda) {
    final u = _r.nextDouble();
    final c = (moda - bajo) / (alto - bajo);
    if (u > c) {
      return alto - (alto - bajo) * math.sqrt((1 - u) * (1 - c));
    }
    return bajo + (alto - bajo) * math.sqrt(u * c);
  }

  T choice<T>(List<T> lista) => lista[_r.nextInt(lista.length)];

  T choices<T>(List<T> lista, List<num> pesos) {
    final total = pesos.fold<double>(0, (a, b) => a + b);
    var x = _r.nextDouble() * total;
    for (var i = 0; i < lista.length; i++) {
      x -= pesos[i];
      if (x < 0) return lista[i];
    }
    return lista.last;
  }

  void shuffle<T>(List<T> lista) => lista.shuffle(_r);

  List<T> sample<T>(List<T> lista, int k) {
    final copia = List<T>.of(lista)..shuffle(_r);
    return copia.sublist(0, k);
  }
}
