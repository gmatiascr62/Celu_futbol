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

## Próximo

### 1. Mercado de pases: lo que falta
La primera parte ya está (1.1). Queda:

- Contratos con años de duración: renovaciones, jugadores que se van
  libres y pretensiones de sueldo que se negocian.
- Que los ingresos se muevan con los resultados y la cantidad de socios.
- Ventas al exterior también de los clubes de la computadora, con
  reemplazos para que la liga no pierda nivel.
- Préstamos.

### 2. DT con estado de ánimo
El "cerebro" del DT en código, sin internet.

- Satisfacción con la dirigencia, confianza en el plantel y presión por
  resultados, en números que cambian con los partidos y con lo que le
  respondés.
- Entre fechas te habla: pide refuerzos según lo que le falta al equipo,
  se queja de una racha mala, quiere subir a un pibe de la cantera.
- Le contestás desde un menú, y él reacciona según cómo lo tratás.
- Si la satisfacción llega muy abajo, renuncia. También lo podés echar y
  contratar otro, con otra personalidad.
- Frases armadas con muchas variantes.

### 3. Que el DT hable con IA (opcional)
Sobre el punto 2, un modelo de lenguaje (Gemini con su nivel gratis, o
Claude) redacta lo que dice el DT y entiende lo que le escribís libremente.

- El código pone las reglas: el modelo solo pone las palabras y no puede
  inventar plata ni jugadores. Contesta en un formato fijo que el
  programa valida.
- Sin internet o sin clave, vuelve a las frases armadas del punto 2.

### 4. El ascenso: todas las divisiones
Que exista el fútbol argentino entero, con ascensos y descensos entre
categorías, y poder agarrar un club chico y llevarlo a Primera.

**Divisiones**, de a una por vez y empezando por arriba:

1. Liga Profesional (la que ya está).
2. Primera Nacional.
3. Primera B Metropolitana y Torneo Federal A (el tercer escalón está
   dividido entre los clubes directamente afiliados a la AFA y los del
   interior).
4. Primera C, Primera D y el Regional Amateur, si tiene sentido llegar
   tan abajo.

**Formatos.** La AFA los cambia casi todos los años: cantidad de equipos,
zonas, reducidos, cuántos suben y cuántos bajan. Por eso cada división se
define con datos (equipos, zonas, ida y vuelta o no, cuántos ascienden
directo, cuántos van al reducido, cuántos descienden) y el código arma el
torneo a partir de eso. Así, adaptar un formato nuevo es cambiar un número
y no reprogramar.

- **Zonas** (como la Primera Nacional, con dos de 18): el fixture se arma
  por zona y hay una final entre los ganadores.
- **Reducido**: eliminación directa entre los que terminan del 2° al 8°,
  con partido único o ida y vuelta, alargue y penales. Sirve también para la
  copa que está en las ideas de más abajo.
- **Promedios**: en Argentina el descenso de Primera se define por los
  puntos promedio de las últimas tres temporadas, además de la tabla anual.
  El historial ya guarda las temporadas, así que alcanza con anotar los
  puntos de cada club por temporada.

**La fuerza de los clubes de ascenso.** football-data.co.uk solo tiene la
Primera, así que no hay resultados para entrenar el modelo de las otras
categorías. La idea es estimarla:

- Los recién ascendidos dan la diferencia entre categorías. Los cuatro
  que subieron hace poco (Estudiantes de Río Cuarto, Gimnasia de Mendoza,
  San Martín de San Juan y Aldosivi) están en promedio medio punto por
  debajo de la media de la Primera en la escala del modelo (ataque menos
  defensa). Esos son los mejores de la Primera Nacional, así que el
  promedio de esa categoría quedaría un poco más abajo.
- Dentro de cada división, la fuerza de cada club se reparte con criterio:
  los históricos y los que pelearon arriba la última temporada, más
  fuertes.
- Si aparece una fuente de resultados de esas categorías, se entrena el
  modelo con ella y se reemplaza la estimación.

**Lo que hay que preparar en el código:**

- Que el torneo largo no dependa de "los clubes del modelo", sino de una
  lista de divisiones con sus clubes y su formato.
- La partida guarda todas las divisiones. Las de abajo se simulan rápido,
  sin relato, como hoy los partidos que no son del club que seguís.
- Al cerrar la temporada: ascensos y descensos, y los clubes cambian de
  división con su plantel.
- El presupuesto del mercado de pases depende de la división, y subir o
  bajar lo cambia. Un plantel de ascenso que llega a Primera necesita
  refuerzos, y ahí el mercado y el DT se juntan.
- El DT con IA ya entiende "equipo más débil contra más fuerte", así que
  sirve para cualquier categoría sin reentrenar.

**Para decidir antes de arrancar:**

- Hasta qué categoría bajar, porque cada división agrega unos 20 a 38
  clubes y muchos partidos por temporada.
- Si se juega con los nombres reales de los clubes (como ahora en Primera)
  o con clubes inventados en las categorías de abajo.
- Formato de cada categoría: el de este año o uno fijo que no cambie.

### 5. Fundar un club
Arrancar de cero con un club propio y subirlo categoría por categoría.
Necesita el ascenso (punto 4) y el mercado de pases (punto 1).

- **Identidad**: nombre, apodo, ciudad o barrio, colores y nombre de la
  cancha. El nombre aparece en el relato y en las tablas como cualquier
  otro club.
- **Dónde arranca**: en la categoría más baja que tenga el juego. Si es
  del interior, por el Regional Amateur y el Federal; si es de Buenos
  Aires, por la Primera D o la C. El club nuevo entra en lugar de uno de
  esa categoría, o se agrega uno más si el formato lo permite.
- **El primer plantel**: jugadores libres y pibes del barrio, flojos y
  baratos, con algunas joyas de potencial alto escondidas. Una parte se
  arma en una "prueba de jugadores" donde elegís a quiénes fichar.
- **Plata**: un presupuesto inicial chico. Después crece con los
  resultados, los ascensos, la cantidad de socios y la venta de
  jugadores. Más adelante se puede invertir en la cancha, en las
  divisiones inferiores (mejores juveniles) o en el predio de
  entrenamiento (entrenan mejor).
- **El primer DT**: lo elegís vos de una lista de DT sin club, cada uno
  con su personalidad, su pretensión de sueldo y su humor (punto 2).
- **Partida propia**: la temporada se guarda igual que ahora, con el
  historial del club desde su fundación: ascensos, títulos, goleadores
  históricos e ídolos.

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
