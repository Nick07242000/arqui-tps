#!/usr/bin/env python3
"""Valida el simulador de referencia contra QEMU (via Unicorn).

Ejecuta programas aleatorios en Unicorn (RISC-V de 32 bits) y en
rv32i_ref.py, y compara registros, PC, memoria de datos e instrucciones
completadas. Asi se comprueba la referencia con un emulador ajeno al proyecto.

Unicorn tiene una unica memoria; los programas aleatorios mantienen el codigo
debajo de 0x400 y los datos en 0x400-0x7FF para que ambos modelos coincidan.
HALT (0x0000000B) no es una instruccion RISC-V valida: se detecta en un hook
antes de ejecutarla.

Uso: validate_reference_with_unicorn.py [--count 200] [--seed 1] [--blocks 60]
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from unicorn import Uc, UcError, UC_ARCH_RISCV, UC_MODE_RISCV32, UC_HOOK_CODE
from unicorn.riscv_const import UC_RISCV_REG_PC, UC_RISCV_REG_X0

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_random_program import Generator          # noqa: E402
from rv32i_ref import ReferenceCpu, HALT_WORD     # noqa: E402

DATA_START = 0x400
DATA_END = 0x1000
MEMORY_SIZE = 0x2000


def assemble(source_text, work_dir):
    source = work_dir / "program.s"
    source.write_text(source_text)
    subprocess.run(["riscv64-unknown-elf-as", "-march=rv32i", "-mabi=ilp32",
                    "-o", str(work_dir / "program.o"), str(source)], check=True)
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", "-j", ".text",
                    str(work_dir / "program.o"), str(work_dir / "program.bin")], check=True)
    binary = (work_dir / "program.bin").read_bytes()
    return [int.from_bytes(binary[i:i + 4], "little") for i in range(0, len(binary), 4)]


def run_unicorn(words):
    emulator = Uc(UC_ARCH_RISCV, UC_MODE_RISCV32)
    emulator.mem_map(0, MEMORY_SIZE)
    emulator.mem_write(0, b"".join(word.to_bytes(4, "little") for word in words))
    result = {"retired": 0, "halt_pc": None}

    def on_instruction(uc, address, size, user_data):
        if int.from_bytes(uc.mem_read(address, 4), "little") == HALT_WORD:
            result["halt_pc"] = address
            uc.emu_stop()
        else:
            result["retired"] += 1

    emulator.hook_add(UC_HOOK_CODE, on_instruction)
    try:
        emulator.emu_start(0, MEMORY_SIZE, count=200000)
    except UcError:
        if result["halt_pc"] is None:
            raise
    result["regs"] = [emulator.reg_read(UC_RISCV_REG_X0 + i) for i in range(32)]
    result["pc"] = emulator.reg_read(UC_RISCV_REG_PC)
    result["data"] = bytes(emulator.mem_read(DATA_START, DATA_END - DATA_START))
    return result


def compare(seed, blocks, work_dir):
    words = assemble(Generator(seed).generate(blocks), work_dir)
    if len(words) * 4 > DATA_START:
        return [f"programa demasiado largo ({len(words)} palabras)"]
    unicorn = run_unicorn(words)
    reference = ReferenceCpu(words).run()
    found = []
    if reference.stop_reason != "HALT" or unicorn["halt_pc"] is None:
        found.append(f"terminacion: referencia {reference.stop_reason}, unicorn halt_pc={unicorn['halt_pc']}")
    if reference.pc != unicorn["halt_pc"]:
        found.append(f"PC final: referencia {reference.pc:#x}, unicorn {unicorn['halt_pc']:#x}")
    if reference.retired != unicorn["retired"]:
        found.append(f"instrucciones: referencia {reference.retired}, unicorn {unicorn['retired']}")
    for index in range(32):
        if reference.regs[index] != unicorn["regs"][index]:
            found.append(f"x{index}: referencia {reference.regs[index]:#010x}, "
                         f"unicorn {unicorn['regs'][index]:#010x}")
    if bytes(reference.data[DATA_START:DATA_END]) != unicorn["data"]:
        found.append("memoria de datos distinta")
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--blocks", type=int, default=60)
    args = parser.parse_args()

    failures = 0
    with tempfile.TemporaryDirectory() as temp:
        for seed in range(args.seed, args.seed + args.count):
            found = compare(seed, args.blocks, Path(temp))
            if found:
                failures += 1
                print(f"[DIFF] semilla {seed}: " + "; ".join(found[:5]))
    print(f"{args.count} programas aleatorios contra QEMU/Unicorn: "
          + ("TODOS COINCIDEN" if not failures else f"{failures} CON DIFERENCIAS"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
