#!/usr/bin/env bash
# bspwm-parrot.sh: instala un entorno bspwm sencillo en Parrot OS 7 (Echo).
#
# Inspirado en https://github.com/xJackSx/BSPWMparrot, pero reescrito para ser mas seguro:
#   - Se detiene en el primer error (el original sigue adelante aunque falle).
#   - No borra carpetas, no toca la shell de root ni compila nada: usa paquetes de apt.
#   - Hace copia de seguridad de lo que vaya a reemplazar.
#   - Tiene modo simulacion: no cambia nada y solo muestra lo que haria.
#
# NO SE HA PROBADO en una maquina Parrot real. Haz una instantanea de la VM antes.
#
# Uso:
#   ./bspwm-parrot.sh --simular            # solo muestra lo que haria
#   ./bspwm-parrot.sh --arreglar-repo      # arregla el error "Redirection ... is forbidden"
#   ./bspwm-parrot.sh                      # instala
#   ./bspwm-parrot.sh --teclado latam      # instala con teclado latinoamericano (por defecto: es)
#   ./bspwm-parrot.sh --fondo ~/Descargas/dragon.jpg
#   ./bspwm-parrot.sh --ayuda

set -Eeuo pipefail
trap 'echo -e "\n\e[31m✗ Fallo en la linea $LINENO. No se ha borrado nada. Revisa el mensaje de arriba.\e[0m" >&2' ERR

SIMULAR=0
ARREGLAR_REPO=0
TECLADO="es"
FONDO=""
FECHA="$(date +%Y%m%d-%H%M%S)"
REPO_DIRECTO="https://deb.parrot.sh/direct/parrot/"

info()  { echo -e "\e[36m➜\e[0m $*"; }
ok()    { echo -e "\e[32m✓\e[0m $*"; }
aviso() { echo -e "\e[33m!\e[0m $*"; }
error() { echo -e "\e[31m✗\e[0m $*" >&2; }

ayuda() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simular) SIMULAR=1 ;;
    --arreglar-repo) ARREGLAR_REPO=1 ;;
    --teclado) TECLADO="${2:?Falta el valor de --teclado (por ejemplo es o latam)}"; shift ;;
    --fondo) FONDO="${2:?Falta la ruta de --fondo}"; shift ;;
    --ayuda|-h|--help) ayuda; exit 0 ;;
    *) error "Opcion desconocida: $1"; ayuda; exit 2 ;;
  esac
  shift
done

# Ejecuta un comando, o solo lo muestra si estamos simulando.
run() {
  if (( SIMULAR )); then echo "   [simulacion] $*"; else "$@"; fi
}

# Escribe en un archivo lo que llegue por la entrada estandar.
escribir() {
  local ruta="$1"
  if (( SIMULAR )); then echo "   [simulacion] se escribiria $ruta"; cat >/dev/null; return 0; fi
  mkdir -p "$(dirname "$ruta")"
  cat > "$ruta"
}

# ---------------------------------------------------------------- comprobaciones
if [[ $EUID -eq 0 ]]; then
  error "No ejecutes este script como root. Usa tu usuario normal (usa sudo por dentro)."
  exit 1
fi
command -v sudo >/dev/null || { error "Falta sudo."; exit 1; }

# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null || true
if [[ "${ID:-}" != "parrot" ]]; then
  aviso "El sistema no se identifica como Parrot (ID='${ID:-?}'). Continuo, pero no esta probado."
fi

(( SIMULAR )) && info "MODO SIMULACION: no se cambiara nada." || sudo -v

# ---------------------------------------------------------------- arreglar el repositorio
arreglar_repo() {
  info "Buscando archivos de apt que usen el director de Parrot..."
  local archivos
  mapfile -t archivos < <(sudo grep -rlE 'director\.parrot\.sh|deb\.parrot\.sh/parrot' \
      /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)

  if [[ ${#archivos[@]} -eq 0 ]]; then
    aviso "No encontre ningun archivo con 'director.parrot.sh' ni 'deb.parrot.sh/parrot'."
    aviso "Estos son tus origenes actuales (pasamelos para revisarlos):"
    sudo grep -rvE '^\s*(#|$)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true
    return 1
  fi

  echo "   Archivos que se modificaran:"; printf '    - %s\n' "${archivos[@]}"
  local copia="/etc/apt/backup-parrot-$FECHA"
  info "Copia de seguridad en $copia"
  run sudo mkdir -p "$copia"
  for f in "${archivos[@]}"; do run sudo cp -a "$f" "$copia/"; done

  info "Apuntando apt a $REPO_DIRECTO (sin redirecciones a espejos)"
  for f in "${archivos[@]}"; do
    run sudo sed -i -E "s#https?://(director\.parrot\.sh|deb\.parrot\.sh/parrot)/?#${REPO_DIRECTO}#g" "$f"
  done
  run sudo apt-get update
  ok "Repositorio actualizado. Para deshacer: copia de vuelta los archivos de $copia"
}

if (( ARREGLAR_REPO )); then
  arreglar_repo
  exit 0
fi

# ---------------------------------------------------------------- confirmacion
if (( ! SIMULAR )); then
  echo
  echo "Voy a instalar bspwm, sxhkd, polybar, picom, rofi, feh y otros con apt,"
  echo "y a crear la configuracion en ~/.config (con copia de seguridad de lo existente)."
  read -r -p "Hiciste una instantanea de la VM y quieres continuar? [s/N] " resp
  [[ "$resp" =~ ^[sSyY]$ ]] || { info "Cancelado. No se cambio nada."; exit 0; }
fi

# ---------------------------------------------------------------- 1. estado de apt
info "1/5 Comprobando que apt funciona y que las descargas no fallan..."
run sudo dpkg --audit
run sudo apt-get check
run sudo apt-get update

# Prueba real de descarga con un paquete pequeño: aqui fallaba el original.
if ! run sudo apt-get install --download-only -y sxhkd; then
  error "apt no puede descargar paquetes. Es el error 'Redirection ... is forbidden' (503)."
  error "Prueba:  $0 --arreglar-repo   y luego vuelve a ejecutar este script."
  exit 1
fi
ok "Las descargas funcionan."

# ---------------------------------------------------------------- 2. paquetes
info "2/5 Instalando paquetes..."
ESENCIALES=(bspwm sxhkd)
OPCIONALES=(polybar picom rofi feh kitty flameshot ranger x11-xkb-utils x11-xserver-utils)

for p in "${ESENCIALES[@]}"; do
  apt-cache show "$p" >/dev/null 2>&1 || { error "El paquete esencial '$p' no existe en tus repositorios."; exit 1; }
done
run sudo apt-get install -y "${ESENCIALES[@]}"

INSTALAR=()
for p in "${OPCIONALES[@]}"; do
  if apt-cache show "$p" >/dev/null 2>&1; then INSTALAR+=("$p"); else aviso "No existe '$p', lo salto."; fi
done
((${#INSTALAR[@]})) && run sudo apt-get install -y "${INSTALAR[@]}"
ok "Paquetes instalados."

# Terminal que usaran los atajos.
if command -v kitty >/dev/null 2>&1 || (( SIMULAR )); then TERMINAL="kitty"
elif command -v konsole >/dev/null 2>&1; then TERMINAL="konsole"
else TERMINAL="xterm"; fi
info "Terminal para los atajos: $TERMINAL"

# ---------------------------------------------------------------- 3. copia de seguridad
info "3/5 Copia de seguridad de configuraciones existentes..."
COPIA="$HOME/.config-backup-bspwm-$FECHA"
for d in bspwm sxhkd polybar picom rofi; do
  if [[ -e "$HOME/.config/$d" ]]; then
    run mkdir -p "$COPIA"
    run mv "$HOME/.config/$d" "$COPIA/$d"
    aviso "Movi ~/.config/$d a $COPIA/$d"
  fi
done

# ---------------------------------------------------------------- 4. configuracion
info "4/5 Escribiendo la configuracion..."
CFG="$HOME/.config"

escribir "$CFG/bspwm/bspwmrc" <<EOF
#!/bin/sh
# Las sesiones de bspwm no heredan el teclado de KDE: se fija aqui.
setxkbmap $TECLADO 2>/dev/null

# Atajos de teclado
pgrep -x sxhkd >/dev/null || sxhkd &

# Escritorios y aspecto
bspc monitor -d 1 2 3 4
bspc config border_width         2
bspc config window_gap           8
bspc config split_ratio          0.52
bspc config borderless_monocle   true
bspc config gapless_monocle      true
bspc config focused_border_color "#e0245e"
bspc config normal_border_color  "#333333"

# Fondo de pantalla (copia una imagen a ~/.config/bspwm/fondo para usarla)
if [ -f "\$HOME/.config/bspwm/fondo" ]; then
  feh --bg-fill "\$HOME/.config/bspwm/fondo"
else
  xsetroot -solid "#10141c"
fi

# Barra superior y efectos
"\$HOME/.config/polybar/launch.sh" &
pgrep -x picom >/dev/null || picom --config "\$HOME/.config/picom/picom.conf" &

# Portapapeles y arrastre entre Windows y la VM (si estan las herramientas de VMware)
command -v vmware-user-suid-wrapper >/dev/null && vmware-user-suid-wrapper &
EOF
run chmod +x "$CFG/bspwm/bspwmrc"

escribir "$CFG/sxhkd/sxhkdrc" <<EOF
# Super = tecla de Windows

# Terminal y lanzador
super + Return
	$TERMINAL
super + d
	rofi -show drun

# Cerrar ventana y pantalla completa
super + w
	bspc node -c
super + f
	bspc node -t "~fullscreen"

# Ir a un escritorio / mandar la ventana a un escritorio
super + {_,shift + }{1-4}
	bspc {desktop -f,node -d} '^{1-4}'

# Moverse entre ventanas
super + {Left,Down,Up,Right}
	bspc node -f {west,south,north,east}

# Intercambiar ventanas de sitio
super + shift + {Left,Down,Up,Right}
	bspc node -s {west,south,north,east}

# Cambiar el tamaño de la ventana
super + alt + {Left,Down,Up,Right}
	bspc node -z {left -20 0,bottom 0 20,top 0 -20,right 20 0}

# Recargar bspwm, recargar atajos y salir de bspwm
super + alt + r
	bspc wm -r
super + Escape
	pkill -USR1 -x sxhkd
super + alt + q
	bspc quit
EOF

escribir "$CFG/polybar/launch.sh" <<'EOF'
#!/bin/sh
killall -q polybar
while pgrep -u "$(id -u)" -x polybar >/dev/null; do sleep 0.5; done
polybar main >>/tmp/polybar-main.log 2>&1 &
EOF
run chmod +x "$CFG/polybar/launch.sh"

escribir "$CFG/polybar/config.ini" <<'EOF'
[colors]
background = #cc10141c
foreground = #dfdfdf
primary = #e0245e
muted = #666666

[bar/main]
width = 100%
height = 26
background = ${colors.background}
foreground = ${colors.foreground}
font-0 = monospace:size=10;2
modules-left = bspwm
modules-center = date
modules-right = cpu memory
padding-right = 2
enable-ipc = true

[module/bspwm]
type = internal/bspwm
label-focused = %name%
label-focused-background = ${colors.primary}
label-focused-padding = 2
label-occupied = %name%
label-occupied-padding = 2
label-empty = %name%
label-empty-foreground = ${colors.muted}
label-empty-padding = 2

[module/date]
type = internal/date
interval = 5
date = %d/%m/%Y
time = %H:%M
label = %date%  %time%

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage:2%%

[module/memory]
type = internal/memory
interval = 3
label = RAM %percentage_used:2%%
EOF

escribir "$CFG/picom/picom.conf" <<'EOF'
# Configuracion minima y segura para maquinas virtuales
backend = "xrender";
vsync = false;
shadow = false;
fading = false;
EOF

if [[ -n "$FONDO" ]]; then
  if [[ -f "$FONDO" ]]; then
    run cp "$FONDO" "$CFG/bspwm/fondo"
    ok "Fondo de pantalla copiado."
  else
    aviso "No existe el archivo de fondo: $FONDO"
  fi
fi

# ---------------------------------------------------------------- 5. comprobacion final
info "5/5 Comprobando que quedo todo..."
if [[ -f /usr/share/xsessions/bspwm.desktop ]] || (( SIMULAR )); then
  ok "La sesion bspwm esta registrada (/usr/share/xsessions/bspwm.desktop)."
else
  aviso "No encuentro /usr/share/xsessions/bspwm.desktop: puede que no aparezca en la pantalla de inicio."
fi

echo
ok "Terminado. Tu sistema actual (KDE) no se ha tocado."
echo "   Para probar bspwm: cierra la sesion y, en la pantalla de inicio, elige la sesion 'bspwm'."
echo "   Para volver a KDE: pulsa Super + Alt + Q (cierra bspwm) y elige KDE otra vez."
if [[ -d "$COPIA" ]]; then
  echo "   Copia de seguridad de lo anterior: $COPIA"
fi
