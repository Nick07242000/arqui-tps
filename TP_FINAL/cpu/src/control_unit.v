`timescale 1ns / 1ps
`include "alu_ops.vh"
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Decodificador / unidad de control RV32I (etapa ID)
// -----------------------------------------------------------------------------
module control_unit (
    input  wire [31:0] i_instruction,

    // ---- Senales de control -------------------------------------------------
    output reg  [3:0]  o_alu_op,
    output reg         o_alu_src_b_is_imm,   // 0: rs2, 1: inmediato
    output reg  [2:0]  o_imm_type,
    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg         o_is_branch,
    output reg         o_is_jal,
    output reg         o_is_jalr,
    output reg         o_is_halt,
    output reg         o_is_illegal,

    // ---- Fuentes realmente usadas (deteccion de load-use) -------------------
    output reg         o_uses_rs1,
    output reg         o_uses_rs2
);

    // -------------------------------------------------------------------------
    // Campos usados para decidir
    // -------------------------------------------------------------------------
    wire [6:0] opcode = i_instruction[6:0];
    wire [2:0] funct3 = i_instruction[14:12];
    wire [6:0] funct7 = i_instruction[31:25];

    // -------------------------------------------------------------------------
    // Validez de cada combinacion funct3/funct7
    // -------------------------------------------------------------------------
    wire funct7_is_base    = (funct7 == `FUNCT7_BASE);
    wire funct7_is_alt     = (funct7 == `FUNCT7_ALT);
    wire funct3_is_srl_sra = (funct3 == `FUNCT3_SRL_SRA);

    // add, sll, slt, sltu, xor, srl, or, and (funct7 base) | sub, sra (funct7 alt)
    wire r_type_is_valid = funct7_is_base
                        || (funct7_is_alt && (funct3 == `FUNCT3_ADD_SUB || funct3_is_srl_sra));

    // Los shifts con inmediato exigen funct7; el resto usa esos bits como inmediato
    wire op_imm_is_valid = (funct3 == `FUNCT3_SLL) ? funct7_is_base :
                           funct3_is_srl_sra       ? (funct7_is_base || funct7_is_alt) :
                                                     1'b1;

    wire load_is_valid   = (funct3 == `FUNCT3_BYTE)   || (funct3 == `FUNCT3_HALF)
                        || (funct3 == `FUNCT3_WORD)   || (funct3 == `FUNCT3_BYTE_U)
                        || (funct3 == `FUNCT3_HALF_U);

    wire store_is_valid  = (funct3 == `FUNCT3_BYTE)   || (funct3 == `FUNCT3_HALF)
                        || (funct3 == `FUNCT3_WORD);

    wire branch_is_valid = (funct3 == `FUNCT3_BEQ)    || (funct3 == `FUNCT3_BNE);

    wire jalr_is_valid   = (funct3 == `FUNCT3_JALR);

    // -------------------------------------------------------------------------
    // Operacion de la ALU
    // -------------------------------------------------------------------------
    wire [3:0] alu_op_r_type = {funct7_is_alt, funct3};
    wire [3:0] alu_op_op_imm = {funct7_is_alt && funct3_is_srl_sra, funct3};

    // -------------------------------------------------------------------------
    // Senales de control
    // -------------------------------------------------------------------------
    always @(*) begin
        // Por defecto: instruccion ilegal y neutralizada
        o_alu_op           = `ALU_OP_ADD;
        o_alu_src_b_is_imm = 1'b0;
        o_imm_type         = `IMM_TYPE_NONE;
        o_reg_write        = 1'b0;
        o_mem_read         = 1'b0;
        o_mem_write        = 1'b0;
        o_is_branch        = 1'b0;
        o_is_jal           = 1'b0;
        o_is_jalr          = 1'b0;
        o_is_halt          = 1'b0;
        o_is_illegal       = 1'b1;
        o_uses_rs1         = 1'b0;
        o_uses_rs2         = 1'b0;

        case (opcode)
            `OPCODE_R_TYPE: if (r_type_is_valid) begin
                o_is_illegal = 1'b0;
                o_alu_op     = alu_op_r_type;
                o_reg_write  = 1'b1;
                o_uses_rs1   = 1'b1;
                o_uses_rs2   = 1'b1;
            end

            `OPCODE_OP_IMM: if (op_imm_is_valid) begin
                o_is_illegal       = 1'b0;
                o_alu_op           = alu_op_op_imm;
                o_alu_src_b_is_imm = 1'b1;
                o_imm_type         = `IMM_TYPE_I;
                o_reg_write        = 1'b1;
                o_uses_rs1         = 1'b1;
            end

            `OPCODE_LOAD: if (load_is_valid) begin
                o_is_illegal       = 1'b0;
                o_alu_src_b_is_imm = 1'b1;
                o_imm_type         = `IMM_TYPE_I;
                o_reg_write        = 1'b1;
                o_mem_read         = 1'b1;
                o_uses_rs1         = 1'b1;
            end

            `OPCODE_STORE: if (store_is_valid) begin
                o_is_illegal       = 1'b0;
                o_alu_src_b_is_imm = 1'b1;
                o_imm_type         = `IMM_TYPE_S;
                o_mem_write        = 1'b1;
                o_uses_rs1         = 1'b1;
                o_uses_rs2         = 1'b1;
            end

            `OPCODE_BRANCH: if (branch_is_valid) begin
                o_is_illegal = 1'b0;
                o_imm_type   = `IMM_TYPE_B;
                o_is_branch  = 1'b1;
                o_uses_rs1   = 1'b1;
                o_uses_rs2   = 1'b1;
            end

            `OPCODE_JAL: begin
                o_is_illegal = 1'b0;
                o_imm_type   = `IMM_TYPE_J;
                o_reg_write  = 1'b1;
                o_is_jal     = 1'b1;
            end

            `OPCODE_JALR: if (jalr_is_valid) begin
                o_is_illegal       = 1'b0;
                o_alu_src_b_is_imm = 1'b1;
                o_imm_type         = `IMM_TYPE_I;
                o_reg_write        = 1'b1;
                o_is_jalr          = 1'b1;
                o_uses_rs1         = 1'b1;
            end

            `OPCODE_LUI: begin
                o_is_illegal       = 1'b0;
                o_alu_op           = `ALU_OP_PASS_B;
                o_alu_src_b_is_imm = 1'b1;
                o_imm_type         = `IMM_TYPE_U;
                o_reg_write        = 1'b1;
            end

            `OPCODE_CUSTOM_0: if (i_instruction == `HALT_INSTRUCTION) begin
                o_is_illegal = 1'b0;
                o_is_halt    = 1'b1;
            end

            default: ;   // opcode no soportado: queda ilegal
        endcase
    end

endmodule
