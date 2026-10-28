# Celu Fútbol para Android

La app de Flutter. El juego está reescrito en Dart en `lib/motor/` (mismas
cuentas que la versión de Python) y las pantallas están en `lib/ui/`. Los
datos (modelo de goles, planteles, divisiones y lo que aprendieron los DT)
son los JSON de la raíz del repo: `tool/copiar_datos.sh` los copia a
`assets/datos/` antes de armar la app.

- `flutter test`: pruebas del motor (goles, empates, guardado, temporadas).
- `dart run tool/calibrar_partidos.dart`: goles, empates y localía por división.
- `dart run tool/temporadas.dart 3 "Boca Juniors"`: varias temporadas seguidas.

El APK lo arma GitHub Actions (`.github/workflows/apk.yml`).
