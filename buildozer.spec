[app]
title = Celu Fútbol
package.name = celufutbol
package.domain = org.gmatiascr62
source.dir = .
source.include_exts = py,json,ttf
# los scripts de entrenamiento necesitan pandas/scipy y no van en la app
source.exclude_patterns = entrenar_*.py
version = 1.9
requirements = python3,kivy==2.3.1
orientation = portrait
fullscreen = 0

android.api = 34
android.minapi = 24
android.archs = arm64-v8a, armeabi-v7a
android.accept_sdk_license = True
android.allow_backup = True

[buildozer]
log_level = 2
warn_on_root = 0
