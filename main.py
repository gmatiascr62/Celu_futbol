"""
Celu Fútbol: la app para Android (Kivy).

Usa la misma lógica del juego (simulador_futbol.py, jugadores.py,
mercado.py, tecnicos.py, club.py) con pantallas propias: elegir club y DT,
la pantalla del club con pestañas, el partido con relato, las reuniones
con el DT y el fin de temporada. Primera etapa: el torneo largo.

En la PC también anda: python main.py (con Kivy instalado).
"""
import os
import random
import re
import sys
import threading

from kivy.app import App
from kivy.clock import Clock
from kivy.core.text import DEFAULT_FONT, LabelBase
from kivy.core.window import Window
from kivy.graphics import Color, Rectangle
from kivy.metrics import dp, sp
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.modalview import ModalView
from kivy.uix.progressbar import ProgressBar
from kivy.uix.screenmanager import NoTransition, Screen, ScreenManager
from kivy.uix.scrollview import ScrollView
from kivy.utils import escape_markup

AQUI = os.path.dirname(os.path.abspath(__file__))
LabelBase.register(DEFAULT_FONT, os.path.join(AQUI, "DejaVuSans.ttf"),
                   fn_bold=os.path.join(AQUI, "DejaVuSans-Bold.ttf"))
os.chdir(AQUI)                         # el juego lee los .json de su carpeta
sys.path.insert(0, AQUI)

import club as C                       # noqa: E402
import jugadores as J                  # noqa: E402
import mercado as M                    # noqa: E402
import simulador_futbol as S           # noqa: E402
import tecnicos as T                   # noqa: E402

# ---------------------------------------------------------------- estilo
FONDO = (0.06, 0.09, 0.07, 1)
PANEL = (0.10, 0.15, 0.12, 1)
VERDE = (0.13, 0.55, 0.30, 1)
VERDE_OSCURO = (0.10, 0.30, 0.18, 1)
GRIS = (0.22, 0.26, 0.24, 1)
ROJO = (0.62, 0.18, 0.18, 1)
TEXTO = (0.92, 0.96, 0.93, 1)
APAGADO = (0.62, 0.70, 0.65, 1)

# La letra no trae emojis de colores: se cambian por símbolos que sí tiene.
EMOJIS = {
    "⚽": ("●", "6fdc6f"), "🟨": ("▮", "ffd92e"), "🧤": ("○", "8fc7ff"),
    "🔄": ("⇆", "b0b0b0"), "🧠": ("◆", "c79bff"), "🏆": ("♛", "ffd92e"),
    "🎉": ("★", "ffd92e"), "✅": ("✔", "6fdc6f"), "🌱": ("♣", "6fdc6f"),
    "🏋": ("▲", "b0b0b0"), "🏗": ("▣", "b0b0b0"), "💰": ("$", "6fdc6f"),
    "📋": ("≡", None), "📌": ("•", "ff8a5c"), "📝": ("✎", None), "📣": ("»", "ff8a5c"),
    "📰": ("■", "8fc7ff"), "🔁": ("⇄", "8fc7ff"), "🗣": ("»", "ff8a5c"),
    "😍": ("♥", "ff6f91"), "🙂": ("☺", "6fdc6f"), "😐": ("○", "b0b0b0"),
    "😡": ("☹", "ff5c5c"), "😢": ("☹", "8fc7ff"), "🚑": ("✚", "ff5c5c"),
    "⚠": ("⚠", "ffd92e"), "⬆": ("⬆", "6fdc6f"), "⬇": ("⬇", "ff5c5c"),
}


def mk(t):
    """Texto del juego a texto de Kivy: escapa el markup y cambia emojis."""
    salida = []
    for ch in str(t):
        if ch in EMOJIS:
            simbolo, color = EMOJIS[ch]
            salida.append(f"[color={color}]{simbolo}[/color]" if color else simbolo)
        elif ch != "️":
            salida.append(escape_markup(ch))
    return "".join(salida)


def fondo(widget, color):
    with widget.canvas.before:
        Color(*color)
        rect = Rectangle(pos=widget.pos, size=widget.size)
    widget.bind(pos=lambda w, v: setattr(rect, "pos", v),
                size=lambda w, v: setattr(rect, "size", v))
    return widget


def texto(t, tam=15, color=TEXTO, negrita=False, centrado=False, marcado=True):
    """Una etiqueta que crece hacia abajo según su texto. marcado=False: t ya
    viene con markup de Kivy."""
    lbl = Label(text=mk(t) if marcado else t, markup=True, font_size=sp(tam), color=color,
                bold=negrita, halign="center" if centrado else "left", valign="top",
                size_hint_y=None)
    lbl.bind(width=lambda w, v: setattr(w, "text_size", (v, None)),
             texture_size=lambda w, s: setattr(w, "height", s[1] + dp(4)))
    return lbl


def boton(t, accion=None, color=VERDE, alto=48, tam=16):
    b = Button(text=t, markup=True, size_hint_y=None, height=dp(alto), font_size=sp(tam),
               background_normal="", background_color=color, color=TEXTO, halign="center")
    b.bind(width=lambda w, v: setattr(w, "text_size", (v - dp(8), None)))
    if accion:
        b.bind(on_release=lambda *a: accion())
    return b


def columna(espacio=6, relleno=10):
    caja = BoxLayout(orientation="vertical", size_hint_y=None, spacing=dp(espacio),
                     padding=dp(relleno))
    caja.bind(minimum_height=caja.setter("height"))
    return caja


def con_scroll(contenido):
    sv = ScrollView(do_scroll_x=False, bar_width=dp(4))
    sv.add_widget(contenido)
    return sv


def fila(*celdas, alto=30, color=None, anchos=None, tam=14):
    """Una fila de tabla. anchos: proporciones de cada celda."""
    f = BoxLayout(size_hint_y=None, height=dp(alto), spacing=dp(4), padding=(dp(4), 0))
    if color:
        fondo(f, color)
    for i, c in enumerate(celdas):
        lbl = Label(text=mk(c), markup=True, font_size=sp(tam), color=TEXTO,
                    halign="left" if i == 1 or len(celdas) == 1 else "center",
                    valign="middle", shorten=True, shorten_from="right")
        lbl.size_hint_x = anchos[i] if anchos else 1
        lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
        f.add_widget(lbl)
    return f


def barra(nombre, valor):
    caja = BoxLayout(size_hint_y=None, height=dp(26), spacing=dp(6))
    lbl = Label(text=nombre, font_size=sp(14), color=TEXTO, size_hint_x=0.35,
                halign="left", valign="middle")
    lbl.bind(size=lambda w, v: setattr(w, "text_size", v))
    caja.add_widget(lbl)
    caja.add_widget(ProgressBar(max=100, value=valor, size_hint_x=0.5))
    caja.add_widget(Label(text=f"{valor:.0f}", font_size=sp(14), color=TEXTO,
                          size_hint_x=0.15))
    return caja


def ventana(titulo, cuerpo_widgets, botones, al_cerrar=None):
    """Una ventana encima de la pantalla, con texto y botones.
    botones: [(texto, acción o None, color)]."""
    mv = ModalView(size_hint=(0.94, None), auto_dismiss=False,
                   background_color=(0, 0, 0, 0.6))
    caja = fondo(BoxLayout(orientation="vertical", padding=dp(12), spacing=dp(8)), PANEL)
    caja.add_widget(texto(titulo, 18, negrita=True))
    cuerpo = columna(6, 0)
    for w in cuerpo_widgets:
        cuerpo.add_widget(w)
    sv = con_scroll(cuerpo)
    caja.add_widget(sv)
    pie = columna(6, 0)
    for etiqueta, accion, color in botones:
        def hacer(accion=accion):
            mv.dismiss()
            if accion:
                accion()
            if al_cerrar:
                al_cerrar()
        pie.add_widget(boton(mk(etiqueta), hacer, color))
    caja.add_widget(pie)
    mv.add_widget(caja)

    def ajustar(*a):
        alto_cuerpo = min(cuerpo.height, Window.height * 0.5)
        sv.size_hint_y, sv.height = None, alto_cuerpo
        mv.height = min(alto_cuerpo + pie.height + dp(100), Window.height * 0.95)
    cuerpo.bind(height=ajustar)
    pie.bind(height=ajustar)
    Clock.schedule_once(ajustar, 0)
    mv.open()
    return mv


# ---------------------------------------------------------------- pantallas
class Inicio(Screen):
    def on_pre_enter(self):
        app = App.get_running_app()
        self.clear_widgets()
        raiz = fondo(BoxLayout(orientation="vertical", padding=dp(20), spacing=dp(12)), FONDO)
        raiz.add_widget(texto("[b]CELU FÚTBOL[/b]", 30, centrado=True, marcado=False))
        raiz.add_widget(texto("Liga Profesional · Primera Nacional · Primera B", 14,
                              APAGADO, centrado=True))
        raiz.add_widget(BoxLayout())
        p = S.cargar_partida()
        if p and p.get("mio"):
            raiz.add_widget(boton(mk(f"Seguir con {p['mio']}\nTemporada {p['temporada']}, "
                                     f"fecha {p['numero']} de {len(p['fixture'])}"),
                                  lambda: app.abrir_partida(p), alto=72))
        raiz.add_widget(boton("Nueva partida", self.nueva, GRIS if p else VERDE, alto=60))
        raiz.add_widget(BoxLayout())
        self.add_widget(raiz)

    def nueva(self):
        app = App.get_running_app()
        if S.cargar_partida():
            ventana("¿Empezar de nuevo?", [texto("La partida guardada se borra.")],
                    [("Sí, empezar de nuevo", lambda: app.ir("club"), ROJO),
                     ("Cancelar", None, GRIS)])
        else:
            app.ir("club")


class ElegirClub(Screen):
    division = 0

    def on_pre_enter(self):
        self.armar()

    def armar(self):
        app = App.get_running_app()
        self.clear_widgets()
        raiz = fondo(BoxLayout(orientation="vertical", padding=dp(8), spacing=dp(6)), FONDO)
        raiz.add_widget(texto("¿Qué club querés dirigir?", 20, negrita=True))
        pestanas = BoxLayout(size_hint_y=None, height=dp(44), spacing=dp(4))
        for d, nombre in enumerate(app.modelo["divisiones"]):
            pestanas.add_widget(boton(nombre, lambda d=d: self.cambiar(d),
                                      VERDE if d == self.division else GRIS, alto=44, tam=13))
        raiz.add_widget(pestanas)
        lista = columna(4, 4)
        niveles = {c: sum(sorted((J.nivel(j) for j in S.PLANTELES[c]), reverse=True)[:11]) / 11
                   for c, d in app.modelo["division"].items() if d == self.division}
        for c in sorted(niveles, key=lambda c: -niveles[c]):
            lista.add_widget(boton(f"{escape_markup(c)}   [size=12sp][color=bbbbbb]nivel "
                                   f"{niveles[c]:.0f}[/color][/size]",
                                   lambda c=c: self.elegido(c), PANEL, alto=46))
        raiz.add_widget(con_scroll(lista))
        raiz.add_widget(boton("Volver", lambda: app.ir("inicio"), GRIS, alto=44))
        self.add_widget(raiz)

    def cambiar(self, d):
        self.division = d
        self.armar()

    def elegido(self, club):
        app = App.get_running_app()
        opciones = [texto(f"[b]{n.capitalize()}[/b]: {escape_markup(S.PERSONALIDADES[n]['desc'])}",
                          15, marcado=False) for n in T.PERSONALIDADES]
        ventana(f"El DT de {club}", opciones,
                [(n.capitalize(), lambda n=n: app.nueva_partida(club, n), VERDE)
                 for n in T.PERSONALIDADES] + [("Cancelar", None, GRIS)])


class Partido(Screen):
    """El partido de tu club, con el relato apareciendo de a poco."""
    reloj = None

    def mostrar(self, partido, al_terminar):
        self.partido, self.al_terminar = partido, al_terminar
        self.eventos = list(partido.get("eventos", []))
        self.i = 0
        self.goles = [0, 0]
        self.terminado = False
        self.clear_widgets()
        raiz = fondo(BoxLayout(orientation="vertical", padding=dp(8), spacing=dp(6)), FONDO)
        marcador = fondo(BoxLayout(orientation="vertical", size_hint_y=None, height=dp(100),
                                   padding=dp(6)), VERDE_OSCURO)
        self.lbl_marcador = texto("", 22, negrita=True, centrado=True)
        self.lbl_minuto = texto("0'", 14, APAGADO, centrado=True)
        marcador.add_widget(self.lbl_marcador)
        marcador.add_widget(self.lbl_minuto)
        raiz.add_widget(marcador)
        self.relato = columna(2, 6)
        for k, nombre in (("L", partido["local"]), ("V", partido["visitante"])):
            f, xi, tactica = partido["alineacion"][k]
            self.relato.add_widget(texto(f"[b]{escape_markup(nombre)}[/b] · {f} · {tactica}",
                                         13, APAGADO, marcado=False))
            self.relato.add_widget(texto(", ".join(n for n, _ in xi), 12, APAGADO))
        self.sv = con_scroll(self.relato)
        raiz.add_widget(self.sv)
        self.btn = boton("Saltar al final", self.boton_abajo, GRIS)
        raiz.add_widget(self.btn)
        self.add_widget(raiz)
        self.actualizar_marcador()
        self.reloj = Clock.schedule_interval(self.siguiente, 0.45)

    def actualizar_marcador(self, minuto=None):
        p = self.partido
        self.lbl_marcador.text = mk(f"{p['local']}  {self.goles[0]} - {self.goles[1]}  "
                                    f"{p['visitante']}")
        if minuto:
            self.lbl_minuto.text = minuto

    def siguiente(self, *a):
        if self.i >= len(self.eventos):
            self.terminar()
            return False
        ev = self.eventos[self.i]
        self.i += 1
        m = re.search(r"\((\d+)-(\d+)\)", ev)
        if "GOL" in ev and m:
            self.goles = [int(m.group(1)), int(m.group(2))]
        minuto = re.match(r"\S+ (\d+(?:\+\d+)?)'", ev)
        self.actualizar_marcador(f"{minuto.group(1)}'" if minuto else None)
        grande = "GOL" in ev or "ENTRETIEMPO" in ev
        self.relato.add_widget(texto(ev, 16 if grande else 14, negrita=grande))
        Clock.schedule_once(lambda dt: setattr(self.sv, "scroll_y", 0), 0)

    def boton_abajo(self):
        if self.terminado:
            self.al_terminar()
            return
        while self.i < len(self.eventos):
            self.siguiente()
        self.terminar()

    def terminar(self):
        if self.reloj:
            self.reloj.cancel()
            self.reloj = None
        if self.terminado:
            return
        self.terminado = True
        p = self.partido
        self.goles = [p["gl"], p["gv"]]
        self.actualizar_marcador("Final")
        L, V = p["L"], p["V"]
        filas = (("Posesión", f"{p['posesion']:.0f}%", f"{100 - p['posesion']:.0f}%"),
                 ("Tiros", p["gl"] + L["atajados"] + L["desviados"],
                  p["gv"] + V["atajados"] + V["desviados"]),
                 ("Al arco", p["gl"] + L["atajados"], p["gv"] + V["atajados"]),
                 ("Amarillas", L["amarillas"], V["amarillas"]))
        self.relato.add_widget(texto(" ", 8))
        for nombre, a, b in filas:
            self.relato.add_widget(fila(nombre, str(a), str(b), anchos=(0.5, 0.25, 0.25)))
        Clock.schedule_once(lambda dt: setattr(self.sv, "scroll_y", 0), 0)
        self.btn.text = "Seguir"
        self.btn.background_color = VERDE


class Club(Screen):
    """La pantalla del club que seguís, con pestañas abajo."""
    pestana = "inicio"
    division_tabla = None

    def on_pre_enter(self):
        self.armar()

    def armar(self):
        app = App.get_running_app()
        p = app.p
        self.clear_widgets()
        raiz = fondo(BoxLayout(orientation="vertical"), FONDO)
        mi = app.mi()
        d = S.division_de(p, mi.nombre)
        pos, f = S.posicion(S.tabla_division(p, d), mi.nombre)
        cab = fondo(BoxLayout(orientation="vertical", size_hint_y=None, height=dp(66),
                              padding=(dp(10), dp(6))), VERDE_OSCURO)
        cab.add_widget(texto(f"[b]{escape_markup(mi.nombre)}[/b] · {pos}° en la "
                             f"{escape_markup(p['divisiones'][d])}", 17, marcado=False))
        cab.add_widget(texto(f"{f['Pts']} pts · Caja {M.plata(mi.caja)} · Hinchada "
                             f"{S.cara(mi.hinchada)} {mi.hinchada:.0f}", 13, APAGADO))
        raiz.add_widget(cab)
        self.cuerpo = BoxLayout()
        raiz.add_widget(self.cuerpo)
        tabs = BoxLayout(size_hint_y=None, height=dp(52), spacing=dp(2))
        for clave, nombre in (("inicio", "Fecha"), ("tabla", "Tabla"), ("plantel", "Plantel"),
                              ("dt", "DT"), ("mas", "Más")):
            tabs.add_widget(boton(nombre, lambda c=clave: self.ir(c),
                                  VERDE if clave == self.pestana else GRIS, alto=52, tam=14))
        raiz.add_widget(tabs)
        self.add_widget(raiz)
        getattr(self, f"pestana_{self.pestana}")()

    def ir(self, clave):
        self.pestana = clave
        self.armar()

    # --- Fecha
    def pestana_inicio(self):
        app = App.get_running_app()
        p = app.p
        caja = columna(8, 10)
        total = len(p["fixture"])
        caja.add_widget(texto(f"Fecha {min(p['numero'] + 1, total)} de {total} · Temporada "
                              f"{p['temporada']}", 18, negrita=True))
        rival = app.proximo_rival()
        if rival:
            caja.add_widget(texto(rival, 16))
        if S.ventana_actual(p):
            caja.add_widget(texto("🔁 Mercado de pases abierto (cierra al jugar la fecha)", 13,
                                  APAGADO))
        if app.ocupado:
            caja.add_widget(texto(app.ocupado, 16, (1, 0.85, 0.3, 1)))
        elif p["numero"] < total:
            caja.add_widget(boton(mk("⚽ Jugar fecha"), app.jugar_fecha, alto=56, tam=18))
            dos = BoxLayout(size_hint_y=None, height=dp(48), spacing=dp(6))
            dos.add_widget(boton("Jugar 5 fechas", lambda: app.jugar_varias(5), GRIS))
            dos.add_widget(boton("Hasta el final", lambda: app.jugar_varias(total), GRIS))
            caja.add_widget(dos)
        for linea in app.ultimo_informe:
            caja.add_widget(texto(linea, 14))
        self.cuerpo.add_widget(con_scroll(caja))

    # --- Tabla
    def pestana_tabla(self):
        app = App.get_running_app()
        p = app.p
        if self.division_tabla is None:
            self.division_tabla = S.division_de(p, p["mio"])
        caja = columna(2, 6)
        selector = BoxLayout(size_hint_y=None, height=dp(40), spacing=dp(4))
        for d, nombre in enumerate(p["divisiones"]):
            selector.add_widget(boton(nombre, lambda d=d: self.ver_division(d),
                                      VERDE if d == self.division_tabla else GRIS, alto=40,
                                      tam=12))
        caja.add_widget(selector)
        anchos = (0.08, 0.5, 0.1, 0.1, 0.1, 0.12)
        caja.add_widget(fila("#", "Equipo", "PJ", "DG", "G", "Pts", anchos=anchos, tam=12,
                             color=GRIS))
        orden = S.ordenar_tabla(S.tabla_division(p, self.division_tabla))
        n = len(orden)
        for i, (nombre, f) in enumerate(orden, 1):
            color = VERDE if nombre == p["mio"] else None
            if not color and self.division_tabla > 0 and i <= S.CAMBIOS_DE_CATEGORIA:
                color = (0.10, 0.25, 0.15, 1)
            if not color and self.division_tabla < len(p["divisiones"]) - 1 \
                    and i > n - S.CAMBIOS_DE_CATEGORIA:
                color = (0.30, 0.12, 0.12, 1)
            caja.add_widget(fila(str(i), nombre, str(f["PJ"]), f"{f['GF'] - f['GC']:+d}",
                                 str(f["G"]), str(f["Pts"]), anchos=anchos, color=color))
        caja.add_widget(texto("Verde: suben · Rojo: bajan", 12, APAGADO))
        self.cuerpo.add_widget(con_scroll(caja))

    def ver_division(self, d):
        self.division_tabla = d
        self.armar()

    # --- Plantel
    def pestana_plantel(self):
        app = App.get_running_app()
        mi = app.mi()
        caja = columna(2, 6)
        anchos = (0.12, 0.46, 0.1, 0.12, 0.2)
        caja.add_widget(fila("Pos", "Jugador", "Ed", "Nv", "Físico", anchos=anchos, tam=12,
                             color=GRIS))
        for j in sorted(mi.plantel, key=lambda j: (J.POSICIONES.index(j.pos), -J.nivel(j))):
            estado = "🚑" if j.lesion else f"{j.fisico:.0%}"
            b = Button(background_normal="", background_color=PANEL, size_hint_y=None,
                       height=dp(32))
            f = fila(j.pos, j.corto, str(j.edad), str(J.nivel(j)), estado, anchos=anchos)
            b.add_widget(f)
            b.bind(pos=lambda w, v, f=f: setattr(f, "pos", v),
                   size=lambda w, v, f=f: setattr(f, "size", v))
            b.bind(on_release=lambda *a, j=j: self.ficha(j))
            caja.add_widget(b)
        caja.add_widget(texto(f"{len(mi.plantel)} jugadores. Tocá uno para ver su ficha.",
                              12, APAGADO))
        self.cuerpo.add_widget(con_scroll(caja))

    def ficha(self, j):
        df = j.atajada if j.pos == "ARQ" else j.defensa
        lineas = [J.NOMBRE_POS[j.pos].capitalize()
                  + (f" (también {J.NOMBRE_POS[j.pos2]})" if j.pos2 else ""),
                  f"{j.edad} años · nivel {J.nivel(j)} · potencial {j.potencial}",
                  f"Ataque {j.ataque:.0f} · Creación {j.creacion:.0f} · "
                  f"{'Atajada' if j.pos == 'ARQ' else 'Defensa'} {df:.0f}",
                  f"Resistencia {j.resistencia:.0f} · Físico {j.fisico:.0%}",
                  f"Contrato: {j.contrato} temporada{'s' if j.contrato != 1 else ''} · "
                  f"{M.plata(M.sueldo(j))}/año",
                  f"Valor: {M.plata(M.valor(j))} · Partidos: {j.partidos}"]
        if j.lesion:
            lineas.append(f"🚑 Lesionado: {j.lesion} fecha{'s' if j.lesion > 1 else ''}")
        ventana(j.completo, [texto(l, 15) for l in lineas], [("Cerrar", None, GRIS)])

    # --- DT
    def pestana_dt(self):
        app = App.get_running_app()
        p, mi = app.p, app.mi()
        t = S.mi_dt(p)
        caja = columna(6, 10)
        if t is None:
            caja.add_widget(texto("No hay DT.", 16))
            self.cuerpo.add_widget(con_scroll(caja))
            return
        caja.add_widget(texto(f"[b]{escape_markup(t.completo)}[/b], {t.edad} años · "
                              f"{t.personalidad}", 17, marcado=False))
        caja.add_widget(texto(f"Prestigio {t.prestigio} · {M.plata(t.sueldo)}/año · "
                              f"contrato {t.contrato} temporada{'s' if t.contrato != 1 else ''}",
                              14, APAGADO))
        caja.add_widget(barra("Satisfacción", t.satisfaccion))
        caja.add_widget(barra("Confianza", t.confianza))
        caja.add_widget(barra("Presión", t.presion))
        juega = mi.formacion_forzada or mi.formacion
        caja.add_widget(texto(f"Juega con {juega}"
                              + (" (se lo pediste vos)" if mi.formacion_forzada else ""), 15))
        for pr in t.promesas:
            caja.add_widget(texto(f"📌 Le prometiste: {T.que_prometio(pr)}", 14))
        caja.add_widget(texto("[b]Historia[/b]", 15, marcado=False))
        for linea in T.curriculum(t):
            caja.add_widget(texto(linea, 13, APAGADO))
        caja.add_widget(boton("Pedirle otra formación", app.pedir_formacion, GRIS))
        costo = t.sueldo * max(t.contrato, 0.5)
        caja.add_widget(boton(mk(f"Echarlo ({M.plata(costo)})"), app.echar_dt, ROJO))
        self.cuerpo.add_widget(con_scroll(caja))

    # --- Más
    def pestana_mas(self):
        app = App.get_running_app()
        p = app.p
        caja = columna(6, 10)
        caja.add_widget(texto("[b]Goleadores de tu división[/b]", 16, marcado=False))
        gol = S.goleadores_division(p, S.division_de(p, p["mio"]))
        for (j, club), n in gol.most_common(10):
            caja.add_widget(fila(str(n), f"{j} ({club})", anchos=(0.12, 0.88)))
        if not gol:
            caja.add_widget(texto("Todavía no hay goles.", 14, APAGADO))
        caja.add_widget(texto("[b]Historial[/b]", 16, marcado=False))
        for r in p["historial"]:
            for nombre, campeon, pts in r.get("campeones", [["", r["campeon"], r["puntos"]]]):
                caja.add_widget(texto(f"T{r['temporada']} 🏆 {campeon} ({pts}) {nombre}", 13))
            if "puesto" in r:
                caja.add_widget(texto(f"   {p['mio']}: {r['puesto']}°", 13, APAGADO))
        if not p["historial"]:
            caja.add_widget(texto("Todavía no terminó ninguna temporada.", 14, APAGADO))
        caja.add_widget(texto("[b]Próximamente en la app[/b]", 16, marcado=False))
        caja.add_widget(texto("Mercado de pases, entrenamiento, instalaciones y cuerpo "
                              "técnico, reserva de juveniles, partido amistoso y "
                              "cuadrangular. Mientras tanto el DT decide el entrenamiento.",
                              13, APAGADO))
        caja.add_widget(boton("Volver al inicio", lambda: app.ir("inicio"), GRIS))
        self.cuerpo.add_widget(con_scroll(caja))


class FinTemporada(Screen):
    def on_pre_enter(self):
        app = App.get_running_app()
        p = app.p
        self.clear_widgets()
        raiz = fondo(BoxLayout(orientation="vertical", padding=dp(10), spacing=dp(8)), FONDO)
        caja = columna(6, 4)
        caja.add_widget(texto(f"[b]FIN DE LA TEMPORADA {p['temporada']}[/b]", 20,
                              centrado=True, marcado=False))
        for d, nombre in enumerate(p["divisiones"]):
            campeon, f = S.ordenar_tabla(S.tabla_division(p, d))[0]
            caja.add_widget(texto(f"🏆 {nombre}: {campeon} ({f['Pts']} pts)", 16))
            gol = S.goleadores_division(p, d)
            if gol:
                (j, club), n = gol.most_common(1)[0]
                caja.add_widget(texto(f"     Goleador: {j} ({club}), {n}", 13, APAGADO))
        for club, de, a in S.cambios_de_categoria(p):
            caja.add_widget(texto(("⬆ Asciende: " if a < de else "⬇ Desciende: ") + club,
                                  15, negrita=club == p["mio"]))
        d = S.division_de(p, p["mio"])
        pos, f = S.posicion(S.tabla_division(p, d), p["mio"])
        caja.add_widget(texto(f"{p['mio']}: {pos}° con {f['Pts']} puntos "
                              f"({f['G']}G {f['E']}E {f['P']}P)", 17, negrita=True))
        raiz.add_widget(con_scroll(caja))
        raiz.add_widget(boton("Jugar la temporada siguiente", app.siguiente_temporada, alto=56))
        self.add_widget(raiz)


# ---------------------------------------------------------------- la app
class CeluFutbol(App):
    title = "Celu Fútbol"

    def build(self):
        Window.clearcolor = FONDO
        os.environ["FUTBOL_PARTIDAS"] = self.user_data_dir   # la partida, dentro de la app
        self.modelo = S.cargar_modelo("modelo_poisson.json")
        S.cargar_ascenso(self.modelo)
        S.PLANTELES = J.cargar_planteles(self.modelo)
        S.cargar_cerebro()
        self.p = None
        self.ocupado = None
        self.ultimo_informe = []
        self.sm = ScreenManager(transition=NoTransition())
        for nombre, clase in (("inicio", Inicio), ("club", ElegirClub), ("partido", Partido),
                              ("juego", Club), ("fin", FinTemporada)):
            self.sm.add_widget(clase(name=nombre))
        return self.sm

    def ir(self, pantalla):
        self.sm.current = pantalla

    def mi(self):
        return next(e for e in self.p["equipos"] if e.nombre == self.p["mio"])

    def pantalla_club(self):
        if self.sm.current == "juego":
            self.sm.get_screen("juego").armar()

    # --- arranque
    def nueva_partida(self, club, personalidad):
        self.p = S.crear_partida(self.modelo, club, personalidad)
        S.guardar_partida(self.p)
        self.abrir_partida(self.p)

    def abrir_partida(self, p):
        self.p = p
        self.ultimo_informe = []
        self.ir("juego")
        self.pendientes()

    def proximo_rival(self):
        p = self.p
        if p["numero"] >= len(p["fixture"]):
            return None
        for l, v in p["fixture"][p["numero"]]:
            local, visitante = p["equipos"][l].nombre, p["equipos"][v].nombre
            if p["mio"] in (local, visitante):
                return f"{local} vs {visitante}"
        return None

    # --- jugar
    def jugar_fecha(self):
        self.ocupado = "Jugando la fecha…"
        self.pantalla_club()

        def trabajo():
            r = S.jugar_una_fecha(self.p, self.modelo, "app")
            Clock.schedule_once(lambda dt: self.fecha_jugada(r, True), 0)
        threading.Thread(target=trabajo, daemon=True).start()

    def jugar_varias(self, cuantas):
        self.ocupado = "Jugando…"
        self.pantalla_club()

        def trabajo():
            jugadas, r = 0, None
            while jugadas < cuantas and self.p["numero"] < len(self.p["fixture"]):
                r = S.jugar_una_fecha(self.p, self.modelo)
                jugadas += 1
                self.ocupado = f"Jugando… fecha {self.p['numero']}"
                Clock.schedule_once(lambda dt: self.pantalla_club(), 0)
                reunion = self.p["reunion"]
                if reunion and reunion["prioridad"] >= 80:
                    break           # tu DT quiere hablar de algo grave
            Clock.schedule_once(lambda dt: self.fecha_jugada(r, False), 0)
        threading.Thread(target=trabajo, daemon=True).start()

    def fecha_jugada(self, r, con_partido):
        self.ocupado = None
        self.ultimo_informe = self.informe(r) if r else []
        if con_partido and r and r["partido"]:
            self.ir("partido")
            self.sm.get_screen("partido").mostrar(r["partido"], self.volver_del_partido)
        else:
            self.volver_del_partido()

    def volver_del_partido(self):
        self.ir("juego")
        self.pantalla_club()
        self.pendientes()

    def informe(self, r):
        p = self.p
        d = S.division_de(p, p["mio"])
        lineas = [f"Resultados de la fecha {p['numero']}:"]
        for es_mio, texto_res, div in r["resultados"]:
            if div == d:
                lineas.append(("► " if es_mio else "    ") + texto_res)
        if r["informe"]:
            (tipo, intensidad), mejoras, lesionados, _ = r["informe"]
            if mejoras:
                lineas.append("🏋 Suben: " + ", ".join(f"{j.corto} {a}→{b}"
                                                       for j, a, b in mejoras))
            for j, n in lesionados:
                lineas.append(f"🚑 Se lesionó {j.corto}: {n} fecha{'s' if n > 1 else ''}")
        return lineas + r["obras"] + p.get("noticias", [])

    # --- lo que hay que resolver entre fechas (lo mismo que la consola)
    def pendientes(self):
        p = self.p
        mi = self.mi()
        if p["numero"] >= len(p["fixture"]):
            self.ir("fin")
            return
        vencidos = [j for j in mi.plantel if j.contrato <= 0]
        if vencidos:
            self.renovacion(max(vencidos, key=J.nivel))
            return
        grandes = [j for j in mi.reserva if j.edad >= C.EDAD_LIMITE]
        if grandes:
            self.pibe_de_21(grandes[0])
            return
        S.abrir_ventana(p)
        if not p["sin_dt"] and p["reunion"]:
            self.reunion()
            return
        if not p["sin_dt"] and p["tecnicos"].get(p["mio"]) is None:
            self.elegir_dt()
            return
        S.guardar_partida(p)
        self.pantalla_club()

    def renovacion(self, j):
        p, mi = self.p, self.mi()
        rng = random.Random(f"{p['semilla']}|{p['temporada']}|renueva|{j.completo}")
        pedido, anios = M.pretension(j, rng), M.anios_contrato(j)
        info = [texto(f"{J.NOMBRE_POS[j.pos].capitalize()}, {j.edad} años, nivel "
                      f"{J.nivel(j)}, potencial {j.potencial}"),
                texto(f"Cobraba {M.plata(M.sueldo(j))}/año. Pide {M.plata(pedido)}/año "
                      f"por {anios} temporada{'s' if anios > 1 else ''}.")]

        def renovar(sueldo):
            M.firmar(j, sueldo, anios)
            self.pendientes()

        def dejar():
            tits = M.titulares(mi)
            M.liberar(j, mi, p["libres"], pagar=False)
            p.setdefault("fin_contratos", []).append(
                f"{j.corto} ({j.pos}, {J.nivel(j)}): termina contrato en {mi.nombre}, "
                f"queda libre")
            t = S.mi_dt(p)
            if t and id(j) in tits:
                T.cambiar(t, sat=-4)
            self.pendientes()
        botones = [(f"Renovar por {M.plata(pedido)}/año", lambda: renovar(pedido), VERDE),
                   (f"Ofrecerle {M.plata(0.9 * pedido)}/año",
                    lambda: renovar(round(0.9 * pedido, 3)), VERDE)]
        if len(mi.plantel) > 16:
            botones.append(("Dejarlo ir", dejar, ROJO))
        ventana(f"📝 Se terminó el contrato de {j.completo}", info, botones)

    def pibe_de_21(self, j):
        mi = self.mi()

        def subir():
            C.subir(mi, j)
            self.pendientes()

        def irse():
            mi.reserva.remove(j)
            self.pendientes()
        botones = [("Subirlo a Primera", subir, VERDE)] if len(mi.plantel) < M.PLANTEL_MAX \
            else []
        ventana(f"🌱 {j.completo} cumple {C.EDAD_LIMITE}",
                [texto(f"{J.NOMBRE_POS[j.pos].capitalize()} de la reserva, nivel {J.nivel(j)}, "
                       f"potencial {C.estrellas_pot(j)}"),
                 texto("Sube a Primera o deja el club.", 14, APAGADO)],
                botones + [("Dejarlo ir", irse, ROJO)])

    def reunion(self):
        p = self.p
        r, t = p["reunion"], S.mi_dt(p)
        p["reunion"] = None
        cuerpo = [texto(f"«{r['texto']}»", 16)]
        for i, linea in enumerate(r.get("lista", []), 1):
            cuerpo.append(texto(f"{i}. {linea}", 14, APAGADO))

        def responder(n):
            textos = S.resolver_reunion(p, r, n)
            if textos:
                ventana(t.apellido, [texto(x, 16) for x in textos],
                        [("Seguir", None, VERDE)], al_cerrar=self.pendientes)
            else:
                self.pendientes()
        botones = [(o[0], lambda n=n: responder(n), VERDE if n == 1 else GRIS)
                   for n, o in enumerate(r["opciones"], 1)]
        ventana(f"📣 Reunión con {t.completo}", cuerpo,
                botones or [("Seguir", lambda: responder(None), VERDE)])

    def elegir_dt(self):
        p = self.p

        def contratar(t):
            aviso = S.contratar(p, t)
            ventana("Nuevo DT", [texto(aviso, 16)], [("Seguir", None, VERDE)],
                    al_cerrar=self.pendientes)
        botones = [(f"{t.completo} · {t.personalidad}\nprestigio {t.prestigio} · "
                    f"{M.plata(t.sueldo)}/año · {T.resumen_cv(t)}",
                    lambda t=t: contratar(t), VERDE_OSCURO) for t in S.dts_disponibles(p)]
        ventana("Elegí al nuevo DT", [texto(f"{p['mio']} necesita DT.", 15, APAGADO)], botones)

    def echar_dt(self):
        p, mi = self.p, self.mi()
        t = S.mi_dt(p)
        costo = t.sueldo * max(t.contrato, 0.5)

        def echar():
            mi.caja -= costo
            p["reunion"] = None
            aviso = S.se_va_mi_dt(p)
            ventana("Se fue el DT", [texto(aviso, 16)], [("Elegir otro DT", None, VERDE)],
                    al_cerrar=self.pendientes)
        ventana(f"¿Echar a {t.completo}?",
                [texto(f"Cuesta {M.plata(costo)} (lo que le queda de contrato).")],
                [("Sí, echarlo", echar, ROJO), ("No", None, GRIS)])

    def pedir_formacion(self):
        p, mi = self.p, self.mi()
        t = S.mi_dt(p)

        def elegir(f):
            p["derrotas_formacion"] = 0
            if f is None or f == mi.formacion:
                if mi.formacion_forzada and f is None:
                    T.cambiar(t, sat=3)
                mi.formacion_forzada = None
                dice = ("Gracias, presidente. Usted no se va a arrepentir." if f is None
                        else "Justo lo que pensaba hacer.")
            else:
                mi.formacion_forzada = f
                T.cambiar(t, sat=-5)
                dice = f"Usted manda, presidente. Jugamos con el {f}, aunque yo no lo haría."
            S.guardar_partida(p)
            ventana(t.apellido, [texto(f"«{dice}»", 16)], [("Seguir", None, VERDE)],
                    al_cerrar=self.pantalla_club)
        botones = [("Que elija él", lambda: elegir(None), VERDE)]
        botones += [(f + (" (la que prefiere)" if f == mi.formacion else ""),
                     lambda f=f: elegir(f), GRIS) for f in J.FORMACIONES]
        ventana("¿Con qué formación?",
                [texto("Si le imponés una, no le va a gustar.", 14, APAGADO)],
                botones + [("Cancelar", None, ROJO)])

    def siguiente_temporada(self):
        p = self.p
        mio = p["mio"]
        d_antes = S.division_de(p, mio)
        cambios = S.cerrar_temporada(p)
        avisos = []
        d_ahora = S.division_de(p, mio)
        if d_ahora < d_antes:
            avisos.append(f"🎉 ¡{mio} ASCENDIÓ a la {p['divisiones'][d_ahora]}! Los ingresos "
                          f"suben un 50%.")
        elif d_ahora > d_antes:
            avisos.append(f"😢 {mio} descendió a la {p['divisiones'][d_ahora]}.")
        retirados, juveniles = cambios[mio]
        if retirados:
            avisos.append("Se retiran: " + ", ".join(f"{j.corto} ({j.pos}, {j.edad})"
                                                     for j in retirados))
        if juveniles:
            avisos.append("🌱 Llegan a la reserva: " + ", ".join(
                f"{j.corto} ({j.pos}, {C.estrellas_pot(j)})" for j in juveniles))
        S.empezar_temporada(p)
        S.guardar_partida(p)
        self.ultimo_informe = []
        self.ir("juego")
        ventana(f"Pretemporada {p['temporada']}", [texto(a, 15) for a in avisos]
                or [texto("Arranca una nueva temporada.")],
                [("Seguir", None, VERDE)], al_cerrar=self.pendientes)


if __name__ == "__main__":
    CeluFutbol().run()
