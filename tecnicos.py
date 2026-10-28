"""
Los DT como personas: nombre, prestigio, sueldo, contrato y estado de ánimo.

El ánimo son tres números de 0 a 100:
  satisfacción: con vos, el dueño. Sube si le cumplís, baja si lo ignorás.
  confianza:    en el plantel. Sube y baja con los resultados.
  presión:      por resultados, según lo que se espera del club.

El DT de tu club te pide reuniones entre fechas. Le contestás eligiendo una
respuesta y cada una cambia su ánimo. Las promesas se anotan y se revisan
cuando cierra el mercado. Si la satisfacción llega muy abajo, renuncia.
Los DT de los otros clubes no hablan con nadie, pero si la presión es
insoportable los echan.

La confianza cambia un poco el rendimiento del equipo (hasta un 3% de los
goles), para que el vestuario importe sin romper la calibración.
"""
from dataclasses import asdict, dataclass, field

import jugadores as J

PERSONALIDADES = ("equilibrado", "conservador", "arriesgado", "impulsivo")
EFECTO_MORAL = 0.03          # la confianza mueve hasta un 3% los goles propios
RENUNCIA = 15                # satisfacción por debajo de la cual se va
ULTIMATUM = 30
PRESION_DESPIDO = 80         # los otros clubes echan al DT por encima de esto
LIBRES = 10                  # DT sin club disponibles
# cuánto le pesa cada cosa según la personalidad
PACIENCIA = {"equilibrado": 1.0, "conservador": 0.7, "arriesgado": 1.2, "impulsivo": 1.6}


@dataclass
class Tecnico:
    nombre: str
    apellido: str
    edad: int
    personalidad: str
    prestigio: int
    contrato: int = 2            # temporadas que le quedan
    satisfaccion: float = 65.0
    confianza: float = 50.0
    presion: float = 40.0
    fechas: int = 0              # fechas en el club
    promesas: list = field(default_factory=list)
    avisos: list = field(default_factory=list)   # temas que ya planteó (no se repiten)
    aumento: float = 1.0         # sube cada vez que renueva
    ultimo_club: str = ""        # de dónde se fue (ahí no vuelve enseguida)
    clubes: list = field(default_factory=list)   # [club, temporada desde, hasta o None]
    logros: list = field(default_factory=list)   # títulos, ascensos y descensos
    despidos: int = 0

    @property
    def completo(self):
        return f"{self.nombre} {self.apellido}"

    @property
    def sueldo(self):
        """Sueldo anual en millones de dólares."""
        return round((0.05 + 0.006 * self.prestigio) * self.aumento, 3)


def puesto(pos):
    """El nombre del puesto con su código, para buscarlo en el mercado."""
    return f"{J.NOMBRE_POS[pos]} ({pos})"


def _clip(v):
    return max(0.0, min(100.0, v))


def cambiar(t, sat=0, conf=0, pres=0):
    t.satisfaccion = _clip(t.satisfaccion + sat * PACIENCIA[t.personalidad])
    t.confianza = _clip(t.confianza + conf)
    t.presion = _clip(t.presion + pres)


def moral(t):
    """Multiplica los goles esperados del equipo según la confianza."""
    if t is None:
        return 1.0
    return 1 + EFECTO_MORAL * (t.confianza - 50) / 50


def nuevo(rng, usados, personalidad=None, prestigio=None):
    nombre, apellido = J.generar_nombre(rng, usados, set())
    return Tecnico(nombre, apellido, rng.randint(36, 68),
                   personalidad or rng.choice(PERSONALIDADES),
                   prestigio if prestigio is not None else rng.randint(30, 85))


def prestigio_para(puesto_esperado, total, rng):
    """Los clubes grandes tienen DT de más nombre."""
    base = 90 - 55 * (puesto_esperado - 1) / max(1, total - 1)
    return int(max(20, min(95, base + rng.gauss(0, 7))))


def bolsa_libres(libres, rng, usados):
    """Completa la lista de DT sin club."""
    while len(libres) < LIBRES:
        libres.append(nuevo(rng, usados))
    del libres[LIBRES + 4:]


# ---------------------------------------------------------------- después de cada fecha
def tras_partido(t, gf, gc):
    """La confianza sube y baja con los resultados, y vuelve de a poco a 50."""
    efecto = 4 if gf > gc else 1 if gf == gc else -4
    if t.personalidad == "impulsivo":
        efecto *= 1.5
    t.confianza = _clip(t.confianza + efecto + 0.05 * (50 - t.confianza))
    t.fechas += 1


def actualizar_presion(t, puesto, esperado, ultimos, jugadas, medios=1.0, hinchada=60.0):
    """La presión sale de la diferencia entre el puesto y lo esperado, de la
    racha (últimos 5 partidos), de los medios (pesan más en los clubes
    grandes) y de la hinchada si está enojada."""
    racha = ultimos[-5:].count("P") - ultimos[-5:].count("G")
    objetivo = 50 + medios * (2.0 * (puesto - esperado) + 6 * racha)
    objetivo = _clip(objetivo + max(0.0, 0.4 * (45 - hinchada)))
    peso = min(1.0, jugadas / 10)       # al principio la tabla dice poco
    objetivo = peso * objetivo + (1 - peso) * 45
    t.presion = _clip(t.presion + 0.25 * (objetivo - t.presion))


def lo_echan(t, rng):
    """¿Los dirigentes de un club de la computadora echan a su DT?"""
    return t.presion > PRESION_DESPIDO and t.fechas >= 6 and rng.random() < 0.12


# ---------------------------------------------------------------- reuniones
# Cada reunión es un dict: tema, texto (lo que dice el DT) y opciones.
# Cada opción: (lo que contestás, cambios de ánimo, promesa o None, respuesta del DT).

def _f(rng, frases, **datos):
    return rng.choice(frases).format(**datos)


FRASES = {
    "refuerzo": (
        "Presidente, necesito un {pos}. Con lo que tengo en ese puesto no llegamos.",
        "Le soy sincero: nos falta un {pos}. Si no lo traemos, lo vamos a sufrir.",
        "Estuve mirando el plantel. El puesto de {pos} es el que más me preocupa.",
        "Para pelear arriba hace falta un {pos} de jerarquía. ¿Se puede?",
    ),
    "racha_mala": (
        "{n} partidos sin ganar, presidente. Sé que no es fácil, pero necesito su respaldo.",
        "Esto no está saliendo. {n} partidos sin ganar. Yo no me escondo, ¿y usted?",
        "Los muchachos están golpeados: {n} sin ganar. Banquémonos, que vamos a salir.",
    ),
    "buena_racha": (
        "Estamos bárbaro, presidente. {n} partidos sin perder. El grupo está enchufado.",
        "¡Qué momento! {n} sin perder. Esto recién empieza.",
        "El equipo está jugando como yo quiero. {n} partidos sin perder.",
    ),
    "juvenil": (
        "El pibe {jugador} está para jugar en Primera. Tiene un potencial bárbaro.",
        "Le pido algo: déjeme tirar a {jugador} a la cancha. El pibe está listo.",
        "¿Vio a {jugador} en los entrenamientos? Ese pibe va a valer millones.",
    ),
    "venta": (
        "¿Por qué vendieron a {jugador} sin avisarme? Era titular, presidente.",
        "Me enteré por los diarios que se fue {jugador}. Así no se puede trabajar.",
        "Se fue {jugador} y nadie me consultó. Espero que venga un reemplazo.",
    ),
    "promesa_cumplida": (
        "Gracias, presidente. Me prometió un {pos} y llegó. Así da gusto trabajar.",
        "Cumplió con el {pos}. Eso no lo voy a olvidar.",
    ),
    "promesa_rota": (
        "Me prometió un {pos} y cerró el mercado sin nadie. Me siento engañado.",
        "Usted me dijo que venía un {pos}. No vino nadie. ¿Qué quiere que le diga?",
        "Otra vez me quedé sin el {pos} que me prometieron. Así no.",
    ),
    "ultimatum": (
        "Le hablo claro: si las cosas no cambian, me voy.",
        "Presidente, no me siento respaldado. Si sigue así, agarro mis cosas.",
        "Esto es un ultimátum: o me dan lo que necesito, o renuncio.",
    ),
    "general_bien": (
        "Todo en orden, presidente. El grupo trabaja bien.",
        "Venimos bien. Solo le pido que sigamos por este camino.",
        "Los muchachos me están respondiendo. Se entrena con ganas.",
        "Pasaba a saludar, presidente. El clima en el vestuario es bueno.",
        "Me gusta lo que veo en la semana. Hay hambre en este grupo.",
    ),
    "general_mal": (
        "La gente está nerviosa, presidente. Hay que dar vuelta esto.",
        "No le voy a mentir: el vestuario está tocado.",
        "Hay caras largas en el vestuario. Necesito que me ayude a levantarlos.",
        "Los resultados no acompañan y los muchachos lo sienten.",
        "Me están criticando mucho afuera. Necesito saber que usted está conmigo.",
    ),
    "vence": (
        "A {jugador} se le termina el contrato. Es importante, presidente: renuévele.",
        "Ojo con {jugador}: le queda un año. Si no lo renovamos, se va gratis.",
        "{jugador} me preguntó por su contrato. No lo quiero perder.",
    ),
    "no_usa": (
        "A {jugador} no lo estoy usando y cobra bastante. Véndalo o déjelo ir.",
        "Le soy sincero: {jugador} no entra en mis planes. Busquémosle club.",
        "{jugador} jugó {n} partidos. Con esa plata podemos traer a otro.",
    ),
    "staff": (
        "Presidente, necesito un {rol}. Así no puedo trabajar.",
        "Me falta un {rol} de nivel. Con eso el grupo rinde más, se lo aseguro.",
        "Le pido un {rol}. Es una inversión, no un gasto.",
    ),
    "lo_quieren": (
        "Presidente, me llamaron de {club}. Quieren que sea su técnico. Quería que lo sepa por mí.",
        "Le voy a ser sincero: {club} me hizo una oferta. Antes de contestar, quiero escucharlo.",
    ),
    "entrenamiento": (
        "Los muchachos están fundidos y los hace entrenar fuerte. Así se me van a lesionar.",
        "Con este entrenamiento no llegamos, presidente. Déjeme manejarlo a mí.",
        "Le pido que me deje decidir el entrenamiento. Yo los veo todos los días.",
    ),
    "formacion": (
        "No juego más con el {formacion}, presidente. Perdimos {n} partidos así.",
        "El {formacion} no nos sale. Déjeme elegir a mí o esto se complica.",
    ),
    "renuncia": (
        "Presidente, vengo a presentar mi renuncia. No hay más nada que hablar.",
        "Me voy. Le agradezco, pero así no puedo seguir.",
        "Renuncio. Le deseo suerte al club, de corazón.",
    ),
    "renovacion": (
        "Se me termina el contrato, presidente. ¿Seguimos juntos?",
        "Quería hablar de mi contrato. Termina ahora. ¿Qué piensa?",
    ),
    "no_renueva": (
        "Le agradezco, pero no voy a renovar. Necesito otro desafío.",
        "No sigo, presidente. Fue un gusto, pero me voy.",
    ),
}
RESPUESTAS = {
    "contento": ("Así me gusta, presidente.", "Gracias por el respaldo.",
                 "Eso quería escuchar."),
    "neutro": ("Bueno, veremos.", "Entendido.", "Está bien, lo tengo en cuenta."),
    "enojado": ("No me gusta lo que escucho.", "Esto no lo voy a olvidar.",
                "Así es difícil, presidente."),
}


def _resp(rng, tono):
    return rng.choice(RESPUESTAS[tono])


def proxima_ventana(temporada, numero, total, abierta):
    """Clave de la ventana en la que se tiene que cumplir una promesa."""
    if abierta:
        return abierta
    if numero < total // 2:
        return f"{temporada}-{total // 2}"
    return f"{temporada + 1}-0"


def reunion_refuerzo(t, rng, pos, nivel, caja, costo, ventana, ventana_abierta,
                     candidatos=()):
    """candidatos: [(nombre completo, línea para mostrar)], los jugadores que
    propone el DT, el primero es el que más le gusta."""
    texto = _f(rng, FRASES["refuerzo"], pos=puesto(pos))
    promesa = {"pos": pos, "nivel": nivel + 3, "ventana": ventana}
    cuando = "en este mercado" if ventana_abierta else "en el próximo mercado"
    no_hay = (-4, 0, 0) if caja < costo else (-10, 0, 0)
    resp_no_hay = (_resp(rng, "neutro") if caja < costo
                   else "¿No hay plata? Yo veo la caja, presidente.")
    if candidatos:
        primero = candidatos[0][0]
        return {"tema": "refuerzo", "texto": texto + " Le traigo nombres:",
                "lista": [linea for _, linea in candidatos],
                "candidatos": [nombre for nombre, _ in candidatos],
                "opciones": [
                    (f"Andá a buscar a {primero.split(' ', 1)[-1]}" if ventana_abierta
                     else f"Traeme a {primero.split(' ', 1)[-1]} en el próximo mercado",
                     (5, 2, 0), dict(promesa, jugador=primero), _resp(rng, "contento")),
                    ("Lo voy a pensar", (0, 0, 0), None, "Bueno, le dejo la lista."),
                    ("No hay plata", no_hay, None, resp_no_hay),
                    ("Arreglate con lo que tenés", (-8, -3, 0), None, _resp(rng, "enojado")),
                ]}
    return {"tema": "refuerzo", "texto": texto, "opciones": [
        (f"Te lo traigo {cuando}", (5, 2, 0), promesa, _resp(rng, "contento")),
        ("No hay plata", no_hay, None, resp_no_hay),
        ("Arreglate con lo que tenés", (-8, -3, 0), None, _resp(rng, "enojado")),
    ]}


def reunion_racha(t, rng, n, mala, pos, nivel, ventana):
    if mala:
        return {"tema": "racha_mala", "texto": _f(rng, FRASES["racha_mala"], n=n),
                "opciones": [
                    ("Te banco, seguimos con vos", (6, 2, -6), None, _resp(rng, "contento")),
                    ("¿Qué necesitás?", (3, 0, 0),
                     {"pos": pos, "nivel": nivel + 3, "ventana": ventana},
                     f"Un {puesto(pos)}, presidente. Con eso cambiamos."),
                    ("Si no ganás el próximo, te vas", (-12, -2, 12), None,
                     _resp(rng, "enojado")),
                ]}
    return {"tema": "buena_racha", "texto": _f(rng, FRASES["buena_racha"], n=n),
            "opciones": [
                ("Seguí así, estamos contentos", (4, 2, -3), None, _resp(rng, "contento")),
                ("Está bien, pero quiero más", (-3, 0, 5), None, _resp(rng, "neutro")),
            ]}


def reunion_juvenil(t, rng, jugador, en_reserva=False):
    subir = ("Subilo a Primera", (4, 1, 0), {"subir": jugador.completo},
             _resp(rng, "contento"))
    return {"tema": "juvenil", "texto": _f(rng, FRASES["juvenil"], jugador=jugador.corto),
            "opciones": [
                subir if en_reserva else ("Dale, que juegue", (4, 1, 0), None,
                                          _resp(rng, "contento")),
                ("Todavía no, que espere", (-3, 0, 0), None, _resp(rng, "neutro")),
            ]}


def reunion_venta(t, rng, jugador, pos, ventana):
    return {"tema": "venta", "texto": _f(rng, FRASES["venta"], jugador=jugador),
            "opciones": [
                ("Era una oferta imposible de rechazar", (-2, 0, 0), None,
                 _resp(rng, "neutro")),
                ("Te traigo un reemplazo", (3, 0, 0), {"pos": pos, "nivel": 0, "ventana": ventana},
                 _resp(rng, "contento")),
                ("Es mi club, decido yo", (-8, -2, 0), None, _resp(rng, "enojado")),
            ]}


def reunion_vence(t, rng, jugador):
    return {"tema": "vence", "texto": _f(rng, FRASES["vence"], jugador=jugador.corto),
            "opciones": [
                ("Lo vamos a renovar", (3, 1, 0), None, _resp(rng, "contento")),
                ("Si quiere seguir, que baje el sueldo", (-1, 0, 0), None, _resp(rng, "neutro")),
                ("Si se va, se va", (-5, -2, 0), None, _resp(rng, "enojado")),
            ]}


def reunion_no_usa(t, rng, jugador, partidos):
    return {"tema": "no_usa", "texto": _f(rng, FRASES["no_usa"], jugador=jugador.corto,
                                          n=partidos),
            "opciones": [
                ("Lo pongo en venta", (3, 0, 0), None, _resp(rng, "contento")),
                ("Se queda, dale minutos", (-3, 0, 0), None, _resp(rng, "neutro")),
            ]}


def reunion_staff(t, rng, rol, nombre_rol, ventana):
    return {"tema": "staff", "texto": _f(rng, FRASES["staff"], rol=nombre_rol.lower()),
            "opciones": [
                ("Lo contrato", (4, 1, 0), {"rol": rol, "nivel": 2, "ventana": ventana,
                                            "nombre": nombre_rol}, _resp(rng, "contento")),
                ("No hay plata para eso", (-3, 0, 0), None, _resp(rng, "neutro")),
                ("No hace falta", (-6, 0, 0), None, _resp(rng, "enojado")),
            ]}


def reunion_lo_quieren(t, rng, club):
    return {"tema": "lo_quieren", "texto": _f(rng, FRASES["lo_quieren"], club=club),
            "opciones": [
                ("Andá, te deseo suerte", (0, 0, 0), {"oferta": club, "acepta": True},
                 "Gracias por todo, presidente. Este club siempre va a ser mío."),
                ("Te subo el sueldo para que te quedes", (8, 2, 0), {"aumento": 1.25},
                 "Me quedo, presidente. Vamos por más."),
                ("Tenés contrato, te quedás", (-12, -2, 0), None, _resp(rng, "enojado")),
            ]}


def reunion_entrenamiento(t, rng):
    return {"tema": "entrenamiento", "texto": _f(rng, FRASES["entrenamiento"]), "opciones": [
        ("Tenés razón, decidí vos", (5, 1, 0), {"plan": None}, _resp(rng, "contento")),
        ("Se entrena como digo yo", (-8, -1, 0), None, _resp(rng, "enojado")),
    ]}


def reunion_formacion(t, rng, formacion, derrotas):
    return {"tema": "formacion", "texto": _f(rng, FRASES["formacion"], formacion=formacion,
                                             n=derrotas), "opciones": [
        ("Está bien, elegí vos", (5, 1, 0), {"formacion": None}, _resp(rng, "contento")),
        ("Se juega así", (-12, -2, 0), None, _resp(rng, "enojado")),
    ]}


def reunion_ultimatum(t, rng, pos, nivel, ventana):
    return {"tema": "ultimatum", "texto": _f(rng, FRASES["ultimatum"]), "opciones": [
        ("Quedate, te traigo refuerzos", (10, 0, -3),
         {"pos": pos, "nivel": nivel + 3, "ventana": ventana}, _resp(rng, "neutro")),
        ("Te banco a muerte", (6, 0, -5), None, _resp(rng, "contento")),
        ("La puerta está abierta", (-15, 0, 0), None, _resp(rng, "enojado")),
    ]}


def reunion_general(t, rng):
    bien = t.confianza >= 50 and t.presion < 60
    return {"tema": "general",
            "texto": _f(rng, FRASES["general_bien" if bien else "general_mal"]),
            "opciones": [
                ("Confío en vos", (3, 0, -2), None, _resp(rng, "contento")),
                ("Quiero resultados ya", (-4, 0, 6), None, _resp(rng, "enojado")),
            ]}


def que_prometio(promesa):
    return promesa["nombre"].lower() if "rol" in promesa else puesto(promesa["pos"])


def reunion_promesa(t, rng, promesa, cumplida, exacto=False):
    if cumplida:
        cambiar(t, sat=21 if exacto else 15, conf=4)
        texto = _f(rng, FRASES["promesa_cumplida"], pos=que_prometio(promesa))
        if exacto:
            texto += f" ¡Y es {promesa['jugador']}, el que le pedí!"
        return {"tema": "promesa", "texto": texto, "opciones": []}
    cambiar(t, sat=-20, conf=-3)
    return {"tema": "promesa", "texto": _f(rng, FRASES["promesa_rota"],
                                           pos=que_prometio(promesa)),
            "opciones": [
                ("Tenés razón, perdón", (4, 0, 0), None, _resp(rng, "neutro")),
                ("No se pudo, hay que bancarse", (-3, 0, 0), None, _resp(rng, "enojado")),
            ]}


def reunion_renovacion(t, rng, sueldo_nuevo):
    if t.satisfaccion < 40:
        return {"tema": "no_renueva", "texto": _f(rng, FRASES["no_renueva"]), "opciones": []}
    return {"tema": "renovacion", "texto": _f(rng, FRASES["renovacion"]), "opciones": [
        (f"Renovamos 2 años (US$ {sueldo_nuevo * 1000:.0f}K/año)", (8, 0, 0),
         {"renovar": 2}, _resp(rng, "contento")),
        ("No, gracias por todo", (0, 0, 0), {"renovar": 0}, "Lo entiendo. Suerte."),
    ]}


def reunion_renuncia(t, rng):
    return {"tema": "renuncia", "texto": _f(rng, FRASES["renuncia"]), "opciones": []}


def aplicar(t, opcion):
    """Aplica la respuesta elegida. Devuelve (promesa o None, respuesta del DT)."""
    _, (sat, conf, pres), promesa, respuesta = opcion
    cambiar(t, sat, conf, pres)
    if promesa and ("pos" in promesa or "rol" in promesa):
        t.promesas.append(promesa)
        promesa = None
    return promesa, respuesta


def revisar_promesas(t, ventana, fichajes, staff=None):
    """Al cerrar una ventana: qué promesas se cumplieron.
    fichajes: [(posición, posición secundaria, nivel)] de los que llegaron en
    esa ventana. Cuenta también si el puesto es la posición secundaria.
    Devuelve [(posición, cumplida)]."""
    resultado, quedan = [], []
    for pr in t.promesas:
        if pr["ventana"] != ventana:
            quedan.append(pr)
            continue
        ok = cumple(pr, fichajes, staff)
        exacto = ok and any(len(f) > 3 and f[3] == pr.get("jugador") for f in fichajes)
        resultado.append((pr, ok, exacto))
    t.promesas = quedan
    return resultado


def cumple(promesa, fichajes, staff=None):
    """Una promesa de refuerzo se cumple si llegó alguien para ese puesto con
    el nivel prometido; una de cuerpo técnico, si hay alguien de ese nivel."""
    if "rol" in promesa:
        return (staff or {}).get(promesa["rol"], {}).get("nivel", 0) >= promesa["nivel"]
    for f in fichajes:
        pos, pos2, nivel = (f[0], None, f[1]) if len(f) == 2 else (f[0], f[1], f[2])
        if promesa["pos"] in (pos, pos2) and nivel >= promesa["nivel"]:
            return True
    return False


def barra(v, ancho=10):
    llenos = round(v / 100 * ancho)
    return "█" * llenos + "░" * (ancho - llenos)


def mostrar(t, club):
    print(f"\n=== DT de {club} ===")
    print(f"{t.completo}, {t.edad} años · {t.personalidad}")
    print(f"Prestigio {t.prestigio} · Sueldo US$ {t.sueldo * 1000:.0f}K/año")
    print(f"Contrato: {t.contrato} temporada{'s' if t.contrato != 1 else ''}")
    print(f"Satisfacción {barra(t.satisfaccion)} {t.satisfaccion:.0f}")
    print(f"Confianza    {barra(t.confianza)} {t.confianza:.0f}")
    print(f"Presión      {barra(t.presion)} {t.presion:.0f}")
    print("Historia:")
    for linea in curriculum(t):
        print(f"  {linea}")
    for pr in t.promesas:
        nivel = f"{pr['nivel']} estrellas" if "rol" in pr else f"nivel {pr['nivel']}"
        print(f"Le prometiste: {que_prometio(pr)}, {nivel} o más (ventana {pr['ventana']})")


def a_dict(t):
    return asdict(t) if t else None


def de_dict(d):
    return Tecnico(**d) if d else None


# ---------------------------------------------------------------- historial
def llega_a(t, club, temporada):
    t.clubes.append([club, temporada, None])


def se_va_de(t, temporada):
    if t.clubes and t.clubes[-1][2] is None:
        t.clubes[-1][2] = temporada


def cambiar_prestigio(t, delta):
    t.prestigio = int(max(10, min(99, round(t.prestigio + delta))))


def curriculum(t):
    """Líneas con su historia: logros y clubes."""
    lineas = list(t.logros[-6:])
    for club, desde, hasta in t.clubes[-5:]:
        lineas.append(f"{club} (T{desde}–{'T' + str(hasta) if hasta else 'hoy'})")
    if t.despidos:
        lineas.append(f"Lo echaron {t.despidos} vez{'es' if t.despidos > 1 else ''}")
    return lineas or ["Sin historia en el fútbol argentino"]


def resumen_cv(t):
    """Una línea para la lista de DT libres."""
    titulos = [l for l in t.logros if l.startswith(("🏆", "⬆"))]
    if titulos:
        return titulos[-1]
    if t.clubes:
        return f"Dirigió {len(t.clubes)} club{'es' if len(t.clubes) > 1 else ''}"
    return "Sin historia en el fútbol argentino"


def reiniciar(t):
    """Ánimo de arranque cuando llega a un club nuevo."""
    t.contrato, t.satisfaccion, t.confianza, t.presion = 2, 65.0, 50.0, 40.0
    t.fechas, t.promesas, t.avisos = 0, [], []
