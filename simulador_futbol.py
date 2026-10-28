#!/usr/bin/env python3
"""
SIMULADOR DE FÚTBOL — 1.9
El partido se juega minuto a minuto con un modelo de Poisson entrenado con
partidos reales (ver entrenar_modelo.py). Cada equipo puede tener un DT con
IA que cambia la táctica según el resultado y el tiempo que queda.

Si existe dt_ia.json (ver entrenar_dt.py), los DTs usan lo que aprendieron
jugando cientos de miles de partidos. Si no, usan el DT calculador.

Cada club tiene un plantel de 24 jugadores ficticios (ver jugadores.py),
que se guarda en planteles.json. El DT elige formación y titulares según
el rival, y hace los cambios según el cansancio y el resultado.

En el torneo largo, entre fecha y fecha cada club entrena: los jugadores
suben de nivel hacia su potencial (más rápido los jóvenes). El de tu club
lo elegís vos o lo decide el DT; entrenar fuerte rinde más, pero cansa y
puede traer lesiones.

El torneo largo se guarda solo después de cada fecha (partida.json) y se
pueden jugar temporadas seguidas: los jugadores cumplen años, los veteranos
bajan y se retiran, y suben juveniles de la cantera.

Hay mercado de pases (ver mercado.py): cada club tiene caja, ingresos y
sueldos, y el mercado abre en la pretemporada y a mitad del torneo.

Los DT son personas (ver tecnicos.py): tienen nombre, prestigio, sueldo,
contrato y ánimo. El de tu club te pide reuniones, se acuerda de lo que le
prometiste y puede renunciar; a los de los otros clubes los echan.

El torneo largo tiene tres categorías de 20 clubes: la Liga Profesional, la
Primera Nacional y la Primera B (ver ascenso.json). Entre cada par de
categorías bajan 2 y suben 2.

Cada club tiene instalaciones y cuerpo técnico (ver club.py), que hacen que
los jugadores mejoren más rápido, se lesionen menos y salgan mejores pibes.

Los DT tienen historial y prestigio que se mueve, opinan si les imponés la
formación o el entrenamiento, y proponen jugadores concretos. Cada club
tiene una hinchada que se nota en la plata, la localía y la presión.

Cada club tiene una reserva con los pibes de las inferiores: llegan cada
pretemporada, su potencial se ve en estrellas, y se suben a Primera o se
venden afuera.

Uso:
    python simulador_futbol.py                     # usa modelo_poisson.json
    python simulador_futbol.py otro_modelo.json    # usa otro modelo

No requiere librerías externas. Si no encuentra el modelo, funciona igual
con equipos inventados y valores promedio.
"""
import json
import math
import os
import random
import sys
import textwrap
from collections import Counter
from dataclasses import asdict, dataclass, field

import jugadores as J
import club as C
import mercado as M
import tecnicos as T

ANCHO = 40  # ancho de las líneas, pensado para pantalla de celular

# Valores por defecto si no hay modelo entrenado
MODELO_VACIO = {"base": math.log(1.15), "localia": math.log(1.25),
                "rho": -0.06, "equipos": {}}

# ---------------------------------------------------------------- tácticas
# propio: multiplica los goles que esperás meter
# rival:  multiplica los goles que esperás recibir
# posesion: puntos de posesión que suma
# Defensiva baja los goles de los dos (partido cerrado, le sirve al débil).
# Ofensiva sube los goles de los dos (partido abierto, le sirve al fuerte).
TACTICAS = {
    "equilibrada":  {"propio": 1.00, "rival": 1.00, "posesion": 0},
    "ofensiva":     {"propio": 1.15, "rival": 1.08, "posesion": 4},
    "defensiva":    {"propio": 0.85, "rival": 0.85, "posesion": -6},
    "contraataque": {"propio": 0.95, "rival": 0.93, "posesion": -8},
    "presion":      {"propio": 1.10, "rival": 1.03, "posesion": 6},
    "todo_al_ataque": {"propio": 1.40, "rival": 1.35, "posesion": 8},
}
BONUS_CONTRA = 1.15                  # el contraataque castiga al que se adelanta
TACTICAS_ADELANTADAS = ("ofensiva", "presion", "todo_al_ataque")
TACTICAS_INICIALES = [t for t in TACTICAS if t != "todo_al_ataque"]
MINUTO_TODO_AL_ATAQUE = 70           # antes de esto no se puede jugar así


def disponibles(minuto):
    """Tácticas que un DT puede elegir en ese minuto."""
    if minuto >= MINUTO_TODO_AL_ATAQUE:
        return list(TACTICAS)
    return TACTICAS_INICIALES

# ---------------------------------------------------------------- DTs
# ganar / empatar: cuánto valora cada resultado (lo normal es 3 y 1)
# umbral: cuánto mejor tiene que ser una táctica para que la cambie
# error:  cuánto se equivoca al evaluar, proporcional a lo que está en
#         juego (el impulsivo decide "a ojo")
PERSONALIDADES = {
    "equilibrado": {"ganar": 3.0, "empatar": 1.0, "umbral": 0.04, "error": 0.15,
                    "desc": "decide con la cabeza fría"},
    "conservador": {"ganar": 3.0, "empatar": 1.6, "umbral": 0.06, "error": 0.15,
                    "desc": "un punto siempre suma"},
    "arriesgado":  {"ganar": 3.6, "empatar": 0.6, "umbral": 0.03, "error": 0.25,
                    "desc": "sale a ganar siempre"},
    "impulsivo":   {"ganar": 3.0, "empatar": 1.0, "umbral": 0.02, "error": 0.80,
                    "desc": "cambia mucho y a veces se equivoca"},
}
TRAMOS = (1, 15, 30, 46, 60, 70, 78, 85)   # momentos en que decide el DT
MOMENTOS_DECISION = TRAMOS[1:]             # (el 1 es la táctica inicial)
# además decide 2 minutos después de cada gol
MIN_ENTRE_CAMBIOS = 8
# Con el partido empatado los equipos arriesgan menos (corrige la cantidad
# de empates, igual que el rho de Dixon-Coles en el modelo).
FACTOR_EMPATE = 0.80
# Ajuste fino: con DTs con IA en los dos equipos, la liga simulada da los mismos
# goles y empates que la real (calibrado con la liga argentina).
ESCALA = 1.06
MAX_CAMBIOS_TACTICOS = 5

# ---------------------------------------------------------------- energía
# La energía del equipo va de 1 (fresco) a 0. Baja cada minuto según la
# táctica: presionar o ir con todo cansa mucho más que defenderse.
DESGASTE = {"equilibrada": 0.0045, "ofensiva": 0.0055, "defensiva": 0.0035,
            "contraataque": 0.0042, "presion": 0.0072, "todo_al_ataque": 0.0085}
RECUPERO_ENTRETIEMPO = 0.05
ENERGIA_MINIMA = 0.30
GANANCIA_CAMBIO = 0.12     # cada cambio recupera el 12% de la energía perdida
CAMBIOS_PERMITIDOS = 5
VENTANAS = 3               # momentos para hacer cambios, sin contar el entretiempo
# Energía por debajo de la cual cada DT empieza a hacer cambios
# Cambios mínimos hechos para cada minuto
META_CAMBIOS = ((60, 1), (70, 3), (78, 4), (85, 5))
UMBRAL_CAMBIO = {"equilibrado": 0.78, "conservador": 0.74, "arriesgado": 0.82,
                 "impulsivo": 0.80, None: 0.76}


def efecto_energia(e_propia, e_rival):
    """Multiplica los goles esperados de un equipo: cansado ataca peor,
    y si el rival está cansado, defiende peor."""
    return (0.75 + 0.25 * e_propia) * (1 + 0.25 * (1 - e_rival))


def decidir_cambios(personalidad, minuto, energia, restantes, ventanas, gf, gc,
                    rng=None):
    """Cuántos cambios hace el DT en este momento."""
    if restantes == 0 or minuto < 46:
        return 0
    entretiempo = minuto == 46
    if not entretiempo and ventanas == 0:
        return 0
    if not entretiempo and ventanas == 1 and minuto >= 70:
        return restantes                 # última ventana: usa todos
    umbral = UMBRAL_CAMBIO[personalidad]
    if gf < gc:
        umbral += 0.03                   # perdiendo, mete gente antes
    if personalidad == "impulsivo" and rng is not None:
        umbral += rng.uniform(-0.08, 0.08)
    por_energia = min(2, restantes) if energia < umbral else 0
    # Como cualquier DT, reparte los cambios a lo largo del segundo tiempo
    usados = CAMBIOS_PERMITIDOS - restantes
    meta = max((n for m, n in META_CAMBIOS if minuto >= m), default=0)
    return min(restantes, max(por_energia, meta - usados))


def aplicar_cambios(energia, cantidad):
    for _ in range(cantidad):
        energia += GANANCIA_CAMBIO * (1 - energia)
    return energia


@dataclass
class Equipo:
    nombre: str
    ataque: float       # escala del modelo (log): 0 = promedio de la liga
    defensa: float      # escala del modelo (log): negativo = recibe menos
    tactica: str = "equilibrada"
    tactica_inicial: str = "equilibrada"
    dt: str | None = "equilibrado"   # None = sin DT, táctica fija
    real: bool = True
    energia: float = 1.0               # promedio de los 10 de campo
    plantel: list | None = None
    formacion: str = J.FORMACION_BASE  # la usa el equipo sin DT
    caja: float = 0.0                  # millones de dólares
    ingreso: float = 0.0               # ingreso anual, millones de dólares
    moral: float = 1.0                 # multiplica los goles: la confianza del DT
    instalaciones: dict = field(default_factory=dict)   # ver club.py
    staff: dict = field(default_factory=dict)           # cuerpo técnico
    obras: list = field(default_factory=list)           # [instalación, fechas que faltan]
    hinchada: float = 60.0             # humor de la hinchada, de 0 a 100
    formacion_forzada: str | None = None   # la formación que le pediste al DT
    reserva: list = field(default_factory=list)          # pibes de las inferiores


PLANTELES = {}   # se cargan de planteles.json


# ---------------------------------------------------------------- entrada
def pedir_numero(texto, minimo=1, maximo=100, defecto=None):
    while True:
        raw = input(texto).strip()
        if not raw and defecto is not None:
            return defecto
        try:
            valor = int(raw)
            if minimo <= valor <= maximo:
                return valor
        except ValueError:
            pass
        print(f"Escribí un número entre {minimo} y {maximo}.")


def pedir_tactica():
    print("Tácticas:")
    for i, t in enumerate(TACTICAS_INICIALES, 1):
        print(f"  {i}. {t}")
    n = pedir_numero("Táctica [1]: ", 1, len(TACTICAS_INICIALES), defecto=1)
    return TACTICAS_INICIALES[n - 1]


def configurar_dt(eq):
    nombres = list(PERSONALIDADES)
    print(f"DT de {eq.nombre}:")
    for i, n in enumerate(nombres, 1):
        print(f"  {i}. {n} ({PERSONALIDADES[n]['desc']})")
    print(f"  {len(nombres) + 1}. sin DT (táctica fija)")
    n = pedir_numero("DT [1]: ", 1, len(nombres) + 1, defecto=1)
    if n <= len(nombres):
        eq.dt = nombres[n - 1]
        eq.tactica_inicial = "equilibrada"  # la define el DT al empezar
        eq.formacion = formacion_preferida(eq.nombre, eq.dt)
        print(f"El DT prefiere jugar con {eq.formacion}.")
    else:
        eq.dt = None
        eq.tactica_inicial = pedir_tactica()
        eq.formacion = pedir_formacion()


# Formación preferida de cada DT (cada club tiene la suya)
PREFERENCIAS = {"4-4-2": 25, "4-3-3": 25, "4-2-3-1": 25, "3-5-2": 12, "5-3-2": 13}
APEGO_FORMACION = 0.04   # puntos extra que le da a su formación preferida


def formacion_preferida(club, dt):
    rng = random.Random(f"{club}|{dt}")
    return rng.choices(list(PREFERENCIAS), weights=list(PREFERENCIAS.values()))[0]


def pedir_formacion():
    nombres = list(J.FORMACIONES)
    print("Formaciones:")
    for i, f in enumerate(nombres, 1):
        print(f"  {i}. {f}")
    n = pedir_numero("Formación [1]: ", 1, len(nombres), defecto=1)
    return nombres[n - 1]


def rating_a_modelo(rating):
    """Convierte un rating 1-100 a la escala del modelo.
    60 = equipo promedio; 90 ≈ x1.57; 30 ≈ x0.64."""
    return (rating - 60) * 0.015


def crear_equipo_inventado(numero):
    nombre = input("Nombre del equipo: ").strip() or f"Equipo {numero}"
    ataque = pedir_numero("Ataque (1-100) [60]: ", defecto=60)
    medio = pedir_numero("Mediocampo (1-100) [60]: ", defecto=60)
    defensa = pedir_numero("Defensa (1-100) [60]: ", defecto=60)
    arquero = pedir_numero("Arquero (1-100) [60]: ", defecto=60)
    fuerza_at = 0.70 * ataque + 0.30 * medio
    fuerza_def = 0.60 * defensa + 0.25 * arquero + 0.15 * medio
    return Equipo(nombre, rating_a_modelo(fuerza_at),
                  -rating_a_modelo(fuerza_def), real=False)


def buscar_club(modelo, permitir_inventado=True):
    """Pregunta un club real de la lista. Devuelve su nombre, o None si el
    usuario quiere inventar uno."""
    nombres = sorted(modelo["equipos"])
    if not nombres:
        return None
    print("Escribí parte del nombre, un número de la lista,")
    print("'l' para ver la lista" + (" o '0' para inventar uno." if permitir_inventado else "."))
    while True:
        raw = input("Equipo: ").strip()
        if raw == "0" and permitir_inventado:
            return None
        if raw.lower() == "l":
            for i, n in enumerate(nombres, 1):
                print(f"{i:>3}. {n}")
            continue
        if raw.isdigit() and 1 <= int(raw) <= len(nombres):
            candidatos = [nombres[int(raw) - 1]]
        else:
            candidatos = [n for n in nombres if raw.lower() in n.lower()] if raw else []
        if len(candidatos) == 1:
            print(f"-> {candidatos[0]}")
            return candidatos[0]
        if candidatos:
            print("Hay varios: " + ", ".join(candidatos[:8]))
        else:
            print("No lo encontré. Probá de nuevo o 'l' para la lista.")


def elegir_equipo(numero, modelo, ya_elegidos=(), etiqueta=None):
    if etiqueta is None:
        etiqueta = "local" if numero == 1 else "visitante"
    print(f"\n--- Equipo {numero} ({etiqueta}) ---")
    club = buscar_club(modelo)
    if club is None:
        eq = crear_equipo_inventado(numero)
    else:
        d = modelo["equipos"][club]
        eq = Equipo(club, d["ataque"], d["defensa"])
        if club in PLANTELES:
            eq.plantel = J.copiar_plantel(PLANTELES[club])
    usados = {e.nombre for e in ya_elegidos}
    base, n = eq.nombre, 2
    while eq.nombre in usados:
        eq.nombre = f"{base} ({n})"
        n += 1
    configurar_dt(eq)
    return eq


def asegurar_plantel(eq):
    """Los equipos inventados reciben un plantel generado con su fuerza."""
    if eq.plantel is None:
        usados = {j.completo for p in PLANTELES.values() for j in p}
        eq.plantel = J.generar_plantel(eq.ataque, eq.defensa,
                                       random.Random(eq.nombre), usados)


def reponer_fisico(*equipos):
    for e in equipos:
        asegurar_plantel(e)
        for j in e.plantel:
            j.fisico = 1.0


# ---------------------------------------------------------------- modelo
def goles_base(local, visitante, modelo):
    """Goles esperados en 90 minutos con tácticas equilibradas."""
    mu_l = math.exp(modelo["base"] + modelo["localia"]
                    + local.ataque + visitante.defensa)
    mu_v = math.exp(modelo["base"] + visitante.ataque + local.defensa)
    return mu_l, mu_v


def multiplicador(t_propia, t_rival, minuto):
    """Cuánto cambian los goles esperados de un equipo según las tácticas."""
    m = TACTICAS[t_propia]["propio"] * TACTICAS[t_rival]["rival"]
    if t_propia == "contraataque" and t_rival in TACTICAS_ADELANTADAS:
        m *= BONUS_CONTRA
    return m


# Peso de cada minuto: los goles son algo más frecuentes al final.
# Promedio 1, así que en 90 minutos suman los goles esperados.
_PESOS = [1 + 0.006 * m for m in range(1, 91)]
PESO = [0.0] + [p * 90 / sum(_PESOS) for p in _PESOS]   # PESO[1..90]
ACUM = [0.0]
for _p in PESO[1:]:
    ACUM.append(ACUM[-1] + _p)


def peso_tramo(desde, hasta):
    """Suma de pesos de los minutos desde..hasta (inclusive) / 90."""
    if desde > hasta:
        return 0.0
    return (ACUM[hasta] - ACUM[desde - 1]) / 90


def goles_restantes(base, t_propia, t_rival, minuto):
    """Goles esperados desde 'minuto' hasta el final."""
    return base * peso_tramo(minuto, 90) * multiplicador(t_propia, t_rival, minuto)


def poisson_pmf(k, mu):
    return math.exp(-mu) * mu ** k / math.factorial(k)


def prob_resultado(gf, gc, mu_f, mu_c, maximo=8):
    """Probabilidad de ganar, empatar y perder, dado el marcador actual
    y los goles esperados que faltan."""
    pf = [poisson_pmf(k, mu_f) for k in range(maximo + 1)]
    pc = [poisson_pmf(k, mu_c) for k in range(maximo + 1)]
    gana = empata = 0.0
    for i, a in enumerate(pf):
        for j, b in enumerate(pc):
            diff = gf + i - gc - j
            if diff > 0:
                gana += a * b
            elif diff == 0:
                empata += a * b
    return gana, empata, 1 - gana - empata


# ---------------------------------------------------------------- DT
def decidir_calculado(k, eq, rival, base_eq, base_rival, gf, gc, minuto, rng):
    """El DT prueba cada táctica para lo que queda del partido y se queda
    con la que más puntos le da en promedio, según su personalidad."""
    p = PERSONALIDADES[eq.dt]
    opciones = disponibles(minuto)
    puntajes = {}
    for t in set(opciones) | {eq.tactica}:
        mu_f = goles_restantes(base_eq, t, rival.tactica, minuto)
        mu_c = goles_restantes(base_rival, rival.tactica, t, minuto)
        gana, empata, _ = prob_resultado(gf, gc, mu_f, mu_c)
        puntajes[t] = p["ganar"] * gana + p["empatar"] * empata
    diferencia = max(puntajes.values()) - min(puntajes.values())
    if diferencia < p["umbral"]:
        return None   # ninguna táctica cambia nada: no vale la pena tocar
    # El error del DT es proporcional a lo que está en juego
    for t in puntajes:
        puntajes[t] += rng.gauss(0, p["error"] * diferencia)
    mejor = max((t for t in puntajes if t in opciones), key=puntajes.get)
    if mejor != eq.tactica and puntajes[mejor] - puntajes[eq.tactica] > p["umbral"]:
        return mejor
    return None


# ---------------------------------------------------------------- DT con IA
# Aprendizaje por refuerzo: para cada situación (momento del partido,
# diferencia de goles, fuerza relativa, tipo de táctica del rival y
# cansancio de su equipo) el DT
# guarda cuántos puntos espera sacar con cada táctica. Juega la mejor.
ACCIONES = list(TACTICAS)
TIPO_RIVAL = {"defensiva": 0, "contraataque": 0, "equilibrada": 1,
              "ofensiva": 2, "presion": 2, "todo_al_ataque": 2}
CORTES_FUERZA = (-0.8, -0.4, -0.15, 0.15, 0.4, 0.8)
TABLA_DE = {"equilibrado": "equilibrado", "conservador": "conservador",
            "arriesgado": "arriesgado", "impulsivo": "equilibrado"}
CEREBRO = None   # se carga de dt_ia.json
VERSION_CEREBRO = 2   # cambia cuando cambia lo que el DT tiene en cuenta


def estado_dt(minuto, gf, gc, base_eq, base_rival, t_rival, energia):
    """Resume la situación del partido como la ve el DT."""
    tramo = sum(1 for t in TRAMOS if t <= minuto) - 1
    dif = max(-2, min(2, gf - gc))
    r = math.log(base_eq / base_rival)
    fuerza = sum(1 for c in CORTES_FUERZA if r > c)
    cansancio = 0 if energia >= 0.8 else 1 if energia >= 0.65 else 2
    return f"{tramo}|{dif}|{fuerza}|{TIPO_RIVAL[t_rival]}|{cansancio}"


def decidir_ia(k, eq, rival, base_eq, base_rival, gf, gc, minuto, rng):
    tabla = CEREBRO["tablas"][TABLA_DE[eq.dt]]
    q = tabla.get(estado_dt(minuto, gf, gc, base_eq, base_rival, rival.tactica,
                            eq.energia))
    if q is None:
        return None   # situación que nunca vio: no toca nada
    validas = [ACCIONES.index(t) for t in disponibles(minuto)]
    if eq.dt == "impulsivo" and rng.random() < 0.25:
        return ACCIONES[rng.choice(validas)]   # decide a ojo
    mejor = max(validas, key=lambda i: q[i])
    actual = ACCIONES.index(eq.tactica)
    if mejor != actual and q[mejor] - q[actual] > 0.02:
        return ACCIONES[mejor]
    return None


def cargar_cerebro(ruta="dt_ia.json"):
    global CEREBRO
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            cerebro = json.load(f)
        if cerebro.get("version") != VERSION_CEREBRO:
            print("dt_ia.json es de una versión anterior: reentrená con "
                  "entrenar_dt.py.\nMientras tanto, los DTs usan el modo calculador.")
            return
        CEREBRO = cerebro
        print(f"DT con IA cargado ({CEREBRO['partidos']:,} partidos de "
              "entrenamiento).".replace(",", "."))
    else:
        print("Sin dt_ia.json: los DTs usan el modo calculador.")


def motivo(gf, gc):
    if gf > gc:
        return f"gana {gf}-{gc}"
    if gf < gc:
        return f"pierde {gf}-{gc}"
    return f"empata {gf}-{gc}"


# ---------------------------------------------------------------- partido
def minuto_texto(rng, m):
    if m in (45, 90) and rng.random() < 0.5:
        return f"{m}+{rng.randint(1, 4)}'"
    return f"{m}'"


def sucede(rng, tasa):
    """True con la probabilidad de que ocurra al menos un evento en el minuto."""
    return rng.random() < 1 - math.exp(-tasa)


OFENSIVOS = ("DC", "ED", "EI", "MCO")
DEFENSIVOS = ("DFC", "MCD")
# Quién suele hacer los goles y quién ve las amarillas
PESO_GOL = {"DC": 5.0, "ED": 2.6, "EI": 2.6, "MCO": 2.3, "MC": 1.4, "MCD": 0.8,
            "LD": 0.7, "LI": 0.7, "DFC": 1.1, "ARQ": 0.0}
PESO_TARJETA = {"DFC": 1.5, "MCD": 1.6, "LD": 1.2, "LI": 1.2, "MC": 1.1, "MCO": 0.8,
                "ED": 0.8, "EI": 0.8, "DC": 0.9, "ARQ": 0.3}


def elegir_alineacion(eq, rival, modelo, es_local, rng):
    """El DT prueba cada formación con sus mejores 11 contra el rival y se
    queda con la que más puntos le da, según su personalidad."""
    if not eq.dt:
        return eq.formacion, J.armar_xi(J.aptos(eq.plantel), eq.formacion)
    if eq.formacion_forzada:      # la formación que le pidió el dueño
        return eq.formacion_forzada, J.armar_xi(J.aptos(eq.plantel), eq.formacion_forzada)
    f_rival = rival.formacion if not rival.dt else J.FORMACION_BASE
    ra, rd, *_ = J.fuerza(J.armar_xi(J.aptos(rival.plantel), f_rival), f_rival)
    p = PERSONALIDADES[eq.dt]
    localia = modelo["localia"]
    opciones = []
    for f in J.FORMACIONES:
        xi = J.armar_xi(J.aptos(eq.plantel), f)
        a, d, *_ = J.fuerza(xi, f)
        mu_f = math.exp(modelo["base"] + (localia if es_local else 0) + a + rd) * ESCALA
        mu_c = math.exp(modelo["base"] + (0 if es_local else localia) + ra + d) * ESCALA
        gana, empata, _ = prob_resultado(0, 0, mu_f, mu_c)
        puntos = p["ganar"] * gana + p["empatar"] * empata
        if f == eq.formacion:
            puntos += APEGO_FORMACION   # solo la cambia si otra es claramente mejor
        opciones.append((puntos, f, xi))
    if eq.dt == "impulsivo" and rng.random() < 0.3:
        _, f, xi = rng.choice(opciones)
    else:
        _, f, xi = max(opciones, key=lambda o: o[0])
    return f, xi


def elegir_cambio(cancha, banco, minuto, gf, gc):
    """A quién saca y a quién mete el DT. Devuelve (índice, entra, posición)."""
    campo = [i for i, (_, s) in enumerate(cancha) if s != "ARQ"]
    n_of = sum(1 for _, s in cancha if s in OFENSIVOS)
    n_def = sum(1 for _, s in cancha if s in DEFENSIVOS)
    if gf < gc and minuto >= 60 and n_of < 5:
        # Perdiendo: saca un volante o un lateral y mete un atacante
        salen = [i for i in campo if cancha[i][1] in ("MCD", "MC", "LD", "LI")]
        entran = [j for j in banco if j.pos in OFENSIVOS]
        if salen and entran:
            i = min(salen, key=lambda i: cancha[i][0].energia)
            entra = max(entran, key=lambda j: J.puntaje(j, j.pos))
            return i, entra, entra.pos
    if gf > gc and minuto >= 70 and n_def < 5:
        # Ganando: saca un atacante y mete un defensor o un volante central
        salen = [i for i in campo if cancha[i][1] in OFENSIVOS]
        entran = [j for j in banco if j.pos in DEFENSIVOS]
        if salen and entran:
            i = min(salen, key=lambda i: cancha[i][0].energia)
            entra = max(entran, key=lambda j: J.puntaje(j, j.pos))
            return i, entra, entra.pos
    # Cambio normal: el más cansado por el mejor suplente para ese puesto
    i = min(campo, key=lambda i: cancha[i][0].energia)
    slot = cancha[i][1]
    entra = max(banco, key=lambda j: J.puntaje(j, slot))
    return i, entra, slot


def elegir_jugador(cancha, pesos, rng, excluir=()):
    candidatos = [(j, s) for j, s in cancha if id(j) not in excluir]
    if not candidatos:
        return None
    w = [pesos[s] * (j.ataque / 65) ** 2 if pesos is PESO_GOL else pesos[s]
         for j, s in candidatos]
    if sum(w) <= 0:
        return None
    return rng.choices([j for j, _ in candidatos], weights=w)[0]


def mostrar_alineacion(e, formacion, xi, tactica):
    print(f"{e.nombre} · {formacion} · DT {e.dt or 'sin DT'}")
    restantes = list(xi)

    def sacar(slot):
        for t in restantes:
            if t[1] == slot:
                restantes.remove(t)
                return t[0].apellido
        return "?"

    lineas = J.FORMACIONES[formacion]
    print(f" Arq: {sacar('ARQ')}")
    for idx, linea in enumerate(lineas):
        etiqueta = "Def" if idx == 0 else "Del" if idx == len(lineas) - 1 else "Med"
        texto = f" {etiqueta}: " + ", ".join(sacar(s) for s in linea)
        print(textwrap.fill(texto, ANCHO, subsequent_indent="      "))
    print(f" Táctica: {tactica}")


EFECTO_ALIENTO = 0.02   # la hinchada mueve hasta un 2% los goles del local


def simular_partido(local, visitante, modelo, mostrar=True, semilla=None,
                    decisor=None, relato=False):
    """decisor: función que decide la táctica de un DT. Por defecto usa la
    IA entrenada si está cargada, o el DT calculador.
    relato=True: sin imprimir nada, devuelve en las estadísticas el relato,
    las alineaciones y la posesión (lo usa la app).
    Devuelve (goles local, goles visitante, estadísticas)."""
    if decisor is None:
        decisor = decidir_ia if CEREBRO else decidir_calculado
    rng = random.Random(semilla)
    eq = {"L": local, "V": visitante}
    otro = {"L": "V", "V": "L"}
    for k in "LV":
        asegurar_plantel(eq[k])

    # Formación y titulares
    formacion, cancha, banco, jugaron = {}, {}, {}, {}
    for k in "LV":
        f, xi = elegir_alineacion(eq[k], eq[otro[k]], modelo, k == "L", rng)
        formacion[k], cancha[k] = f, xi
        en_cancha = {id(j) for j, _ in xi}
        banco[k] = [j for j in J.aptos(eq[k].plantel) if id(j) not in en_cancha]
        jugaron[k] = [j for j, _ in xi]
        for j in eq[k].plantel:
            j.energia = j.fisico
    titulares = {k: [list(x) for x in cancha[k]] for k in "LV"}

    goles = {"L": 0, "V": 0}
    stats = {k: Counter() for k in "LV"}
    autores = []           # (lado, jugador, minuto)
    amonestados = set()
    ultimo_cambio = {"L": -99, "V": -99}
    cambios_rest = {"L": CAMBIOS_PERMITIDOS, "V": CAMBIOS_PERMITIDOS}
    ventanas = {"L": VENTANAS, "V": VENTANAS}
    ultimo_gol = -99
    eventos = []
    posesion_total = 0.0

    def log(texto):
        if mostrar or relato:
            eventos.append(texto)

    def energia_equipo(k):
        campo = [j.energia for j, s in cancha[k] if s != "ARQ"]
        return sum(campo) / len(campo)

    def calcular_bases():
        fz = {k: J.fuerza(cancha[k], formacion[k]) for k in "LV"}
        mu_l = math.exp(modelo["base"] + modelo["localia"] + fz["L"][0] + fz["V"][1])
        mu_v = math.exp(modelo["base"] + fz["V"][0] + fz["L"][1])
        aliento = 1 + EFECTO_ALIENTO * (local.hinchada - 60) / 40   # cancha llena
        return {"L": mu_l * local.moral * aliento, "V": mu_v * visitante.moral}

    def creacion(k):
        campo = [j.creacion * j.energia for j, s in cancha[k] if s != "ARQ"]
        return sum(campo) / len(campo)

    base = calcular_bases()

    # Táctica inicial: la elige el DT o queda la fija
    for k in "LV":
        eq[k].tactica = eq[k].tactica_inicial
        eq[k].energia = energia_equipo(k)
    for k in "LV":
        if eq[k].dt:
            nueva = decisor(k, eq[k], eq[otro[k]], base[k], base[otro[k]], 0, 0, 1, rng)
            if nueva:
                eq[k].tactica = nueva
    tacticas_iniciales = {k: eq[k].tactica for k in "LV"}

    for minuto in range(1, 91):
        mt = minuto_texto(rng, minuto)
        if minuto == 46:
            for k in "LV":
                for j, _ in cancha[k]:
                    j.energia = min(1.0, j.energia + RECUPERO_ENTRETIEMPO)

        # Cambios de jugadores
        if minuto in MOMENTOS_DECISION:
            hubo = False
            for k in "LV":
                e = eq[k]
                e.energia = energia_equipo(k)
                n = decidir_cambios(e.dt, minuto, e.energia, cambios_rest[k],
                                    ventanas[k], goles[k], goles[otro[k]], rng)
                n = min(n, len(banco[k]))
                if not n:
                    continue
                for _ in range(n):
                    i, entra, slot = elegir_cambio(cancha[k], banco[k], minuto,
                                                   goles[k], goles[otro[k]])
                    sale = cancha[k][i][0]
                    cancha[k][i] = [entra, slot]
                    banco[k].remove(entra)
                    jugaron[k].append(entra)
                    log(f"🔄 {minuto}' {e.nombre}: sale {sale.corto} "
                        f"({sale.energia:.0%}), entra {entra.corto} ({slot})")
                cambios_rest[k] -= n
                if minuto != 46:
                    ventanas[k] -= 1
                stats[k]["sustituciones"] += n
                hubo = True
            if hubo:
                base = calcular_bases()
        for k in "LV":
            eq[k].energia = energia_equipo(k)

        # Decisiones tácticas de los DT
        if minuto in MOMENTOS_DECISION or minuto == ultimo_gol + 2:
            for k in "LV":
                e = eq[k]
                if (not e.dt or stats[k]["cambios"] >= MAX_CAMBIOS_TACTICOS
                        or minuto - ultimo_cambio[k] < MIN_ENTRE_CAMBIOS):
                    continue
                nueva = decisor(k, e, eq[otro[k]], base[k], base[otro[k]],
                                goles[k], goles[otro[k]], minuto, rng)
                if nueva:
                    e.tactica = nueva
                    ultimo_cambio[k] = minuto
                    stats[k]["cambios"] += 1
                    log(f"🧠 {minuto}' DT de {e.nombre}: {nueva} "
                        f"({motivo(goles[k], goles[otro[k]])})")

        # Lo que pasa en el minuto
        empate = goles["L"] == goles["V"]
        for k in "LV":
            e, r = eq[k], eq[otro[k]]
            tasa = (base[k] * ESCALA * PESO[minuto] / 90
                    * multiplicador(e.tactica, r.tactica, minuto)
                    * efecto_energia(e.energia, r.energia))
            if empate:
                tasa *= FACTOR_EMPATE
            if sucede(rng, tasa):
                goles[k] += 1
                ultimo_gol = minuto
                autor = elegir_jugador(cancha[k], PESO_GOL, rng)
                autores.append((k, autor, minuto))
                log(f"⚽ {mt} GOL de {e.nombre}: {autor.corto}  "
                    f"({goles['L']}-{goles['V']})")
            elif sucede(rng, 2.4 * tasa):
                stats[k]["atajados"] += 1
                arq = next((j for j, s in cancha[otro[k]] if s == "ARQ"), None)
                log(f"🧤 {mt} Ataja {arq.corto} ({r.nombre})")
            elif sucede(rng, 5.5 * tasa + 1.5 / 90):
                stats[k]["desviados"] += 1
                if rng.random() < 0.3:
                    tirador = elegir_jugador(cancha[k], PESO_GOL, rng)
                    log(f"↗ {mt} Desviado: {tirador.corto} ({e.nombre})")
            if sucede(rng, 2.2 / 90):
                j = elegir_jugador(cancha[k], PESO_TARJETA, rng, amonestados)
                if j:
                    amonestados.add(id(j))
                    stats[k]["amarillas"] += 1
                    log(f"🟨 {mt} Amarilla: {j.corto} ({e.nombre})")

        # Desgaste: depende de la táctica y de la resistencia de cada uno
        for k in "LV":
            d = DESGASTE[eq[k].tactica]
            for j, s in cancha[k]:
                factor = 0.4 if s == "ARQ" else 1 + (65 - j.resistencia) * 0.012
                j.energia = max(ENERGIA_MINIMA, j.energia - d * factor)

        posesion_total += (50 + (creacion("L") - creacion("V")) * 0.6
                           + TACTICAS[local.tactica]["posesion"]
                           - TACTICAS[visitante.tactica]["posesion"])
        if minuto == 45:
            log(f"--- ENTRETIEMPO {goles['L']}-{goles['V']} ---")

    # Cómo quedan físicamente los que jugaron
    for k in "LV":
        for j in jugaron[k]:
            j.fisico = j.energia
            j.partidos += 1
        eq[k].energia = energia_equipo(k)
    stats["goles"] = autores
    stats["formacion"] = formacion

    gl, gv = goles["L"], goles["V"]
    if relato:
        stats["eventos"] = eventos
        stats["posesion"] = max(25, min(75, posesion_total / 90 + rng.gauss(0, 3)))
        stats["alineacion"] = {k: (formacion[k], [(j.corto, s) for j, s in titulares[k]],
                                   tacticas_iniciales[k]) for k in "LV"}
    if not mostrar:
        return gl, gv, stats

    posesion = max(25, min(75, posesion_total / 90 + rng.gauss(0, 3)))
    print("\n" + "=" * ANCHO)
    print(f" {local.nombre} vs {visitante.nombre}")
    print("=" * ANCHO)
    for k in "LV":
        mostrar_alineacion(eq[k], formacion[k], titulares[k], tacticas_iniciales[k])
        print()
    print("-" * ANCHO)
    for texto in eventos:
        print(textwrap.fill(texto, ANCHO, subsequent_indent="     "))

    L, V = stats["L"], stats["V"]
    print("\n" + "-" * ANCHO)
    print(f" FINAL: {local.nombre} {gl} - {gv} {visitante.nombre}")
    print("-" * ANCHO)
    for k in "LV":
        suyos = [(j, m) for lado, j, m in autores if lado == k]
        if suyos:
            por_jugador = {}
            for j, m in suyos:
                por_jugador.setdefault(j.corto, []).append(f"{m}'")
            texto = f" {eq[k].nombre}: " + ", ".join(
                f"{n} {' '.join(ms)}" for n, ms in por_jugador.items())
            print(textwrap.fill(texto, ANCHO, subsequent_indent="   "))
    filas = (("Posesión", f"{posesion:.0f}%", f"{100 - posesion:.0f}%"),
             ("Tiros", gl + L["atajados"] + L["desviados"],
              gv + V["atajados"] + V["desviados"]),
             ("Al arco", gl + L["atajados"], gv + V["atajados"]),
             ("Atajadas", V["atajados"], L["atajados"]),
             ("Amarillas", L["amarillas"], V["amarillas"]),
             ("Cambios", L["sustituciones"], V["sustituciones"]),
             ("Tácticas DT", L["cambios"], V["cambios"]),
             ("Energía", f"{local.energia:.0%}", f"{visitante.energia:.0%}"))
    print()
    for nombre, a, b in filas:
        print(f"{nombre:<12}{str(a):>6}  -  {str(b):<6}")
    if gl > gv:
        print(f"\nGanador: {local.nombre}")
    elif gv > gl:
        print(f"\nGanador: {visitante.nombre}")
    else:
        print("\nEmpate.")
    return gl, gv, stats


def prueba_masiva(local, visitante, modelo, cantidad=1000):
    conteo, marcadores, cambios, total = Counter(), Counter(), Counter(), 0
    formaciones, goleadores = Counter(), Counter()
    for i in range(cantidad):
        reponer_fisico(local, visitante)
        gl, gv, stats = simular_partido(local, visitante, modelo,
                                        mostrar=False, semilla=i)
        total += gl + gv
        marcadores[(gl, gv)] += 1
        cambios["L"] += stats["L"]["cambios"]
        cambios["V"] += stats["V"]["cambios"]
        formaciones[(local.nombre, stats["formacion"]["L"])] += 1
        formaciones[(visitante.nombre, stats["formacion"]["V"])] += 1
        for lado, j, _ in stats["goles"]:
            goleadores[(j.corto, (local if lado == "L" else visitante).nombre)] += 1
        conteo["L" if gl > gv else "V" if gv > gl else "E"] += 1
    print(f"\n--- {cantidad} PARTIDOS ---")
    print(f"{local.nombre}: {conteo['L'] / cantidad:.1%}")
    print(f"Empate: {conteo['E'] / cantidad:.1%}")
    print(f"{visitante.nombre}: {conteo['V'] / cantidad:.1%}")
    print(f"Goles por partido: {total / cantidad:.2f}")
    print(f"Cambios tácticos por partido: {cambios['L'] / cantidad:.1f} - "
          f"{cambios['V'] / cantidad:.1f}")
    print("Resultados más comunes:")
    for (gl, gv), n in marcadores.most_common(5):
        print(f"  {gl}-{gv}: {n / cantidad:.1%}")
    print("Formación más usada:")
    for e in (local, visitante):
        f, n = max(((f, n) for (eq, f), n in formaciones.items() if eq == e.nombre),
                   key=lambda x: x[1])
        print(f"  {e.nombre}: {f} ({n / cantidad:.0%})")
    print("Goleadores (goles cada 10 partidos):")
    for (j, club), n in goleadores.most_common(5):
        print(f"  {j} ({club[:12]}): {10 * n / cantidad:.1f}")


# ---------------------------------------------------------------- menú
def cargar_modelo(ruta):
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            modelo = json.load(f)
        print(f"Modelo cargado: {len(modelo['equipos'])} equipos.")
        return modelo
    print(f"No encontré {ruta}: solo equipos inventados.")
    return MODELO_VACIO


# Divisiones (ver ascenso.json): la Liga Profesional con los clubes del modelo
# que figuran en "primera", y abajo las categorías del ascenso. No hay
# resultados reales del ascenso para entrenar el modelo, así que la fuerza de
# esos clubes se estima con su peso histórico (1 a 5). Los recién ascendidos
# a Primera están medio punto por debajo de la media en la escala del modelo
# (ataque menos defensa): eso es un club de peso 5 de la Primera Nacional.
ARCHIVO_ASCENSO = "ascenso.json"
CAMBIOS_DE_CATEGORIA = 2     # entre cada par de divisiones bajan 2 y suben 2


def fuerza_estimada(club, peso, ajuste):
    rng = random.Random(f"ascenso|{club}")
    neto = -1.10 + 0.12 * peso + ajuste + rng.gauss(0, 0.08)
    sesgo = rng.gauss(0, 0.08)            # más de ataque o más de defensa
    return {"ataque": neto / 2 + sesgo, "defensa": -neto / 2 + sesgo}


def cargar_ascenso(modelo, ruta=ARCHIVO_ASCENSO):
    """Arma las divisiones: agrega los clubes del ascenso al modelo y anota
    la división de cada club. Los del modelo que no están en "primera"
    bajan a la segunda división con su fuerza real."""
    modelo["division"] = {c: 0 for c in modelo["equipos"]}
    modelo["divisiones"] = ["Liga Profesional"]
    if not modelo["equipos"] or not os.path.exists(ruta):
        return
    with open(ruta, encoding="utf-8") as f:
        datos = json.load(f)
    primera = [c for c in datos.get("primera", modelo["equipos"]) if c in modelo["equipos"]]
    bajan = [c for c in modelo["equipos"] if c not in primera]
    modelo["division"] = {c: 0 for c in primera}
    for d, division in enumerate(datos["divisiones"], 1):
        modelo["divisiones"].append(division["nombre"])
        if d == 1:
            modelo["division"].update({c: 1 for c in bajan})
        for club, peso in division["clubes"].items():
            if club not in modelo["equipos"]:
                modelo["equipos"][club] = fuerza_estimada(club, peso, division.get("ajuste", 0.0))
            modelo["division"][club] = d
    tamanios = [sum(1 for v in modelo["division"].values() if v == d)
                for d in range(len(modelo["divisiones"]))]
    print("Divisiones: " + ", ".join(f"{n} ({t})" for n, t in zip(modelo["divisiones"],
                                                                     tamanios)) + ".")


# ---------------------------------------------------------------- cuadrangular
# Todos contra todos, ida y vuelta: 6 fechas, 2 partidos por fecha.
# Cada par de números es (local, visitante) según el orden de los equipos.
FIXTURE_IDA = [((0, 1), (2, 3)), ((0, 2), (3, 1)), ((3, 0), (1, 2))]
FIXTURE = FIXTURE_IDA + [tuple((v, l) for l, v in fecha) for fecha in FIXTURE_IDA]


def ordenar_tabla(tabla):
    """Puntos, diferencia de gol, goles a favor."""
    return sorted(tabla.items(), key=lambda kv: (kv[1]["Pts"], kv[1]["GF"] - kv[1]["GC"],
                                                kv[1]["GF"]), reverse=True)


def mostrar_tabla(tabla):
    print(f"\n{'':<3}{'Equipo':<14}{'PJ':>3}{'G':>3}{'E':>3}{'P':>3}{'DG':>4}{'Pts':>5}")
    for i, (nombre, f) in enumerate(ordenar_tabla(tabla), 1):
        dg = f["GF"] - f["GC"]
        print(f"{i:<3}{nombre[:13]:<14}{f['PJ']:>3}{f['G']:>3}{f['E']:>3}{f['P']:>3}"
              f"{dg:>+4}{f['Pts']:>5}")


RECUPERO_FECHA = 0.25   # físico que se recupera entre una fecha y la otra


def mostrar_goleadores(goleadores, cantidad=5):
    if not goleadores:
        return
    print("\nGoleadores:")
    for (j, club), n in goleadores.most_common(cantidad):
        print(f"  {n}  {j} ({club})")


def cuadrangular(modelo):
    print("\n=== CUADRANGULAR (ida y vuelta) ===")
    equipos = []
    for i in range(1, 5):
        equipos.append(elegir_equipo(i, modelo, ya_elegidos=equipos,
                                     etiqueta="cuadrangular"))
    tabla = {e.nombre: Counter(PJ=0) for e in equipos}
    goleadores = Counter()
    reponer_fisico(*equipos)

    for numero, fecha in enumerate(FIXTURE, 1):
        print("\n" + "#" * ANCHO)
        print(f" FECHA {numero} de {len(FIXTURE)}"
              + ("  (vuelta)" if numero > len(FIXTURE_IDA) else ""))
        for l, v in fecha:
            print(f"  {equipos[l].nombre} vs {equipos[v].nombre}")
        print("#" * ANCHO)
        resultados = []
        for l, v in fecha:
            input("\nEnter para jugar el partido...")
            local, visitante = equipos[l], equipos[v]
            gl, gv, stats = simular_partido(local, visitante, modelo)
            resultados.append(f"{local.nombre} {gl} - {gv} {visitante.nombre}")
            for lado, j, _ in stats["goles"]:
                goleadores[(j.corto, (local if lado == "L" else visitante).nombre)] += 1
            anotar(tabla, local, visitante, gl, gv)
        input("\nEnter para ver la tabla...")
        print(f"\nResultados de la fecha {numero}:")
        for r in resultados:
            print("  " + r)
        mostrar_tabla(tabla)
        mostrar_goleadores(goleadores)
        # Descanso entre fechas: los que jugaron recuperan parte del físico
        for e in equipos:
            for j in e.plantel:
                j.fisico = min(1.0, j.fisico + RECUPERO_FECHA)

    campeon, f = ordenar_tabla(tabla)[0]
    print("\n" + "*" * ANCHO)
    print(f" 🏆 CAMPEÓN: {campeon}")
    print(f" {f['Pts']} puntos, {f['G']} ganados, {f['E']} empatados, {f['P']} perdidos")
    if goleadores:
        (j, club), n = goleadores.most_common(1)[0]
        print(f" ⚽ Goleador: {j} ({club}), {n} goles")
    print("*" * ANCHO)


# ---------------------------------------------------------------- torneo largo
# Todos contra todos, ida y vuelta, con todos los clubes del modelo.
PERSONALIDAD_AL_AZAR = {"equilibrado": 40, "conservador": 25, "arriesgado": 25,
                        "impulsivo": 10}


def armar_fixture(cantidad, rng):
    """Fixture de todos contra todos (método del círculo), ida y vuelta.
    Devuelve una lista de fechas; cada fecha es una lista de (local, visitante)."""
    orden = list(range(cantidad))
    rng.shuffle(orden)
    if len(orden) % 2:
        orden.append(None)          # con cantidad impar, uno queda libre
    n = len(orden)
    ida = []
    for ronda in range(n - 1):
        fecha = []
        for i in range(n // 2):
            a, b = orden[i], orden[n - 1 - i]
            if a is None or b is None:
                continue
            # se alterna la localía para que cada uno juegue la mitad de local
            if (i == 0 and ronda % 2) or (i > 0 and i % 2):
                a, b = b, a
            fecha.append((a, b))
        ida.append(fecha)
        orden = [orden[0], orden[-1]] + orden[1:-1]
    vuelta = [[(b, a) for a, b in fecha] for fecha in ida]
    return ida + vuelta


def anotar(tabla, local, visitante, gl, gv):
    for eq, gf, gc in ((local, gl, gv), (visitante, gv, gl)):
        f = tabla[eq.nombre]
        f["PJ"] += 1
        f["GF"] += gf
        f["GC"] += gc
        if gf > gc:
            f["G"] += 1
            f["Pts"] += 3
        elif gf == gc:
            f["E"] += 1
            f["Pts"] += 1
        else:
            f["P"] += 1


# Intensidad que elige cada DT cuando el plantel está bien físicamente
INTENSIDAD_DT = {"equilibrado": "normal", "conservador": "suave",
                 "arriesgado": "fuerte", None: "normal"}


def plan_dt(eq, rng):
    """El DT elige el entrenamiento de la semana: si el plantel está cansado
    descansa, y si no, trabaja lo que más le falta al equipo."""
    sanos = [j for j in eq.plantel if not j.lesion]
    fisico = sum(j.fisico for j in sanos) / len(sanos)
    if fisico < 0.85:
        return "descanso", "suave"
    if eq.dt == "impulsivo":
        return (rng.choice(("completo", "ataque", "defensa", "fisico")),
                rng.choice(list(J.INTENSIDADES)))
    intensidad = INTENSIDAD_DT[eq.dt]
    if intensidad == "fuerte" and fisico < 0.92:
        intensidad = "normal"
    a, d, *_ = J.fuerza(J.armar_xi(J.aptos(eq.plantel), J.FORMACION_BASE, False))
    if a < -d - 0.05:
        return "ataque", intensidad
    if -d < a - 0.05:
        return "defensa", intensidad
    return "completo", intensidad


def pedir_entrenamiento():
    """El plan de entrenamiento de tu club. None = lo decide el DT."""
    print("\n--- Entrenamiento ---")
    tipos = list(J.TIPOS_ENTRENAMIENTO)
    print("0) Que lo decida el DT")
    for i, t in enumerate(tipos, 1):
        print(f"{i}) {t} ({J.TIPOS_ENTRENAMIENTO[t]})")
    n = pedir_numero("Tipo [0]: ", 0, len(tipos), defecto=0)
    if n == 0:
        return None
    tipo = tipos[n - 1]
    if tipo == "descanso":
        return tipo, "suave"
    print("1) suave (sube poco, llegan frescos)")
    print("2) normal")
    print("3) fuerte (sube más, cansa y hay")
    print("   riesgo de lesiones)")
    n = pedir_numero("Intensidad [2]: ", 1, len(J.INTENSIDADES), defecto=2)
    intensidad = list(J.INTENSIDADES)[n - 1]
    return tipo, intensidad


def mostrar_entrenamiento(club, plan, mejoras, lesionados, del_dt):
    tipo, intensidad = plan
    quien = "elegido por el DT" if del_dt else "elegido por vos"
    texto = (f"🏋 Entrenamiento de {club}: {tipo}"
             + (f" ({intensidad})" if tipo != "descanso" else "") + f", {quien}.")
    print("\n" + textwrap.fill(texto, ANCHO, subsequent_indent="  "))
    if mejoras:
        texto = "Suben: " + ", ".join(f"{j.corto} {a}→{b}" for j, a, b in mejoras)
        print(textwrap.fill(texto, ANCHO, subsequent_indent="  "))
    for j, n in lesionados:
        print(f"🚑 Se lesionó {j.corto}: {n} fecha{'s' if n > 1 else ''} afuera")


def posicion(tabla, nombre):
    for i, (n, f) in enumerate(ordenar_tabla(tabla), 1):
        if n == nombre:
            return i, f


# ---------------------------------------------------------------- partida guardada
# El torneo largo se guarda solo después de cada fecha, y se pueden encadenar
# temporadas: los jugadores mantienen lo que mejoraron, cumplen años, los
# veteranos se retiran y suben juveniles. Si existe la variable de entorno
# FUTBOL_PARTIDAS, la partida se guarda en esa carpeta.
ARCHIVO_PARTIDA = "partida.json"
VERSION_PARTIDA = 1


def ruta_partida():
    return os.path.join(os.environ.get("FUTBOL_PARTIDAS") or ".", ARCHIVO_PARTIDA)


def division_de(p, club):
    return p["division"].get(club, 0)


def tabla_division(p, d):
    return {n: f for n, f in p["tabla"].items() if division_de(p, n) == d}


def goleadores_division(p, d):
    return Counter({k: v for k, v in p["goleadores"].items() if division_de(p, k[1]) == d})


def division_a_mostrar(p):
    """La división del club que seguís (o la Primera)."""
    return division_de(p, p["mio"]) if p["mio"] else 0


def pedir_division(p):
    if len(p["divisiones"]) == 1:
        return 0
    for i, nombre in enumerate(p["divisiones"], 1):
        print(f"{i}) {nombre}")
    return pedir_numero(f"División [{division_a_mostrar(p) + 1}]: ", 1, len(p["divisiones"]),
                        defecto=division_a_mostrar(p) + 1) - 1


def guardar_partida(p):
    datos = dict(p, version=VERSION_PARTIDA,
                 equipos=[asdict(e) for e in p["equipos"]],
                 tabla={n: dict(f) for n, f in p["tabla"].items()},
                 goleadores=[[j, c, n] for (j, c), n in p["goleadores"].items()],
                 libres=[asdict(j) for j in p["libres"]],
                 ofertas=[[c, j.completo, m] for c, j, m in p["ofertas"]],
                 tecnicos={c: T.a_dict(t) for c, t in p["tecnicos"].items()},
                 dts_libres=[T.a_dict(t) for t in p["dts_libres"]])
    ruta = ruta_partida()
    os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
    with open(ruta + ".tmp", "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False)
    os.replace(ruta + ".tmp", ruta)    # si se corta a la mitad, queda la anterior


def cargar_partida():
    try:
        with open(ruta_partida(), encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError):
        return None
    if datos.get("version") != VERSION_PARTIDA:
        return None
    equipos = []
    for d in datos["equipos"]:
        e = Equipo(**{k: v for k, v in d.items() if k not in ("plantel", "reserva")})
        e.plantel = [J.Jugador(**j) for j in d["plantel"]]
        e.reserva = [J.Jugador(**j) for j in d.get("reserva", [])]
        equipos.append(e)
    datos["equipos"] = equipos
    datos["fixture"] = [[tuple(x) for x in fecha] for fecha in datos["fixture"]]
    datos["tabla"] = {n: Counter(f) for n, f in datos["tabla"].items()}
    datos["goleadores"] = Counter({(j, c): n for j, c, n in datos["goleadores"]})
    datos["plan_mio"] = tuple(datos["plan_mio"]) if datos["plan_mio"] else None
    # las partidas de antes del mercado de pases arrancan con las finanzas de cero,
    # y las de antes de los contratos, con contratos nuevos
    M.iniciar_contratos([e.plantel for e in equipos], random.Random(f"{datos['semilla']}|c"))
    M.iniciar_finanzas(equipos)
    datos["libres"] = [J.Jugador(**j) for j in datos.get("libres", [])]
    mios = {j.completo: j for e in equipos if e.nombre == datos["mio"]
            for j in e.plantel + e.reserva}
    datos["ofertas"] = [(c, mios[n], m) for c, n, m in datos.get("ofertas", []) if n in mios]
    datos.setdefault("ventana", None)
    # las partidas de antes del ascenso siguen con una sola división
    datos.setdefault("division", {e.nombre: 0 for e in equipos})
    datos.setdefault("divisiones", ["Liga Profesional"])
    datos.setdefault("movimientos", [])
    datos.setdefault("sondeos", {})
    # las partidas de antes de los DT con ánimo arrancan con DT nuevos
    if "tecnicos" in datos:
        datos["tecnicos"] = {c: T.de_dict(d) for c, d in datos["tecnicos"].items()}
        datos["dts_libres"] = [T.de_dict(d) for d in datos["dts_libres"]]
    else:
        iniciar_tecnicos(datos)
    if "esperado_global" not in datos:
        calcular_esperado(datos)
    if "staff_libres" not in datos:     # partidas de antes de las instalaciones
        iniciar_club(datos)
    if not datos.get("con_reserva"):     # partidas de antes de la reserva
        iniciar_reserva(datos)
    return datos


def elegir_club_a_seguir(modelo):
    print("¿Querés seguir a un club? Sus partidos se ven con relato")
    print("y elegís su DT. Enter para no seguir a ninguno.")
    nombres_lista = sorted(modelo["equipos"])
    while True:
        raw = input("Club: ").strip()
        if not raw:
            return None
        if raw.isdigit() and 1 <= int(raw) <= len(nombres_lista):
            candidatos = [nombres_lista[int(raw) - 1]]
        else:
            candidatos = [n for n in nombres_lista if raw.lower() in n.lower()]
        if len(candidatos) == 1:
            print(f"-> {candidatos[0]}")
            return candidatos[0]
        print("Hay varios: " + ", ".join(candidatos[:8]) if candidatos
              else "No lo encontré. Probá de nuevo (o Enter para ninguno).")


def nueva_partida(modelo):
    """Partida nueva, eligiendo club y DT por consola."""
    return crear_partida(modelo, elegir_club_a_seguir(modelo), configurar_dt)


def crear_partida(modelo, mio, dt_mio="equilibrado"):
    """Partida nueva siguiendo al club mio (o None). dt_mio: la personalidad
    del DT de tu club, o una función que lo configura (la consola)."""
    equipos = []
    clubes = sorted(modelo.get("division") or PLANTELES)
    for c in clubes:
        d = modelo["equipos"][c]
        e = Equipo(c, d["ataque"], d["defensa"])
        e.plantel = J.copiar_plantel(PLANTELES[c])
        if c == mio and callable(dt_mio):
            dt_mio(e)
        elif c == mio:
            e.dt = dt_mio
            e.formacion = formacion_preferida(c, e.dt)
        else:
            rng_dt = random.Random(f"dt|{c}")
            e.dt = rng_dt.choices(list(PERSONALIDAD_AL_AZAR),
                                  weights=list(PERSONALIDAD_AL_AZAR.values()))[0]
            e.formacion = formacion_preferida(c, e.dt)
        equipos.append(e)
    M.iniciar_contratos([e.plantel for e in equipos], random.Random(f"{mio}|contratos"))
    M.iniciar_finanzas(equipos)
    p = {"equipos": equipos, "mio": mio, "plan_mio": None, "temporada": 0,
         "semilla": random.randrange(10 ** 9), "historial": [],
         "division": {c: modelo.get("division", {}).get(c, 0) for c in clubes},
         "divisiones": modelo.get("divisiones", ["Liga Profesional"]),
         "libres": [], "ofertas": [], "ventana": None, "movimientos": [], "sondeos": {}}
    empezar_temporada(p)
    iniciar_tecnicos(p)
    iniciar_club(p)
    iniciar_reserva(p)
    return p


def empezar_temporada(p):
    p["temporada"] += 1
    reponer_fisico(*p["equipos"])
    # cada división arma su fixture; en cada fecha juegan todas
    rng = random.Random(f"{p['semilla']}|{p['temporada']}")
    p["fixture"] = []
    for d in range(len(p["divisiones"])):
        indices = [i for i, e in enumerate(p["equipos"]) if division_de(p, e.nombre) == d]
        for k, fecha in enumerate(armar_fixture(len(indices), rng)):
            if k == len(p["fixture"]):
                p["fixture"].append([])
            p["fixture"][k] += [(indices[a], indices[b]) for a, b in fecha]
    p["tabla"] = {e.nombre: Counter(PJ=0) for e in p["equipos"]}
    p["goleadores"] = Counter()
    p["numero"] = 0
    for e in p["equipos"]:
        for j in e.plantel:
            j.partidos = 0
    if "tecnicos" in p:
        arrancar_temporada_dt(p)
    if "staff_libres" in p:
        renovar_staff_libres(p)


def cambios_de_categoria(p):
    """Quiénes bajan y quiénes suben: [(club, de, a)]."""
    cambios = []
    for d in range(len(p["divisiones"]) - 1):
        arriba = [n for n, _ in ordenar_tabla(tabla_division(p, d))]
        abajo = [n for n, _ in ordenar_tabla(tabla_division(p, d + 1))]
        cambios += [(n, d, d + 1) for n in arriba[-CAMBIOS_DE_CATEGORIA:]]
        cambios += [(n, d + 1, d) for n in abajo[:CAMBIOS_DE_CATEGORIA]]
    return cambios


SUBA_DE_INGRESOS = 1.5       # subir a una categoría más arriba multiplica los ingresos


def cerrar_temporada(p):
    """Anota los campeones en el historial, hace los ascensos y descensos,
    y pasa el año de todos los planteles."""
    registro = {"temporada": p["temporada"], "campeones": []}
    for d, nombre in enumerate(p["divisiones"]):
        campeon, f = ordenar_tabla(tabla_division(p, d))[0]
        registro["campeones"].append([nombre, campeon, f["Pts"]])
        orden = [n for n, _ in ordenar_tabla(tabla_division(p, d))]
        M.premios([e for e in p["equipos"] if division_de(p, e.nombre) == d], orden, p["mio"])
    registro["campeon"], registro["puntos"] = registro["campeones"][0][1:]
    (goleador, club), goles = goleadores_division(p, 0).most_common(1)[0]
    registro["goleador"] = f"{goleador} ({club}), {goles}"
    if p["mio"]:
        d = division_de(p, p["mio"])
        registro["puesto"] = posicion(tabla_division(p, d), p["mio"])[0]
        registro["division_mio"] = p["divisiones"][d]
    registro["ascensos"], registro["descensos"] = [], []
    balance_de_temporada(p, registro)
    for nombre, campeon, _ in registro["campeones"]:
        e = next(x for x in p["equipos"] if x.nombre == campeon)
        e.hinchada = min(100.0, e.hinchada + 15)
    for club, de, a in cambios_de_categoria(p):
        p["division"][club] = a
        e = next(x for x in p["equipos"] if x.nombre == club)
        e.hinchada = max(0.0, min(100.0, e.hinchada + (15 if a < de else -20)))
        if a < de:
            e.ingreso = round(e.ingreso * SUBA_DE_INGRESOS, 3)
            registro["ascensos"].append(club)
        else:
            e.ingreso = round(e.ingreso / SUBA_DE_INGRESOS, 3)
            registro["descensos"].append(club)
    p["historial"].append(registro)
    for j in p["libres"]:
        j.edad += 1
    rng = random.Random(f"{p['semilla']}|{p['temporada']}|retiros")
    usados = {j.completo for e in p["equipos"] for j in e.plantel}
    # pasa un año de contrato para todos
    for e in p["equipos"]:
        for j in e.plantel:
            j.contrato -= 1
    cambios = {}
    for e in p["equipos"]:
        cambios[e.nombre] = J.pasar_temporada(e.plantel, e.ataque, e.defensa, rng, usados,
                                              C.cantera(e) if e.instalaciones else 0.0,
                                              reponer=not p.get("con_reserva"))
        for j in cambios[e.nombre][1]:       # los juveniles firman su primer contrato
            M.firmar(j, anios=3)
    p["fin_contratos"] = M.vencimientos_ia(p["equipos"], p["mio"], p["libres"], rng)
    if p.get("con_reserva"):
        usados |= {j.completo for e in p["equipos"] for j in e.reserva}
        for e in p["equipos"]:
            C.pasar_anio_reserva(e, rng)
            if e.nombre != p["mio"]:
                C.reserva_ia(e)
            nuevos = C.llegan_pibes(e, rng, usados)
            cambios[e.nombre] = (cambios[e.nombre][0], cambios[e.nombre][1] + nuevos)
    contratos_dt(p)
    return cambios


def balance_de_temporada(p, registro):
    """Fin de temporada: el prestigio de cada DT sube o baja según cómo le
    fue contra lo que se esperaba, y se anotan sus logros."""
    campeones = {c: nombre for nombre, c, _ in registro["campeones"]}
    cambios = {club: (de, a) for club, de, a in cambios_de_categoria(p)}
    temporada = p["temporada"]
    for e in p["equipos"]:
        t = p["tecnicos"].get(e.nombre)
        if t is None:
            continue
        d = division_de(p, e.nombre)
        puesto = posicion(tabla_division(p, d), e.nombre)[0]
        T.cambiar_prestigio(t, max(-6, min(6, 0.6 * (p["esperado"][e.nombre] - puesto))))
        if e.nombre in campeones:
            T.cambiar_prestigio(t, 8)
            t.logros.append(f"🏆 Campeón {campeones[e.nombre]} T{temporada} con {e.nombre}")
        if e.nombre in cambios:
            de, a = cambios[e.nombre]
            if a < de:
                T.cambiar_prestigio(t, 6)
                t.logros.append(f"⬆ Ascendió con {e.nombre} T{temporada}")
            else:
                T.cambiar_prestigio(t, -6)
                t.logros.append(f"⬇ Descendió con {e.nombre} T{temporada}")


# ---------------------------------------------------------------- hinchada
# El humor de cada hinchada (0 a 100) sube y baja con los resultados, pesa
# el doble en los clásicos, y se nota en la plata (entradas y socios), en la
# localía y en la presión sobre el DT. Los medios pesan más en los grandes.
CLASICOS = {frozenset(par) for par in (
    ("Boca Juniors", "River Plate"), ("Racing Club", "Independiente"),
    ("Rosario Central", "Newells Old Boys"), ("Estudiantes L.P.", "Gimnasia L.P."),
    ("San Lorenzo", "Huracan"), ("Colon de Santa Fe", "Union de Santa Fe"),
    ("Talleres Cordoba", "Belgrano"), ("Lanus", "Banfield"),
    ("Velez Sarsfield", "Ferro"), ("Atl. Tucuman", "San Martin Tucuman"),
    ("Godoy Cruz", "Ind. Rivadavia"), ("Chacarita", "Atlanta"),
    ("Quilmes", "Arsenal Sarandi"), ("Los Andes", "Temperley"))}
ENTRADAS = 0.10   # la hinchada mueve hasta un 10% los ingresos del año


def es_clasico(a, b):
    return frozenset((a, b)) in CLASICOS


def peso_medios(p, club):
    """Cuánto pesan los medios: mucho en los grandes, poco en el ascenso."""
    if division_de(p, club) > 0:
        return 0.8
    return 1.4 if p["esperado_global"][club] <= 6 else 1.0


def cara(h):
    return "😍" if h >= 75 else "🙂" if h >= 55 else "😐" if h >= 35 else "😡"


def hinchada_fecha(p, partidos):
    """Después de cada fecha: el humor de las hinchadas y lo que entra por
    entradas y socios."""
    mio = p["mio"]
    for local, visitante, gl, gv in partidos:
        clasico = es_clasico(local.nombre, visitante.nombre)
        for e, gf, gc in ((local, gl, gv), (visitante, gv, gl)):
            antes = e.hinchada
            cambio = 3 if gf > gc else -0.5 if gf == gc else -3
            if clasico:
                cambio *= 2.5
            e.hinchada = max(0.0, min(100.0, e.hinchada + cambio + 0.03 * (60 - e.hinchada)))
            if e.nombre == mio:
                t = mi_dt(p)
                if antes >= 30 > e.hinchada and t:
                    p["noticias"].append(f"📰 Silbidos en la cancha de {mio}: la hinchada "
                                         f"pide la cabeza de {t.completo}.")
                elif antes <= 85 < e.hinchada:
                    p["noticias"].append(f"📰 ¡Banderazo! La hinchada de {mio} está de fiesta.")
        if clasico and division_de(p, local.nombre) == division_a_mostrar(p):
            p["noticias"].append(f"📰 Clásico: {local.nombre} {gl}-{gv} {visitante.nombre}")
    for e in p["equipos"]:
        e.caja += ENTRADAS * e.ingreso * (e.hinchada - 60) / 40 / len(p["fixture"])


def cambiar_hinchada(e, delta):
    e.hinchada = max(0.0, min(100.0, e.hinchada + delta))


def mostrar_historial(p):
    print("\n=== HISTORIAL ===")
    for r in p["historial"]:
        print(f"Temporada {r['temporada']}:")
        for nombre, campeon, pts in r.get("campeones", [["", r["campeon"], r["puntos"]]]):
            print(f"  🏆 {campeon} ({pts} pts)" + (f" · {nombre}" if nombre else ""))
        if "puesto" in r:
            donde = f" en la {r['division_mio']}" if "division_mio" in r else ""
            print(f"  {p['mio']}: {r['puesto']}°{donde}")
        print(f"  Goleador: {r['goleador']}")
        if r.get("ascensos"):
            print(textwrap.fill("  ⬆ Suben: " + ", ".join(r["ascensos"]), ANCHO,
                                subsequent_indent="    "))
            print(textwrap.fill("  ⬇ Bajan: " + ", ".join(r["descensos"]), ANCHO,
                                subsequent_indent="    "))
    if not p["historial"]:
        print("Todavía no terminó ninguna temporada.")


def jugar_una_fecha(p, modelo, relato=None):
    """Juega la próxima fecha de todas las divisiones, con el entrenamiento,
    las finanzas, los DT y la hinchada de la semana, y guarda la partida.
    relato: None (sin relato), "consola" (relata tu partido en la terminal) o
    "app" (devuelve el relato de tu partido sin imprimir).
    Devuelve {"resultados": [(es_mio, texto, división)], "informe": lo del
    entrenamiento de tu club, "obras": textos, "partido": tu partido o None}."""
    equipos, mio = p["equipos"], p["mio"]
    abrir_ventana(p)       # por si se saltea la fecha en que abre el mercado
    cierra = ventana_actual(p)  # la ventana que se cierra al jugar esta fecha
    fixture, tabla, semilla = p["fixture"], p["tabla"], p["semilla"]
    for e in equipos:
        e.moral = T.moral(p["tecnicos"].get(e.nombre))
    marcadores, partidos = {}, []
    fecha = fixture[p["numero"]]
    p["numero"] += 1
    numero = p["numero"]
    clave = f"{semilla}|{p['temporada']}|{numero}"
    resultados, informe, obras, mi_partido = [], None, [], None
    for l, v in fecha:
        local, visitante = equipos[l], equipos[v]
        es_mio = mio in (local.nombre, visitante.nombre)
        if es_mio and relato == "consola":
            print("\n" + "#" * ANCHO)
            print(f" FECHA {numero} de {len(fixture)} · TEMPORADA {p['temporada']}")
            print("#" * ANCHO)
            input("Enter para jugar tu partido...")
        gl, gv, stats = simular_partido(local, visitante, modelo,
                                        mostrar=es_mio and relato == "consola",
                                        semilla=f"{clave}|{l}|{v}",
                                        relato=es_mio and relato == "app")
        anotar(tabla, local, visitante, gl, gv)
        marcadores[local.nombre], marcadores[visitante.nombre] = (gl, gv), (gv, gl)
        partidos.append((local, visitante, gl, gv))
        for lado, j, _ in stats["goles"]:
            p["goleadores"][(j.corto, (local if lado == "L" else visitante).nombre)] += 1
        resultados.append((es_mio, f"{local.nombre[:15]} {gl}-{gv} {visitante.nombre[:15]}",
                           division_de(p, local.nombre)))
        if es_mio:
            mi_partido = dict(stats, local=local.nombre, visitante=visitante.nombre,
                              gl=gl, gv=gv)
    # Recuperación y entrenamiento de la semana
    rng_entreno = random.Random(f"{clave}|entrenamiento")
    for e in equipos:
        for j in e.plantel:
            j.fisico = min(1.0, j.fisico + RECUPERO_FECHA + C.recupero_extra(e))
        plan_mio = p["plan_mio"]
        plan = plan_mio if e.nombre == mio and plan_mio else plan_dt(e, rng_entreno)
        mejoras, lesionados = J.entrenar(e.plantel, *plan, rng_entreno,
                                         C.multiplicadores(e))
        J.entrenar(e.reserva, "completo", "suave", rng_entreno, C.multiplicadores(e))
        if e.nombre == mio:
            informe = (plan, mejoras, lesionados, plan_mio is None)
    M.cobrar_fecha(equipos, len(fixture))
    for e in equipos:
        C.pagar_fecha(e, len(fixture))
        for tipo in C.avanzar_obras(e):
            if e.nombre == mio:
                obras.append(f"🏗 Terminó la obra: {C.INSTALACIONES[tipo]} "
                             f"nivel {e.instalaciones[tipo]}.")
    tras_fecha_dt(p, marcadores, cierra)
    hinchada_fecha(p, partidos)
    guardar_partida(p)
    return {"resultados": resultados, "informe": informe, "obras": obras,
            "partido": mi_partido}


def torneo_largo(modelo):
    if len(PLANTELES) < 4:
        print("Hacen falta al menos 4 clubes reales en el modelo.")
        return
    print("\n=== TORNEO LARGO ===")
    p = cargar_partida()
    if p:
        club = f", {p['mio']}" if p["mio"] else ""
        print(f"Hay una partida guardada: temporada {p['temporada']}, "
              f"fecha {p['numero']} de {len(p['fixture'])}{club}.")
        print("1) Seguirla  2) Empezar una nueva (se borra)")
        if input("> ").strip() == "2":
            p = None
    if not p:
        p = nueva_partida(modelo)
        guardar_partida(p)
    equipos, mio = p["equipos"], p["mio"]
    print(f"{len(equipos)} equipos, ida y vuelta.")
    if len(p["divisiones"]) > 1:
        print(", ".join(p["divisiones"]) + f": entre cada una bajan "
              f"{CAMBIOS_DE_CATEGORIA} y suben {CAMBIOS_DE_CATEGORIA}.")
    informe = None             # lo que pasó en el último entrenamiento de tu club
    informe_obras = []         # obras de tu club que se terminaron

    def jugar_fecha(con_relato):
        nonlocal informe
        r = jugar_una_fecha(p, modelo, "consola" if con_relato else None)
        informe = r["informe"]
        informe_obras.extend(r["obras"])
        return r["resultados"]

    def resumen_mio():
        for texto in informe_obras:
            print(texto)
        informe_obras.clear()
        if mio:
            d = division_de(p, mio)
            pos, f = posicion(tabla_division(p, d), mio)
            donde = f" en la {p['divisiones'][d]}" if len(p["divisiones"]) > 1 else ""
            print(f"\n{mio}: {pos}°{donde} con {f['Pts']} puntos "
                  f"({f['G']}G {f['E']}E {f['P']}P)")
            print(f"Caja: {M.plata(mi_equipo().caja)} · Hinchada: "
                  f"{cara(mi_equipo().hinchada)} {mi_equipo().hinchada:.0f}")

    def mi_equipo():
        return next(e for e in equipos if e.nombre == mio)

    while True:
        total = len(p["fixture"])
        if p["numero"] >= total:
            if not fin_de_temporada(p):
                return
            continue
        if mio and any(j.contrato <= 0 for j in mi_equipo().plantel):
            renovaciones(p)
            guardar_partida(p)
        if mio and any(j.edad >= C.EDAD_LIMITE for j in mi_equipo().reserva):
            pibes_que_cumplen_21(p)
            guardar_partida(p)
        abrir_ventana(p)
        abierto = ventana_actual(p) is not None
        if mio and not p["sin_dt"]:
            if p["reunion"]:
                mostrar_reunion(p)
                guardar_partida(p)
            if p["tecnicos"].get(mio) is None:
                contratar_dt(p)
                guardar_partida(p)
        print(f"\n--- Fecha {p['numero'] + 1} de {total} · Temporada {p['temporada']} ---")
        print("1) Jugar fecha  2) Jugar 5 fechas")
        print("3) Jugar hasta el final  4) Ver tabla")
        print("5) Goleadores  6) Guardar y salir")
        print("7) Entrenamiento  8) Mi plantel\n9) Historial" if mio else "9) Historial")
        if mio:
            print("10) Mercado de pases " + ("(abierto)" if abierto else "(cerrado)"))
            if not p["sin_dt"]:
                print("11) Mi DT")
            print("12) Instalaciones y cuerpo técnico")
            if p.get("con_reserva"):
                print(f"13) Reserva ({len(mi_equipo().reserva)} pibes)")
        opcion = input("> ").strip()
        if opcion in ("1", "2", "3") and mio and promesas_pendientes(p):
            for pr in promesas_pendientes(p):
                print(textwrap.fill(f"⚠ Le prometiste al DT un {T.que_prometio(pr)} "
                                    f"y el plazo vence con esta fecha.", ANCHO))
            print("¿Jugar igual? (s/n)")
            if input("> ").strip().lower() != "s":
                continue
        if opcion == "1":
            resultados = jugar_fecha(con_relato=True)
            input("\nEnter para ver los resultados de la fecha...")
            d = division_a_mostrar(p)
            print(f"\nResultados de la fecha {p['numero']} ({p['divisiones'][d]}):")
            for es_mio, r, div in resultados:
                if div == d:
                    print(("► " if es_mio else "  ") + r)
            resumen_mio()
            if informe:
                mostrar_entrenamiento(mio, *informe)
            mostrar_noticias(p)
        elif opcion in ("2", "3"):
            hasta = total if opcion == "3" else min(total, p["numero"] + 5)
            while p["numero"] < hasta:
                resultados = jugar_fecha(con_relato=False)
                propio = [r for es_mio, r, _ in resultados if es_mio]
                print(f"Fecha {p['numero']}: " + (propio[0] if propio else "jugada"))
                mostrar_noticias(p)
                # se corta si tu DT quiere hablar de algo grave
                if p["reunion"] and p["reunion"]["prioridad"] >= 80:
                    print("📣 Tu DT pidió una reunión urgente.")
                    break
            resumen_mio()
        elif opcion == "4":
            mostrar_tabla(tabla_division(p, pedir_division(p)))
        elif opcion == "5":
            mostrar_goleadores(goleadores_division(p, pedir_division(p)), 10)
        elif opcion == "6":
            guardar_partida(p)
            print("Partida guardada. La seguís desde 'Torneo largo'.")
            return
        elif opcion == "7" and mio:
            p["plan_mio"] = pedir_entrenamiento()
            if p["plan_mio"]:
                print(f"Plan: {p['plan_mio'][0]} ({p['plan_mio'][1]}) todas las semanas.")
                opinion_entrenamiento(p)
            else:
                print("El DT decide el entrenamiento cada semana.")
            guardar_partida(p)
        elif opcion == "8" and mio:
            J.mostrar_plantel(mio, next(e for e in equipos if e.nombre == mio).plantel)
        elif opcion == "9":
            mostrar_historial(p)
        elif opcion == "13" and mio and p.get("con_reserva"):
            menu_reserva(p)
            guardar_partida(p)
        elif opcion == "12" and mio:
            menu_club(p)
            guardar_partida(p)
        elif opcion == "11" and mio and not p["sin_dt"]:
            menu_dt(p)
            guardar_partida(p)
        elif opcion == "10" and mio:
            if abierto:
                menu_mercado(p)
                guardar_partida(p)
            else:
                print(f"El mercado está cerrado. Abre en la pretemporada y "
                      f"antes de la fecha {total // 2 + 1}. Caja: {M.plata(mi_equipo().caja)}")
                if p["movimientos"]:
                    mostrar_movimientos(p)
        else:
            print("Elegí una opción de la lista.")


# ---------------------------------------------------------------- técnicos
# Cada club tiene un DT con nombre, prestigio, sueldo, contrato y ánimo
# (ver tecnicos.py). El de tu club te pide reuniones; los de los otros
# clubes pueden ser echados si la presión es insoportable.
PRIORIDAD = {"renuncia": 100, "renovacion": 95, "promesa": 90, "lo_quieren": 88,
             "ultimatum": 80, "venta": 70, "entrenamiento": 65, "formacion": 65,
             "racha": 60, "refuerzo": 50, "regular": 10}


def fuerza_titular(e):
    niveles = sorted((J.nivel(j) for j in e.plantel), reverse=True)[:11]
    return sum(niveles) / len(niveles)


def calcular_esperado(p):
    """Puesto que se espera de cada club en su división (para la presión) y
    en todo el fútbol (para el prestigio de su DT)."""
    orden = sorted(p["equipos"], key=lambda e: (division_de(p, e.nombre), -fuerza_titular(e)))
    p["esperado_global"] = {e.nombre: i for i, e in enumerate(orden, 1)}
    p["esperado"] = {}
    for d in range(len(p["divisiones"])):
        en_d = [e for e in orden if division_de(p, e.nombre) == d]
        p["esperado"].update({e.nombre: i for i, e in enumerate(en_d, 1)})


def iniciar_tecnicos(p):
    """Un DT para cada club. Los grandes tienen DT de más prestigio."""
    rng = random.Random(f"{p['semilla']}|tecnicos")
    calcular_esperado(p)
    usados = set()
    p["tecnicos"] = {}
    total = len(p["equipos"])
    for e in p["equipos"]:
        if e.dt is None:          # sin DT: táctica fija
            continue
        prestigio = T.prestigio_para(p["esperado_global"][e.nombre], total, rng)
        p["tecnicos"][e.nombre] = T.nuevo(rng, usados, e.dt, prestigio)
        T.llega_a(p["tecnicos"][e.nombre], e.nombre, p["temporada"])
        e.ingreso += p["tecnicos"][e.nombre].sueldo   # el club ya contaba con pagarle
    p["dts_libres"] = []
    T.bolsa_libres(p["dts_libres"], rng, usados)
    p["sin_dt"] = bool(p["mio"]) and p["mio"] not in p["tecnicos"]
    p.update(reunion=None, noticias=[], fichajes_ventana=[],
             ultimos={e.nombre: "" for e in p["equipos"]}, prox_reunion=4)


def arrancar_temporada_dt(p):
    calcular_esperado(p)
    p["ultimos"] = {e.nombre: "" for e in p["equipos"]}
    p["prox_reunion"] = 4
    for t in p["tecnicos"].values():
        if t:
            t.presion = 40.0
    usados = {t.completo for t in p["tecnicos"].values() if t}
    T.bolsa_libres(p["dts_libres"], random.Random(f"{p['semilla']}|{p['temporada']}|dts"),
                   usados)


def proponer(p, reunion, tema):
    """Deja una reunión pendiente con tu DT, si es más importante que la que
    ya había."""
    reunion["prioridad"] = PRIORIDAD[tema]
    actual = p["reunion"]
    if actual is None or reunion["prioridad"] >= actual["prioridad"]:
        p["reunion"] = reunion


def mi_dt(p):
    return p["tecnicos"].get(p["mio"]) if p["mio"] else None


def pedido_de_refuerzo(p, abierta=None):
    """El puesto más flojo, el nivel que tiene hoy y la ventana en que se
    tiene que cumplir si se le promete."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    pos, actual = M.necesidad(mi)
    ventana = T.proxima_ventana(p["temporada"], p["numero"], len(p["fixture"]), abierta)
    return mi, pos, round(actual), ventana


def promesas_pendientes(p):
    """Lo que le prometiste al DT para la ventana abierta y todavía no llegó."""
    t, clave = mi_dt(p), ventana_actual(p)
    if t is None or clave is None:
        return []
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    return [pr for pr in t.promesas
            if pr["ventana"] == clave and not T.cumple(pr, p["fichajes_ventana"], mi.staff)]


def candidatos_del_dt(p, t, pos, nivel, rng):
    """Los jugadores que el DT propone para el puesto: [(nombre, línea)]."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    lista = M.recomendar(p["equipos"], mi, p["libres"], pos, nivel + 3, t.personalidad,
                         t.prestigio, rng)
    salida = []
    for i, (j, club, precio) in enumerate(lista):
        donde = (f"{club.nombre}, piden {M.plata(precio)}" if club
                 else f"libre, pide {M.plata(M.sueldo_pedido(j))}/año")
        gusta = " · ★ mi preferido" if i == 0 else ""
        puesto = j.pos if j.pos == pos else f"{j.pos}→{pos}"
        salida.append((j.completo, f"{j.corto} ({puesto}, {j.edad}a, Nv{J.nivel(j)}): "
                                   f"{donde}{gusta}"))
    return salida


def pedido_de_mercado(p, clave):
    """Cuando abre el mercado, el DT pide lo que más le falta."""
    t = mi_dt(p)
    if t is None:
        return
    mi, pos, nivel, ventana = pedido_de_refuerzo(p, clave)
    if any(pr["ventana"] == clave for pr in t.promesas):
        return
    costo = 1.2 * math.exp(0.13 * (nivel + 3 - 70))
    rng = random.Random(f"{p['semilla']}|{clave}|pedido")
    proponer(p, T.reunion_refuerzo(t, rng, pos, nivel, mi.caja, costo, ventana, True,
                                   candidatos_del_dt(p, t, pos, nivel, rng)), "refuerzo")


def aviso_venta(p, mi, j):
    """Si vendés a un titular, el DT se entera (y no le gusta). Si es una de
    las tres figuras, la hinchada tampoco."""
    if j in sorted(mi.plantel, key=J.nivel)[-3:]:
        cambiar_hinchada(mi, -8)
        print(f"😡 A la hinchada no le gustó que se vaya {j.corto}.")
    t = mi_dt(p)
    if t is None or id(j) not in M.titulares(mi):
        return
    rng = random.Random(f"{p['semilla']}|venta|{j.completo}")
    proponer(p, T.reunion_venta(t, rng, j.corto, j.pos, p["ventana"]), "venta")


def reemplazar_dt(p, e, rng, motivo):
    """Un club de la computadora cambia de DT: se queda con el libre que
    mejor le cuadra según su tamaño."""
    viejo = p["tecnicos"].get(e.nombre)
    total = len(p["equipos"])
    buscado = T.prestigio_para(p["esperado_global"][e.nombre], total, rng)
    candidatos = [t for t in p["dts_libres"] if t.ultimo_club != e.nombre]
    nuevo = min(candidatos, key=lambda t: abs(t.prestigio - buscado) + rng.random() * 5)
    p["dts_libres"].remove(nuevo)
    T.reiniciar(nuevo)
    p["tecnicos"][e.nombre] = nuevo
    T.llega_a(nuevo, e.nombre, p["temporada"])
    e.dt = nuevo.personalidad
    e.formacion = formacion_preferida(f"{e.nombre}|{nuevo.apellido}", e.dt)
    if viejo:
        T.reiniciar(viejo)
        T.se_va_de(viejo, p["temporada"])
        if motivo == "echó":
            viejo.despidos += 1
            T.cambiar_prestigio(viejo, -4)
        viejo.ultimo_club = e.nombre
        p["dts_libres"].append(viejo)
        p["noticias"].append(f"📰 {e.nombre} {motivo} a {viejo.completo}. "
                             f"Asume {nuevo.completo} ({nuevo.personalidad}).")


def tras_fecha_dt(p, marcadores, cierra):
    """Después de cada fecha: ánimo de todos los DT, despidos en los otros
    clubes, y lo que te quiere plantear el tuyo."""
    p["noticias"] = []
    rng = random.Random(f"{p['semilla']}|{p['temporada']}|{p['numero']}|dt")
    jugadas = p["numero"]
    for e in p["equipos"]:
        gf, gc = marcadores.get(e.nombre, (0, 0))
        p["ultimos"][e.nombre] = (p["ultimos"][e.nombre] +
                                  ("G" if gf > gc else "E" if gf == gc else "P"))[-10:]
        t = p["tecnicos"].get(e.nombre)
        if t is None:
            continue
        T.tras_partido(t, gf, gc)
        puesto = posicion(tabla_division(p, division_de(p, e.nombre)), e.nombre)[0]
        T.actualizar_presion(t, puesto, p["esperado"][e.nombre], p["ultimos"][e.nombre],
                             jugadas, peso_medios(p, e.nombre), e.hinchada)
        if e.nombre != p["mio"] and T.lo_echan(t, rng):
            reemplazar_dt(p, e, rng, "echó")
    # sueldos de los DT
    for e in p["equipos"]:
        t = p["tecnicos"].get(e.nombre)
        if t:
            e.caja -= t.sueldo / len(p["fixture"])
    t = mi_dt(p)
    if t is None:
        return
    mi, pos, nivel, ventana = pedido_de_refuerzo(p)
    # promesas de la ventana que acaba de cerrar
    if cierra:
        for promesa, ok, exacto in T.revisar_promesas(t, cierra, p["fichajes_ventana"],
                                                       mi.staff):
            proponer(p, T.reunion_promesa(t, rng, promesa, ok, exacto), "promesa")
        p["pedidos_dt"] = []
    if t.satisfaccion < T.RENUNCIA:
        proponer(p, T.reunion_renuncia(t, rng), "renuncia")
        return
    if t.satisfaccion < T.ULTIMATUM and "ultimatum" not in t.avisos:
        t.avisos.append("ultimatum")
        proponer(p, T.reunion_ultimatum(t, rng, pos, nivel, ventana), "ultimatum")
        return
    if t.satisfaccion > 50 and "ultimatum" in t.avisos:
        t.avisos.remove("ultimatum")
    opiniones_tras_fecha(p, t, mi, *marcadores.get(mi.nombre, (0, 0)), rng)
    ultimos = p["ultimos"][mi.nombre]
    sin_ganar = len(ultimos) - len(ultimos.rstrip("EP"))
    sin_perder = len(ultimos) - len(ultimos.rstrip("GE"))
    if sin_ganar in (3, 5, 7):
        proponer(p, T.reunion_racha(t, rng, sin_ganar, True, pos, nivel, ventana), "racha")
    elif sin_perder in (5, 8) and ultimos.endswith("G"):
        proponer(p, T.reunion_racha(t, rng, sin_perder, False, pos, nivel, ventana), "racha")
    elif jugadas >= p["prox_reunion"]:
        p["prox_reunion"] = jugadas + rng.randint(3, 5)
        peor = min(J.nivel(j) for j in mi.plantel)
        juveniles = [j for j in mi.plantel + mi.reserva
                     if j.edad <= 21 and j.potencial - J.nivel(j) >= 8
                     and (J.nivel(j) >= peor if j in mi.reserva else id(j) not in M.titulares(mi))
                     and f"juvenil:{j.completo}" not in t.avisos]
        prometido = any(pr.get("pos") == pos for pr in t.promesas)
        tits = M.titulares(mi)
        # a mitad de temporada mira los contratos que vencen
        vencen = [j for j in mi.plantel if j.contrato == 1 and id(j) in tits
                  and jugadas >= len(p["fixture"]) // 2 - 3
                  and f"vence:{j.completo}|{p['temporada']}" not in t.avisos]
        sueldos = sorted(M.sueldo(j) for j in mi.plantel)
        no_usa = [j for j in mi.plantel if jugadas >= 10 and j.partidos <= 0.2 * jugadas
                  and j.edad > 21 and M.sueldo(j) >= sueldos[len(sueldos) // 2]
                  and f"no_usa:{j.completo}|{p['temporada']}" not in t.avisos]
        sin_staff = [r for r in C.ROLES if mi.staff.get(r, {}).get("nivel", 0) <= 1
                     and not any(pr.get("rol") == r for pr in t.promesas)] if mi.instalaciones else []
        opciones = ((["juvenil"] if juveniles else []) + ([] if prometido else ["refuerzo"])
                    + (["vence"] if vencen else []) + (["no_usa"] if no_usa else [])
                    + (["staff"] if sin_staff else []))
        # si no hay nada puntual, a veces pasa a charlar y a veces no
        tema = rng.choice(opciones) if opciones and rng.random() < 0.7 else "general"
        if tema == "general" and rng.random() < 0.5:
            return
        if tema == "staff":
            rol = rng.choice(sin_staff)
            reunion = T.reunion_staff(t, rng, rol, C.ROLES[rol], ventana)
        elif tema == "vence":
            j = max(vencen, key=J.nivel)
            t.avisos.append(f"vence:{j.completo}|{p['temporada']}")
            reunion = T.reunion_vence(t, rng, j)
        elif tema == "no_usa":
            j = max(no_usa, key=M.sueldo)
            t.avisos.append(f"no_usa:{j.completo}|{p['temporada']}")
            reunion = T.reunion_no_usa(t, rng, j, j.partidos)
        elif tema == "juvenil":
            j = max(juveniles, key=lambda j: j.potencial)
            t.avisos.append(f"juvenil:{j.completo}")
            reunion = T.reunion_juvenil(t, rng, j, j in mi.reserva)
        elif tema == "refuerzo":
            costo = 1.2 * math.exp(0.13 * (nivel + 3 - 70))
            reunion = T.reunion_refuerzo(t, rng, pos, nivel, mi.caja, costo, ventana, False,
                                         candidatos_del_dt(p, t, pos, nivel, rng))
        else:
            reunion = T.reunion_general(t, rng)
        proponer(p, reunion, "regular")


def contratos_dt(p):
    """Fin de temporada: se descuenta un año de contrato. En los otros
    clubes renuevan si la cosa anduvo bien; con el tuyo se habla."""
    rng = random.Random(f"{p['semilla']}|{p['temporada']}|contratos")
    cambiaron = []
    for e in p["equipos"]:
        t = p["tecnicos"].get(e.nombre)
        if t is None:
            continue
        t.contrato -= 1
        if t.contrato > 0:
            continue
        if e.nombre == p["mio"]:
            proponer(p, T.reunion_renovacion(t, rng, round(t.sueldo * 1.1, 3)), "renovacion")
        elif t.presion < 60:
            t.contrato = 2
        else:
            reemplazar_dt(p, e, rng, "no le renovó")
            cambiaron.append(e)
    # si tu DT tiene más prestigio que el que eligió un club más grande, lo tientan
    t = mi_dt(p)
    if t is None:
        return
    mas_grandes = [e for e in cambiaron
                   if p["esperado_global"][e.nombre] < p["esperado_global"][p["mio"]]
                   and t.prestigio >= p["tecnicos"][e.nombre].prestigio + 5]
    if mas_grandes and rng.random() < 0.6:
        club = min(mas_grandes, key=lambda e: p["esperado_global"][e.nombre]).nombre
        proponer(p, T.reunion_lo_quieren(t, rng, club), "lo_quieren")


def mostrar_reunion(p):
    r, t = p["reunion"], mi_dt(p)
    p["reunion"] = None
    if t is None:
        return
    print("\n" + "=" * ANCHO)
    print(f"📣 Reunión con tu DT, {t.completo}")
    print("=" * ANCHO)
    print(textwrap.fill(f"«{r['texto']}»", ANCHO))
    for i, linea in enumerate(r.get("lista", []), 1):
        print(textwrap.fill(f"{i}. {linea}", ANCHO, subsequent_indent="   "))
    n = None
    if r["opciones"]:
        for i, (texto, *_) in enumerate(r["opciones"], 1):
            print(textwrap.fill(f"{i}) {texto}", ANCHO, subsequent_indent="   "))
        n = pedir_numero("> ", 1, len(r["opciones"]))
    else:
        input("\nEnter para seguir...")
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    for texto in resolver_reunion(p, r, n, lambda nombre: ir_a_buscar(p, mi, nombre)):
        print(textwrap.fill(texto, ANCHO))


def resolver_reunion(p, r, n, ir_a_buscar_jugador=None):
    """Aplica la respuesta n (desde 1; None si la reunión no tenía opciones).
    ir_a_buscar_jugador: qué hacer si le decís al DT que vas a buscar a su
    preferido con el mercado abierto (la consola negocia ahí mismo).
    Devuelve los textos para mostrar: lo que contesta el DT y lo que pasó."""
    t = mi_dt(p)
    if t is None:
        return []
    if r["tema"] in ("renuncia", "no_renueva"):
        return [se_va_mi_dt(p)]
    if n is None:
        return []
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    extra, respuesta = T.aplicar(t, r["opciones"][n - 1])
    textos = [f"«{respuesta}»"]
    if r.get("candidatos") and n <= 2:
        p["pedidos_dt"] = r["candidatos"]        # quedan en el mercado como pedidos
        if n == 1 and ventana_actual(p) and ir_a_buscar_jugador:
            ir_a_buscar_jugador(r["candidatos"][0])
        elif n == 1:
            textos.append("Lo vas a encontrar en el mercado, en los pedidos del DT.")
    if extra and "renovar" in extra:
        if extra["renovar"]:
            t.contrato = extra["renovar"]
            t.aumento = round(t.aumento * 1.1, 3)
            textos.append(f"Renovó por {t.contrato} temporadas.")
        else:
            textos.append(se_va_mi_dt(p))
    elif extra and "oferta" in extra:
        textos.append(se_va_a_otro_club(p, t, extra["oferta"]))
    elif extra and "aumento" in extra:
        t.aumento = round(t.aumento * extra["aumento"], 3)
        textos.append(f"Ahora cobra {M.plata(t.sueldo)}/año.")
    elif extra and "plan" in extra:
        p["plan_mio"] = None
        textos.append("El entrenamiento lo decide el DT.")
    elif extra and "subir" in extra:
        pibe = next((j for j in mi.reserva if j.completo == extra["subir"]), None)
        if pibe and len(mi.plantel) < M.PLANTEL_MAX:
            C.subir(mi, pibe)
            textos.append(f"⬆ {pibe.corto} sube a Primera.")
    elif extra and "formacion" in extra:
        mi.formacion_forzada = None
        p["derrotas_formacion"] = 0
        textos.append(f"Vuelve a jugar con su {mi.formacion}.")
    return textos


def se_va_a_otro_club(p, t, club):
    """Tu DT se va a un club más grande, que paga la rescisión. El DT que
    había elegido ese club queda libre."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    otro = next(e for e in p["equipos"] if e.nombre == club)
    compensacion = t.sueldo * max(t.contrato, 1)
    mi.caja += compensacion
    reemplazado = p["tecnicos"][club]
    T.se_va_de(reemplazado, p["temporada"])
    reemplazado.ultimo_club = club
    p["dts_libres"].append(reemplazado)
    T.se_va_de(t, p["temporada"])
    T.reiniciar(t)
    T.llega_a(t, club, p["temporada"])
    p["tecnicos"][club] = t
    otro.dt = t.personalidad
    otro.formacion = formacion_preferida(f"{club}|{t.apellido}", t.personalidad)
    p["tecnicos"][p["mio"]] = None
    return (f"{t.completo} es el nuevo DT de {club}. {club} paga "
            f"{M.plata(compensacion)} de rescisión.")


def se_va_mi_dt(p):
    t = mi_dt(p)
    T.reiniciar(t)
    T.se_va_de(t, p["temporada"])
    t.ultimo_club = p["mio"]
    p["dts_libres"].append(t)
    p["tecnicos"][p["mio"]] = None
    return f"{t.completo} ya no es el DT de {p['mio']}."


def dts_disponibles(p):
    """Los DT libres que se pueden contratar (los de más prestigio primero)."""
    return sorted((t for t in p["dts_libres"] if t.ultimo_club != p["mio"]),
                  key=lambda t: -t.prestigio)[:6]


def contratar(p, t):
    """Contrata a t como DT de tu club. Devuelve el texto del anuncio."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    p["dts_libres"].remove(t)
    T.reiniciar(t)
    T.llega_a(t, mi.nombre, p["temporada"])
    p["tecnicos"][mi.nombre] = t
    mi.dt = t.personalidad
    mi.formacion = formacion_preferida(f"{mi.nombre}|{t.apellido}", t.personalidad)
    mi.formacion_forzada = None
    return (f"✅ {t.completo} es el nuevo DT de {mi.nombre} ({t.personalidad}, "
            f"prefiere el {mi.formacion}).")


def contratar_dt(p):
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    libres = dts_disponibles(p)
    print(f"\n=== {mi.nombre} necesita DT ===")
    for i, t in enumerate(libres, 1):
        print(f"{i}. {t.completo}, {t.edad} años")
        print(f"   {t.personalidad} · prestigio {t.prestigio} · {M.plata(t.sueldo)}/año")
        print(textwrap.fill(f"   {T.resumen_cv(t)}", ANCHO, subsequent_indent="   "))
    t = libres[pedir_numero("¿A quién contratás? ", 1, len(libres)) - 1]
    print(contratar(p, t))


def menu_dt(p):
    t = mi_dt(p)
    T.mostrar(t, p["mio"])
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    costo = t.sueldo * max(t.contrato, 0.5)
    juega = mi.formacion_forzada or mi.formacion
    print(f"Juega con: {juega}" + (" (se lo pediste vos)" if mi.formacion_forzada else ""))
    print(f"\n1) Volver  2) Echarlo (cuesta {M.plata(costo)})")
    print("3) Pedirle que juegue con otra formación")
    opcion = input("> ").strip()
    if opcion == "3":
        pedir_formacion_al_dt(p, mi, t)
        return
    if opcion == "2":
        print("¿Seguro? (s/n)")
        if input("> ").strip().lower() == "s":
            next(e for e in p["equipos"] if e.nombre == p["mio"]).caja -= costo
            p["reunion"] = None
            print(se_va_mi_dt(p))
            contratar_dt(p)


def dice_el_dt(t, texto):
    print(textwrap.fill(f"🗣 {t.apellido}: «{texto}»", ANCHO, subsequent_indent="   "))


def pedir_formacion_al_dt(p, mi, t):
    nombres = list(J.FORMACIONES)
    print("\n0) Que elija él")
    for i, f in enumerate(nombres, 1):
        print(f"{i}) {f}" + (" (la que prefiere)" if f == mi.formacion else ""))
    n = pedir_numero("> ", 0, len(nombres))
    p["derrotas_formacion"] = 0
    if n == 0:
        mi.formacion_forzada = None
        T.cambiar(t, sat=3)
        dice_el_dt(t, "Gracias, presidente. Usted no se va a arrepentir.")
        return
    mi.formacion_forzada = nombres[n - 1]
    if mi.formacion_forzada == mi.formacion:
        mi.formacion_forzada = None
        dice_el_dt(t, "Justo lo que pensaba hacer.")
        return
    T.cambiar(t, sat=-5)
    dice_el_dt(t, f"Usted manda, presidente. Jugamos con el {mi.formacion_forzada}, "
                  f"aunque yo no lo haría.")


def opinion_entrenamiento(p):
    """Cuando elegís vos el entrenamiento, el DT opina."""
    t = mi_dt(p)
    if t is None:
        return
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    suyo = plan_dt(mi, random.Random(f"{p['semilla']}|{p['numero']}|opinion"))
    if tuple(p["plan_mio"]) == tuple(suyo):
        dice_el_dt(t, "Coincido, es lo que yo hubiera hecho.")
    else:
        T.cambiar(t, sat=-3)
        dice_el_dt(t, f"Yo hubiera hecho {suyo[0]} ({suyo[1]}), pero usted manda.")


def opiniones_tras_fecha(p, t, mi, gf, gc, rng):
    """Si le impusiste la formación o el entrenamiento, el DT opina según
    cómo salió el partido."""
    if mi.formacion_forzada:
        if gf > gc:
            T.cambiar(t, sat=1)
            if rng.random() < 0.25:
                p["noticias"].append(f"🗣 {t.apellido}: «Lo admito, con el "
                                     f"{mi.formacion_forzada} jugamos bien.»")
        elif gf < gc:
            T.cambiar(t, sat=-2)
            p["derrotas_formacion"] = p.get("derrotas_formacion", 0) + 1
            if p["derrotas_formacion"] >= 3 and t.personalidad in ("arriesgado", "impulsivo"):
                proponer(p, T.reunion_formacion(t, rng, mi.formacion_forzada,
                                                p["derrotas_formacion"]), "formacion")
                p["derrotas_formacion"] = 0
    if p["plan_mio"]:
        sanos = [j for j in mi.plantel if not j.lesion]
        cansados = sum(j.fisico for j in sanos) / len(sanos) < 0.85
        queja = (cansados and p["plan_mio"][1] == "fuerte") or (gf < gc and rng.random() < 0.15)
        if queja and p["numero"] - p.get("queja_entreno", -99) >= 6:
            p["queja_entreno"] = p["numero"]
            proponer(p, T.reunion_entrenamiento(t, rng), "entrenamiento")


def mostrar_noticias(p):
    for texto in p.get("noticias", []):
        print(textwrap.fill(texto, ANCHO, subsequent_indent="   "))


# ---------------------------------------------------------------- instalaciones
# Predio, centro médico, estadio e inferiores, y el cuerpo técnico (ver club.py).
def iniciar_club(p):
    if "esperado_global" not in p:
        calcular_esperado(p)
    rng = random.Random(f"{p['semilla']}|club")
    C.iniciar(p["equipos"], p["esperado_global"], rng)
    renovar_staff_libres(p)


def iniciar_reserva(p):
    usados = {j.completo for e in p["equipos"] for j in e.plantel}
    C.iniciar_reserva(p["equipos"], random.Random(f"{p['semilla']}|reserva"), usados)
    p["con_reserva"] = True


def renovar_staff_libres(p):
    rng = random.Random(f"{p['semilla']}|{p['temporada']}|staff")
    p["staff_libres"] = C.candidatos(rng, set())


def barra5(n):
    return "█" * n + "░" * (C.NIVEL_MAX - n)


def estrellas(n):
    return "★" * n + "☆" * (C.NIVEL_MAX - n)


EFECTO_INSTALACION = {"predio": "los jugadores mejoran más rápido",
                      "medico": "menos lesiones y más cortas",
                      "estadio": "un 10% más de ingresos",
                      "inferiores": "mejores juveniles"}


def mostrar_club(mi):
    print(f"\n=== {mi.nombre}: CLUB ===")
    print(f"Caja: {M.plata(mi.caja)}")
    print("\nINSTALACIONES")
    for i, (tipo, nombre) in enumerate(C.INSTALACIONES.items(), 1):
        n = mi.instalaciones[tipo]
        obra = next((o for o in mi.obras if o[0] == tipo), None)
        print(f"{i}) {nombre:<14}{barra5(n)} {n}")
        if obra:
            print(f"   en obra → {n + 1}, faltan {obra[1]} fechas")
        elif n < C.NIVEL_MAX:
            print(f"   → {n + 1}: {M.plata(C.costo_obra(tipo, n + 1))}, "
                  f"{C.duracion_obra(n + 1)} fechas")
        else:
            print("   nivel máximo")
    print(f"Mantenimiento: {M.plata(C.mantenimiento(mi))}/año")
    print("\nCUERPO TÉCNICO")
    for i, (rol, nombre) in enumerate(C.ROLES.items(), 1):
        m = mi.staff.get(rol)
        print(f"{i}) {nombre}")
        print(f"   {m['nombre']} {estrellas(m['nivel'])} {M.plata(m['sueldo'])}/año"
              if m else "   (no hay)")


def menu_club(p):
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    while True:
        mostrar_club(mi)
        print("\n1) Mejorar instalación  2) Contratar")
        print("3) Despedir  4) Volver")
        opcion = input("> ").strip()
        if opcion == "1":
            mejorar_instalacion(mi)
        elif opcion == "2":
            contratar_staff(p, mi)
        elif opcion == "3":
            despedir_staff(mi)
        elif opcion == "4":
            return
        else:
            print("Elegí del 1 al 4.")


def mejorar_instalacion(mi):
    tipos = list(C.INSTALACIONES)
    print()
    for i, tipo in enumerate(tipos, 1):
        print(f"{i}) {C.INSTALACIONES[tipo]}: {EFECTO_INSTALACION[tipo]}")
    k = elegir_de_lista(len(tipos), "¿Cuál? (Enter = volver) ")
    if k is None:
        return
    tipo = tipos[k]
    n = mi.instalaciones[tipo] + 1
    if n > C.NIVEL_MAX:
        print("Ya está al máximo.")
        return
    if any(o[0] == tipo for o in mi.obras):
        print("Ya hay una obra en marcha.")
        return
    costo = C.costo_obra(tipo, n)
    if costo > mi.caja:
        print(f"No te alcanza: cuesta {M.plata(costo)} y tenés {M.plata(mi.caja)}.")
        return
    extra = C.mantenimiento(mi)
    print(f"{C.INSTALACIONES[tipo]} a nivel {n}: {M.plata(costo)}, "
          f"{C.duracion_obra(n)} fechas de obra.")
    mi.instalaciones[tipo] += 1
    extra = C.mantenimiento(mi) - extra
    mi.instalaciones[tipo] -= 1
    print(f"El mantenimiento sube {M.plata(extra)}/año. ¿Arrancamos? (s/n)")
    if input("> ").strip().lower() == "s":
        C.empezar_obra(mi, tipo)
        print(f"🏗 Arrancó la obra. Termina en {C.duracion_obra(n)} fechas.")


def elegir_rol(texto):
    roles = list(C.ROLES)
    print()
    for i, rol in enumerate(roles, 1):
        print(f"{i}) {C.ROLES[rol]}")
    k = elegir_de_lista(len(roles), texto)
    return None if k is None else roles[k]


def contratar_staff(p, mi):
    rol = elegir_rol("¿Qué buscás? (Enter = volver) ")
    if rol is None:
        return
    lista = p["staff_libres"][rol]
    if not lista:
        print("No hay nadie disponible hasta la próxima temporada.")
        return
    actual = mi.staff.get(rol)
    if actual:
        print(textwrap.fill(f"Hoy: {actual['nombre']} {estrellas(actual['nivel'])}. Si "
                            f"contratás a otro, se va (cuesta "
                            f"{M.plata(actual['sueldo'] / 2)}).", ANCHO))
    print()
    for i, m in enumerate(lista, 1):
        print(f"{i}) {m['nombre']} {estrellas(m['nivel'])} {M.plata(m['sueldo'])}/año")
    k = elegir_de_lista(len(lista), "¿A quién contratás? (Enter = volver) ")
    if k is None:
        return
    nuevo = lista.pop(k)
    if actual:
        mi.caja -= actual["sueldo"] / 2
    mi.staff[rol] = nuevo
    print(f"✅ {nuevo['nombre']} es el nuevo {C.ROLES[rol].lower()}.")


def despedir_staff(mi):
    rol = elegir_rol("¿A quién despedís? (Enter = volver) ")
    if rol is None:
        return
    m = mi.staff.get(rol)
    if not m:
        print("No hay nadie en ese puesto.")
        return
    print(f"Despedir a {m['nombre']} cuesta {M.plata(m['sueldo'] / 2)}. ¿Seguro? (s/n)")
    if input("> ").strip().lower() == "s":
        mi.caja -= m["sueldo"] / 2
        del mi.staff[rol]
        print(f"{m['nombre']} ya no trabaja en el club.")


# ---------------------------------------------------------------- reserva
# Los pibes de las inferiores (ver club.py). El potencial se ve en estrellas,
# estimado por el club: con un buen coordinador de inferiores, se acerca más.
def linea_pibe(i, j):
    print(f"{i:>2}. {j.pos:<3} {j.corto[:16]:<17}{j.edad}a Nv{J.nivel(j)} {C.estrellas_pot(j)}")


def lista_reserva(mi):
    pibes = sorted(mi.reserva, key=lambda j: (-(j.pot_est or j.potencial), -J.nivel(j)))
    print(f"\n=== Reserva de {mi.nombre} ({len(pibes)}/{C.RESERVA_MAX}) ===")
    print("(★ = potencial que estima el club)")
    for i, j in enumerate(pibes, 1):
        linea_pibe(i, j)
    return pibes


def menu_reserva(p):
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    while True:
        pibes = lista_reserva(mi)
        coord = mi.staff.get("inferiores", {}).get("nivel", 0)
        print(f"Coordinador de inferiores: {estrellas(coord)}")
        print(f"Plantel de Primera: {len(mi.plantel)} jugadores")
        print("\n1) Subir a Primera  2) Dejarlo ir")
        print("3) Ofrecerlo afuera  4) Volver")
        opcion = input("> ").strip()
        if opcion == "4":
            return
        if opcion not in ("1", "2", "3"):
            print("Elegí del 1 al 4.")
            continue
        k = elegir_de_lista(len(pibes), "¿Cuál? (Enter = volver) ")
        if k is None:
            continue
        j = pibes[k]
        if opcion == "1":
            if len(mi.plantel) >= M.PLANTEL_MAX:
                print(f"Tenés {M.PLANTEL_MAX} en el plantel: liberá o vendé a alguno antes.")
                continue
            C.subir(mi, j)
            print(f"⬆ {j.corto} sube a Primera con contrato por 3 temporadas.")
        elif opcion == "2":
            print(f"¿Seguro que dejás ir a {j.corto}? (s/n)")
            if input("> ").strip().lower() == "s":
                mi.reserva.remove(j)
                print(f"{j.corto} deja el club.")
        else:
            ofrecer_pibe(p, mi, j)


def ofrecer_pibe(p, mi, j):
    """Mostrarlo a clubes de afuera (en las ventanas de pases)."""
    if ventana_actual(p) is None:
        print("Solo se puede con el mercado abierto.")
        return
    clave = f"pibe:{j.completo}"
    if clave not in p["sondeos"]:
        rng = random.Random(f"{p['semilla']}|{p['ventana']}|{clave}")
        interesa = rng.random() < 0.25 + 0.12 * ((j.pot_est or j.potencial) - 60) / 8
        p["sondeos"][clave] = ([[rng.choice(M.EXTERIOR), C.oferta_exterior(j, rng)]]
                               if interesa else [])
    ofertas = p["sondeos"][clave]
    if not ofertas:
        print(f"Afuera nadie se interesó por {j.corto} en esta ventana.")
        return
    club, monto = ofertas[0]
    print(f"{club} ofrece {M.plata(monto)} por {j.corto}. ¿Aceptás? (s/n)")
    if input("> ").strip().lower() == "s":
        vender_pibe(p, mi, j, club, monto)


def pibes_que_cumplen_21(p):
    """Pretemporada: los pibes que cumplen 21 suben a Primera o se van."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    grandes = sorted((j for j in mi.reserva if j.edad >= C.EDAD_LIMITE), key=J.nivel,
                     reverse=True)
    print("\n" + "=" * ANCHO)
    print(f"🌱 {len(grandes)} pibe{'s' if len(grandes) > 1 else ''} de la reserva "
          f"cumple{'n' if len(grandes) > 1 else ''} {C.EDAD_LIMITE}")
    print("=" * ANCHO)
    print("Suben a Primera o dejan el club.")
    for j in grandes:
        print()
        linea_pibe(1, j)
        if len(mi.plantel) >= M.PLANTEL_MAX:
            print(f"El plantel está lleno ({M.PLANTEL_MAX}): deja el club.")
            mi.reserva.remove(j)
            continue
        print("1) Subirlo a Primera  2) Dejarlo ir")
        if pedir_numero("> ", 1, 2) == 1:
            C.subir(mi, j)
            print(f"⬆ {j.corto} sube a Primera.")
        else:
            mi.reserva.remove(j)
            print(f"{j.corto} deja el club.")


# ---------------------------------------------------------------- mercado de pases
def ventana_actual(p):
    """Clave de la ventana de pases abierta ahora, o None si está cerrado.
    Abre antes de la primera fecha y a mitad del torneo."""
    if p["numero"] in (0, len(p["fixture"]) // 2):
        return f"{p['temporada']}-{p['numero']}"
    return None


def abrir_ventana(p):
    """La primera vez que se llega a una ventana, los otros clubes hacen sus
    movimientos y le llegan ofertas al club que seguís."""
    clave = ventana_actual(p)
    if clave is None or p["ventana"] == clave:
        return
    p["ventana"] = clave
    p["fichajes_ventana"] = []
    rng = random.Random(f"{p['semilla']}|mercado|{clave}")
    equipos = p["equipos"]
    usados = {j.completo for e in equipos for j in e.plantel}
    usados |= {j.completo for j in p["libres"]}
    viejos = sorted((j for j in p["libres"] if j.edad < 35), key=J.nivel, reverse=True)[:40]
    p["libres"] = viejos + M.generar_libres(equipos, rng, usados, M.nivel_medio(equipos))
    p["movimientos"] = (p.pop("fin_contratos", [])
                        + M.movimientos_ia(equipos, p["mio"], p["libres"], rng,
                                           usados=usados))
    if "staff_libres" in p:
        for e in equipos:
            if e.nombre != p["mio"]:
                noticia = C.invertir_ia(e, rng)
                if noticia:
                    p["movimientos"].append(noticia)
    p["ofertas"] = M.ofertas_por_mios(equipos, p["mio"], rng) if p["mio"] else []
    if p["mio"]:
        mi = next(e for e in equipos if e.nombre == p["mio"])
        for j in mi.reserva:
            if j.pot_est >= 76 and rng.random() < 0.35:
                p["ofertas"].append((rng.choice(M.EXTERIOR), j, C.oferta_exterior(j, rng)))
    p["sondeos"] = {}
    pedido_de_mercado(p, clave)
    guardar_partida(p)
    if p["mio"]:
        print(f"\n🔁 Se abrió el mercado de pases: {len(p['movimientos'])} movimientos"
              + (f", {len(p['ofertas'])} ofertas por tus jugadores" if p["ofertas"] else "")
              + ". Opción 10.")


def mostrar_movimientos(p):
    print("\n--- Movimientos del mercado ---")
    for texto in p["movimientos"] or ["Ninguno."]:
        print(textwrap.fill(texto, ANCHO, subsequent_indent="   "))


def pedir_monto(texto, defecto):
    raw = input(texto).strip().replace(",", ".")
    if not raw:
        return defecto
    try:
        return max(0.0, float(raw))
    except ValueError:
        return 0.0


def linea_jugador(i, j, extra=""):
    """Dos líneas por jugador, para que entre en la pantalla del celular."""
    print(f"{i:>2}. {j.pos:<3} {j.corto[:16]:<17}{j.edad}a Nv{J.nivel(j)} Pot{j.potencial}")
    if extra:
        print(f"    {extra}")


def elegir_de_lista(cantidad, texto="Número (Enter = volver): "):
    raw = input(texto).strip()
    if raw.isdigit() and 1 <= int(raw) <= cantidad:
        return int(raw) - 1
    return None


def pedir_posicion():
    raw = input("Posición (ARQ, DFC, LD, LI, MCD, MC,\n"
                "MCO, ED, EI, DC; Enter = todas): ").strip().upper()
    return raw if raw in J.POSICIONES else None


def aviso_sueldos(mi, extra):
    masa = M.masa_salarial(mi.plantel) + extra
    if masa > mi.ingreso:
        print(f"Ojo: los sueldos ({M.plata(masa)}/año) van a superar tus "
              f"ingresos ({M.plata(mi.ingreso)}/año).")


def negociar(j, pedido, anios, mi):
    """Negociación del sueldo con un jugador. Devuelve el sueldo acordado,
    o None si no hay acuerdo."""
    print(f"{j.corto} pide {M.plata(pedido)}/año por {anios} "
          f"temporada{'s' if anios > 1 else ''}.")
    aviso_sueldos(mi, pedido - (M.sueldo(j) if j in mi.plantel else 0))
    while True:
        print("1) Aceptar  2) Ofrecer otro sueldo  3) No")
        opcion = input("> ").strip()
        if opcion == "1":
            return pedido
        if opcion == "2":
            oferta = pedir_monto("Sueldo por año, en millones: ", pedido)
            if M.acepta(oferta, pedido):
                print(f"Acepta {M.plata(oferta)}/año.")
                return oferta
            print(f"No acepta. Quiere {M.plata(pedido)}/año.")
        elif opcion == "3":
            return None


def menu_mercado(p):
    equipos, mio = p["equipos"], p["mio"]
    mi = next(e for e in equipos if e.nombre == mio)
    rng = random.Random(f"{p['semilla']}|{p['ventana']}|sondeos")
    while True:
        print("\n=== MERCADO DE PASES ===")
        print("Cierra cuando juegues la próxima fecha.")
        for pr in promesas_pendientes(p):
            if "pos" in pr:
                print(textwrap.fill(f"📌 Le prometiste al DT: {T.puesto(pr['pos'])}, "
                                    f"nivel {pr['nivel']} o más", ANCHO,
                                    subsequent_indent="   "))
        print(f"Caja: {M.plata(mi.caja)} · Plantel: {len(mi.plantel)}")
        print(f"Ingresos: {M.plata(mi.ingreso)}/año")
        print(f"Sueldos: {M.plata(M.masa_salarial(mi.plantel))}/año")
        print("1) Buscar jugadores  2) Libres")
        print(f"3) Ofertas recibidas ({len(p['ofertas'])})  4) Vender")
        print("5) Liberar  6) Movimientos")
        print("7) Contratos  8) Volver")
        if p.get("pedidos_dt"):
            print(f"9) 📋 Pedidos del DT ({len(p['pedidos_dt'])})")
        opcion = input("> ").strip()
        if opcion == "1":
            comprar(p, mi)
        elif opcion == "2":
            fichar_libres(p, mi)
        elif opcion == "3":
            ofertas_recibidas(p, mi)
        elif opcion == "4":
            vender(p, mi, rng)
        elif opcion == "5":
            liberar(p, mi)
        elif opcion == "6":
            mostrar_movimientos(p)
        elif opcion == "7":
            renovar(p, mi)
        elif opcion == "8":
            return
        elif opcion == "9" and p.get("pedidos_dt"):
            pedidos_del_dt(p, mi)
        else:
            print("Elegí del 1 al 8.")


def comprar(p, mi):
    pos = pedir_posicion()
    candidatos = [(j, e) for e in p["equipos"] if e is not mi for j in e.plantel
                  if pos is None or j.pos == pos]
    candidatos.sort(key=lambda x: -J.nivel(x[0]))
    candidatos = candidatos[:12]
    tits = {}
    print()
    for i, (j, e) in enumerate(candidatos, 1):
        if e.nombre not in tits:
            tits[e.nombre] = M.titulares(e)
        precio = M.precio_pedido(e, j, tits[e.nombre])
        linea_jugador(i, j, f"{e.nombre[:20]} · piden {M.plata(precio)}")
    k = elegir_de_lista(len(candidatos))
    if k is None:
        return
    negociar_compra(p, mi, *candidatos[k])


def negociar_compra(p, mi, j, vendedor):
    """Negociación con el club y después con el jugador."""
    if len(mi.plantel) >= M.PLANTEL_MAX:
        print(f"Tenés {M.PLANTEL_MAX} jugadores: vendé o liberá a alguno antes.")
        return
    if not M.puede_vender(vendedor, j):
        print(f"{vendedor.nombre} no lo vende: se queda corto en el puesto.")
        return
    pedido = M.precio_pedido(vendedor, j)
    print(f"\n{j.completo} ({j.pos}, {j.edad} años, nivel {J.nivel(j)})")
    print(f"Valor: {M.plata(M.valor(j))} · Contrato: {j.contrato} año{'s' if j.contrato > 1 else ''}")
    print(f"{vendedor.nombre} pide {M.plata(pedido)}.")
    oferta = pedir_monto("Tu oferta en millones (Enter = lo que\npiden): ", pedido)
    if oferta > mi.caja:
        print(f"No te alcanza: tenés {M.plata(mi.caja)}.")
        return
    resp, monto = M.respuesta(vendedor, j, oferta)
    if resp == "contraoferta":
        print(f"{vendedor.nombre} quiere {M.plata(monto)}. ¿Aceptás? (s/n)")
        if input("> ").strip().lower() != "s":
            return
        if monto > mi.caja:
            print(f"No te alcanza: tenés {M.plata(mi.caja)}.")
            return
    elif resp == "rechaza":
        print(f"{vendedor.nombre} rechaza la oferta. Pide {M.plata(monto)}.")
        return
    print(f"{vendedor.nombre} acepta. Falta arreglar con el jugador.")
    rng = random.Random(f"{p['semilla']}|{p['ventana']}|{j.completo}")
    anios = M.anios_contrato(j)
    sueldo = negociar(j, round(1.1 * M.pretension(j, rng), 3), anios, mi)
    if sueldo is None:
        print("Se cayó el pase.")
        return
    M.transferir(j, vendedor, mi, monto, sueldo, anios)
    llego(p, mi, j)
    p["movimientos"].append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {vendedor.nombre} → "
                            f"{mi.nombre}, {M.plata(monto)}")
    print(f"✅ ¡{j.completo} es nuevo jugador de {mi.nombre}! ({M.plata(monto)})")


def llego(p, mi, j):
    """Un refuerzo nuevo: cuenta para las promesas al DT, y si es una de las
    figuras del plantel, la hinchada se entusiasma."""
    p["fichajes_ventana"].append([j.pos, j.pos2, J.nivel(j), j.completo])
    if j in sorted(mi.plantel, key=J.nivel)[-3:]:
        cambiar_hinchada(mi, 5)
        print(f"😍 La hinchada festeja la llegada de {j.corto}.")


def buscar_por_nombre(p, nombre):
    """El jugador con ese nombre y el club que lo tiene (None si está libre)."""
    for e in p["equipos"]:
        for j in e.plantel:
            if j.completo == nombre:
                return j, e
    for j in p["libres"]:
        if j.completo == nombre:
            return j, None
    return None, None


def ir_a_buscar(p, mi, nombre):
    """Desde una reunión o desde los pedidos: negociar por un jugador."""
    j, club = buscar_por_nombre(p, nombre)
    if j is None or club is mi:
        print("Ese jugador ya no está disponible.")
    elif club is None:
        negociar_libre(p, mi, j)
    else:
        negociar_compra(p, mi, j, club)


def pedidos_del_dt(p, mi):
    if not p.get("pedidos_dt"):
        print("El DT no te pidió a nadie en esta ventana.")
        return
    lista = [buscar_por_nombre(p, n) for n in p["pedidos_dt"]]
    lista = [(j, c) for j, c in lista if j is not None and c is not mi]
    print()
    for i, (j, c) in enumerate(lista, 1):
        donde = f"{c.nombre[:20]} · piden {M.plata(M.precio_pedido(c, j))}" if c else \
                f"libre · pide {M.plata(M.sueldo_pedido(j))}/año"
        linea_jugador(i, j, donde)
    k = elegir_de_lista(len(lista))
    if k is not None:
        ir_a_buscar(p, mi, lista[k][0].completo)


def vender_pibe(p, mi, j, club, monto):
    mi.reserva.remove(j)
    mi.caja += monto
    p["ofertas"] = [o for o in p["ofertas"] if o[1] is not j]
    p["movimientos"].append(f"{j.corto} ({j.pos}, {j.edad} años, reserva): {mi.nombre} → "
                            f"{club}, {M.plata(monto)}")
    print(f"💰 {j.corto} se va a {club}. Entran {M.plata(monto)}.")


def fichar_libres(p, mi):
    pos = pedir_posicion()
    libres = sorted((j for j in p["libres"] if pos is None or j.pos == pos),
                    key=lambda j: -J.nivel(j))[:12]
    if not libres:
        print("No hay libres en ese puesto.")
        return
    print()
    for i, j in enumerate(libres, 1):
        linea_jugador(i, j, f"libre · pide {M.plata(M.sueldo_pedido(j))}/año")
    k = elegir_de_lista(len(libres))
    if k is None:
        return
    negociar_libre(p, mi, libres[k])


def negociar_libre(p, mi, j):
    if len(mi.plantel) >= M.PLANTEL_MAX:
        print(f"Tenés {M.PLANTEL_MAX} jugadores: vendé o liberá a alguno antes.")
        return
    rng = random.Random(f"{p['semilla']}|{p['ventana']}|{j.completo}")
    anios = max(1, M.anios_contrato(j) - 1)
    sueldo = negociar(j, M.pretension(j, rng), anios, mi)
    if sueldo is None:
        return
    M.fichar_libre(j, mi, p["libres"], sueldo, anios)
    llego(p, mi, j)
    p["movimientos"].append(f"{j.corto} ({j.pos}, {J.nivel(j)}): libre → {mi.nombre}")
    print(f"✅ Firmó {j.completo}.")


def ofertas_recibidas(p, mi):
    if not p["ofertas"]:
        print("No hay ofertas por tus jugadores.")
        return
    print()
    for i, (club, j, monto) in enumerate(p["ofertas"], 1):
        linea_jugador(i, j, f"{club[:20]} ofrece {M.plata(monto)}")
    k = elegir_de_lista(len(p["ofertas"]))
    if k is None:
        return
    club, j, monto = p["ofertas"][k]
    print(f"1) Aceptar {M.plata(monto)} por {j.corto}  2) Rechazar")
    opcion = input("> ").strip()
    if opcion == "1":
        if j in mi.reserva:
            vender_pibe(p, mi, j, club, monto)
            return
        if j not in mi.plantel or not M.puede_vender(mi, j):
            print("No podés venderlo: te quedás corto de plantel o sin nadie en el puesto.")
            return
        aviso_venta(p, mi, j)
        M.vender(j, mi, club, p["equipos"], monto)
        p["movimientos"].append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {mi.nombre} → "
                                f"{club}, {M.plata(monto)}")
        print(f"Vendido. Entran {M.plata(monto)}.")
        p["ofertas"] = [o for o in p["ofertas"] if o[1] is not j]
    elif opcion == "2":
        p["ofertas"].pop(k)
        print("Oferta rechazada.")


def lista_propia(mi):
    plantel = sorted(mi.plantel, key=lambda j: (J.POSICIONES.index(j.pos), -J.nivel(j)))
    print()
    for i, j in enumerate(plantel, 1):
        linea_jugador(i, j, f"valor {M.plata(M.valor(j))} · {M.plata(M.sueldo(j))}/año"
                            f" · {j.contrato}a")
    return plantel


def vender(p, mi, rng):
    """Ponés a un jugador en venta y ves quiénes ofrecen (una vez por
    jugador en cada ventana)."""
    plantel = lista_propia(mi)
    k = elegir_de_lista(len(plantel), "¿A quién ponés en venta? ")
    if k is None:
        return
    j = plantel[k]
    if not M.puede_vender(mi, j):
        print("No podés venderlo: te quedás corto de plantel o sin nadie en el puesto.")
        return
    if j.completo not in p["sondeos"]:
        p["sondeos"][j.completo] = M.ofertas_por_jugador(p["equipos"], p["mio"], j, rng)
    ofertas = p["sondeos"][j.completo]
    if not ofertas:
        print(f"Nadie ofertó por {j.corto} en esta ventana.")
        return
    for i, (club, monto) in enumerate(ofertas, 1):
        print(f"{i}) {club}: {M.plata(monto)}")
    k = elegir_de_lista(len(ofertas), "¿Cuál aceptás? (Enter = ninguna) ")
    if k is None:
        return
    club, monto = ofertas[k]
    aviso_venta(p, mi, j)
    M.vender(j, mi, club, p["equipos"], monto)
    p["movimientos"].append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {mi.nombre} → "
                            f"{club}, {M.plata(monto)}")
    p["ofertas"] = [o for o in p["ofertas"] if o[1] is not j]
    print(f"Vendido a {club}. Entran {M.plata(monto)}.")


def liberar(p, mi):
    plantel = lista_propia(mi)
    k = elegir_de_lista(len(plantel), "¿A quién liberás? ")
    if k is None:
        return
    j = plantel[k]
    if not M.puede_vender(mi, j):
        print("No podés: te quedás corto de plantel o sin nadie en el puesto.")
        return
    costo = M.indemnizacion(j)
    print(f"Liberar a {j.corto} cuesta {M.plata(costo)} de indemnización "
          f"(le quedan {j.contrato} año{'s' if j.contrato > 1 else ''}). ¿Seguro? (s/n)")
    if input("> ").strip().lower() == "s":
        M.liberar(j, mi, p["libres"])
        p["ofertas"] = [o for o in p["ofertas"] if o[1] is not j]
        p["movimientos"].append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {mi.nombre} lo deja libre")
        print(f"{j.corto} quedó libre.")


def renovar(p, mi):
    """Renovar antes de tiempo a uno de tus jugadores (en el mercado)."""
    print("\n(a = años de contrato que le quedan)")
    plantel = lista_propia(mi)
    k = elegir_de_lista(len(plantel), "¿A quién le renovás? (Enter = volver) ")
    if k is None:
        return
    j = plantel[k]
    rng = random.Random(f"{p['semilla']}|{p['ventana']}|renueva|{j.completo}")
    anios = M.anios_contrato(j)
    sueldo = negociar(j, max(M.sueldo(j), M.pretension(j, rng)), anios, mi)
    if sueldo is not None:
        M.firmar(j, sueldo, anios)
        print(f"✅ {j.corto} renovó hasta dentro de {anios} temporada{'s' if anios > 1 else ''}.")


def renovaciones(p):
    """Pretemporada: los jugadores de tu club a los que se les terminó el
    contrato. Renuevan o se van libres."""
    mi = next(e for e in p["equipos"] if e.nombre == p["mio"])
    vencidos = sorted((j for j in mi.plantel if j.contrato <= 0), key=J.nivel, reverse=True)
    print("\n" + "=" * ANCHO)
    print(f"📝 Se terminaron {len(vencidos)} contratos en {mi.nombre}")
    print("=" * ANCHO)
    tits = M.titulares(mi)
    for j in vencidos:
        rng = random.Random(f"{p['semilla']}|{p['temporada']}|renueva|{j.completo}")
        print(f"\n{j.completo} ({j.pos}, {j.edad} años, nivel {J.nivel(j)}, "
              f"pot. {j.potencial})")
        print(f"Cobraba {M.plata(M.sueldo(j))}/año.")
        anios = M.anios_contrato(j)
        sueldo = None
        if len(mi.plantel) > 16:
            sueldo = negociar(j, M.pretension(j, rng), anios, mi)
        else:
            print("Te quedás sin jugadores si se va: renueva por lo que pide.")
            sueldo = M.pretension(j, rng)
        if sueldo is not None:
            M.firmar(j, sueldo, anios)
            print(f"✅ {j.corto} renovó por {anios} temporada{'s' if anios > 1 else ''}.")
        else:
            M.liberar(j, mi, p["libres"], pagar=False)
            p.setdefault("fin_contratos", []).append(
                f"{j.corto} ({j.pos}, {J.nivel(j)}): termina contrato en {mi.nombre}, "
                f"queda libre")
            print(f"{j.corto} se va libre.")
            t = mi_dt(p)
            if t and id(j) in tits:
                T.cambiar(t, sat=-4)
    if len(mi.plantel) < M.PLANTEL_MIN:
        print(f"\nTenés {len(mi.plantel)} jugadores. Fichá en el mercado (opción 10).")


def fin_de_temporada(p):
    """Muestra el cierre de la temporada y pregunta si se sigue con la próxima.
    Devuelve True si empieza otra."""
    mio = p["mio"]
    d_mio = division_a_mostrar(p)
    mostrar_tabla(tabla_division(p, d_mio))
    mostrar_goleadores(goleadores_division(p, d_mio), 10)
    for d, nombre in enumerate(p["divisiones"]):
        campeon, f = ordenar_tabla(tabla_division(p, d))[0]
        print("\n" + "*" * ANCHO)
        print(f" 🏆 CAMPEÓN {nombre.upper()} {p['temporada']}: {campeon}")
        print(f" {f['Pts']} puntos, {f['G']} ganados, {f['E']} empatados, {f['P']} perdidos")
        goleadores = goleadores_division(p, d)
        if goleadores:
            (j, club), n = goleadores.most_common(1)[0]
            print(f" ⚽ Goleador: {j} ({club}), {n} goles")
        print("*" * ANCHO)
    for club, de, a in cambios_de_categoria(p):
        flecha = "⬆ Asciende" if a < de else "⬇ Desciende"
        marca = "► " if club == mio else ""
        print(f"{marca}{flecha}: {club}")
    if mio:
        pos, f = posicion(tabla_division(p, d_mio), mio)
        print(f"\n{mio}: {pos}° con {f['Pts']} puntos "
              f"({f['G']}G {f['E']}E {f['P']}P)")
    print("\n1) Jugar la temporada siguiente")
    print("2) Guardar y volver al menú")
    if input("> ").strip() != "1":
        guardar_partida(p)
        return False
    d_antes = division_a_mostrar(p)
    cambios = cerrar_temporada(p)
    if mio and division_a_mostrar(p) != d_antes:
        nueva = p["divisiones"][division_a_mostrar(p)]
        if division_a_mostrar(p) < d_antes:
            print(f"\n🎉 ¡{mio} ASCENDIÓ a la {nueva}! Los ingresos suben un 50%.")
        else:
            print(f"\n😢 {mio} descendió a la {nueva}. Los ingresos bajan.")
    if mio:
        retirados, juveniles = cambios[mio]
        print(f"\n=== {mio}: pretemporada ===")
        if retirados:
            texto = "Se retiran: " + ", ".join(
                f"{j.corto} ({j.pos}, {j.edad})" for j in retirados)
            print(textwrap.fill(texto, ANCHO, subsequent_indent="  "))
        if juveniles and p.get("con_reserva"):
            texto = "🌱 Llegan a la reserva: " + ", ".join(
                f"{j.corto} ({j.pos}, {j.edad}, {C.estrellas_pot(j)})" for j in juveniles)
            print(textwrap.fill(texto, ANCHO, subsequent_indent="  "))
        elif juveniles:
            texto = "Suben de la cantera: " + ", ".join(
                f"{j.corto} ({j.pos}, {j.edad}, pot. {j.potencial})" for j in juveniles)
            print(textwrap.fill(texto, ANCHO, subsequent_indent="  "))
        if not retirados:
            print("No se retira nadie.")
        mi = next(e for e in p["equipos"] if e.nombre == mio)
        if len(mi.plantel) < M.PLANTEL_MIN:
            print(textwrap.fill(f"⚠ Quedan {len(mi.plantel)} jugadores en el plantel: subí "
                                f"pibes de la reserva (13) o fichá en el mercado (10).", ANCHO))
    empezar_temporada(p)
    guardar_partida(p)
    return True


# ---------------------------------------------------------------- menú
def partido_amistoso(modelo):
    local = elegir_equipo(1, modelo)
    visitante = elegir_equipo(2, modelo, ya_elegidos=[local])
    reponer_fisico(local, visitante)
    simular_partido(local, visitante, modelo)
    while True:
        print("\n1) Otro partido  2) 1000 partidos")
        print("3) Cambiar DTs  4) Cambiar equipos")
        print("5) Volver al menú")
        opcion = input("> ").strip()
        if opcion == "1":
            reponer_fisico(local, visitante)
            simular_partido(local, visitante, modelo)
        elif opcion == "2":
            prueba_masiva(local, visitante, modelo)
        elif opcion == "3":
            print()
            configurar_dt(local)
            print()
            configurar_dt(visitante)
        elif opcion == "4":
            local = elegir_equipo(1, modelo)
            visitante = elegir_equipo(2, modelo, ya_elegidos=[local])
        elif opcion == "5":
            break
        else:
            print("Elegí del 1 al 5.")


def ver_plantel(modelo):
    print("\n--- Ver plantel ---")
    club = buscar_club(modelo, permitir_inventado=False)
    if club:
        J.mostrar_plantel(club, PLANTELES[club])


def main():
    global PLANTELES
    print("SIMULADOR DE FÚTBOL — 1.9")
    ruta = sys.argv[1] if len(sys.argv) > 1 else "modelo_poisson.json"
    modelo = cargar_modelo(ruta)
    cargar_ascenso(modelo)
    PLANTELES = J.cargar_planteles(modelo)
    cargar_cerebro()
    while True:
        print("\n=== MENÚ ===")
        print("1) Partido  2) Cuadrangular")
        print("3) Torneo largo  4) Ver plantel")
        print("5) Salir")
        opcion = input("> ").strip()
        if opcion == "1":
            partido_amistoso(modelo)
        elif opcion == "2":
            cuadrangular(modelo)
        elif opcion == "3":
            torneo_largo(modelo)
        elif opcion == "4":
            if PLANTELES:
                ver_plantel(modelo)
            else:
                print("No hay clubes reales cargados.")
        elif opcion == "5":
            print("¡Hasta la próxima!")
            break
        else:
            print("Elegí del 1 al 5.")


if __name__ == "__main__":
    main()
