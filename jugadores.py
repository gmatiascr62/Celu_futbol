"""
Jugadores, posiciones, formaciones y planteles para el simulador.

Cada club tiene 24 jugadores ficticios. Los planteles se generan para que
el equipo titular tenga la misma fuerza que el modelo aprendió del club
real, y se guardan en planteles.json para que sean siempre los mismos.
"""
import json
import math
import os
import random
from dataclasses import asdict, dataclass

ARCHIVO_PLANTELES = "planteles.json"
VERSION_PLANTELES = 2   # si cambia, los planteles se vuelven a generar

# ---------------------------------------------------------------- posiciones
POSICIONES = ("ARQ", "DFC", "LD", "LI", "MCD", "MC", "MCO", "ED", "EI", "DC")
NOMBRE_POS = {"ARQ": "arquero", "DFC": "defensor central", "LD": "lateral derecho",
              "LI": "lateral izquierdo", "MCD": "volante central",
              "MC": "volante mixto", "MCO": "enganche", "ED": "extremo derecho",
              "EI": "extremo izquierdo", "DC": "centrodelantero"}
LINEA = {"ARQ": 0, "DFC": 1, "LD": 1, "LI": 1, "MCD": 2, "MC": 2, "MCO": 2,
         "ED": 3, "EI": 3, "DC": 3}

# Cuánto aporta cada posición al ataque y a la defensa del equipo
APORTE = {"ARQ": (0.0, 3.0), "DFC": (0.2, 1.6), "LD": (0.6, 1.0), "LI": (0.6, 1.0),
          "MCD": (0.5, 1.1), "MC": (1.0, 0.7), "MCO": (1.4, 0.3),
          "ED": (1.3, 0.4), "EI": (1.3, 0.4), "DC": (1.3, 0.15)}
# Qué parte del rendimiento ofensivo sale del ataque y qué parte de la creación
MEZCLA_OF = {"ARQ": (0.0, 0.0), "DFC": (0.2, 0.8), "LD": (0.5, 0.5), "LI": (0.5, 0.5),
             "MCD": (0.2, 0.8), "MC": (0.4, 0.6), "MCO": (0.3, 0.7),
             "ED": (0.6, 0.4), "EI": (0.6, 0.4), "DC": (0.85, 0.15)}

# Rendimiento jugando fuera de su posición
CERCANAS = {("LD", "LI"): 0.90, ("DFC", "LD"): 0.85, ("DFC", "LI"): 0.85,
            ("DFC", "MCD"): 0.85, ("MCD", "MC"): 0.93, ("MC", "MCO"): 0.92,
            ("MCO", "ED"): 0.88, ("MCO", "EI"): 0.88, ("ED", "EI"): 0.92,
            ("ED", "DC"): 0.88, ("EI", "DC"): 0.88, ("MCO", "DC"): 0.85,
            ("LD", "ED"): 0.85, ("LI", "EI"): 0.85}
SECUNDARIAS = {"DFC": ("MCD", "LD", "LI"), "LD": ("LI", "ED", "DFC"),
               "LI": ("LD", "EI", "DFC"), "MCD": ("DFC", "MC"), "MC": ("MCD", "MCO"),
               "MCO": ("MC", "ED", "EI"), "ED": ("EI", "MCO", "DC"),
               "EI": ("ED", "MCO", "DC"), "DC": ("ED", "EI", "MCO")}

FORMACIONES = {
    "4-4-2":   [["LD", "DFC", "DFC", "LI"], ["ED", "MCD", "MC", "EI"], ["DC", "DC"]],
    "4-3-3":   [["LD", "DFC", "DFC", "LI"], ["MCD", "MC", "MC"], ["ED", "DC", "EI"]],
    "4-2-3-1": [["LD", "DFC", "DFC", "LI"], ["MCD", "MCD"], ["ED", "MCO", "EI"], ["DC"]],
    "5-3-2":   [["LD", "DFC", "DFC", "DFC", "LI"], ["MCD", "MC", "MC"], ["DC", "DC"]],
    "3-5-2":   [["DFC", "DFC", "DFC"], ["ED", "MCD", "MCO", "MC", "EI"], ["DC", "DC"]],
}
FORMACION_BASE = "4-4-2"   # con esta se calibra la fuerza del plantel
# Efecto propio de cada formación (ataque, defensa) en la escala del modelo.
# Defensa positiva = recibe más goles. Las ofensivas abren el partido para
# los dos lados y las defensivas lo cierran; el plantel define cuál conviene.
# Ya compensa lo que cambia el plantel promedio en cada formación, así que
# para un plantel típico el efecto total es:
#   4-3-3 +4% / +4%   4-2-3-1 +2% / +1%   5-3-2 -10% / -9%   3-5-2 +5% / +8%
EFECTO_FORMACION = {"4-4-2": (0.0, 0.0), "4-3-3": (0.039, 0.034),
                    "4-2-3-1": (-0.006, 0.009), "5-3-2": (-0.069, -0.084),
                    "3-5-2": (0.035, 0.058)}

# Escala: 1 punto de promedio = 2,5% de goles. 65 = equipo promedio.
K = 0.025
PROMEDIO = 65.0



# Composición del plantel: 24 jugadores
COMPOSICION = {"ARQ": 3, "DFC": 4, "LD": 2, "LI": 2, "MCD": 2, "MC": 3,
               "MCO": 2, "ED": 2, "EI": 2, "DC": 2}

# Perfil de cada posición: diferencia de cada atributo respecto del nivel
# ofensivo (ataque, creación) o defensivo (defensa, atajada) del club
PERFIL = {
    "ARQ": {"ataque": -40, "creacion": -25, "defensa": -30},
    "DFC": {"ataque": -22, "creacion": -8, "defensa": 0},
    "LD":  {"ataque": -6, "creacion": -2, "defensa": -4},
    "MCD": {"ataque": -14, "creacion": -1, "defensa": -2},
    "MC":  {"ataque": -6, "creacion": 1, "defensa": -10},
    "MCO": {"ataque": -2, "creacion": 4, "defensa": -25},
    "ED":  {"ataque": 1, "creacion": -1, "defensa": -24},
    "DC":  {"ataque": 3, "creacion": -12, "defensa": -30},
}
PERFIL["LI"], PERFIL["EI"] = PERFIL["LD"], PERFIL["ED"]

# ---------------------------------------------------------------- nombres
NOMBRES = ("Adrián", "Agustín", "Alan", "Alejandro", "Alexis", "Andrés", "Ariel", "Axel",
           "Benjamín", "Braian", "Brian", "Bruno", "Camilo", "Carlos", "Claudio",
           "Cristian", "Damián", "Dante", "Darío", "Diego", "Elías", "Emanuel",
           "Emiliano", "Enzo", "Ernesto", "Esteban", "Ezequiel", "Fabricio", "Facundo",
           "Federico", "Fernando", "Francisco", "Franco", "Gabriel", "Gastón", "Germán",
           "Gerónimo", "Gonzalo", "Guillermo", "Hernán", "Hugo", "Ignacio", "Iván",
           "Javier", "Joaquín", "Jonathan", "Jorge", "José", "Juan Cruz", "Juan Manuel",
           "Julián", "Kevin", "Lautaro", "Leandro", "Leonel", "Lisandro", "Lorenzo",
           "Lucas", "Luciano", "Luis", "Marcelo", "Marcos", "Martín", "Mateo", "Matías",
           "Mauro", "Maximiliano", "Miguel", "Milton", "Nahuel", "Nicolás", "Octavio",
           "Pablo", "Pedro", "Ramiro", "Rodrigo", "Rubén", "Samuel", "Santiago",
           "Sebastián", "Simón", "Thiago", "Tobías", "Tomás", "Ulises", "Valentín",
           "Víctor", "Walter")
APELLIDOS = {
    # (peso, apellidos)
    "italianos": (45, (
        "Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci",
        "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Mancini", "Costa",
        "Giordano", "Rizzo", "Lombardi", "Moretti", "Barbieri", "Fontana", "Santoro",
        "Mariani", "Rinaldi", "Caruso", "Ferrara", "Galli", "Martini", "Leone", "Longo",
        "Gentile", "Martinelli", "Vitale", "Serra", "Coppola", "De Santis", "D'Angelo",
        "Marchetti", "Parisi", "Villa", "Cattaneo", "Sala", "Pellegrini", "Palumbo",
        "Sanna", "Fabbri", "Monti", "Grasso", "Bellini", "Basile", "Riva", "Donati",
        "Piras", "Messina", "Benedetti", "Tedesco", "Zanetti", "Bianco", "Di Stefano",
        "Lucchetti", "Cavallo", "Spinelli", "Pagano", "Sartori", "Rota", "Bassi",
        "Guerra", "Ferraro", "Agostini", "Amato", "Baldini", "Battaglia", "Bellucci",
        "Bernardi", "Bertolini", "Bonetti", "Borrelli", "Brambilla", "Calabrese",
        "Canale", "Capello", "Carbone", "Castelli", "Cerutti", "Colonna", "Corsi",
        "Crespi", "D'Amico", "De Rosa", "Del Vecchio", "Di Marco", "Di Pietro",
        "Falcone", "Farina", "Fiore", "Gatti", "Giuliani", "Grassi", "Guidi", "Iacono",
        "Lanza", "Lazzari", "Locatelli", "Lombardo", "Lupo", "Maggi", "Mancuso",
        "Marini", "Mazza", "Melis", "Milani", "Montanari", "Morelli", "Negri", "Neri",
        "Orlando", "Pace", "Palmieri", "Papa", "Pastore", "Perrone", "Piazza",
        "Pirovano", "Poli", "Pozzi", "Proietti", "Raimondi", "Riccardi", "Ruggiero",
        "Salvi", "Santini", "Sorrentino", "Testa", "Toscano", "Valentini", "Vaccaro",
        "Zanella", "Zappa", "Bonfiglio", "Tomasini", "Righetti", "Ottaviano", "Scotti")),
    "españoles": (34, (
        "González", "Rodríguez", "Gómez", "Fernández", "López", "Díaz", "Martínez",
        "Pérez", "García", "Sánchez", "Romero", "Sosa", "Álvarez", "Torres", "Ruiz",
        "Ramírez", "Flores", "Acosta", "Benítez", "Medina", "Suárez", "Herrera",
        "Aguirre", "Giménez", "Molina", "Castro", "Rojas", "Ortiz", "Silva", "Núñez",
        "Luna", "Juárez", "Cabrera", "Ríos", "Morales", "Godoy", "Ledesma", "Vera",
        "Ojeda", "Ponce", "Villalba", "Cardozo", "Navarro", "Quiroga", "Figueroa",
        "Correa", "Paz", "Coronel", "Peralta", "Acuña", "Aguilar", "Alonso", "Amaya",
        "Arias", "Ayala", "Barrios", "Blanco", "Bravo", "Bustos", "Cáceres", "Campos",
        "Carrizo", "Castillo", "Cejas", "Chávez", "Cruz", "Delgado", "Domínguez",
        "Escobar", "Espinoza", "Farías", "Ferreyra", "Fuentes", "Galván", "Gauna",
        "Gutiérrez", "Guzmán", "Hernández", "Ibáñez", "Lucero", "Maldonado", "Mansilla",
        "Márquez", "Mendoza", "Miranda", "Montenegro", "Moreno", "Muñoz", "Olivera",
        "Ortega", "Páez", "Palacios", "Pereyra", "Quintana", "Ramos", "Reynoso",
        "Rivero", "Robledo", "Salinas", "Sandoval", "Santillán", "Soria", "Sotelo",
        "Vázquez", "Vega", "Villegas", "Zárate")),
    "vascos": (6, (
        "Echeverría", "Goicoechea", "Iturbe", "Larrea", "Aramburu", "Etcheverry",
        "Urquiza", "Arrieta", "Zubiría", "Olaechea", "Ibarra", "Iriarte", "Lizarraga",
        "Mendizábal", "Ochoa", "Garmendia", "Elizondo", "Uriarte", "Zabala", "Ugarte",
        "Irigoyen", "Basualdo")),
    "europeos": (10, (
        "Kowalski", "Nowak", "Wiśniewski", "Lewandowski", "Zielinski", "Kamiński",
        "Wójcik", "Kowalczyk", "Szymański", "Dąbrowski", "Kozłowski", "Mazur",
        "Schmidt", "Müller", "Weber", "Fischer", "Hoffmann", "Becker", "Schneider",
        "Wagner", "Klein", "Krüger", "Braun", "Vogel", "Dubois", "Moreau", "Lefèvre",
        "Bernard", "Laurent", "Girard", "Fournier", "Chevalier", "Dupont", "Petrovich",
        "Kovačević", "Babić", "Horvat", "Jurić", "Perić", "Marković", "Vuković",
        "Kelly", "O'Connor", "Walsh", "Murphy", "Ryan", "Kuznetsov", "Shevchenko",
        "Bondarenko", "Tkachenko", "Popov", "Novak", "Andersen", "Jensen", "Nielsen",
        "Kazlauskas", "Kevorkian", "Arslanian", "Bedoyan", "Avedikian", "Goldberg",
        "Kaplan", "Feldman", "Rosenberg")),
    "árabes": (5, (
        "Haddad", "Saadi", "Jalil", "Nasif", "Abdala", "Yunes", "Daher", "Chehade",
        "Karam", "Zaidan", "Abraham", "Saad", "Nazar", "Hamed", "Cury", "Kalil",
        "Massad", "Sleiman", "Tannus", "Nahas", "Faraj")),
}
# Combinaciones de jugadores reales conocidos que no queremos repetir
FAMOSOS = {"Lautaro Martínez", "Enzo Fernández", "Julián Álvarez", "Emiliano Martínez",
           "Nicolás Otamendi", "Leandro Paredes", "Cristian Romero", "Nahuel Molina",
           "Gonzalo Montiel", "Nicolás Tagliafico", "Lisandro Martínez",
           "Rodrigo De Paul", "Enzo Pérez", "Franco Armani", "Lucas Martínez",
           "Gonzalo Higuaín", "Javier Zanetti", "Diego Simeone", "Pablo Aimar",
           "Ezequiel Lavezzi", "Sebastián Battaglia", "Marcos Rojo", "Ramiro Funes Mori",
           "Lucas Biglia", "Gabriel Batistuta", "Matías Almeyda", "Juan Cruz Komar",
           "Facundo Medina", "Valentín Gómez", "Nicolás González", "Thiago Almada",
           "Valentín Barco", "Franco Mastantuono", "Lucas Romero", "Matías Rojas",
           "Mateo Retegui", "Luciano Vietto", "Diego Milito", "Germán Pezzella",
           "Walter Samuel", "Juan Manuel Sara", "Brian Romero", "Lucas Benítez",
           "Marcos Acuña", "Mauro Zárate", "Ariel Ortega", "Maximiliano Rodríguez",
           "Gonzalo Martínez", "Franco Vázquez", "Nicolás Domínguez", "Joaquín Correa",
           "Alejandro Gómez", "Ignacio Fernández", "Matías Suárez", "Cristian Medina",
           "Brian Aguirre", "Javier Pastore", "Ezequiel Palacios", "Esteban Andrada",
           "Hernán Crespo", "Fernando Gago", "Claudio López", "Cristian Pavón",
           "Rodrigo Palacio", "José Sosa", "Leonel Vangioni", "Pablo Pérez",
           "Darío Benedetto", "Ariel Garcé", "Juan Pablo Sorín", "Martín Ojeda"}

MAX_POR_APELLIDO = 3


def generar_nombre(rng, usados, apellidos_club):
    """Nombre y apellido al azar. No repite nombres en toda la liga, ni
    apellidos dentro del mismo club, ni jugadores famosos reales."""
    grupos = list(APELLIDOS.values())
    pesos = [g[0] for g in grupos]
    intentos = 0
    while True:
        intentos += 1
        apellido = rng.choice(rng.choices(grupos, weights=pesos)[0][1])
        nombre = rng.choice(NOMBRES)
        completo = f"{nombre} {apellido}"
        # cada apellido aparece como mucho 3 veces en toda la liga
        repetido = intentos < 60 and sum(
            1 for n in usados if n.endswith(" " + apellido)) >= MAX_POR_APELLIDO
        if (completo not in usados and completo not in FAMOSOS
                and apellido not in apellidos_club and not repetido):
            usados.add(completo)
            apellidos_club.add(apellido)
            return nombre, apellido


# ---------------------------------------------------------------- jugador
@dataclass(eq=False)
class Jugador:
    nombre: str
    apellido: str
    pos: str
    edad: int
    ataque: float
    creacion: float
    defensa: float
    atajada: float
    resistencia: float
    potencial: int = 0
    pos2: str | None = None
    forma: float = 1.0
    fisico: float = 1.0     # cómo llega al partido (1 = descansado)
    energia: float = 1.0    # durante el partido
    lesion: int = 0         # fechas que le quedan afuera por lesión
    contrato: int = 0       # temporadas de contrato que le quedan (0 = libre o vencido)
    sueldo: float = 0.0     # sueldo anual pactado, millones de dólares (0 = sin pactar)
    partidos: int = 0       # partidos jugados en la temporada
    pot_est: int = 0        # potencial que estima el club (los pibes de la reserva)

    @property
    def completo(self):
        return f"{self.nombre} {self.apellido}"

    @property
    def corto(self):
        return f"{self.nombre[0]}. {self.apellido}"


def afinidad(j, slot):
    """Qué porcentaje de su rendimiento da un jugador en esa posición."""
    if j.pos == slot:
        return 1.0
    if slot == j.pos2:
        return 0.95
    if "ARQ" in (j.pos, slot):
        return 0.3
    f = CERCANAS.get((j.pos, slot)) or CERCANAS.get((slot, j.pos))
    if f:
        return f
    return 0.8 if abs(LINEA[j.pos] - LINEA[slot]) <= 1 else 0.65


def valores(j, slot):
    """Rendimiento ofensivo y defensivo de un jugador en una posición."""
    f = afinidad(j, slot) * j.forma
    if slot == "ARQ":
        return 0.0, j.atajada * f
    wa, wc = MEZCLA_OF[slot]
    of = wa * j.ataque + wc * j.creacion
    de = 0.75 * j.defensa + 0.25 * j.creacion if slot == "MCD" else j.defensa
    return of * f, de * f


def puntaje(j, slot, con_fisico=True):
    """Qué tan bueno es un jugador para esa posición (para elegir titulares)."""
    wa, wd = APORTE[slot]
    of, de = valores(j, slot)
    p = (wa * of + wd * de) / (wa + wd)
    return p * (0.7 + 0.3 * j.fisico) if con_fisico else p


def nivel(j):
    """Nivel general del jugador en su posición."""
    return round(puntaje(j, j.pos, con_fisico=False))


def fuerza(xi, formacion=None):
    """Fuerza de los 11 en cancha, en la escala del modelo de goles.
    xi: lista de [jugador, posición]. Devuelve (ataque, defensa, ...)."""
    sa = pa = sd = pd = 0.0
    for j, s in xi:
        wa, wd = APORTE[s]
        of, de = valores(j, s)
        sa += wa * of
        pa += wa
        sd += wd * de
        pd += wd
    prom_of = sa / pa if pa else 0.0
    prom_de = sd / pd if pd else 0.0
    ataque = K * (prom_of - PROMEDIO)
    defensa = -K * (prom_de - PROMEDIO)
    if formacion:
        ef_at, ef_df = EFECTO_FORMACION[formacion]
        ataque += ef_at
        defensa += ef_df
    return ataque, defensa, prom_of, prom_de


ORDEN_SLOTS = ("ARQ", "DC", "DFC", "MCD", "LD", "LI", "MCO", "ED", "EI", "MC")


def aptos(plantel):
    """Los que pueden jugar (sin lesión). Si faltan para armar un equipo,
    juegan todos."""
    sanos = [j for j in plantel if not j.lesion]
    return sanos if len(sanos) >= 16 else list(plantel)


def armar_xi(plantel, formacion, con_fisico=True):
    """Elige los 11 mejores para esa formación, puesto por puesto."""
    slots = ["ARQ"] + [s for linea in FORMACIONES[formacion] for s in linea]
    libres = list(plantel)
    xi = []
    for s in sorted(slots, key=ORDEN_SLOTS.index):
        mejor = max(libres, key=lambda j: puntaje(j, s, con_fisico))
        libres.remove(mejor)
        xi.append([mejor, s])
    return xi


# ---------------------------------------------------------------- generación
def _clip(v, lo=20, hi=99):
    return max(lo, min(hi, v))


def _potencial(j, rng):
    """Hasta dónde puede llegar: los jóvenes tienen margen."""
    if j.edad <= 21:
        extra = rng.randint(6, 22)
    elif j.edad <= 25:
        extra = rng.randint(2, 11)
    elif j.edad <= 29:
        extra = rng.randint(0, 4)
    else:
        extra = 0
    return min(99, nivel(j) + extra)


def _redondear(j):
    j.ataque, j.creacion = round(_clip(j.ataque)), round(_clip(j.creacion))
    j.defensa, j.atajada = round(_clip(j.defensa)), round(_clip(j.atajada, 10))
    j.resistencia = round(j.resistencia)


def generar_jugador(pos, edad, meta_of, meta_de, calidad, rng, usados, apellidos_club):
    """Un jugador nuevo para un club con ese nivel ofensivo y defensivo."""
    if edad <= 21:
        calidad -= 5
    elif edad >= 33:
        calidad -= 2
    p = PERFIL[pos]
    at = meta_of + p["ataque"] + calidad + rng.gauss(0, 3.5)
    cr = meta_of + p["creacion"] + calidad + rng.gauss(0, 3.5)
    df = meta_de + p["defensa"] + calidad + rng.gauss(0, 3.5)
    aj = meta_de + calidad + rng.gauss(0, 3) if pos == "ARQ" else rng.uniform(10, 25)
    res = rng.gauss(68, 9) - (8 if edad >= 33 else 0)
    nombre, apellido = generar_nombre(rng, usados, apellidos_club)
    pos2 = rng.choice(SECUNDARIAS[pos]) if pos in SECUNDARIAS and rng.random() < 0.35 else None
    return Jugador(nombre, apellido, pos, edad, at, cr, df, aj, _clip(res, 35, 95), pos2=pos2)


def metas(ataque, defensa):
    """Nivel ofensivo y defensivo de un club, a partir de su fuerza en el modelo."""
    return PROMEDIO + ataque / K, PROMEDIO - defensa / K


def generar_plantel(ataque, defensa, rng, usados=None):
    """Genera 24 jugadores cuyo equipo titular tiene la fuerza pedida
    (ataque y defensa en la escala del modelo: 0 = promedio de la liga)."""
    usados = set() if usados is None else usados
    meta_of, meta_de = metas(ataque, defensa)
    plantel = []
    apellidos_club = set()
    for pos, cantidad in COMPOSICION.items():
        for i in range(cantidad):
            edad = round(rng.triangular(19, 37, 28)) if pos == "ARQ" \
                else round(rng.triangular(18, 35, 26))
            calidad = (4, 0, -5)[min(i, 2)] + rng.gauss(0, 3)
            plantel.append(generar_jugador(pos, edad, meta_of, meta_de, calidad, rng,
                                           usados, apellidos_club))

    # Ajuste fino: el equipo titular tiene que dar exactamente la fuerza pedida
    for _ in range(5):
        _, _, prom_of, prom_de = fuerza(armar_xi(plantel, FORMACION_BASE, False),
                                        FORMACION_BASE)
        d_of, d_de = meta_of - prom_of, meta_de - prom_de
        for j in plantel:
            j.ataque, j.creacion = j.ataque + d_of, j.creacion + d_of
            j.defensa += d_de
            if j.pos == "ARQ":
                j.atajada += d_de
    for j in plantel:
        _redondear(j)
        j.potencial = _potencial(j, rng)
    return plantel


# ---------------------------------------------------------------- temporadas
# Al terminar una temporada todos cumplen un año. Desde los 31 empiezan a
# bajar, desde los 34 se pueden retirar, y por cada retirado sube un
# juvenil de la cantera para el mismo puesto.
EDAD_RETIRO = 34          # los arqueros duran 2 años más
EDAD_RETIRO_SEGURO = 40


def pasar_temporada(plantel, ataque, defensa, rng, usados, cantera=0.0, reponer=True):
    """Envejece el plantel. ataque y defensa: la fuerza del club en el modelo,
    que define el nivel de los juveniles; cantera: cuánto mejores salen por
    las inferiores del club (0 = como siempre). Con reponer=False no sube un
    juvenil por cada retirado (cuando el club tiene reserva, ver club.py).
    Devuelve (retirados, juveniles)."""
    meta_of, meta_de = metas(ataque, defensa)
    retirados, juveniles = [], []
    for j in list(plantel):
        j.edad += 1
        j.fisico, j.lesion = 1.0, 0
        extra = 2 if j.pos == "ARQ" else 0
        if j.edad >= 31 + extra:
            baja = rng.uniform(0.5, 1.5) * (j.edad - 30 - extra)
            j.ataque, j.creacion = j.ataque - baja, j.creacion - baja
            j.defensa, j.atajada = j.defensa - baja, j.atajada - baja
            j.resistencia -= rng.uniform(1, 3)
            _redondear(j)
            j.potencial = min(j.potencial, nivel(j))
        prob = 0.15 * (j.edad - EDAD_RETIRO - extra + 1)
        if j.edad >= EDAD_RETIRO_SEGURO + extra or (prob > 0 and rng.random() < prob):
            plantel.remove(j)
            retirados.append(j)
    apellidos_club = {j.apellido for j in plantel}
    for viejo in (retirados if reponer else []):
        nuevo = generar_jugador(viejo.pos, rng.randint(17, 21), meta_of, meta_de,
                                rng.gauss(-6 + cantera, 4), rng, usados, apellidos_club)
        _redondear(nuevo)
        nuevo.potencial = min(99, _potencial(nuevo, rng) + max(0, round(cantera)))
        plantel.append(nuevo)
        juveniles.append(nuevo)
    return retirados, juveniles


# ---------------------------------------------------------------- entrenamiento
# Entre fecha y fecha cada club entrena. El nivel sube hacia el potencial,
# más rápido cuanto más joven es el jugador y más fuerte el entrenamiento.
# Entrenar fuerte rinde más, pero llegan más cansados y se pueden lesionar.
TIPOS_ENTRENAMIENTO = {
    "completo": "un poco de todo",
    "ataque": "ataque y creación",
    "defensa": "defensa y atajada",
    "fisico": "resistencia",
    "descanso": "recuperar energía",
}
# progreso, físico que suma o resta, chance de lesión por jugador
INTENSIDADES = {"suave": (0.5, 0.06, 0.0),
                "normal": (1.0, 0.0, 0.004),
                "fuerte": (1.7, -0.07, 0.012)}
RITMO = 0.008             # parte del margen hasta el potencial que gana por fecha
RITMO_RESISTENCIA = 0.15  # puntos de resistencia por fecha (entrenando físico)
RECUPERO_DESCANSO = 0.12
# Qué atributos mejora cada tipo (en los arqueros, la atajada)
ATRIBUTOS = {"completo": ("ataque", "creacion", "defensa"),
             "ataque": ("ataque", "creacion"), "defensa": ("defensa",)}
ENFOQUE = 1.5             # entrenar algo puntual rinde más en eso


def ritmo_edad(edad):
    return 1.4 if edad <= 21 else 1.0 if edad <= 25 else 0.6 if edad <= 29 else 0.3


SIN_EFECTO = {}   # multiplicadores de un club "promedio" (ver club.py)


def entrenar(plantel, tipo, intensidad, rng, mult=SIN_EFECTO):
    """Una semana de entrenamiento. Devuelve (mejoras, lesionados):
    mejoras = [(jugador, nivel antes, nivel después)] de los que subieron
    al menos un punto; lesionados = [(jugador, fechas afuera)].
    mult: lo que aportan las instalaciones y el cuerpo técnico del club
    (progreso, cada atributo, resistencia, lesiones y su duración)."""
    progreso, fisico, riesgo = INTENSIDADES[intensidad]
    if tipo == "descanso":
        progreso, fisico, riesgo = 0.0, RECUPERO_DESCANSO, 0.0
    progreso *= mult.get("progreso", 1.0)
    riesgo *= mult.get("lesion", 1.0)
    mejoras, lesionados = [], []
    for j in plantel:
        if j.lesion:
            j.lesion -= 1
            continue
        j.fisico = max(0.5, min(1.0, j.fisico + fisico))
        if tipo == "fisico":
            j.resistencia = min(95, j.resistencia + RITMO_RESISTENCIA * progreso
                                * mult.get("resistencia", 1.0)
                                * ritmo_edad(j.edad) * rng.uniform(0.5, 1.5))
        elif progreso:
            if j.pos == "ARQ":
                attrs = ("atajada",) if tipo != "ataque" else ()
            else:
                attrs = ATRIBUTOS[tipo]
            antes = puntaje(j, j.pos, con_fisico=False)
            margen = j.potencial - antes
            if attrs and margen > 0:
                paso = (RITMO * progreso * ritmo_edad(j.edad) * margen
                        * rng.uniform(0.5, 1.5) * (1 if tipo == "completo" else ENFOQUE))
                pasos = {a: paso * mult.get(a, 1.0) for a in attrs}
                for a in attrs:
                    setattr(j, a, min(99, getattr(j, a) + pasos[a]))
                # el nivel nunca pasa el potencial
                subio = puntaje(j, j.pos, con_fisico=False) - antes
                if subio > margen:
                    for a in attrs:
                        setattr(j, a, getattr(j, a) - pasos[a] * (1 - margen / subio))
                if nivel(j) > round(antes):
                    mejoras.append((j, round(antes), nivel(j)))
        if riesgo and rng.random() < riesgo:
            j.lesion = max(1, rng.choice((1, 1, 2, 2, 3, 4)) - mult.get("dur", 0))
            lesionados.append((j, j.lesion))
    return mejoras, lesionados


# ---------------------------------------------------------------- archivo
def _a_dict(j):
    d = asdict(j)
    d.pop("fisico")
    d.pop("energia")
    for campo in ("lesion", "contrato", "sueldo", "partidos", "pot_est"):
        d.pop(campo)
    return d


def cargar_planteles(modelo, ruta=ARCHIVO_PLANTELES):
    """Lee planteles.json; genera los clubes que falten y lo guarda."""
    clubes = {}
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            datos = json.load(f)
        if datos.get("version") == VERSION_PLANTELES:
            clubes = {c: [Jugador(**d) for d in js] for c, js in datos["clubes"].items()}
    faltan = [c for c in sorted(modelo["equipos"]) if c not in clubes]
    if faltan:
        usados = {j.completo for js in clubes.values() for j in js}
        rng = random.Random(f"planteles-{len(clubes)}")
        for c in faltan:
            d = modelo["equipos"][c]
            clubes[c] = generar_plantel(d["ataque"], d["defensa"], rng, usados)
        with open(ruta, "w", encoding="utf-8") as f:
            json.dump({"version": VERSION_PLANTELES,
                       "clubes": {c: [_a_dict(j) for j in js] for c, js in clubes.items()}},
                      f, ensure_ascii=False, indent=1)
        print(f"Planteles generados para {len(faltan)} clubes (guardados en {ruta}).")
    return clubes


def copiar_plantel(plantel):
    return [Jugador(**asdict(j)) for j in plantel]


def mostrar_plantel(nombre_club, plantel):
    print(f"\n=== {nombre_club} ===")
    print(f"{'Pos':<4}{'Jugador':<15}{'Ed':>3}{'Nv':>4}{'Pot':>4}"
          f"{'At':>4}{'Cr':>4}{'Df':>4}{'Res':>4}")
    for j in sorted(plantel, key=lambda j: (POSICIONES.index(j.pos), -nivel(j))):
        df = j.atajada if j.pos == "ARQ" else j.defensa
        pos = j.pos + ("*" if j.pos2 else "")
        print(f"{pos:<4}{j.corto[:14]:<15}{j.edad:>3}{nivel(j):>4}{j.potencial:>4}"
              f"{j.ataque:>4.0f}{j.creacion:>4.0f}{df:>4.0f}{j.resistencia:>4.0f}")
    print("(* = juega también en otra posición. En arqueros, Df = atajada)")
    lesionados = [j for j in plantel if j.lesion]
    if lesionados:
        print("Lesionados: " + ", ".join(
            f"{j.corto} ({j.lesion} fecha{'s' if j.lesion > 1 else ''})"
            for j in lesionados))
