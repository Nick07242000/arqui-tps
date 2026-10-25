#!/bin/bash
# Ensambla un programa RISC-V (RV32I) y genera una palabra de 32 bits por linea
# en hexadecimal, listo para $readmemh o para transmitir por UART.
# Uso: ./build_program.sh programa.s   ->  programa.hex y programa.lst
set -e
source_file="$1"
base="${source_file%.s}"

riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o "$base.o" "$source_file"
riscv64-unknown-elf-objcopy -O binary -j .text "$base.o" "$base.bin"
od -An -v -tx4 -w4 "$base.bin" | tr -d ' ' > "$base.hex"
riscv64-unknown-elf-objdump -d -M no-aliases "$base.o" > "$base.lst"
rm -f "$base.o" "$base.bin"
echo "$(wc -l < "$base.hex") palabras en $base.hex"
