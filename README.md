# Celu Fútbol

Simulador de fútbol argentino para jugar en la terminal, pensado para el
celular (Pydroid 3). Los partidos se juegan minuto a minuto con un modelo
estadístico entrenado con resultados reales de la Liga Profesional, y cada
equipo tiene un DT con IA que aprendió solo qué táctica conviene en cada
momento.

No necesita librerías externas para jugar: solo Python 3.10 o más nuevo.

## Cómo jugar

```
python simulador_futbol.py
```

Menú principal:

1. **Partido**: dos equipos, con relato completo. Después se puede repetir,
   simular 1000 partidos para ver las probabilidades o cambiar los DT.
2. **Cuadrangular**: 4 equipos, todos contra todos, ida y vuelta.
3. **Torneo largo**: los 32 clubes, ida y vuelta (62 fechas). Seguís a un
   club, elegís su DT y su entrenamiento, comprás y vendés jugadores, y
   podés jugar temporadas seguidas. Se guarda solo después de cada fecha.
4. **Ver plantel**: la ficha de los 24 jugadores de cada club.

Los equipos se eligen escribiendo parte del nombre (`boca`), con un número
de la lista (`l` la muestra) o con `0` para inventar uno con ratings 1-100.

### En el celular

Lo cómodo es tener un lanzador fuera del repo que baje la última versión de
`main` como zip y ejecute el simulador. El lanzador define la variable de
entorno `FUTBOL_PARTIDAS` con su propia carpeta, así la partida guardada
no se borra cuando se baja una versión nueva.

## Cómo funciona

### El partido

- **Modelo de goles**: regresión de Poisson con corrección Dixon-Coles,
  entrenada con unos 1500 partidos reales (`entrenar_modelo.py`). Cada club
  tiene un ataque y una defensa. La liga simulada da unos 2 goles por
  partido, 41% de victorias locales y 31% de empates, como la real.
- **Minuto a minuto**: cada minuto cada equipo tiene una chance de gol que
  depende de los 11 que están en cancha, la formación, la táctica de los
  dos equipos y el cansancio.
- **Tácticas**: equilibrada, ofensiva, defensiva, contraataque, presión y
  todo al ataque (esta solo desde el minuto 70). Defenderse cierra el
  partido y le sirve al más débil; atacar lo abre y le sirve al más fuerte.
  El contraataque castiga al que se adelanta.
- **Energía**: cada jugador se cansa según la táctica y su resistencia. Un
  equipo cansado ataca y defiende peor. 5 cambios en 3 ventanas más el
  entretiempo.

### Los DT

- **Personalidades**: equilibrado, conservador (valora más el empate),
  arriesgado (sale a ganar) e impulsivo (cambia mucho y a veces se
  equivoca). También se puede jugar sin DT, con táctica fija.
- **IA entrenada** (`dt_ia.json`): aprendizaje por refuerzo. En cada
  situación (minuto, resultado, fuerza de los equipos, táctica del rival y
  energía) probaron el resto del partido con cada táctica, con la misma
  suerte, y anotaron cuántos puntos sacaba cada una. Se entrenó con más de
  12 millones de partidos simulados. Le gana al DT calculador (1,375 contra
  1,312 puntos por partido). Si no está el archivo, los DT usan el modo
  calculador.
- **Alineación y cambios**: el DT prueba cada formación (4-4-2, 4-3-3,
  4-2-3-1, 5-3-2 y 3-5-2) contra el rival y elige la que más puntos le
  da. Hace los cambios según el cansancio y el resultado: perdiendo mete
  delanteros, ganando mete defensores.

### El DT de tu club (torneo largo)

- Cada DT tiene nombre, edad, personalidad, prestigio, sueldo y contrato.
- Su ánimo son tres números de 0 a 100 (opción 11): **satisfacción** con
  vos, **confianza** en el plantel (sube y baja con los resultados) y
  **presión** (según lo que se espera del club y la racha).
- Cada 4 o 5 fechas, y cuando pasa algo, te pide una reunión: refuerzos
  para el puesto más flojo, rachas buenas y malas, un pibe que está para
  jugar, la venta de un titular, ultimátums, la renovación del contrato.
  Le contestás eligiendo una respuesta y cada una cambia su ánimo.
- Las promesas se anotan: si le prometés un refuerzo y cierra el mercado
  sin que llegue, se enoja mucho más.
- Si la satisfacción llega muy abajo, renuncia. También lo podés echar
  (pagando lo que le queda de contrato) y elegir otro de los DT libres.
- La confianza mueve hasta un 3% los goles del equipo.
- A los DT de los otros clubes los echan si la presión es insoportable, y
  te enterás por las noticias.

### Los jugadores

- 24 jugadores ficticios por club en 10 posiciones (ARQ, DFC, LD, LI, MCD,
  MC, MCO, ED, EI, DC). Tienen ataque, creación, defensa, atajada,
  resistencia, edad, nivel y potencial, y algunos juegan en una segunda
  posición. Fuera de su puesto rinden menos.
- Los planteles están calibrados para que el equipo titular tenga la misma
  fuerza que el modelo aprendió del club real. Se guardan en
  `planteles.json`; si se borra, se generan otros.
- Los nombres mezclan apellidos como en Argentina: mayoría italianos y
  españoles, y también vascos, polacos, alemanes, franceses, croatas,
  armenios y sirio-libaneses. No salen jugadores famosos reales.

### Torneo largo y temporadas

- **Entrenamiento entre fechas**: completo, ataque, defensa, físico o
  descanso, con intensidad suave, normal o fuerte. El nivel sube hacia el
  potencial, más rápido en los jóvenes. Entrenar fuerte rinde más, pero
  cansa y puede traer lesiones de 1 a 4 fechas. El de tu club lo elegís vos
  o lo decide el DT.
- **Temporadas**: al terminar el torneo, todos cumplen un año. Desde los 31
  empiezan a bajar, desde los 34 se pueden retirar, y por cada retirado sube
  un juvenil de la cantera. Hay un historial de campeones.
- **Partida guardada**: `partida.json`, después de cada fecha.

### Mercado de pases

- La plata está en millones de dólares. Cada jugador tiene un valor según
  su nivel, su edad y su potencial, y cobra un sueldo del 18% de ese valor
  por año.
- Cada club tiene caja e ingresos anuales, según su tamaño. Los sueldos se
  pagan fecha a fecha, y a fin de temporada hay premios según el puesto.
- El mercado abre en la pretemporada y a mitad del torneo (opción 10).
  Podés buscar jugadores de otros clubes y ofertar (el club acepta, pide
  más o rechaza), fichar libres, vender, liberar (con indemnización) y ver
  todos los movimientos.
- Te llegan ofertas por tus jugadores, también de clubes del exterior por
  los más caros.
- Los clubes de la computadora compran lo que más les falta, venden si les
  pagan bien y fichan libres para completar el plantel. Un jugador que
  llega a un club no se vuelve a vender en la misma ventana.

## Archivos

| Archivo | Qué es |
|---|---|
| `simulador_futbol.py` | El juego: partido, DT, cuadrangular, torneo largo y menú. |
| `jugadores.py` | Jugadores, posiciones, formaciones, planteles, entrenamiento y temporadas. |
| `mercado.py` | Valores, sueldos, finanzas de los clubes y mercado de pases. |
| `tecnicos.py` | Los DT como personas: ánimo, reuniones, promesas y despidos. |
| `modelo_poisson.json` | El modelo de goles entrenado con la liga argentina. |
| `dt_ia.json` | Lo que aprendieron los DT. |
| `planteles.json` | Los planteles de los 32 clubes. |
| `entrenar_modelo.py` | Reentrena el modelo de goles con datos de football-data.co.uk. |
| `entrenar_dt.py` | Entrena a los DT. |

## Reentrenar

Modelo de goles (necesita `pip install pandas numpy scipy`):

```
python entrenar_modelo.py            # baja la liga argentina
python entrenar_modelo.py ARG.csv    # o con un CSV local
```

DT (sin librerías; si ya existe `dt_ia.json`, suma experiencia):

```
python entrenar_dt.py 1000           # pruebas por situación, unos 17 minutos
```

Si cambian los equipos del modelo, conviene borrar `planteles.json` para que
se generen los planteles de los clubes nuevos.

Ver [ROADMAP.md](ROADMAP.md) para lo que viene.
