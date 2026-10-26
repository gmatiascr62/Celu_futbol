#!/usr/bin/env python3
"""
Entrena un modelo de Poisson (con corrección Dixon-Coles) usando resultados
reales y muestra el ataque y la defensa de cada equipo.

Uso:
    python entrenar_modelo.py                 # descarga la liga argentina
    python entrenar_modelo.py mi_archivo.csv  # usa un CSV local

Librerías: pip install pandas numpy scipy

El resultado se guarda en modelo_poisson.json, listo para usar en el simulador.
"""
import json
import sys

import numpy as np
import pandas as pd
from scipy.optimize import minimize
from scipy.stats import poisson

URL_ARGENTINA = "https://www.football-data.co.uk/new/ARG.csv"
TEMPORADAS = 3        # cuántas temporadas recientes usar
VIDA_MEDIA_DIAS = 365  # un partido de hace 1 año pesa la mitad que uno de hoy
MIN_PARTIDOS = 10      # equipos con menos partidos se descartan


# ---------------------------------------------------------------- datos
def cargar_datos(origen):
    df = pd.read_csv(origen, encoding="latin-1")
    # football-data tiene dos formatos de columnas; se normalizan
    if "Home" in df.columns:
        df = df.rename(columns={"Home": "local", "Away": "visitante",
                                "HG": "gl", "AG": "gv"})
    else:
        df = df.rename(columns={"HomeTeam": "local", "AwayTeam": "visitante",
                                "FTHG": "gl", "FTAG": "gv"})
    df["fecha"] = pd.to_datetime(df["Date"], dayfirst=True, errors="coerce")
    df = df.dropna(subset=["fecha", "local", "visitante", "gl", "gv"])
    df["gl"] = df["gl"].astype(int)
    df["gv"] = df["gv"].astype(int)

    if "Season" in df.columns:
        ultimas = sorted(df["Season"].astype(str).unique())[-TEMPORADAS:]
        df = df[df["Season"].astype(str).isin(ultimas)]

    # se descartan equipos con pocos partidos (ascendidos recientes, etc.)
    for _ in range(3):
        conteo = pd.concat([df["local"], df["visitante"]]).value_counts()
        validos = conteo[conteo >= MIN_PARTIDOS].index
        df = df[df["local"].isin(validos) & df["visitante"].isin(validos)]

    dias = (df["fecha"].max() - df["fecha"]).dt.days.to_numpy()
    df["peso"] = 0.5 ** (dias / VIDA_MEDIA_DIAS)
    return df.reset_index(drop=True)


# ---------------------------------------------------------------- modelo
def tau(gl, gv, mu_l, mu_v, rho):
    """Corrección Dixon-Coles para 0-0, 1-0, 0-1 y 1-1."""
    t = np.ones_like(mu_l)
    m = (gl == 0) & (gv == 0); t[m] = 1 - mu_l[m] * mu_v[m] * rho
    m = (gl == 0) & (gv == 1); t[m] = 1 + mu_l[m] * rho
    m = (gl == 1) & (gv == 0); t[m] = 1 + mu_v[m] * rho
    m = (gl == 1) & (gv == 1); t[m] = 1 - rho
    return np.clip(t, 1e-10, None)


def entrenar(df):
    equipos = sorted(set(df["local"]) | set(df["visitante"]))
    idx = {e: i for i, e in enumerate(equipos)}
    n = len(equipos)
    il = df["local"].map(idx).to_numpy()
    iv = df["visitante"].map(idx).to_numpy()
    gl, gv, w = df["gl"].to_numpy(), df["gv"].to_numpy(), df["peso"].to_numpy()

    def desarmar(p):
        ataque = p[:n] - p[:n].mean()   # se fija el promedio en 0
        defensa = p[n:2 * n] - p[n:2 * n].mean()
        return ataque, defensa, p[2 * n], p[2 * n + 1], p[2 * n + 2]

    def neg_log_vero(p):
        ataque, defensa, base, localia, rho = desarmar(p)
        mu_l = np.exp(base + localia + ataque[il] + defensa[iv])
        mu_v = np.exp(base + ataque[iv] + defensa[il])
        ll = (poisson.logpmf(gl, mu_l) + poisson.logpmf(gv, mu_v)
              + np.log(tau(gl, gv, mu_l, mu_v, rho)))
        return -(w * ll).sum()

    p0 = np.concatenate([np.zeros(2 * n), [0.1, 0.2, -0.05]])
    limites = [(None, None)] * (2 * n + 2) + [(-0.3, 0.3)]
    res = minimize(neg_log_vero, p0, method="L-BFGS-B", bounds=limites)
    ataque, defensa, base, localia, rho = desarmar(res.x)
    return {
        "base": float(base), "localia": float(localia), "rho": float(rho),
        "equipos": {e: {"ataque": float(ataque[i]), "defensa": float(defensa[i])}
                    for e, i in idx.items()},
    }


# ---------------------------------------------------------------- control
def goles_esperados(modelo, local, visitante):
    a, b = modelo["equipos"][local], modelo["equipos"][visitante]
    mu_l = np.exp(modelo["base"] + modelo["localia"] + a["ataque"] + b["defensa"])
    mu_v = np.exp(modelo["base"] + b["ataque"] + a["defensa"])
    return mu_l, mu_v


def comparar_con_realidad(modelo, df, semilla=0):
    """Simula los mismos partidos con el modelo y compara con lo real."""
    rng = np.random.default_rng(semilla)
    sim_gl, sim_gv = [], []
    for _ in range(20):
        for l, v in zip(df["local"], df["visitante"]):
            mu_l, mu_v = goles_esperados(modelo, l, v)
            sim_gl.append(rng.poisson(mu_l)); sim_gv.append(rng.poisson(mu_v))
    sim_gl, sim_gv = np.array(sim_gl), np.array(sim_gv)

    def resumen(gl, gv):
        return ((gl + gv).mean(), (gl > gv).mean(), (gl == gv).mean(), (gl < gv).mean())

    print("\n                 Goles/partido  Gana local  Empate  Gana visitante")
    for nombre, (g, l, e, v) in (("Real", resumen(df["gl"].to_numpy(), df["gv"].to_numpy())),
                                 ("Modelo", resumen(sim_gl, sim_gv))):
        print(f"{nombre:<16} {g:>10.2f} {l:>11.1%} {e:>7.1%} {v:>15.1%}")


def mostrar_tabla(modelo):
    filas = [(e, np.exp(d["ataque"]), np.exp(d["defensa"]))
             for e, d in modelo["equipos"].items()]
    filas.sort(key=lambda f: f[1] / f[2], reverse=True)
    print(f"\n{'Equipo':<24}{'Ataque':>8}{'Defensa':>9}")
    print("(1.00 = promedio de la liga. Ataque alto = mete más; "
          "defensa baja = recibe menos)")
    for e, at, de in filas:
        print(f"{e:<24}{at:>8.2f}{de:>9.2f}")
    print(f"\nGoles esperados base: {np.exp(modelo['base']):.2f}  |  "
          f"Ventaja de localía: x{np.exp(modelo['localia']):.2f}  |  "
          f"rho Dixon-Coles: {modelo['rho']:.3f}")


def main():
    origen = sys.argv[1] if len(sys.argv) > 1 else URL_ARGENTINA
    print(f"Cargando datos de {origen} ...")
    df = cargar_datos(origen)
    print(f"{len(df)} partidos, {df['fecha'].min():%d/%m/%Y} a {df['fecha'].max():%d/%m/%Y}")
    modelo = entrenar(df)
    mostrar_tabla(modelo)
    comparar_con_realidad(modelo, df)
    with open("modelo_poisson.json", "w", encoding="utf-8") as f:
        json.dump(modelo, f, ensure_ascii=False, indent=2)
    print("\nModelo guardado en modelo_poisson.json")


if __name__ == "__main__":
    main()
