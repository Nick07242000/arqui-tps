`timescale 1ns / 1ps
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Generador de inmediatos RV32I
// -----------------------------------------------------------------------------
module immediate_generator (
    input  wire [31:0] i_instruction,
    input  wire [2:0]  i_imm_type,
    output reg  [31:0] o_immediate
);

    wire sign_bit = i_instruction[31];

    // ---- Un inmediato por formato -------------------------------------------
    wire [31:0] immediate_i_type = {{20{sign_bit}}, i_instruction[31:20]};

    wire [31:0] immediate_s_type = {{20{sign_bit}}, i_instruction[31:25],
                                                    i_instruction[11:7]};

    wire [31:0] immediate_b_type = {{20{sign_bit}}, i_instruction[7],
                                                    i_instruction[30:25],
                                                    i_instruction[11:8],
                                                    1'b0};

    wire [31:0] immediate_u_type = {i_instruction[31:12], 12'b0};

    wire [31:0] immediate_j_type = {{12{sign_bit}}, i_instruction[19:12],
                                                    i_instruction[20],
                                                    i_instruction[30:21],
                                                    1'b0};

    // ---- Seleccion segun el tipo --------------------------------------------
    always @(*) begin
        case (i_imm_type)
            `IMM_TYPE_I: o_immediate = immediate_i_type;
            `IMM_TYPE_S: o_immediate = immediate_s_type;
            `IMM_TYPE_B: o_immediate = immediate_b_type;
            `IMM_TYPE_U: o_immediate = immediate_u_type;
            `IMM_TYPE_J: o_immediate = immediate_j_type;
            default:     o_immediate = 32'b0;
        endcase
    end

endmodule
