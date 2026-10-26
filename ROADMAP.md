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

## Próximo

### 1. Mercado de pases
Lo que hace falta para que el DT tenga qué pedir.

- Presupuesto del club, según su tamaño, y que se mueva con los
  resultados.
- Valor de mercado y sueldo de cada jugador, según nivel, potencial y edad.
- Comprar y vender entre fechas, o en ventanas de pases entre temporadas
  y a mitad de temporada.
- Los otros clubes también compran y venden, con su lógica.
- Contratos con años de duración y jugadores libres.

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
