"""
Mercado de pases y finanzas de los clubes.

La plata está en millones de dólares. Cada jugador tiene un valor de
mercado según su nivel, su edad y su potencial, y cobra un sueldo anual
proporcional a ese valor. Cada club tiene una caja y un ingreso anual (que
sale del tamaño del club); los sueldos se pagan fecha a fecha y a fin de
temporada hay premios según el puesto.

El mercado abre dos veces por temporada: en la pretemporada y a mitad del
torneo. Los clubes que maneja la computadora compran lo que más les falta,
venden si les pagan bien y fichan libres para completar el plantel.

Cada jugador tiene un contrato de 1 a 4 temporadas con un sueldo pactado.
Al terminar, renueva o se va libre. Con un año de contrato vale menos,
porque el club sabe que lo puede perder gratis.
"""
import math

import jugadores as J

PLANTEL_MIN = 20
PLANTEL_MAX = 30
SUELDO_SOBRE_VALOR = 0.18    # el sueldo anual es el 18% del valor
SUELDO_MINIMO = 0.02         # US$ 20.000 por año
PARTE_SUELDOS = 0.8          # al arrancar, los sueldos son el 80% del ingreso
CAJA_INICIAL = 0.35          # caja inicial, en proporción al ingreso anual
PREMIO_CAMPEON = 0.30        # premio al campeón, en proporción a su ingreso
CAJA_MAXIMA = 2.0            # tope de caja de los clubes de la computadora (años de ingreso)
INDEMNIZACION = 0.5          # liberar a un jugador cuesta la mitad de lo que le queda
DESCUENTO_ULTIMO_ANIO = 0.7  # con un año de contrato vale menos
LIBRES_POR_POSICION = 3
# Por los jugadores caros de tu club también llegan ofertas de afuera
EXTERIOR = ("un club de Brasil", "un club de México", "un club de la MLS",
            "un club de Portugal", "un club de España", "un club de Italia")
VALOR_EXTERIOR = 1.5         # desde este valor, interesan afuera


def plata(m):
    """Monto en millones de dólares, en texto corto."""
    if abs(m) >= 1:
        return f"US$ {m:.1f}M".replace(".", ",")
    return f"US$ {m * 1000:.0f}K"


# ---------------------------------------------------------------- valores
def valor(j):
    """Valor de mercado en millones de dólares."""
    n = J.nivel(j)
    base = math.exp(0.13 * (n - 70))
    e = j.edad
    edad = (1.25 if e <= 21 else 1.15 if e <= 23 else 1.0 if e <= 28
            else 0.8 if e <= 30 else 0.55 if e <= 32 else 0.3)
    potencial = 1 + 0.04 * max(0, j.potencial - n)
    return round(base * edad * potencial, 3)


def sueldo_pedido(j):
    """Lo que pide de sueldo anual hoy, según su valor (millones de dólares)."""
    return max(SUELDO_MINIMO, SUELDO_SOBRE_VALOR * valor(j))


def sueldo(j):
    """Lo que cobra: el sueldo pactado en su contrato."""
    return j.sueldo or sueldo_pedido(j)


def anios_contrato(j):
    """Cuántos años firma: los jóvenes más, los veteranos menos."""
    return 4 if j.edad <= 25 else 3 if j.edad <= 29 else 2 if j.edad <= 32 else 1


def firmar(j, sueldo_anual=None, anios=None):
    j.sueldo = round(sueldo_anual if sueldo_anual is not None else sueldo_pedido(j), 3)
    j.contrato = anios or anios_contrato(j)


def iniciar_contratos(planteles, rng):
    """Contratos para los que todavía no tienen (al arrancar una partida)."""
    for plantel in planteles:
        for j in plantel:
            if not j.sueldo:
                firmar(j, sueldo_pedido(j) * rng.uniform(0.85, 1.15), rng.randint(1, 4))


def pretension(j, rng):
    """Lo que pide para renovar: más si está en su mejor momento."""
    extra = 1.25 if j.edad <= 29 and j.potencial > J.nivel(j) else 1.1
    return round(sueldo_pedido(j) * rng.uniform(1.0, extra), 3)


def acepta(oferta, pedido):
    """El jugador acepta si le ofrecen al menos el 90% de lo que pide."""
    return oferta >= 0.9 * pedido


def masa_salarial(plantel):
    return sum(sueldo(j) for j in plantel)


def iniciar_finanzas(equipos):
    """Ingreso anual y caja de cada club, según lo que paga de sueldos."""
    for e in equipos:
        if not e.ingreso:
            e.ingreso = round(masa_salarial(e.plantel) / PARTE_SUELDOS, 3)
            e.caja = round(e.ingreso * CAJA_INICIAL, 3)


def cobrar_fecha(equipos, fechas):
    """Una fecha de ingresos y sueldos."""
    for e in equipos:
        e.caja += (e.ingreso - masa_salarial(e.plantel)) / fechas


def premios(equipos, orden, mio=None):
    """Premios de fin de temporada: más plata cuanto mejor el puesto.
    orden: nombres de los clubes del primero al último. Los clubes de la
    computadora invierten en el club (obras, deudas) lo que les sobra por
    encima de dos años de ingresos, así no juntan plata sin fin."""
    n = len(orden)
    por_nombre = {e.nombre: e for e in equipos}
    for i, nombre in enumerate(orden):
        e = por_nombre[nombre]
        e.caja += e.ingreso * PREMIO_CAMPEON * (1 - i / (n - 1))
        if nombre != mio:
            e.caja = min(e.caja, CAJA_MAXIMA * e.ingreso)


# ---------------------------------------------------------------- plantel
def titulares(e):
    """Los 11 que pondría hoy (para saber a quién le cuesta más vender)."""
    return {id(j) for j, _ in J.armar_xi(J.aptos(e.plantel), e.formacion, False)}


def necesidad(e):
    """El puesto más flojo del equipo titular: (posición, puntaje)."""
    xi = J.armar_xi(J.aptos(e.plantel), e.formacion, False)
    j, slot = min((x for x in xi), key=lambda x: J.puntaje(x[0], x[1], False))
    return slot, J.puntaje(j, slot, False)


def puede_vender(e, j):
    """Un club no vende si se queda corto de plantel o sin nadie en el puesto."""
    if len(e.plantel) <= PLANTEL_MIN:
        return False
    mismos = sum(1 for x in e.plantel if x.pos == j.pos)
    return mismos > (2 if j.pos == "ARQ" else 1)


def precio_pedido(e, j, tits=None):
    """Lo que pide un club por un jugador: el doble si es una de sus tres
    figuras, más si es titular, menos si está sin plata o le queda un año."""
    tits = titulares(e) if tits is None else tits
    figuras = sorted(e.plantel, key=J.nivel)[-3:]
    factor = 2.0 if j in figuras else 1.4 if id(j) in tits else 1.1
    if e.caja < 0:
        factor -= 0.2
    if j.contrato <= 1:
        factor *= DESCUENTO_ULTIMO_ANIO
    return round(valor(j) * factor, 3)


def respuesta(e, j, oferta):
    """Cómo responde un club a una oferta. Devuelve ('acepta', monto),
    ('contraoferta', monto) o ('rechaza', monto pedido)."""
    pedido = precio_pedido(e, j)
    if oferta >= pedido:
        return "acepta", oferta
    if oferta >= 0.8 * pedido:
        return "contraoferta", pedido
    return "rechaza", pedido


def transferir(j, vendedor, comprador, monto, sueldo_anual=None, anios=None):
    """Pase con contrato nuevo. Sin sueldo pactado, cobra un 10% más de lo
    que pide (para cambiar de club siempre se mejora)."""
    vendedor.plantel.remove(j)
    comprador.plantel.append(j)
    vendedor.caja += monto
    comprador.caja -= monto
    firmar(j, sueldo_anual if sueldo_anual is not None else 1.1 * sueldo_pedido(j), anios)
    j.fisico = min(j.fisico, 0.9)    # llega sin haber hecho la pretemporada con el grupo


def es_exterior(club):
    return club in EXTERIOR


def vender(j, vendedor, club, equipos, monto):
    """Venta a otro club de la liga o al exterior (ahí el jugador se va)."""
    if es_exterior(club):
        vendedor.plantel.remove(j)
        vendedor.caja += monto
        j.contrato, j.sueldo = 0, 0.0
    else:
        transferir(j, vendedor, next(e for e in equipos if e.nombre == club), monto)


def indemnizacion(j):
    return INDEMNIZACION * sueldo(j) * max(j.contrato, 1)


def liberar(j, e, libres, pagar=True):
    """Rescinde el contrato: el jugador queda libre y el club paga la mitad
    de lo que le quedaba por cobrar."""
    e.plantel.remove(j)
    if pagar:
        e.caja -= indemnizacion(j)
    j.contrato, j.sueldo = 0, 0.0
    libres.append(j)


def fichar_libre(j, e, libres, sueldo_anual=None, anios=None):
    libres.remove(j)
    e.plantel.append(j)
    firmar(j, sueldo_anual, anios)


def vencimientos_ia(equipos, mio, libres, rng):
    """Fin de temporada en los clubes de la computadora: a los que se les
    terminó el contrato los renuevan si les sirven, si no quedan libres."""
    log = []
    for e in equipos:
        if e.nombre == mio:
            continue
        orden = sorted(e.plantel, key=J.nivel, reverse=True)
        importantes = {id(j) for j in orden[:16]}
        for j in [j for j in e.plantel if j.contrato <= 0]:
            sigue = (id(j) in importantes and j.edad < 34) or len(e.plantel) <= PLANTEL_MIN
            if sigue:
                firmar(j, pretension(j, rng))
            else:
                liberar(j, e, libres, pagar=False)
                log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): termina contrato en "
                           f"{e.nombre}, queda libre")
    return log


# ---------------------------------------------------------------- libres
def generar_libres(equipos, rng, usados, nivel_medio):
    """Jugadores sin club: veteranos que nadie renovó y jugadores de
    ascenso. En promedio, bastante más flojos que la liga."""
    libres = []
    for pos in J.COMPOSICION:
        for _ in range(LIBRES_POR_POSICION):
            edad = rng.randint(22, 35)
            meta = nivel_medio - rng.uniform(10, 22)
            j = J.generar_jugador(pos, edad, meta, meta, 0, rng, usados, set())
            J._redondear(j)
            j.potencial = J._potencial(j, rng)
            libres.append(j)
    return libres


def nivel_medio(equipos):
    niveles = [J.nivel(j) for e in equipos for j in e.plantel]
    return sum(niveles) / len(niveles)


# ---------------------------------------------------------------- la computadora
def importar(c, pos, actual, rng, usados):
    """Un club con la caja llena trae un refuerzo del exterior."""
    meta = actual + rng.uniform(4, 8)
    j = J.generar_jugador(pos, rng.randint(24, 30), meta, meta, 0, rng, usados,
                          {x.apellido for x in c.plantel})
    J._redondear(j)
    j.potencial = J._potencial(j, rng)
    precio = round(valor(j) * 1.3, 3)
    if J.nivel(j) < actual + 3 or precio > 0.6 * c.caja:
        return None
    c.plantel.append(j)
    c.caja -= precio
    firmar(j, 1.1 * sueldo_pedido(j))
    return j, precio


def movimientos_ia(equipos, mio, libres, rng, prob=0.5, usados=None):
    """Lo que hacen en una ventana los clubes que maneja la computadora.
    Devuelve los movimientos en texto. No le compran al club del jugador:
    a ese le hacen ofertas (ver ofertas_por_mios)."""
    log = []
    movidos = set()      # el que llega a un club en esta ventana no se vuelve a vender
    tits = {e.nombre: titulares(e) for e in equipos}
    compradores = [e for e in equipos if e.nombre != mio]
    rng.shuffle(compradores)
    # los que tienen la caja llena salen a comprar más
    compradores += [c for c in compradores if c.caja > c.ingreso]
    for c in compradores:
        rico = c.caja > c.ingreso
        if (not rico and rng.random() > prob) or len(c.plantel) >= PLANTEL_MAX:
            continue
        pos, actual = necesidad(c)
        presupuesto = 0.6 * c.caja
        opciones = []
        for v in equipos:
            if v is c or v.nombre == mio:
                continue
            for j in v.plantel:
                if (j.pos == pos and not j.lesion and J.nivel(j) >= actual + 3
                        and id(j) not in movidos and puede_vender(v, j)):
                    precio = precio_pedido(v, j, tits[v.nombre])
                    # el sueldo nuevo tiene que entrar en lo que gana el club
                    if (precio <= presupuesto and masa_salarial(c.plantel) + sueldo_pedido(j)
                            <= (1.3 if rico else 1.05) * c.ingreso):
                        opciones.append((J.nivel(j) - 2 * precio / max(c.ingreso, 0.1),
                                         j, v, precio))
        if opciones:
            _, j, v, precio = max(opciones, key=lambda o: o[0])
            transferir(j, v, c, precio)
            movidos.add(id(j))
            log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {v.nombre} → "
                       f"{c.nombre}, {plata(precio)}")
        elif rico and usados is not None and (traido := importar(c, pos, actual, rng, usados)):
            j, precio = traido
            movidos.add(id(j))
            log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): del exterior → "
                       f"{c.nombre}, {plata(precio)}")
        else:
            mejores = [j for j in libres if j.pos == pos and J.nivel(j) >= actual + 2
                       and masa_salarial(c.plantel) + sueldo_pedido(j) <= c.ingreso]
            if mejores:
                j = max(mejores, key=J.nivel)
                fichar_libre(j, c, libres)
                movidos.add(id(j))
                log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): libre → {c.nombre}")
    # Los que quedaron largos de plantel liberan al peor; los cortos fichan libres
    for e in equipos:
        if e.nombre == mio:
            continue
        while len(e.plantel) > PLANTEL_MAX - 2:
            j = min((x for x in e.plantel if id(x) not in movidos), key=J.nivel)
            if not puede_vender(e, j):
                break
            liberar(j, e, libres)
            log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): {e.nombre} lo deja libre")
        while len(e.plantel) < PLANTEL_MIN + 2 and libres:
            pos, _ = necesidad(e)
            candidatos = [j for j in libres if j.pos == pos] or libres
            # el mejor que puede pagar; si no le alcanza para ninguno, el más barato
            margen = e.ingreso - masa_salarial(e.plantel)
            pagables = [j for j in candidatos if sueldo_pedido(j) <= max(margen, SUELDO_MINIMO)]
            j = (max(pagables, key=J.nivel) if pagables
                 else min(candidatos, key=sueldo_pedido))
            fichar_libre(j, e, libres)
            log.append(f"{j.corto} ({j.pos}, {J.nivel(j)}): libre → {e.nombre}")
    return log


def ofertas_por_mios(equipos, mio, rng, cantidad=None):
    """Ofertas que le llegan al club del jugador: (comprador, jugador, monto)."""
    mi = next(e for e in equipos if e.nombre == mio)
    cantidad = rng.choice((0, 1, 1, 2, 2, 3)) if cantidad is None else cantidad
    otros = [e for e in equipos if e.nombre != mio and len(e.plantel) < PLANTEL_MAX]
    tope = max((0.6 * e.caja for e in otros), default=0)
    # los buenos que algún club puede pagar
    candidatos = sorted((j for j in mi.plantel if valor(j) * 0.9 <= tope),
                        key=lambda j: -valor(j))[:12]
    ofertas = []
    for j in rng.sample(candidatos, min(cantidad, len(candidatos))):
        monto = valor(j) * rng.uniform(0.9, 1.5)
        interesados = [e for e in otros if 0.6 * e.caja >= monto]
        if not interesados:
            monto = valor(j) * 0.9
            interesados = [e for e in otros if 0.6 * e.caja >= monto]
        if interesados:
            ofertas.append((rng.choice(interesados).nombre, j, round(monto, 3)))
    # Afuera miran a los caros
    caros = [j for j in mi.plantel if valor(j) >= VALOR_EXTERIOR
             and all(o[1] is not j for o in ofertas)]
    if caros and rng.random() < 0.5:
        j = rng.choice(caros)
        ofertas.append((rng.choice(EXTERIOR), j, round(valor(j) * rng.uniform(1.0, 1.6), 3)))
    return ofertas


def ofertas_por_jugador(equipos, mio, j, rng):
    """Si ponés a un jugador en venta, quiénes ofrecen y cuánto."""
    ofertas = []
    for e in equipos:
        if e.nombre == mio or len(e.plantel) >= PLANTEL_MAX:
            continue
        pos, actual = necesidad(e)
        interes = 1.0 if j.pos == pos else 0.25
        if J.nivel(j) < actual - 2:
            interes *= 0.2
        monto = valor(j) * rng.uniform(0.7, 1.2)
        if rng.random() < interes * 0.5 and 0.6 * e.caja >= monto:
            ofertas.append((e.nombre, round(monto, 3)))
    if valor(j) >= VALOR_EXTERIOR and rng.random() < 0.6:
        ofertas.append((rng.choice(EXTERIOR), round(valor(j) * rng.uniform(0.9, 1.4), 3)))
    return sorted(ofertas, key=lambda o: -o[1])[:3]
