#!/usr/bin/env python3
"""Compara el datapath (simulado con Icarus Verilog) con el simulador de referencia.

Para cada programa ejecuta ambos hasta HALT y compara estado, PC, registros,
memoria de datos, indicadores de error, instrucciones completadas y ciclos.

Uso (desde la carpeta raiz del proyecto):
    tools/compare_with_reference.py program programs/reference_program.hex
    tools/compare_with_reference.py random --count 200 --seed 1
"""
import argparse
import collections
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_random_program import Generator          # noqa: E402
from rv32i_ref import ReferenceCpu, load_hex       # noqa: E402

RTL_FILES = ["unpipelined_datapath", "mux", "register", "alu", "control_unit",
             "immediate_generator", "registers", "program_memory", "data_memory",
             "data_access_checker", "load_data_extender", "store_data_formatter"]
STATE_LINE = re.compile(r"^(STATUS|PC|RETIRED|CYCLES|FLAGS|REG \d+|MEM \d+) (.*)$")


def run(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs).stdout


def build_simulator(args):
    args.build_dir.mkdir(parents=True, exist_ok=True)
    simulator = args.build_dir / "dump_state.vvp"
    sources = [str(args.rtl_dir / f"{name}.v") for name in RTL_FILES]
    run(["iverilog", "-g2005", f"-I{args.tb_dir}", f"-I{args.rtl_dir}", "-o", str(simulator),
         str(args.tb_dir / "tb_dump_state.v")] + sources)
    return simulator


def assemble(source, hex_path, args):
    run([str(args.programs_dir / "build_program.sh"), str(source)])
    produced = source.with_suffix(".hex")
    if produced != hex_path:
        produced.replace(hex_path)


def parse_state(lines):
    state = {}
    for line in lines:
        match = STATE_LINE.match(line.strip())
        if match:
            state[match.group(1)] = match.group(2)
    return state


def run_datapath(simulator, hex_path, word_count):
    output = run(["vvp", str(simulator), f"+hex={hex_path}", f"+words={word_count}"])
    return parse_state(output.splitlines())


def run_reference(hex_path):
    return parse_state(ReferenceCpu(load_hex(hex_path)).run().state_lines())


def differences(reference, datapath, compare_cycles):
    keys = [key for key in reference if compare_cycles or key != "CYCLES"]
    return [(key, reference[key], datapath.get(key, "<falta>"))
            for key in keys if reference[key] != datapath.get(key)]


def report_differences(name, found):
    print(f"[DIFF] {name}: {len(found)} diferencias")
    for key, expected, obtained in found[:8]:
        print(f"         {key}: referencia = {expected}, datapath = {obtained}")
    if len(found) > 8:
        print(f"         ... y {len(found) - 8} mas")


def compare_program(simulator, hex_path, name, args):
    word_count = len(load_hex(hex_path))
    found = differences(run_reference(hex_path), run_datapath(simulator, hex_path, word_count),
                        not args.no_cycles)
    if found:
        report_differences(name, found)
    return not found


def command_program(args):
    simulator = build_simulator(args)
    ok = compare_program(simulator, args.hex, args.hex.name, args)
    if ok:
        print(f"[OK] {args.hex.name}: el datapath coincide con la referencia "
              "(registros, memoria, PC, flags, instrucciones y ciclos)")
    return ok


def command_random(args):
    simulator = build_simulator(args)
    out_dir = args.build_dir / "random"
    out_dir.mkdir(parents=True, exist_ok=True)
    mnemonics = collections.Counter()
    failures = []
    for seed in range(args.seed, args.seed + args.count):
        source, hex_path = out_dir / f"random_{seed}.s", out_dir / f"random_{seed}.hex"
        source.write_text(Generator(seed).generate(args.blocks))
        assemble(source, hex_path, args)
        for line in source.read_text().splitlines():
            token = line.split()[0] if line.strip() and not line.strip().endswith(":") else ""
            if token and not token.startswith("."):
                mnemonics[token] += 1
        if not compare_program(simulator, hex_path, f"semilla {seed}", args):
            failures.append(seed)
        else:
            for stale in (source, hex_path, source.with_suffix(".lst")):
                stale.unlink(missing_ok=True)

    print(f"\n{args.count} programas aleatorios (semillas {args.seed}..{args.seed + args.count - 1}, "
          f"{args.blocks} bloques cada uno): "
          + ("TODOS COINCIDEN" if not failures else f"{len(failures)} CON DIFERENCIAS {failures}"))
    print("Instrucciones generadas: " + ", ".join(f"{name} {count}" for name, count
                                                  in sorted(mnemonics.items())))
    return not failures


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rtl-dir", type=Path, default=root / "rtl")
    parser.add_argument("--tb-dir", type=Path, default=root / "tb")
    parser.add_argument("--programs-dir", type=Path, default=root / "programs")
    parser.add_argument("--build-dir", type=Path, default=root / "build" / "differential")
    parser.add_argument("--no-cycles", action="store_true",
                        help="no comparar ciclos (para el pipeline, donde difieren)")
    commands = parser.add_subparsers(dest="command", required=True)

    program = commands.add_parser("program", help="comparar una imagen .hex")
    program.add_argument("hex", type=Path)
    program.set_defaults(handler=command_program)

    random_cmd = commands.add_parser("random", help="comparar programas aleatorios")
    random_cmd.add_argument("--count", type=int, default=100)
    random_cmd.add_argument("--seed", type=int, default=1)
    random_cmd.add_argument("--blocks", type=int, default=60)
    random_cmd.set_defaults(handler=command_random)

    args = parser.parse_args()
    sys.exit(0 if args.handler(args) else 1)


if __name__ == "__main__":
    main()
