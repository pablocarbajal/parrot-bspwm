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

# 3. Instala (--teclado es = España, --teclado latam = Latinoamérica):
./bspwm-parrot.sh --teclado es
```

Después cierra la sesión y elige **bspwm** en la pantalla de inicio. Para volver a KDE: `Super + Alt + Q`.

## Opciones

| Opción | Qué hace |
| --- | --- |
| `--simular` | Muestra lo que haría, sin cambiar nada |
| `--arreglar-repo` | Apunta `apt` a `https://deb.parrot.sh/direct/parrot/` (con copia de seguridad) |
| `--teclado es\|latam` | Teclado de la sesión bspwm (por defecto `es`) |
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

## Qué hace y qué no

- Instala con `apt`: `bspwm`, `sxhkd`, `polybar`, `picom`, `rofi`, `feh`, `kitty`, `flameshot`, `ranger`.
- Escribe una configuración mínima en `~/.config` (tu configuración anterior se mueve a `~/.config-backup-bspwm-FECHA`).
- No ejecuta `parrot-upgrade`: hazlo tú antes.
- No cambia tu sesión de KDE.
