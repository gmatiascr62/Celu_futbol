"""
Instalaciones y cuerpo técnico de los clubes.

Instalaciones, de nivel 1 a 5. Mejorarlas cuesta plata, la obra tarda unas
fechas y cada nivel tiene un mantenimiento por año:
  predio:      los jugadores mejoran más rápido entrenando
  medico:      menos lesiones, y las que hay duran menos
  estadio:     más ingresos (cada nivel nuevo, un 10% más)
  inferiores:  mejores juveniles

Cuerpo técnico, de nivel 0 (no hay) a 5. Cobran un sueldo por año:
  preparador:  más resistencia y mejor recuperación entre fechas
  ataque:      mejora el ataque y la creación cuando se entrenan
  defensa:     mejora la defensa cuando se entrena
  arqueros:    mejora la atajada
  inferiores:  mejores juveniles

Los efectos se miden contra un club promedio (nivel 2,5): un club
promedio entrena igual que antes, uno con todo en 5 mejora bastante más
rápido y uno sin nada, bastante más lento.
"""
import random

import jugadores as J

INSTALACIONES = {"predio": "Predio", "medico": "Centro médico", "estadio": "Estadio",
                 "inferiores": "Inferiores"}
ROLES = {"preparador": "Preparador físico", "ataque": "Ayudante de ataque",
         "defensa": "Ayudante de defensa", "arqueros": "Entrenador de arqueros",
         "inferiores": "Coordinador de inferiores"}
NIVEL_MAX = 5
PROMEDIO = 2.5
SUBA_ESTADIO = 0.10          # cada nivel nuevo de estadio: 10% más de ingresos
CANDIDATOS_POR_ROL = 4


# ---------------------------------------------------------------- costos
def costo_obra(tipo, nivel_nuevo):
    """Lo que cuesta llevar una instalación a ese nivel (millones de dólares)."""
    base = 0.6 * 2 ** (nivel_nuevo - 2)
    return round(base * (2 if tipo == "estadio" else 1), 3)


def duracion_obra(nivel_nuevo):
    return 4 * nivel_nuevo


def mantenimiento(e):
    """Lo que cuesta por año mantener las instalaciones."""
    return round(sum(0.04 * n ** 1.5 for n in e.instalaciones.values()), 3)


def sueldo_staff(nivel):
    return round(0.03 * nivel ** 1.6, 3) if nivel else 0.0


def gastos_anuales(e):
    """Mantenimiento más sueldos del cuerpo técnico."""
    return mantenimiento(e) + sum(m["sueldo"] for m in e.staff.values())


# ---------------------------------------------------------------- efectos
def _f(nivel, k):
    return 1 + k * (nivel - PROMEDIO)


def multiplicadores(e):
    """Lo que aportan las instalaciones y el cuerpo técnico al entrenamiento."""
    inst = e.instalaciones
    st = {r: e.staff.get(r, {}).get("nivel", 0) for r in ROLES}
    return {
        "progreso": _f(inst.get("predio", 2), 0.15),
        "ataque": _f(st["ataque"], 0.12), "creacion": _f(st["ataque"], 0.12),
        "defensa": _f(st["defensa"], 0.12), "atajada": _f(st["arqueros"], 0.12),
        "resistencia": _f(st["preparador"], 0.15),
        "lesion": max(0.4, _f(inst.get("medico", 2), -0.15)),
        "dur": 1 if inst.get("medico", 2) >= 4 else 0,
    }


def recupero_extra(e):
    """Físico extra que se recupera entre fechas con un buen preparador."""
    return 0.015 * (e.staff.get("preparador", {}).get("nivel", 0) - PROMEDIO)


def cantera(e):
    """Cuánto mejores salen los juveniles (puntos de nivel y de potencial)."""
    inf = e.instalaciones.get("inferiores", 2)
    coord = e.staff.get("inferiores", {}).get("nivel", 0)
    return 1.2 * (inf - PROMEDIO) + 0.8 * (coord - PROMEDIO)


# ---------------------------------------------------------------- arranque
def nuevo_staff(rng, rol, nivel, usados):
    nombre, apellido = J.generar_nombre(rng, usados, set())
    return {"nombre": f"{nombre[0]}. {apellido}", "nivel": nivel, "sueldo": sueldo_staff(nivel)}


def iniciar(equipos, ranking, rng):
    """Instalaciones y cuerpo técnico según el tamaño del club.
    ranking: puesto del club entre todos (1 = el más grande).
    El club ya contaba con esos gastos: se suman a sus ingresos."""
    usados = set()
    total = len(equipos)
    for e in equipos:
        if e.instalaciones:
            continue
        grande = 1 - (ranking[e.nombre] - 1) / max(1, total - 1)    # 1 a 0
        base = 1 + 3 * grande                                          # 4 a 1
        e.instalaciones = {t: int(max(1, min(4, round(base + rng.uniform(-0.6, 0.6)))))
                           for t in INSTALACIONES}
        e.staff = {}
        for rol in ROLES:
            nivel = int(max(0, min(5, round(base + rng.uniform(-1.2, 0.8)))))
            if nivel:
                e.staff[rol] = nuevo_staff(rng, rol, nivel, usados)
        e.obras = []
        e.ingreso = round(e.ingreso + gastos_anuales(e), 3)


def candidatos(rng, usados, cantidad=CANDIDATOS_POR_ROL):
    """Cuerpo técnico sin club: algunos de cada rol, de distintos niveles."""
    return {rol: sorted((nuevo_staff(rng, rol, rng.choice((1, 2, 2, 3, 3, 4, 5)), usados)
                         for _ in range(cantidad)), key=lambda m: -m["nivel"])
            for rol in ROLES}


# ---------------------------------------------------------------- obras
def empezar_obra(e, tipo):
    """Arranca la mejora de una instalación. Devuelve el costo, o None si no
    se puede (ya está al máximo o ya hay una obra de eso)."""
    nivel = e.instalaciones[tipo] + 1
    if nivel > NIVEL_MAX or any(o[0] == tipo for o in e.obras):
        return None
    costo = costo_obra(tipo, nivel)
    e.caja -= costo
    e.obras.append([tipo, duracion_obra(nivel)])
    return costo


def avanzar_obras(e):
    """Una fecha de obra. Devuelve las instalaciones que se terminaron."""
    listas = []
    for obra in list(e.obras):
        obra[1] -= 1
        if obra[1] <= 0:
            tipo = obra[0]
            e.instalaciones[tipo] += 1
            if tipo == "estadio":
                e.ingreso = round(e.ingreso * (1 + SUBA_ESTADIO), 3)
            e.obras.remove(obra)
            listas.append(tipo)
    return listas


def pagar_fecha(e, fechas):
    e.caja -= gastos_anuales(e) / fechas


# ---------------------------------------------------------------- la computadora
PRIORIDAD_IA = ("predio", "inferiores", "medico", "estadio")


def invertir_ia(e, rng):
    """Un club de la computadora con la caja llena mejora una instalación o
    su cuerpo técnico. Devuelve un texto para las noticias, o None."""
    if e.caja < 1.2 * e.ingreso or e.obras:
        return None
    for tipo in sorted(PRIORIDAD_IA, key=lambda t: (e.instalaciones[t], PRIORIDAD_IA.index(t))):
        nivel = e.instalaciones[tipo] + 1
        if nivel <= NIVEL_MAX and costo_obra(tipo, nivel) <= 0.5 * e.caja:
            empezar_obra(e, tipo)
            return f"🏗 {e.nombre} mejora: {INSTALACIONES[tipo]}, nivel {nivel}."
    rol = min(ROLES, key=lambda r: e.staff.get(r, {}).get("nivel", 0))
    nivel = e.staff.get(rol, {}).get("nivel", 0) + 1
    if nivel <= NIVEL_MAX and sueldo_staff(nivel) <= 0.05 * e.ingreso:
        e.staff[rol] = nuevo_staff(rng, rol, nivel, set())
    return None


# ---------------------------------------------------------------- reserva
# Los pibes de 16 a 20 años que todavía no están en el plantel. Cada
# pretemporada llegan nuevos (más con mejores inferiores), entrenan en la
# reserva sin jugar, y antes de cumplir 21 hay que subirlos o dejarlos ir.
# Su potencial no se ve exacto: el club lo estima en estrellas, y cuanto
# mejor el coordinador de inferiores, menos se equivoca.
RESERVA_MAX = 12
EDAD_LIMITE = 21
PIBES_AL_ARRANCAR = 5
PLANTEL_IDEAL = 24          # la computadora sube pibes hasta tener esto


def cuantos_llegan(e):
    return 2 + e.instalaciones.get("inferiores", 2) // 2


def estimar(j, e, rng):
    """El potencial que ve el club, con un error que achica el coordinador."""
    coord = e.staff.get("inferiores", {}).get("nivel", 0)
    j.pot_est = int(round(j.potencial + rng.gauss(0, max(1.0, 7 - 1.2 * coord))))


def estrellas_pot(j):
    pe = j.pot_est or j.potencial
    n = 1 if pe < 60 else 2 if pe < 68 else 3 if pe < 76 else 4 if pe < 84 else 5
    return "★" * n + "☆" * (NIVEL_MAX - n)


def nuevo_pibe(e, edad, rng, usados):
    """Un pibe de las inferiores: bastante más flojo que el plantel, con un
    potencial que puede ser cualquier cosa (alguno sale crack)."""
    meta_of, meta_de = J.metas(e.ataque, e.defensa)
    pos = rng.choices(list(J.COMPOSICION), weights=list(J.COMPOSICION.values()))[0]
    bonus = cantera(e) if e.instalaciones else 0.0
    j = J.generar_jugador(pos, edad, meta_of, meta_de,
                          rng.gauss(-14 + 0.5 * bonus + 2 * (edad - 16), 4), rng, usados,
                          {x.apellido for x in e.plantel + e.reserva})
    J._redondear(j)
    crack = rng.randint(5, 15) if rng.random() < 0.10 else 0   # uno de cada diez
    j.potencial = min(99, J._potencial(j, rng) + crack + max(0, round(0.6 * bonus)))
    estimar(j, e, rng)
    return j


def iniciar_reserva(equipos, rng, usados):
    for e in equipos:
        if not e.reserva:
            e.reserva = [nuevo_pibe(e, rng.randint(16, 20), rng, usados)
                         for _ in range(PIBES_AL_ARRANCAR)]


def llegan_pibes(e, rng, usados):
    """Pretemporada: llegan los pibes nuevos de las inferiores."""
    nuevos = []
    for _ in range(cuantos_llegan(e)):
        if len(e.reserva) >= RESERVA_MAX:
            break
        j = nuevo_pibe(e, rng.randint(16, 17), rng, usados)
        e.reserva.append(j)
        nuevos.append(j)
    return nuevos


def pasar_anio_reserva(e, rng):
    """Cumplen un año y el club vuelve a estimar su potencial."""
    for j in e.reserva:
        j.edad += 1
        j.fisico, j.lesion = 1.0, 0
        estimar(j, e, rng)


def subir(e, j):
    """El pibe pasa al plantel con su primer contrato."""
    import mercado as M
    e.reserva.remove(j)
    e.plantel.append(j)
    M.firmar(j, anios=3)


def reserva_ia(e):
    """Pretemporada en un club de la computadora: sube a los mejores pibes
    hasta tener el plantel completo, y a los que cumplen 21 los sube si sirven
    o los deja ir."""
    while len(e.plantel) < PLANTEL_IDEAL and e.reserva:
        subir(e, max(e.reserva, key=J.nivel))
    peor = min(J.nivel(j) for j in e.plantel)
    for j in [j for j in e.reserva if j.edad >= EDAD_LIMITE]:
        if J.nivel(j) > peor and len(e.plantel) < 30:
            subir(e, j)
        else:
            e.reserva.remove(j)


def oferta_exterior(j, rng):
    """Lo que ofrecen de afuera por un pibe: pagan el potencial."""
    import mercado as M
    return round(M.valor(j) * rng.uniform(1.5, 3.0) * (1 + max(0, j.potencial - 75) / 15), 3)
