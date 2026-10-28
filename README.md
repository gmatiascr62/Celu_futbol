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
3. **Torneo largo**: Liga Profesional, Primera Nacional y Primera B, 20
   clubes cada una, ida y vuelta (38 fechas), con ascensos y descensos.
   Seguís a un
   club, elegís su DT y su entrenamiento, comprás y vendés jugadores, y
   podés jugar temporadas seguidas. Se guarda solo después de cada fecha.
4. **Ver plantel**: la ficha de los 24 jugadores de cada club.

Los equipos se eligen escribiendo parte del nombre (`boca`), con un número
de la lista (`l` la muestra) o con `0` para inventar uno con ratings 1-100.

### En el celular

**Con la app (APK).** GitHub arma el APK solo cada vez que cambia algo en
`main` (pestaña *Actions* → "Armar APK" → la última corrida → *Artifacts*
→ `celu-futbol-apk`). Viene en un zip: adentro está el `.apk` para
instalar. Android avisa que es de origen desconocido porque no está en
Play Store; hay que permitirlo una vez. La partida se guarda dentro de la
app (si se desinstala, se pierde), y cada versión nueva es un APK nuevo
que se instala encima. La app es el mismo juego con una pantalla de
consola, botones para los números y un cuadro para escribir (`main.py`,
con Kivy). Los emojis se cambian por símbolos que la letra sí tiene.

**Con Pydroid 3.**

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
- **Historial y prestigio**: cada DT anota sus clubes, títulos, ascensos,
  descensos y despidos. A fin de temporada el prestigio sube o baja según
  cómo le fue contra lo esperado. Los grandes buscan DT de prestigio, y si
  el tuyo la rompe, un club más grande te lo puede querer llevar: lo dejás
  ir (te pagan la rescisión), le subís el sueldo o lo retenés.
- **Opina**: en "11) Mi DT" le podés pedir que juegue con otra formación.
  Te hace caso pero no le gusta; si pierden seguido, el arriesgado o el
  impulsivo se planta. Si elegís vos el entrenamiento, te dice qué haría
  él, y se queja si el plantel está fundido o vienen mal.
- **Propone jugadores**: cuando pide un refuerzo, nombra hasta tres
  jugadores de otros clubes o libres, que mejoren al titular y que el club
  pueda pagar, elegidos según su personalidad (el conservador prefiere
  veteranos, el arriesgado los de más potencial). Un DT de más prestigio
  conoce más clubes. Con "Andá a buscar" vas directo a negociar; la lista
  queda en el mercado como "📋 Pedidos del DT". Si traés justo al que te
  pidió, se pone más contento.

### Hinchada y medios

- Cada club tiene una hinchada de 0 a 100 que sube y baja con los
  resultados; en los clásicos (Boca-River, Racing-Independiente,
  Central-Newell's, Estudiantes-Gimnasia, San Lorenzo-Huracán y otros)
  pesa más de dos veces. También se mueve al vender a una figura o traer
  una, al salir campeón, ascender o descender.
- Se nota en la plata (entradas y socios, hasta un 10% de los ingresos),
  en la localía (hasta un 2%) y en la presión sobre el DT. Los medios
  pesan más en los clubes grandes.
- Noticias: clásicos, banderazos y silbidos.

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

- **Tres categorías** de 20 clubes que juegan en paralelo: la Liga
  Profesional (los 20 más fuertes del modelo), la Primera Nacional (los 12
  del modelo que no entran en Primera y los 8 más pesados del ascenso) y
  la Primera B (el resto del ascenso). Al final de cada temporada, entre
  cada par de categorías bajan 2 y suben 2. Subir multiplica los ingresos
  por 1,5 y bajar los divide. El reparto está en `ascenso.json` y se
  puede cambiar.
- No hay resultados reales del ascenso para entrenar el modelo, así que
  la fuerza de esos clubes se estima con su peso histórico (de 1 a 5). Un
  club de peso 5 queda como los recién ascendidos reales: medio punto por
  debajo de la media de la Primera en la escala del modelo. La Primera B
  tiene un ajuste para abajo.
- Podés seguir a cualquier club de las tres categorías. La tabla, los
  goleadores y los resultados muestran tu división; las opciones 4 y 5
  preguntan cuál querés ver.

- **Entrenamiento entre fechas**: completo, ataque, defensa, físico o
  descanso, con intensidad suave, normal o fuerte. El nivel sube hacia el
  potencial, más rápido en los jóvenes. Entrenar fuerte rinde más, pero
  cansa y puede traer lesiones de 1 a 4 fechas. El de tu club lo elegís vos
  o lo decide el DT.
- **Temporadas**: al terminar el torneo, todos cumplen un año. Desde los 31
  empiezan a bajar y desde los 34 se pueden retirar; el plantel se renueva
  con los pibes de la reserva. Hay un historial de campeones.
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
  llega a un club no se vuelve a vender en la misma ventana. Por sus tres
  figuras piden el doble, y los que tienen la caja llena traen refuerzos
  del exterior.

### Instalaciones y cuerpo técnico (opción 12)

- **Instalaciones**, de nivel 1 a 5: predio (los jugadores mejoran más
  rápido), centro médico (menos lesiones y más cortas), estadio (10% más
  de ingresos por nivel) e inferiores (mejores juveniles). Mejorar cuesta
  plata, la obra tarda unas fechas y cada nivel tiene mantenimiento.
- **Cuerpo técnico**, de 1 a 5 estrellas: preparador físico (resistencia y
  recuperación), ayudantes de ataque y de defensa, entrenador de arqueros
  y coordinador de inferiores. Cobran sueldo y se contratan de una lista
  que se renueva cada temporada.
- Un club promedio (nivel 2,5) entrena igual que antes; la diferencia la
  hace quién invierte más. Cada club arranca según su tamaño, y los de la
  computadora invierten cuando les sobra plata.
- El DT te puede pedir cuerpo técnico en las reuniones, y la promesa se
  revisa como la de un refuerzo.

### Reserva (opción 13)

- Los pibes de 16 a 20 años de las inferiores, aparte del plantel. Cada
  pretemporada llegan 2 a 4 nuevos (más con mejores inferiores) y
  entrenan en la reserva sin jugar.
- Su potencial no se ve exacto: el club lo estima en estrellas (★★★☆☆),
  y cuanto mejor el coordinador de inferiores, menos se equivoca. Uno de
  cada diez tiene potencial de crack.
- Los subís a Primera cuando quieras (firman 3 años), los dejás ir, o los
  ofrecés afuera en las ventanas de pases: un pibe con potencial vale
  mucho. También llegan ofertas del exterior por los mejores.
- Al cumplir 21 hay que decidir: suben o se van. El DT te avisa cuando uno
  está para jugar.
- Ya no sube un juvenil automático por cada retirado: el plantel se
  renueva con la reserva. Los clubes de la computadora suben a los
  mejores hasta tener 24.

### Contratos

- Cada jugador tiene un contrato de 1 a 4 temporadas (los jóvenes firman
  por más años) con un sueldo pactado.
- Al fichar a alguien, primero arreglás con el club y después con el
  jugador, que pide un sueldo. Podés aceptar, ofrecerle otro (acepta desde
  el 90% de lo que pide) o dejarlo. Si no hay acuerdo, se cae el pase.
- En la pretemporada, a los que se les terminó el contrato los renovás o
  se van libres. También podés renovar antes de tiempo desde el mercado
  (opción 7, Contratos).
- Con un año de contrato un jugador vale menos, porque su club lo puede
  perder gratis. Liberar a alguien cuesta la mitad de lo que le queda por
  cobrar.
- Los otros clubes renuevan a los que les sirven; los demás quedan libres
  y otro club los puede fichar.
- El DT avisa cuando a un titular le queda un año de contrato, y pide
  vender a los que no usa y cobran mucho.

## Archivos

| Archivo | Qué es |
|---|---|
| `main.py` | La app para Android (Kivy): la pantalla del juego. |
| `buildozer.spec` | Cómo se arma el APK (lo usa GitHub Actions). |
| `simulador_futbol.py` | El juego: partido, DT, cuadrangular, torneo largo y menú. |
| `jugadores.py` | Jugadores, posiciones, formaciones, planteles, entrenamiento y temporadas. |
| `mercado.py` | Valores, sueldos, finanzas de los clubes y mercado de pases. |
| `tecnicos.py` | Los DT como personas: ánimo, reuniones, promesas y despidos. |
| `club.py` | Instalaciones, obras y cuerpo técnico de los clubes. |
| `modelo_poisson.json` | El modelo de goles entrenado con la liga argentina. |
| `dt_ia.json` | Lo que aprendieron los DT. |
| `planteles.json` | Los planteles de los 60 clubes. |
| `ascenso.json` | Cómo se reparten los clubes en las divisiones y el peso histórico de los del ascenso. |
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
