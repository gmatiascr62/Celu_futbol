#!/bin/sh
# Copia los datos del juego (los mismos de la versión de Python) a la app.
# Se corre antes de armar el APK: tool/copiar_datos.sh
cd "$(dirname "$0")/.." || exit 1
mkdir -p assets/datos
for f in modelo_poisson.json ascenso.json planteles.json dt_ia.json; do
  cp "../$f" assets/datos/
done
