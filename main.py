"""
App para Android (Kivy) del simulador de fútbol.

El juego es el mismo de siempre (simulador_futbol.py): corre en segundo
plano y esta pantalla hace de consola. Lo que el juego escribe se muestra
arriba, y lo que tocás en los botones o escribís abajo le llega como si lo
tipearas en la terminal.

En la PC también anda: python main.py (con Kivy instalado).
"""
import builtins
import os
import queue
import sys
import threading
import traceback

from kivy.app import App
from kivy.clock import Clock
from kivy.core.text import LabelBase
from kivy.core.window import Window
from kivy.metrics import dp
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.gridlayout import GridLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.uix.textinput import TextInput
from kivy.utils import escape_markup

AQUI = os.path.dirname(os.path.abspath(__file__))
LabelBase.register("Mono", os.path.join(AQUI, "DejaVuSansMono.ttf"))

ANCHO = 40           # ancho de las líneas del juego (ver simulador_futbol.ANCHO)
MAX_LINEAS = 400     # lo que se guarda en pantalla
BLOQUE = 40          # líneas por etiqueta (una etiqueta muy alta no se dibuja en Android)
FONDO = (0.07, 0.09, 0.08, 1)

# La letra no trae emojis de colores: se reemplazan por símbolos que sí tiene,
# algunos con color.
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
BOTONES = (("1", "2", "3", "4", "5", "6", "7"),
           ("8", "9", "10", "11", "12", "13", "0"),
           ("s", "n", "↵"))


def a_pantalla(texto):
    """Texto del juego a texto de Kivy: escapa el markup y cambia los emojis."""
    salida = []
    for ch in texto:
        if ch in EMOJIS:
            simbolo, color = EMOJIS[ch]
            salida.append(f"[color={color}]{simbolo}[/color]" if color else simbolo)
        elif ch == "️":      # selector de variante de los emojis
            continue
        else:
            salida.append(escape_markup(ch))
    return "".join(salida)


class Consola:
    """Hace de sys.stdout: junta lo que escribe el juego."""

    def __init__(self):
        self.lineas = [""]
        self.borradas = 0       # líneas viejas que ya no se guardan
        self.cambio = False
        self.lock = threading.Lock()

    def write(self, texto):
        with self.lock:
            partes = texto.split("\n")
            self.lineas[-1] += partes[0]
            self.lineas.extend(partes[1:])
            sobran = len(self.lineas) - MAX_LINEAS
            if sobran > 0:
                del self.lineas[:sobran]
                self.borradas += sobran
            self.cambio = True

    def flush(self):
        pass

    def bloques(self):
        """{número de bloque: texto} con las líneas que hay ahora."""
        with self.lock:
            self.cambio = False
            salida = {}
            for i, linea in enumerate(self.lineas, self.borradas):
                salida.setdefault(i // BLOQUE, []).append(linea)
            return {n: "\n".join(ls) for n, ls in salida.items()}


class FutbolApp(App):
    title = "Celu Fútbol"

    def build(self):
        Window.clearcolor = FONDO
        self.consola = Consola()
        self.respuestas = queue.Queue()

        raiz = BoxLayout(orientation="vertical", padding=dp(4), spacing=dp(4))
        self.scroll = ScrollView(do_scroll_x=False, bar_width=dp(4))
        self.pantalla = BoxLayout(orientation="vertical", size_hint_y=None)
        self.pantalla.bind(minimum_height=self.pantalla.setter("height"))
        self.scroll.add_widget(self.pantalla)
        self.etiquetas = {}          # número de bloque: (Label, texto que muestra)
        raiz.add_widget(self.scroll)

        fila = BoxLayout(size_hint_y=None, height=dp(44), spacing=dp(4))
        self.entrada = TextInput(multiline=False, font_name="Mono", font_size=dp(16),
                                 hint_text="Escribí acá (nombres, montos)…")
        self.entrada.bind(on_text_validate=lambda w: self.enviar(w.text))
        fila.add_widget(self.entrada)
        ok = Button(text="OK", size_hint_x=None, width=dp(56))
        ok.bind(on_release=lambda b: self.enviar(self.entrada.text))
        fila.add_widget(ok)
        raiz.add_widget(fila)

        for botones in BOTONES:
            grilla = GridLayout(cols=len(botones), size_hint_y=None, height=dp(46),
                                spacing=dp(4))
            for etiqueta in botones:
                b = Button(text=etiqueta, font_name="Mono", font_size=dp(18))
                b.bind(on_release=lambda b: self.enviar("" if b.text == "↵" else b.text))
                grilla.add_widget(b)
            raiz.add_widget(grilla)

        Window.bind(size=lambda *a: self.ajustar_letra())
        Clock.schedule_interval(self.refrescar, 0.1)
        return raiz

    def letra(self):
        """Que entren las 40 columnas del juego a lo ancho de la pantalla."""
        ancho = Window.width - dp(16)
        # cada letra de DejaVu Sans Mono ocupa 0,602 de su tamaño, y un margen
        return max(dp(9), ancho / (ANCHO + 2) / 0.61), ancho

    def ajustar_letra(self):
        tam, ancho = self.letra()
        for etiqueta, _ in self.etiquetas.values():
            etiqueta.font_size, etiqueta.text_size = tam, (ancho, None)

    def nueva_etiqueta(self):
        tam, ancho = self.letra()
        e = Label(font_name="Mono", markup=True, halign="left", valign="top",
                  size_hint_y=None, color=(0.9, 0.95, 0.9, 1), font_size=tam,
                  text_size=(ancho, None))
        e.bind(texture_size=lambda w, s: setattr(w, "height", s[1]))
        self.pantalla.add_widget(e)
        return e

    # ------------------------------------------------------------ el juego
    def on_start(self):
        os.environ["FUTBOL_PARTIDAS"] = self.user_data_dir   # la partida, dentro de la app
        os.chdir(AQUI)                                       # para que encuentre los .json
        sys.path.insert(0, AQUI)
        sys.stdout = self.consola
        builtins.input = self.pedir
        threading.Thread(target=self.correr, daemon=True).start()

    def correr(self):
        try:
            import simulador_futbol
            sys.argv = ["simulador_futbol.py"]
            simulador_futbol.main()
        except Exception:
            print("\n" + traceback.format_exc())
            print("Se cortó el juego. Mandale esta pantalla al que lo programa.")
            return
        Clock.schedule_once(lambda dt: self.stop(), 1)

    def pedir(self, prompt=""):
        """Reemplaza a input(): espera lo que toques o escribas."""
        print(prompt, end="")
        respuesta = self.respuestas.get()
        print(respuesta)             # como en la terminal, queda lo que contestaste
        return respuesta

    def enviar(self, texto):
        self.entrada.text = ""
        self.respuestas.put(texto)

    def refrescar(self, dt):
        """Redibuja solo los bloques que cambiaron, y baja hasta el final."""
        if not self.consola.cambio:
            return
        bloques = self.consola.bloques()
        for n in [n for n in self.etiquetas if n not in bloques]:
            self.pantalla.remove_widget(self.etiquetas.pop(n)[0])
        for n in sorted(bloques):
            if n not in self.etiquetas:
                self.etiquetas[n] = (self.nueva_etiqueta(), None)
            etiqueta, mostrado = self.etiquetas[n]
            if mostrado != bloques[n]:
                etiqueta.text = a_pantalla(bloques[n])
                self.etiquetas[n] = (etiqueta, bloques[n])
        Clock.schedule_once(lambda dt: setattr(self.scroll, "scroll_y", 0), 0)


if __name__ == "__main__":
    FutbolApp().run()
