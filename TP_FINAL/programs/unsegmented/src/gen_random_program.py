#!/usr/bin/env python3
"""Generador de programas RV32I aleatorios pero siempre validos y finitos.

Los programas usan solo instrucciones de la lista obligatoria, terminan en
HALT y no producen accesos fuera de rango, desalineados ni instrucciones
ilegales. Registros reservados:
    x31 = base de datos (0x400)    x30 = contador de lazos
    x28, x27 = enlace del patron jalr
Los saltos son siempre hacia adelante, salvo los lazos acotados.

Uso: gen_random_program.py <semilla> [cantidad_de_bloques]   (imprime el .s)
"""
import random
import sys

DATA_BASE = 0x400
EDGE_VALUES = [0, 1, 2, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x0000FFFF, 0xFFFF0000, 0x80000001]
R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_OPS = ["slli", "srli", "srai"]
LOADS = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]
POOL = list(range(1, 27)) + [29]            # registros de datos libres
HOT_WORD_COUNT = 6                          # palabras de datos de uso frecuente


class Generator:
    def __init__(self, seed):
        self.random = random.Random(seed)
        self.lines = []
        self.label_count = 0
        # Pocas palabras de datos compartidas por loads y stores: asi los loads
        # leen datos escritos antes (con bytes de signo en 1, mitades distintas, etc.)
        self.hot_words = self.random.sample(range(0, 256), HOT_WORD_COUNT)

    # ---- Utilidades ---------------------------------------------------------
    def emit(self, text):
        self.lines.append("        " + text)

    def label(self, name):
        self.lines.append(f"{name}:")

    def new_label(self):
        self.label_count += 1
        return f"L{self.label_count}"

    def source(self):
        return self.random.choice(POOL + [0])

    def dest(self):
        return 0 if self.random.random() < 0.05 else self.random.choice(POOL)

    def immediate(self):
        if self.random.random() < 0.3:
            return self.random.choice([-2048, -1, 0, 1, 2047, 1024, -1024])
        return self.random.randint(-2048, 2047)

    def emit_constant(self, register, value):
        upper = ((value + 0x800) >> 12) & 0xFFFFF
        lower = ((value & 0xFFF) ^ 0x800) - 0x800
        self.emit(f"lui     x{register}, {upper}")
        self.emit(f"addi    x{register}, x{register}, {lower}")

    # ---- Instrucciones simples (una palabra, sin saltos) ------------------------
    def simple_alu(self):
        kind = self.random.random()
        rd = self.dest()
        if kind < 0.5:
            op = self.random.choice(R_OPS)
            self.emit(f"{op:<7} x{rd}, x{self.source()}, x{self.source()}")
        elif kind < 0.8:
            op = self.random.choice(I_OPS)
            self.emit(f"{op:<7} x{rd}, x{self.source()}, {self.immediate()}")
        elif kind < 0.93:
            op = self.random.choice(SHIFT_OPS)
            self.emit(f"{op:<7} x{rd}, x{self.source()}, {self.random.randint(0, 31)}")
        else:
            self.emit(f"lui     x{rd}, {self.random.randint(0, 0xFFFFF)}")

    def data_offset(self, size):
        """Desplazamiento alineado dentro de una de las palabras de uso frecuente."""
        word = self.random.choice(self.hot_words)
        return word * 4 + self.random.randrange(0, 4, size)

    def memory_access(self):
        if self.random.random() < 0.45:
            op, size = self.random.choice(STORES)
            self.emit(f"{op:<7} x{self.source()}, {self.data_offset(size)}(x31)")
        else:
            op, size = self.random.choice(LOADS)
            self.emit(f"{op:<7} x{self.dest()}, {self.data_offset(size)}(x31)")

    def simple_instruction(self):
        if self.random.random() < 0.8:
            self.simple_alu()
        else:
            self.memory_access()

    # ---- Construcciones ----------------------------------------------------------
    def forward_branch(self):
        op = self.random.choice(["beq", "bne"])
        rs1 = self.source()
        rs2 = rs1 if self.random.random() < 0.4 else self.source()
        target = self.new_label()
        self.emit(f"{op:<7} x{rs1}, x{rs2}, {target}")
        for _ in range(self.random.randint(1, 3)):
            self.simple_instruction()
        self.label(target)

    def forward_jal(self):
        target = self.new_label()
        rd = 0 if self.random.random() < 0.3 else self.random.choice(POOL)
        self.emit(f"jal     x{rd}, {target}")
        for _ in range(self.random.randint(1, 2)):
            self.simple_alu()
        self.label(target)

    def jalr_pattern(self):
        # x28 = direccion de la instruccion jalr; destino = jalr + 12 (o 13: bit 0 se limpia)
        here = self.new_label()
        rd = 0 if self.random.random() < 0.3 else 27
        self.emit(f"jal     x28, {here}")
        self.label(here)
        self.emit(f"jalr    x{rd}, {self.random.choice([12, 13])}(x28)")
        self.simple_alu()
        self.simple_alu()

    def bounded_loop(self):
        loop = self.new_label()
        self.emit(f"addi    x30, x0, {self.random.randint(2, 5)}")
        self.label(loop)
        for _ in range(self.random.randint(2, 4)):
            self.simple_instruction()
        self.emit("addi    x30, x30, -1")
        self.emit(f"bne     x30, x0, {loop}")

    # ---- Programa completo -----------------------------------------------------
    def generate(self, blocks):
        self.lines += ["        .macro  halt", "        .word   0x0000000B",
                       "        .endm", "        .text", "        .globl  _start", "_start:"]
        self.emit(f"addi    x31, x0, {DATA_BASE}")
        for register in self.random.sample(POOL, 12):
            value = self.random.choice(EDGE_VALUES) if self.random.random() < 0.4 \
                else self.random.getrandbits(32)
            self.emit_constant(register, value)
        for word in self.hot_words:
            self.emit(f"sw      x{self.random.choice(POOL)}, {word * 4}(x31)")

        constructs = [(self.simple_alu, 40), (self.memory_access, 20), (self.forward_branch, 14),
                      (self.forward_jal, 5), (self.jalr_pattern, 5), (self.bounded_loop, 6)]
        functions = [item[0] for item in constructs]
        weights = [item[1] for item in constructs]
        for _ in range(blocks):
            self.random.choices(functions, weights)[0]()
        self.emit("halt")
        return "\n".join(self.lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    seed = int(sys.argv[1])
    blocks = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    sys.stdout.write(Generator(seed).generate(blocks))
