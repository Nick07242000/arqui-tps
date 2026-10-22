// -----------------------------------------------------------------------------
// Definiciones RISC-V compartidas: opcodes, funct3/funct7 y tipos de inmediato
// -----------------------------------------------------------------------------
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---- Opcodes (bits [6:0]) ---------------------------------------------------
`define OPCODE_R_TYPE    7'b0110011
`define OPCODE_OP_IMM    7'b0010011
`define OPCODE_LOAD      7'b0000011
`define OPCODE_STORE     7'b0100011
`define OPCODE_BRANCH    7'b1100011
`define OPCODE_JAL       7'b1101111
`define OPCODE_JALR      7'b1100111
`define OPCODE_LUI       7'b0110111
`define OPCODE_CUSTOM_0  7'b0001011

// ---- HALT (instruccion custom, palabra completa) ----------------------------
`define HALT_INSTRUCTION 32'h0000000B

// ---- funct7 -------------------------------------------------------------------
`define FUNCT7_BASE      7'b0000000
`define FUNCT7_ALT       7'b0100000   // sub, sra, srai

// ---- funct3: operaciones aritmeticas/logicas (R e I) -------------------------
`define FUNCT3_ADD_SUB   3'b000
`define FUNCT3_SLL       3'b001
`define FUNCT3_SLT       3'b010
`define FUNCT3_SLTU      3'b011
`define FUNCT3_XOR       3'b100
`define FUNCT3_SRL_SRA   3'b101
`define FUNCT3_OR        3'b110
`define FUNCT3_AND       3'b111

// ---- funct3: loads, stores, branches y jalr ----------------------------------
`define FUNCT3_BYTE      3'b000       // lb  / sb
`define FUNCT3_HALF      3'b001       // lh  / sh
`define FUNCT3_WORD      3'b010       // lw  / sw
`define FUNCT3_BYTE_U    3'b100       // lbu
`define FUNCT3_HALF_U    3'b101       // lhu
`define FUNCT3_BEQ       3'b000
`define FUNCT3_BNE       3'b001
`define FUNCT3_JALR      3'b000

// ---- Tipo de inmediato (lo produce control_unit, lo consume immediate_generator)
`define IMM_TYPE_NONE    3'b000
`define IMM_TYPE_I       3'b001
`define IMM_TYPE_S       3'b010
`define IMM_TYPE_B       3'b011
`define IMM_TYPE_U       3'b100
`define IMM_TYPE_J       3'b101

`endif
