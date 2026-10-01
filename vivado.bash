#!/usr/bin/env bash
# Sync the Vivado project with the current sources, then open the GUI.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

"$VIVADO" -mode gui -source "$SCRIPT_DIR/project.tcl" "${ARGS[@]}"