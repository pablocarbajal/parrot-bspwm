# parrot-bspwm

Script para instalar un entorno **bspwm** sencillo en **Parrot OS 7 (Echo)**.

Inspirado en [xJackSx/BSPWMparrot](https://github.com/xJackSx/BSPWMparrot), pero reescrito (no copia su código): se detiene en el primer error, instala con `apt` sin compilar nada, no borra carpetas, no toca la shell de `root` y guarda copia de lo que reemplaza.

> ⚠️ **No está probado en una máquina Parrot real.** Haz una instantánea de la VM antes de usarlo.

## Pasos

```bash
git clone https://github.com/pablocarbajal/parrot-bspwm.git
cd parrot-bspwm

# 1. Si `apt` falla con "Redirection ... is forbidden" (503), arregla el repositorio:
./bspwm-parrot.sh --arreglar-repo

# 2. Mira lo que haría, sin cambiar nada:
./bspwm-parrot.sh --simular

# 3. Instala (--teclado es = España, latam = Latinoamérica, us = inglés ANSI):
./bspwm-parrot.sh --teclado es
```

Después cierra la sesión y elige **bspwm** en la pantalla de inicio. Para volver a KDE: `Super + Alt + Q`.

## Opciones

| Opción | Qué hace |
| --- | --- |
| `--simular` | Muestra lo que haría, sin cambiar nada |
| `--arreglar-repo` | Apunta `apt` a `https://deb.parrot.sh/direct/parrot/` (con copia de seguridad) |
| `--teclado es\|latam\|us` | Teclado de la sesión bspwm: `es` España, `latam` Latinoamérica, `us` inglés ANSI (por defecto `es`) |
| `--fondo RUTA` | Imagen de fondo de pantalla |
| `--ayuda` | Muestra la ayuda |

## Atajos (`Super` = tecla de Windows)

| Atajo | Acción |
| --- | --- |
| `Super + Enter` | Terminal |
| `Super + D` | Lanzador (`rofi`) |
| `Super + W` | Cerrar ventana |
| `Super + F` | Pantalla completa |
| `Super + 1` a `4` | Ir al escritorio 1 a 4 |
| `Super + ←↓↑→` | Moverse entre ventanas |
| `Super + Alt + R` | Recargar bspwm |
| `Super + Alt + Q` | Salir de bspwm |

## Protecciones (para evitar problemas de instalaciones anteriores)

- **Recursos de la VM:** antes de instalar nada, el script detecta la RAM y los núcleos. Si hay **menos de 4 GB de RAM** o **menos de 2 núcleos**, muestra una advertencia recomendando subir los recursos de la VM y pregunta si quieres continuar. En una VM de "4 GB" el sistema puede ver un poco menos de 4 GB y saltar el aviso.
- **kitty sin zsh:** si `~/.config/kitty/kitty.conf` tiene `shell zsh` pero `zsh` no está instalado, el script comenta esa línea, añade `shell bash` y guarda una copia (`kitty.conf.copia-FECHA`). Así se evita el error `Failed to launch child: zsh`.
- **Fondo sin mosaico:** el `bspwmrc` usa siempre `feh --bg-fill`, nunca `--bg-center` ni `--bg-tile`, para que el fondo no se repita al cambiar la resolución.
- **Teclado validado:** `--teclado` solo acepta `es`, `latam` o `us`; cualquier otro valor da error antes de tocar nada.

## Qué hace y qué no

- Instala con `apt`: `bspwm`, `sxhkd`, `polybar`, `picom`, `rofi`, `feh`, `kitty`, `flameshot`, `ranger`.
- Escribe una configuración mínima en `~/.config` (tu configuración anterior se mueve a `~/.config-backup-bspwm-FECHA`).
- No ejecuta `parrot-upgrade`: hazlo tú antes.
- No cambia tu sesión de KDE.
