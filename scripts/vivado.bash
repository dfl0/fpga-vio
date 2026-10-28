#!/usr/bin/env bash
# Sync the Vivado project with the current sources, then open the GUI.
#   ./vivado.bash          sync + open
#   ./vivado.bash clean    recreate from scratch + open
set -e

# Repo root = folder containing this script (pwd -W gives C:/... paths on Git Bash)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && (pwd -W 2>/dev/null || pwd))"

source "$REPO_DIR/project.env"

VIVADO="$(command -v vivado || command -v vivado.bat || true)"
if [[ -z "$VIVADO" ]]; then
    echo "Vivado not found on PATH. Add its bin folder (e.g. /c/Xilinx/Vivado/$VIVADO_VERSION/bin)."
    exit 1
fi

ARGS=()
if [[ "$1" == "clean" ]]; then
    ARGS=(-tclargs clean)
fi

# Run from build/vivado/ so .Xil/, vivado.log and vivado.jou land there
mkdir -p "$REPO_DIR/$BUILD_DIR/vivado"
cd "$REPO_DIR/$BUILD_DIR/vivado"

"$VIVADO" -mode gui -source "$REPO_DIR/fpga/vivado/project.tcl" "${ARGS[@]}"