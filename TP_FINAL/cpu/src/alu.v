`timescale 1ns / 1ps
`include "alu_ops.vh"

// -----------------------------------------------------------------------------
// ALU combinacional de 32 bits para RV32I
// -----------------------------------------------------------------------------
module alu (
    input  wire [31:0] i_operand_a,
    input  wire [31:0] i_operand_b,
    input  wire [3:0]  i_alu_op,
    output reg  [31:0] o_result
);

    // ---- Preparacion de operandos -------------------------------------------
    wire signed [31:0] operand_a_signed = i_operand_a;
    wire signed [31:0] operand_b_signed = i_operand_b;
    wire        [4:0]  shift_amount     = i_operand_b[4:0];

    // ---- Resultados intermedios ---------------------------------------------
    wire [31:0] sum_result  = i_operand_a + i_operand_b;
    wire [31:0] diff_result = i_operand_a - i_operand_b;

    wire        is_less_signed   = (operand_a_signed < operand_b_signed);
    wire        is_less_unsigned = (i_operand_a < i_operand_b);

    wire [31:0] shift_left_result          = i_operand_a << shift_amount;
    wire [31:0] shift_right_logic_result   = i_operand_a >> shift_amount;
    wire [31:0] shift_right_arith_result   = operand_a_signed >>> shift_amount;

    // ---- Seleccion de la operacion ------------------------------------------
    always @(*) begin
        case (i_alu_op)
            `ALU_OP_ADD:    o_result = sum_result;
            `ALU_OP_SUB:    o_result = diff_result;
            `ALU_OP_AND:    o_result = i_operand_a & i_operand_b;
            `ALU_OP_OR:     o_result = i_operand_a | i_operand_b;
            `ALU_OP_XOR:    o_result = i_operand_a ^ i_operand_b;
            `ALU_OP_SLL:    o_result = shift_left_result;
            `ALU_OP_SRL:    o_result = shift_right_logic_result;
            `ALU_OP_SRA:    o_result = shift_right_arith_result;
            `ALU_OP_SLT:    o_result = {31'b0, is_less_signed};
            `ALU_OP_SLTU:   o_result = {31'b0, is_less_unsigned};
            `ALU_OP_PASS_B: o_result = i_operand_b;
            default:        o_result = 32'b0;
        endcase
    end

endmodule
