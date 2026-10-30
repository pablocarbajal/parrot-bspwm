#!/usr/bin/env bash
# arch-gh0stzk.sh: automatiza la instalación del entorno bspwm de gh0stzk en una máquina Arch Linux (o derivada).
#
# Descarga el instalador oficial (RiceInstaller de https://github.com/gh0stzk/dotfiles), lo revisa,
# te enseña lo que va a hacer y lo ejecuta contestando por ti las preguntas que hace.
#
# El instalador de gh0stzk SOLO funciona en Arch y derivadas: no sirve en Parrot (Debian).
# Este script NO instala Arch: primero hay que tener Arch (o EndeavourOS, etc.) instalado.
# NO SE HA PROBADO en una máquina Arch real. Haz una instantánea de la VM antes.
#
# Uso:
#   ./arch-gh0stzk.sh --simular                 # descarga y revisa el instalador, sin instalar nada
#   ./arch-gh0stzk.sh                           # instala (sin Neovim ni tema de Firefox de gh0stzk)
#   ./arch-gh0stzk.sh --con-nvim --con-firefox  # acepta también su Neovim y su tema de Firefox
#   ./arch-gh0stzk.sh --hash SHA256             # aborta si el instalador descargado no tiene ese SHA-256
#   ./arch-gh0stzk.sh --reiniciar               # reinicia la máquina al terminar
#   ./arch-gh0stzk.sh --ayuda

set -Eeuo pipefail
trap 'echo -e "\n\e[31m✗ Fallo en la línea $LINENO. Revisa el mensaje de arriba y el registro: ${ARCHIVO_DE_REGISTRO:-sin registro}\e[0m" >&2' ERR

readonly URL_DEL_INSTALADOR="https://raw.githubusercontent.com/gh0stzk/dotfiles/master/RiceInstaller"
readonly NOMBRE_DEL_INSTALADOR="RiceInstaller"

# Recursos mínimos recomendados para la máquina virtual.
readonly KILOBYTES_POR_GIGABYTE=1048576
readonly MINIMO_RAM_GIGABYTES=4
readonly MINIMO_RAM_KILOBYTES=$(( MINIMO_RAM_GIGABYTES * KILOBYTES_POR_GIGABYTE ))
readonly MINIMO_NUCLEOS_CPU=2

# Cada cuántos segundos se renueva la contraseña de sudo para que no caduque durante la instalación.
readonly SEGUNDOS_ENTRE_RENOVACIONES_DE_SUDO=50

MODO_SIMULACION=0
ACEPTAR_NEOVIM="n"
ACEPTAR_FIREFOX="n"
REINICIAR_AL_TERMINAR=0
HASH_ESPERADO=""
FECHA_Y_HORA="$(date +%Y%m%d-%H%M%S)"
ARCHIVO_DE_REGISTRO="$HOME/arch-gh0stzk-$FECHA_Y_HORA.log"
CARPETA_TEMPORAL=""
PROCESO_RENOVADOR_DE_SUDO=""

informar()    { echo -e "\e[36m➜\e[0m $*"; }
confirmar_ok() { echo -e "\e[32m✓\e[0m $*"; }
advertir()    { echo -e "\e[33m!\e[0m $*"; }
fallar()      { echo -e "\e[31m✗\e[0m $*" >&2; }

mostrar_ayuda() { sed -n '2,/^$/{/^$/!p}' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simular) MODO_SIMULACION=1 ;;
    --con-nvim) ACEPTAR_NEOVIM="y" ;;
    --con-firefox) ACEPTAR_FIREFOX="y" ;;
    --reiniciar) REINICIAR_AL_TERMINAR=1 ;;
    --hash) HASH_ESPERADO="${2:?Falta el valor de --hash (SHA-256 esperado)}"; shift ;;
    --ayuda|-h|--help) mostrar_ayuda; exit 0 ;;
    *) fallar "Opción desconocida: $1"; mostrar_ayuda; exit 2 ;;
  esac
  shift
done

# Al salir: borra la carpeta temporal y detiene la renovación de sudo.
limpiar_al_salir() {
  [[ -n "$PROCESO_RENOVADOR_DE_SUDO" ]] && kill "$PROCESO_RENOVADOR_DE_SUDO" 2>/dev/null || true
  if [[ -n "$CARPETA_TEMPORAL" && -d "$CARPETA_TEMPORAL" ]]; then
    rm -rf "${CARPETA_TEMPORAL:?}"
  fi
}
trap limpiar_al_salir EXIT

# ---------------------------------------------------------------- comprobaciones
revisar_que_es_arch() {
  if [[ $EUID -eq 0 ]]; then
    fallar "No ejecutes este script como root. Usa tu usuario normal (usa sudo por dentro)."
    exit 1
  fi
  if [[ ! -f /etc/arch-release ]]; then
    fallar "Esto no es Arch Linux (no existe /etc/arch-release). El instalador de gh0stzk solo funciona en Arch y derivadas."
    fallar "En Parrot usa bspwm-parrot.sh."
    exit 1
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    fallar "El instalador necesita systemd (no sirve en Artix u otras distribuciones sin systemd)."
    exit 1
  fi
  command -v sudo >/dev/null 2>&1 || { fallar "Falta sudo."; exit 1; }
  command -v curl >/dev/null 2>&1 || { fallar "Falta curl. Instálalo con: sudo pacman -S curl"; exit 1; }
}

revisar_recursos_de_la_maquina() {
  local ram_total_kilobytes nucleos_de_cpu ram_total_gigabytes recursos_insuficientes=0
  ram_total_kilobytes="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  nucleos_de_cpu="$(nproc)"
  ram_total_gigabytes="$(awk -v kilobytes="$ram_total_kilobytes" -v por_gigabyte="$KILOBYTES_POR_GIGABYTE" \
      'BEGIN { printf "%.1f", kilobytes / por_gigabyte }')"
  informar "Recursos detectados: ${ram_total_gigabytes} GB de RAM y ${nucleos_de_cpu} núcleos de CPU."

  if (( ram_total_kilobytes < MINIMO_RAM_KILOBYTES )); then
    recursos_insuficientes=1
    advertir "Tienes menos de ${MINIMO_RAM_GIGABYTES} GB de RAM (${ram_total_gigabytes} GB)."
  fi
  if (( nucleos_de_cpu < MINIMO_NUCLEOS_CPU )); then
    recursos_insuficientes=1
    advertir "Tienes menos de ${MINIMO_NUCLEOS_CPU} núcleos de CPU (${nucleos_de_cpu})."
  fi
  if (( recursos_insuficientes )); then
    advertir "Recomendación: apaga la VM y sube sus recursos (al menos ${MINIMO_RAM_GIGABYTES} GB de RAM y ${MINIMO_NUCLEOS_CPU} núcleos) antes de continuar."
    if (( ! MODO_SIMULACION )); then
      read -r -p "Tu máquina tiene pocos recursos. ¿Quieres continuar de todas formas? [s/N] " respuesta_recursos
      [[ "$respuesta_recursos" =~ ^[sSyY]$ ]] || { informar "Cancelado. No se cambió nada."; exit 0; }
    fi
  fi
}

# ---------------------------------------------------------------- descarga y revisión
descargar_y_revisar_el_instalador() {
  CARPETA_TEMPORAL="$(mktemp -d)"
  RUTA_DEL_INSTALADOR="${CARPETA_TEMPORAL:?}/$NOMBRE_DEL_INSTALADOR"

  informar "Descargando el instalador de $URL_DEL_INSTALADOR"
  curl --fail --silent --show-error --location --output "$RUTA_DEL_INSTALADOR" "$URL_DEL_INSTALADOR"

  local hash_descargado cantidad_de_lineas
  hash_descargado="$(sha256sum "$RUTA_DEL_INSTALADOR" | awk '{print $1}')"
  cantidad_de_lineas="$(wc -l < "$RUTA_DEL_INSTALADOR")"
  informar "Instalador: ${cantidad_de_lineas} líneas, SHA-256 ${hash_descargado}"

  if [[ -n "$HASH_ESPERADO" && "$HASH_ESPERADO" != "$hash_descargado" ]]; then
    fallar "El SHA-256 no coincide con el esperado (${HASH_ESPERADO}). No se ejecuta nada."
    exit 1
  fi

  head -n 1 "$RUTA_DEL_INSTALADOR" | grep -q '^#!/bin/sh' \
    || { fallar "El instalador no empieza con #!/bin/sh: ya no es el archivo que revisé. No se ejecuta."; exit 1; }
  sh -n "$RUTA_DEL_INSTALADOR" || { fallar "El instalador tiene errores de sintaxis."; exit 1; }
  confirmar_ok "El instalador se descargó y no tiene errores de sintaxis."

  echo
  echo "   Lo que hace el instalador (según lo leído en su código; puede cambiar si lo actualizan):"
  echo "    - Añade a /etc/pacman.conf dos repositorios de terceros: el de gh0stzk y Chaotic-AUR,"
  echo "      y confía en sus claves de firma."
  echo "    - Instala con pacman unos 100 paquetes, y paru (AUR) para xwinwrap."
  echo "    - Clona https://github.com/gh0stzk/dotfiles en ~/.local/share/gh0stzk."
  echo "    - Mueve tus configuraciones actuales a ~/.RiceBackup/FECHA y copia las suyas a ~/.config."
  echo "    - Cambia tu shell a zsh y activa servicios de usuario (mpd, ArchUpdates)."
  echo
  echo "   Líneas del instalador que modifican el sistema fuera de tu carpeta personal:"
  grep -n -E 'pacman\.conf|pacman-key|pacman\.d/hooks|chsh|systemctl disable' "$RUTA_DEL_INSTALADOR" | sed 's/^/    /' || true
}

# ---------------------------------------------------------------- instalación
mantener_sudo_activo() {
  sudo -v
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true 2>/dev/null || exit 0
      sleep "$SEGUNDOS_ENTRE_RENOVACIONES_DE_SUDO"
    done
  ) &
  PROCESO_RENOVADOR_DE_SUDO=$!
}

actualizar_el_sistema_completo() {
  # El instalador hace "pacman -Syy" y luego instala paquetes sueltos, lo que en Arch puede dejar el sistema
  # a medias (actualización parcial). Por eso se actualiza todo primero.
  informar "Actualizando el sistema completo antes de empezar (pacman -Syu)..."
  sudo pacman -Syu --noconfirm
  sudo pacman -S --needed --noconfirm git base-devel
}

ejecutar_el_instalador() {
  local ruta_final="$HOME/$NOMBRE_DEL_INSTALADOR"
  if [[ -e "$ruta_final" ]]; then
    local ruta_respaldo="$ruta_final.anterior-$FECHA_Y_HORA"
    advertir "Ya existe $ruta_final: lo muevo a $ruta_respaldo"
    mv "$ruta_final" "$ruta_respaldo"
  fi
  cp "$RUTA_DEL_INSTALADOR" "$ruta_final"
  chmod +x "$ruta_final"

  informar "Ejecutando el instalador. Respuestas automáticas: continuar=y, Neovim=${ACEPTAR_NEOVIM}, Firefox=${ACEPTAR_FIREFOX}, reiniciar=n"
  informar "Registro de la instalación: $ARCHIVO_DE_REGISTRO"
  # El instalador exige ejecutarse desde HOME. Orden de sus preguntas: continuar, Neovim, Firefox, reiniciar.
  (
    cd "$HOME"
    printf 'y\n%s\n%s\nn\n' "$ACEPTAR_NEOVIM" "$ACEPTAR_FIREFOX" | "./$NOMBRE_DEL_INSTALADOR"
  ) 2>&1 | tee -a "$ARCHIVO_DE_REGISTRO"
}

# ---------------------------------------------------------------- principal
revisar_que_es_arch
revisar_recursos_de_la_maquina
descargar_y_revisar_el_instalador

if (( MODO_SIMULACION )); then
  echo
  confirmar_ok "Simulación terminada. No se instaló nada. Para instalar, ejecuta el script sin --simular."
  exit 0
fi

echo
echo "Voy a modificar /etc/pacman.conf (repositorios de terceros), instalar paquetes y cambiar tu shell."
read -r -p "¿Hiciste una instantánea de la VM y quieres continuar? [s/N] " respuesta_instantanea
[[ "$respuesta_instantanea" =~ ^[sSyY]$ ]] || { informar "Cancelado. No se cambió nada."; exit 0; }

mantener_sudo_activo
actualizar_el_sistema_completo
ejecutar_el_instalador

echo
confirmar_ok "El instalador terminó. Debes reiniciar la máquina para aplicar los cambios."
echo "   Copia de tus configuraciones anteriores: ~/.RiceBackup/"
echo "   Registro: $ARCHIVO_DE_REGISTRO"
if (( REINICIAR_AL_TERMINAR )); then
  informar "Reiniciando..."
  sudo reboot
else
  echo "   Reinicia con: sudo reboot"
fi
