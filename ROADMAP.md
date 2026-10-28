# Roadmap

La idea de fondo: un juego de manager donde sos el dueño del club. El DT
es tu empleado: pide, opina, se enoja y puede renunciar. Las decisiones de
plata, compras, ventas y si sigue o no en el cargo son tuyas.

## Hecho

- **0.2**: modelo de Poisson con Dixon-Coles entrenado con la liga
  argentina.
- **0.3**: partido minuto a minuto y DT que calcula la mejor táctica, con
  personalidades.
- **0.4**: DT que aprende solo (aprendizaje por refuerzo).
- **0.5**: cuadrangular ida y vuelta.
- **0.6**: energía y cambios.
- **0.7**: planteles de 24 jugadores ficticios, titulares y cambios con
  nombre, goleadores.
- **0.8**: torneo largo con los 32 clubes; formaciones con efecto propio.
- **0.9**: entrenamiento entre fechas y lesiones.
- **1.0**: partida guardada y temporadas seguidas (edad, retiros y
  juveniles).
- **1.1**: mercado de pases: valores, sueldos, caja e ingresos, dos
  ventanas por temporada, ofertas (también del exterior), libres y lo que
  hacen los otros clubes.
- **1.2**: DT con nombre, prestigio, sueldo, contrato y ánimo; reuniones
  con promesas, ultimátums y renuncias; despidos en los otros clubes.
- **1.3**: contratos con sueldo pactado, negociación al fichar y renovar,
  vencimientos y jugadores que se van libres; refuerzos del exterior para
  los clubes grandes; el DT avisa de contratos y de los que no usa.
- **1.4**: ascenso: Primera Nacional con 32 clubes reales, en paralelo
  con la Liga Profesional; bajan 2 y suben 2.
- **1.5**: instalaciones (predio, centro médico, estadio, inferiores) y
  cuerpo técnico (preparador físico, ayudantes, arqueros, inferiores).
- **1.6**: DT completo: historial y prestigio, ofertas de otros clubes por
  tu DT, opina de la formación y el entrenamiento, propone jugadores
  concretos; hinchada, clásicos y medios.
- **1.7**: tres divisiones de 20 clubes (Liga Profesional, Primera
  Nacional y Primera B), torneos de 38 fechas.

## Próximo

Orden sugerido:

1. **Reserva y juveniles** (punto 6, segunda parte).
2. **Fundar un club** (punto 5): queda para más adelante.
3. **Que el DT hable con IA** (punto 3), opcional.
4. Lo que falta del ascenso (punto 4), si hace falta.

Las ideas del final se pueden ir metiendo en el medio.

### 1. Mercado de pases: lo que falta
Ya están el mercado (1.1) y los contratos (1.3). Queda:

- Que los ingresos se muevan con los resultados y la cantidad de socios.
- Ventas al exterior también de los clubes de la computadora, con
  reemplazos para que la liga no pierda nivel.
- Préstamos.

### 2. DT con estado de ánimo
Hecho en la 1.2 y la 1.6: ánimo, reuniones, promesas, historial,
prestigio, opiniones, jugadores que propone, hinchada y medios.

### 3. Que el DT hable con IA (opcional)
Ya se puede hacer, porque las reuniones del punto 2 están armadas: cada
una tiene un tema, las opciones y lo que cambia en el ánimo del DT. Un
modelo de lenguaje (Gemini con su nivel gratis, o Claude) redactaría lo
que dice el DT con su personalidad, y entendería lo que le escribís
libremente para elegir cuál de las opciones es.

- El código pone las reglas: el modelo solo pone las palabras y no puede
  inventar plata ni jugadores. Contesta en un formato fijo que el
  programa valida.
- Sin internet o sin clave, vuelve a las frases armadas del punto 2.
- Las decisiones dentro del partido (táctica, cambios, titulares) siguen
  siendo del código: son cientos por fecha, el nivel gratis no alcanza, y
  el DT entrenado decide mejor que un modelo de lenguaje.

### 4. El ascenso: lo que falta
Ya están (1.4 y 1.7): Liga Profesional, Primera Nacional y Primera B, 20
clubes cada una, bajan 2 y suben 2 entre cada par. Queda, si hace falta:

- Formatos más fieles: en la realidad las categorías tienen más clubes,
  zonas, finales y reducidos.
- Volver a sumar los 4 clubes que quedaron afuera (Colegiales, Central
  Norte, Güemes y Gimnasia y Tiro) si se agrega otra categoría.
- Promedios para el descenso de Primera.
- Entrenar el modelo del ascenso si aparece una fuente de resultados.

### 5. Fundar un club
Arrancar de cero con un club propio y subirlo categoría por categoría.
El ascenso, el mercado de pases y los DT ya están, así que se puede
hacer cuando quieras.

- **Identidad**: nombre, apodo, ciudad o barrio, colores y nombre de la
  cancha. El nombre aparece en el relato y en las tablas como cualquier
  otro club.
- **Dónde arranca**: en la Primera B, la categoría más baja del juego, en
  lugar de uno de sus clubes.
- **El primer plantel**: jugadores libres y pibes del barrio, flojos y
  baratos, con algunas joyas de potencial alto escondidas. Una parte se
  arma en una "prueba de jugadores" donde elegís a quiénes fichar.
- **Plata**: un presupuesto inicial chico. Después crece con los
  resultados, los ascensos, la cantidad de socios y la venta de
  jugadores. Más adelante se puede invertir en la cancha, en las
  divisiones inferiores (mejores juveniles) o en el predio de
  entrenamiento (entrenan mejor).
- **El primer DT**: lo elegís de la lista de DT sin club, como ya se hace
  cuando renuncia o lo echás, pero solo vas a poder pagar los de poco
  prestigio.
- **Partida propia**: la temporada se guarda igual que ahora, con el
  historial del club desde su fundación: ascensos, títulos, goleadores
  históricos e ídolos.

### 6. Instalaciones, cuerpo técnico y juveniles
En qué gastar la plata del club para que los jugadores mejoren más.
Los efectos se calibran para que un club promedio quede como ahora: lo
que ya está ajustado (goles, empates, nivel de la liga) no cambia, y la
diferencia la marca quién invierte más.

**Primera parte: instalaciones y cuerpo técnico** (hecho, 1.5)

- **Instalaciones**, cada una de nivel 1 a 5. Mejorar cuesta plata, la
  obra tarda unas fechas y cada nivel tiene un mantenimiento por año:
  - Predio de entrenamiento: los jugadores mejoran más rápido entrenando.
  - Centro médico: menos lesiones, y las que hay duran menos.
  - Estadio: más socios y entradas, más ingresos.
  - Inferiores: mejores juveniles, y más.
- Cada club arranca con niveles según su tamaño (Boca y River con 4, un
  club chico del ascenso con 1 o 2). Los clubes de la computadora también
  invierten: la plata que hoy se les pierde por el tope de caja va a
  instalaciones.
- **Cuerpo técnico**, que se contrata de una lista; cada uno tiene un
  nivel y cuanto mejor, más cobra:
  - Preparador físico: más resistencia y mejor recuperación entre fechas.
  - Ayudante de ataque y ayudante de defensa: mejoran esas
    características cuando se entrenan.
  - Entrenador de arqueros: mejora la atajada.
  - Coordinador de inferiores: desarrolla mejor a los pibes.
- El DT puede pedirlos en las reuniones.

**Segunda parte: reserva y juveniles**

- Una reserva aparte del plantel. Cada pretemporada llegan pibes de 16 a
  18 años, más y mejores según las inferiores y el coordinador.
- Crecen en la reserva sin ocupar lugar en el plantel. Vos decidís cuándo
  subirlos a Primera, o los liberás. El DT avisa cuando uno está listo.
- El potencial de los pibes no se ve exacto, se ve en estrellas
  (★★★☆☆). Un buen coordinador lo afina. Así alguno sorprende y alguno
  decepciona.
- Vender juveniles al exterior, la forma de hacer plata de un club chico.

## Ideas para más adelante

- **El DT juega según la tabla**: en la última fecha sabe si le alcanza el
  empate o necesita ganar por dos.
- **Rojas y penales** que cambien el partido: un expulsado baja el
  rendimiento del equipo.
- **Tarjetas por jugador**: el DT saca al amonestado y hay suspensiones por
  acumulación de amarillas.
- **Copa** con eliminación directa, alargue y penales.
- **Simular el torneo 1000 veces** para ver las chances de campeón de cada
  club.
- **Otras ligas**: entrenar el modelo con la Premier, La Liga o el
  Brasileirão.
- **Estadísticas**: asistencias, vallas invictas, figura del partido.
