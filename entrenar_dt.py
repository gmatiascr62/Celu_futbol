#!/usr/bin/env python3
"""
Entrena a los DTs con aprendizaje por refuerzo.

Los DTs arrancan sin saber nada y aprenden jugando miles de situaciones:
  - Aprenden de atrás para adelante: primero qué conviene en el minuto 85,
    después en el 78 (sabiendo ya qué harán en el 85), y así hasta el
    arranque del partido.
  - En cada situación juegan el resto del partido con cada una de las
    tácticas posibles y con la misma suerte (los mismos números al azar),
    así la diferencia de resultado es mérito de la táctica y no del azar.
  - Anotan cuántos puntos promedio sacó cada táctica en cada situación.
  - Tienen en cuenta el cansancio: presionar rinde, pero gasta energía.
Cada personalidad aprende por separado, porque valora distinto los
resultados (el conservador valora más el empate, el arriesgado la victoria).

Uso:
    python entrenar_dt.py         # 100 pruebas por situación
    python entrenar_dt.py 400     # más pruebas = aprende mejor (tarda más)

Necesita simulador_futbol.py en la misma carpeta (y modelo_poisson.json
para la prueba final). Si ya existe dt_ia.json de esta versión, sigue
sumando experiencia.
"""
import json
import math
import os
import random
import sys
import time

import simulador_futbol as S

ARCHIVO = "dt_ia.json"
PERSONALIDADES = ("equilibrado", "conservador", "arriesgado")
N_ACC = len(S.ACCIONES)
# Rangos de fuerza relativa (log del cociente de goles esperados)
RANGOS_FUERZA = list(zip((-1.6,) + S.CORTES_FUERZA, S.CORTES_FUERZA + (1.6,)))

# ------------------------------------------------- tablas precalculadas
# Para que el entrenamiento sea rápido se precalcula todo lo posible.
PESO_MIN = [S.PESO[m] * S.ESCALA / 90 for m in range(91)]
MULT = [[S.multiplicador(S.ACCIONES[a], S.ACCIONES[b], 0) for b in range(N_ACC)]
        for a in range(N_ACC)]
DESGASTE = [S.DESGASTE[a] for a in S.ACCIONES]
VALIDAS = [[S.ACCIONES.index(t) for t in S.disponibles(m)] for m in range(91)]
POR_TIPO = {t: [i for i, a in enumerate(S.ACCIONES) if S.TIPO_RIVAL[a] == t]
            for t in (0, 1, 2)}
MOMENTOS = set(S.MOMENTOS_DECISION)


def puntos(personalidad, gf, gc):
    p = S.PERSONALIDADES[personalidad]
    return p["ganar"] if gf > gc else p["empatar"] if gf == gc else 0.0


def decide_tabla(tablas, pers, actual, minuto, gf, gc, b_f, b_c, t_rival, energia):
    """Lo que haría el DT en ese momento con lo que ya aprendió."""
    q = tablas[pers].get(S.estado_dt(minuto, gf, gc, b_f, b_c,
                                     S.ACCIONES[t_rival], energia))
    if not q:
        return actual
    mejor = max(VALIDAS[minuto], key=q.__getitem__)
    return mejor if q[mejor] - q[actual] > 0.02 else actual


def jugar_resto(tablas, b, t, g, e, cambios, vent, pers, desde, rng):
    """Juega desde 'desde' hasta el 90. Índice 0 = el DT que aprende,
    1 = el rival. Los dos deciden con lo ya aprendido. Imita al simulador:
    entretiempo, cambios, decisiones tácticas, goles y desgaste."""
    t, g, e, cambios, vent = list(t), list(g), list(e), list(cambios), list(vent)
    ultimo_cambio = [desde, desde]
    ultimo_gol = -99
    for m in range(desde, 91):
        if m != desde:
            if m == 46:
                e = [min(1.0, x + S.RECUPERO_ENTRETIEMPO) for x in e]
            if m in MOMENTOS:
                for i in (0, 1):
                    n = S.decidir_cambios(pers[i], m, e[i], cambios[i], vent[i],
                                          g[i], g[1 - i])
                    if n:
                        e[i] = S.aplicar_cambios(e[i], n)
                        cambios[i] -= n
                        if m != 46:
                            vent[i] -= 1
            if m in MOMENTOS or m == ultimo_gol + 2:
                for i in (0, 1):
                    if m - ultimo_cambio[i] >= S.MIN_ENTRE_CAMBIOS:
                        nueva = decide_tabla(tablas, pers[i], t[i], m, g[i], g[1 - i],
                                             b[i], b[1 - i], t[1 - i], e[i])
                        if nueva != t[i]:
                            t[i], ultimo_cambio[i] = nueva, m
        empate = g[0] == g[1]
        for i in (0, 1):
            tasa = (b[i] * PESO_MIN[m] * MULT[t[i]][t[1 - i]]
                    * (0.75 + 0.25 * e[i]) * (1 + 0.25 * (1 - e[1 - i])))
            if empate:
                tasa *= S.FACTOR_EMPATE
            if rng.random() < 1 - math.exp(-tasa):
                g[i] += 1
                ultimo_gol = m
        for i in (0, 1):
            e[i] = max(S.ENERGIA_MINIMA, e[i] - DESGASTE[t[i]])
    return g


def estado_fisico(minuto, pers, rng):
    """Energía, cambios y ventanas que le quedan a un equipo al llegar a
    'minuto', jugando un partido típico."""
    desgaste = rng.uniform(0.0038, 0.0068)
    energia, cambios, vent = 1.0, S.CAMBIOS_PERMITIDOS, S.VENTANAS
    for m in range(1, minuto + 1):
        if m == 46:
            energia = min(1.0, energia + S.RECUPERO_ENTRETIEMPO)
        if m in MOMENTOS:
            n = S.decidir_cambios(pers, m, energia, cambios, vent, 0, 0)
            if n:
                energia = S.aplicar_cambios(energia, n)
                cambios -= n
                if m != 46:
                    vent -= 1
        if m < minuto:
            energia = max(S.ENERGIA_MINIMA, energia - desgaste)
    return energia, cambios, vent


def entrenar(tablas, conteos, pruebas, rng):
    inicio = time.time()
    tramos = len(S.TRAMOS)
    for tramo in reversed(range(tramos)):
        desde = S.TRAMOS[tramo]
        hasta = S.TRAMOS[tramo + 1] - 1 if tramo + 1 < tramos else 90
        difs = (0,) if tramo == 0 else (-2, -1, 0, 1, 2)
        for pers in PERSONALIDADES:
            tabla, cont = tablas[pers], conteos[pers]
            for dif in difs:
                for lo, hi in RANGOS_FUERZA:
                    for tipo in (0, 1, 2):
                        for _ in range(pruebas):
                            minuto = desde if tramo == 0 else rng.randint(desde, hasta)
                            r = rng.uniform(lo, hi)
                            total = rng.uniform(1.6, 2.8)
                            b_f = total * math.exp(r) / (1 + math.exp(r))
                            b_c = total - b_f
                            gc = max(0, -dif) + rng.choice((0, 0, 1))
                            gf = gc + dif
                            t_r = rng.choice(POR_TIPO[tipo])
                            pers_r = rng.choice(PERSONALIDADES)
                            fis_f = estado_fisico(minuto, pers, rng)
                            fis_c = estado_fisico(minuto, pers_r, rng)
                            estado = S.estado_dt(minuto, gf, gc, b_f, b_c,
                                                 S.ACCIONES[t_r], fis_f[0])
                            q = tabla.setdefault(estado, [0.0] * N_ACC)
                            n = cont.setdefault(estado, [0] * N_ACC)
                            semilla = rng.getrandbits(32)
                            for a in VALIDAS[minuto]:   # misma suerte para cada táctica
                                g = jugar_resto(tablas, (b_f, b_c), (a, t_r), (gf, gc),
                                                (fis_f[0], fis_c[0]), (fis_f[1], fis_c[1]),
                                                (fis_f[2], fis_c[2]), (pers, pers_r),
                                                minuto, random.Random(semilla))
                                n[a] += 1
                                q[a] += (puntos(pers, g[0], g[1]) - q[a]) / n[a]
        print(f"  minuto {desde:>2} aprendido  ({time.time() - inicio:.0f} s)")


def equipo_al_azar(modelo, rng):
    if modelo["equipos"]:
        nombre = rng.choice(list(modelo["equipos"]))
        d = modelo["equipos"][nombre]
        return S.Equipo(nombre, d["ataque"] + rng.gauss(0, 0.1),
                        d["defensa"] + rng.gauss(0, 0.1))
    return S.Equipo("X", rng.gauss(0, 0.25), rng.gauss(0, 0.25))


def evaluar(modelo, cantidad=3000):
    """Partidos completos: DT con IA contra el DT calculador y contra un
    equipo sin DT. Cada cruce se juega de local y de visitante."""
    rng = random.Random(12345)
    for contra, nombre in (("calc", "DT calculador"), (None, "sin DT")):
        pts_ia = pts_rival = 0
        for _ in range(cantidad):
            a, b = equipo_al_azar(modelo, rng), equipo_al_azar(modelo, rng)
            semilla = rng.getrandbits(32)
            for ia_local in (True, False):
                local = S.Equipo(a.nombre, a.ataque, a.defensa)
                visitante = S.Equipo(b.nombre, b.ataque, b.defensa)
                lado_ia = "L" if ia_local else "V"
                if contra is None:
                    (visitante if ia_local else local).dt = None

                def decisor(k, *resto):
                    f = S.decidir_ia if k == lado_ia else S.decidir_calculado
                    return f(k, *resto)

                gl, gv, _ = S.simular_partido(local, visitante, modelo, False,
                                              semilla, decisor=decisor)
                gf, gc = (gl, gv) if ia_local else (gv, gl)
                pts_ia += 3 if gf > gc else 1 if gf == gc else 0
                pts_rival += 3 if gc > gf else 1 if gf == gc else 0
        n = 2 * cantidad
        print(f"  IA vs {nombre:<14} {pts_ia / n:.3f} - {pts_rival / n:.3f} puntos por partido")


def mostrar_aprendido(tablas):
    print("\nLo que aprendieron (equipos parejos, rival equilibrado,")
    print("energía normal para ese minuto):")
    situaciones = [(1, 0, 0, "Arranque"), (60, 0, 0, "60' empatando"),
                   (70, 0, 1, "70' perdiendo por 1"), (70, 1, 0, "70' ganando por 1"),
                   (85, 0, 1, "85' perdiendo por 1"), (85, 1, 0, "85' ganando por 1"),
                   (85, 0, 0, "85' empatando")]
    print(f"{'':<20}" + "".join(f"{p[:5]:>11}" for p in PERSONALIDADES))
    for minuto, gf, gc, texto in situaciones:
        energia = 1.0 if minuto < 30 else 0.85 if minuto < 46 else 0.72
        estado = S.estado_dt(minuto, gf, gc, 1.0, 1.0, "equilibrada", energia)
        fila = f"{texto:<20}"
        for p in PERSONALIDADES:
            q = tablas[p].get(estado)
            mejor = max(VALIDAS[minuto], key=q.__getitem__) if q else None
            fila += f"{(S.ACCIONES[mejor] if q else '?')[:10]:>11}"
        print(fila)


def main():
    pruebas = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    tablas = {p: {} for p in PERSONALIDADES}
    conteos = {p: {} for p in PERSONALIDADES}
    previas = 0
    if os.path.exists(ARCHIVO):
        with open(ARCHIVO, encoding="utf-8") as f:
            guardado = json.load(f)
        if guardado.get("version") == S.VERSION_CEREBRO:
            tablas, conteos = guardado["tablas"], guardado["conteos"]
            previas = guardado.get("pruebas", 0)
            print(f"Sigo sumando experiencia ({previas} pruebas por situación).")
        else:
            print("dt_ia.json es de una versión anterior: entreno de cero.")

    print(f"Entrenando con {pruebas} pruebas por situación...")
    entrenar(tablas, conteos, pruebas, random.Random(previas + 7))
    situaciones = sum(len(t) for t in tablas.values())
    partidos = sum(sum(n) for c in conteos.values() for n in c.values())

    with open(ARCHIVO, "w", encoding="utf-8") as f:
        json.dump({"version": S.VERSION_CEREBRO, "pruebas": previas + pruebas,
                   "partidos": partidos,
                   "tablas": {p: {e: [round(v, 4) for v in q] for e, q in t.items()}
                              for p, t in tablas.items()},
                   "conteos": conteos}, f)
    print(f"Guardado en {ARCHIVO}: {situaciones} situaciones, "
          f"{partidos:,} partidos jugados.".replace(",", "."))

    S.CEREBRO = {"tablas": tablas, "partidos": partidos}
    mostrar_aprendido(tablas)
    print("\nPrueba final con partidos completos (DT equilibrado):")
    evaluar(S.cargar_modelo("modelo_poisson.json"))


if __name__ == "__main__":
    main()
