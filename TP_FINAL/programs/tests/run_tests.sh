#!/bin/bash
# Compila y ejecuta los testbenches de instrucciones (T2.1.2)
# Uso: ./run_tests.sh [testbench ...]   (sin argumentos: ejecuta todos)
RTL_DIR="${RTL_DIR:-rtl}"
TB_DIR="${TB_DIR:-tb}"
BUILD_DIR="${BUILD_DIR:-build}"

RTL_FILES="unpipelined_datapath mux register alu control_unit immediate_generator \
registers program_memory data_memory data_access_checker load_data_extender store_data_formatter"

mkdir -p "$BUILD_DIR"
sources=""
for module in $RTL_FILES; do sources="$sources $RTL_DIR/$module.v"; done

if [ $# -gt 0 ]; then testbenches="$@"; else testbenches=$(ls $TB_DIR/tb_*.v | xargs -n1 basename | sed 's/\.v$//' | grep -v tb_dump_state); fi

status=0
for testbench in $testbenches; do
    echo "=== $testbench ==="
    if ! iverilog -g2005 -I"$TB_DIR" -I"$RTL_DIR" -o "$BUILD_DIR/$testbench.vvp" "$TB_DIR/$testbench.v" $sources; then
        echo "ERROR de compilacion en $testbench"; status=1; continue
    fi
    output=$(vvp "$BUILD_DIR/$testbench.vvp")
    echo "$output"
    echo "$output" | grep -qE "FAIL|FALLARON" && status=1
done

[ $status -eq 0 ] && echo "RESULTADO GLOBAL: TODO OK" || echo "RESULTADO GLOBAL: HAY FALLAS"
exit $status
