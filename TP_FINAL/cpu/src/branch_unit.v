`timescale 1ns / 1ps
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Resolucion de saltos (etapa EX): decide si el flujo cambia y hacia donde
// -----------------------------------------------------------------------------
module branch_unit (
    // ---- Instruccion en EX --------------------------------------------------
    input  wire        i_valid,
    input  wire        i_is_branch,
    input  wire        i_is_jal,
    input  wire        i_is_jalr,
    input  wire [2:0]  i_funct3,          // distingue beq de bne
    input  wire [31:0] i_pc,
    input  wire [31:0] i_immediate,

    // ---- Operandos ya adelantados por el forwarding -------------------------
    input  wire [31:0] i_rs1_value,
    input  wire [31:0] i_rs2_value,
    input  wire [31:0] i_alu_result,      // rs1 + inmediato: lo usa jalr

    output wire        o_redirect,        // el proximo PC no es PC + 4
    output wire [31:0] o_redirect_pc
);

    // -------------------------------------------------------------------------
    // Condicion del branch
    // -------------------------------------------------------------------------
    wire operands_are_equal = (i_rs1_value == i_rs2_value);

    wire branch_condition_is_met = (i_funct3 == `FUNCT3_BNE) ? !operands_are_equal
                                                             :  operands_are_equal;

    wire branch_is_taken = i_is_branch && branch_condition_is_met;

    // -------------------------------------------------------------------------
    // Destino del salto
    // -------------------------------------------------------------------------
    wire [31:0] pc_relative_target = i_pc + i_immediate;               // branch y jal
    wire [31:0] jalr_target        = {i_alu_result[31:1], 1'b0};       // la ISA anula el bit 0

    assign o_redirect_pc = i_is_jalr ? jalr_target : pc_relative_target;

    // -------------------------------------------------------------------------
    // Solo una instruccion valida puede cambiar el flujo
    // -------------------------------------------------------------------------
    assign o_redirect = i_valid && (branch_is_taken || i_is_jal || i_is_jalr);

endmodule
