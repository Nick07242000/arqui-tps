#!/usr/bin/env python3
"""Simulador de referencia RV32I para el procesador del proyecto.

Ejecuta una imagen de programa (palabras de 32 bits) con las reglas del
proyecto: memoria de programa y de datos separadas, HALT custom 0x0000000B,
instrucciones ilegales neutralizadas, accesos fuera de rango suprimidos y
accesos desalineados alineados hacia abajo.

Uso:  rv32i_ref.py programa.hex      (imprime el estado final)
"""
import sys

MASK32 = 0xFFFFFFFF
HALT_WORD = 0x0000000B
DATA_WORDS = 1024
DATA_BYTES = DATA_WORDS * 4

OPCODE_R, OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_STORE = 0x33, 0x13, 0x03, 0x23
OPCODE_BRANCH, OPCODE_JAL, OPCODE_JALR, OPCODE_LUI = 0x63, 0x6F, 0x67, 0x37


def to_signed(value):
    value &= MASK32
    return value - (1 << 32) if value & 0x80000000 else value


def sign_extend(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


class ReferenceCpu:
    def __init__(self, program_words):
        self.program = list(program_words)
        self.regs = [0] * 32
        self.pc = 0
        self.data = bytearray(DATA_BYTES)
        self.retired = 0
        self.loads = 0
        self.stop_reason = None            # "HALT" o "END_OF_IMAGE"
        self.seen_illegal = False
        self.seen_out_of_range = False
        self.seen_misaligned = False

    # ---- Utilidades --------------------------------------------------------
    def write_register(self, index, value):
        if index != 0:
            self.regs[index] = value & MASK32

    def read_data_word(self, word_index):
        offset = word_index * 4
        return int.from_bytes(self.data[offset:offset + 4], "little")

    # ---- Ejecucion -----------------------------------------------------------
    def run(self, max_instructions=100000):
        while self.stop_reason is None and self.retired < max_instructions:
            self.step()
        if self.stop_reason is None:
            self.stop_reason = "TIMEOUT"
        return self

    def step(self):
        word_index = self.pc >> 2
        if word_index >= len(self.program):
            self.stop_reason = "END_OF_IMAGE"
            return
        word = self.program[word_index]
        if word == HALT_WORD:
            self.stop_reason = "HALT"
            return

        opcode = word & 0x7F
        rd, funct3 = (word >> 7) & 31, (word >> 12) & 7
        rs1, rs2, funct7 = (word >> 15) & 31, (word >> 20) & 31, word >> 25
        a, b = self.regs[rs1], self.regs[rs2]
        next_pc = (self.pc + 4) & MASK32

        if opcode == OPCODE_R and self._r_type_is_valid(funct3, funct7):
            self.write_register(rd, self._alu(funct3, funct7 == 0x20, a, b))
        elif opcode == OPCODE_OP_IMM and self._op_imm_is_valid(funct3, funct7):
            imm = sign_extend(word >> 20, 12)
            is_shift = funct3 in (1, 5)
            second = (word >> 20) & 31 if is_shift else imm & MASK32
            self.write_register(rd, self._alu(funct3, is_shift and funct7 == 0x20, a, second))
        elif opcode == OPCODE_LOAD and funct3 in (0, 1, 2, 4, 5):
            self._load(rd, funct3, (a + sign_extend(word >> 20, 12)) & MASK32)
        elif opcode == OPCODE_STORE and funct3 in (0, 1, 2):
            imm = sign_extend(((word >> 25) << 5) | ((word >> 7) & 31), 12)
            self._store(funct3, (a + imm) & MASK32, b)
        elif opcode == OPCODE_BRANCH and funct3 in (0, 1):
            imm = sign_extend((((word >> 31) & 1) << 12) | (((word >> 7) & 1) << 11)
                              | (((word >> 25) & 0x3F) << 5) | (((word >> 8) & 0xF) << 1), 13)
            if (a == b) == (funct3 == 0):
                next_pc = (self.pc + imm) & MASK32
        elif opcode == OPCODE_JAL:
            imm = sign_extend((((word >> 31) & 1) << 20) | (((word >> 12) & 0xFF) << 12)
                              | (((word >> 20) & 1) << 11) | (((word >> 21) & 0x3FF) << 1), 21)
            self.write_register(rd, self.pc + 4)
            next_pc = (self.pc + imm) & MASK32
        elif opcode == OPCODE_JALR and funct3 == 0:
            target = ((a + sign_extend(word >> 20, 12)) & MASK32) & ~1
            self.write_register(rd, self.pc + 4)
            next_pc = target
        elif opcode == OPCODE_LUI:
            self.write_register(rd, word & 0xFFFFF000)
        else:
            self.seen_illegal = True       # neutralizada: no escribe ni salta

        self.pc = next_pc
        self.retired += 1

    # ---- Instrucciones -----------------------------------------------------------
    @staticmethod
    def _r_type_is_valid(funct3, funct7):
        return funct7 == 0 or (funct7 == 0x20 and funct3 in (0, 5))

    @staticmethod
    def _op_imm_is_valid(funct3, funct7):
        if funct3 == 1:
            return funct7 == 0
        if funct3 == 5:
            return funct7 in (0, 0x20)
        return True

    @staticmethod
    def _alu(funct3, alternate, a, b):
        shift = b & 31
        if funct3 == 0:
            return a - b if alternate else a + b
        if funct3 == 1:
            return a << shift
        if funct3 == 2:
            return int(to_signed(a) < to_signed(b))
        if funct3 == 3:
            return int(a < b)
        if funct3 == 4:
            return a ^ b
        if funct3 == 5:
            return to_signed(a) >> shift if alternate else a >> shift
        if funct3 == 6:
            return a | b
        return a & b

    def _check_access(self, funct3, address):
        in_range = (address >> 12) == 0
        misaligned = (funct3 & 3 == 1 and address & 1) or (funct3 & 3 == 2 and address & 3)
        self.seen_out_of_range |= not in_range
        self.seen_misaligned |= bool(misaligned)
        return in_range

    def _load(self, rd, funct3, address):
        self.loads += 1
        if not self._check_access(funct3, address):
            self.write_register(rd, 0)
            return
        word = self.read_data_word((address >> 2) & (DATA_WORDS - 1))
        if funct3 in (0, 4):
            value = (word >> (8 * (address & 3))) & 0xFF
            value = sign_extend(value, 8) if funct3 == 0 else value
        elif funct3 in (1, 5):
            value = (word >> (16 * ((address >> 1) & 1))) & 0xFFFF
            value = sign_extend(value, 16) if funct3 == 1 else value
        else:
            value = word
        self.write_register(rd, value)

    def _store(self, funct3, address, value):
        if not self._check_access(funct3, address):
            return
        base = (address >> 2) * 4
        if funct3 == 0:
            self.data[base + (address & 3)] = value & 0xFF
        elif funct3 == 1:
            offset = base + 2 * ((address >> 1) & 1)
            self.data[offset:offset + 2] = (value & 0xFFFF).to_bytes(2, "little")
        else:
            self.data[base:base + 4] = (value & MASK32).to_bytes(4, "little")

    # ---- Resultado ---------------------------------------------------------------
    def cycles(self):
        """Ciclos del datapath no segmentado: un load ocupa dos ciclos."""
        return self.retired + self.loads

    def state_lines(self):
        lines = [f"STATUS {self.stop_reason}",
                 f"PC {self.pc:08x}",
                 f"RETIRED {self.retired}",
                 f"CYCLES {self.cycles()}",
                 f"FLAGS illegal={int(self.seen_illegal)} "
                 f"out_of_range={int(self.seen_out_of_range)} "
                 f"misaligned={int(self.seen_misaligned)}"]
        lines += [f"REG {i} {value:08x}" for i, value in enumerate(self.regs)]
        lines += [f"MEM {i} {self.read_data_word(i):08x}" for i in range(32)]
        return lines


def load_hex(path):
    with open(path) as hex_file:
        return [int(line, 16) for line in hex_file if line.strip()]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print("\n".join(ReferenceCpu(load_hex(sys.argv[1])).run().state_lines()))
