`timescale 1ns / 1ps
`include "riscv_defs.vh"

// ------------------------------------------------------------------------------
// Convierte la palabra leida de memoria en el dato de un load (lb/lh/lw/lbu/lhu)
// ------------------------------------------------------------------------------
module load_data_extender (
    input  wire [2:0]  i_funct3,
    input  wire [1:0]  i_byte_offset,        // addr[1:0]
    input  wire [31:0] i_raw_word,
    output reg  [31:0] o_load_data
);

    wire [7:0]  selected_byte     = i_raw_word[8*i_byte_offset +: 8];
    wire [15:0] selected_halfword = i_byte_offset[1] ? i_raw_word[31:16]
                                                     : i_raw_word[15:0];

    always @(*) begin
        case (i_funct3)
            `FUNCT3_BYTE:   o_load_data = {{24{selected_byte[7]}},      selected_byte};
            `FUNCT3_BYTE_U: o_load_data = {24'b0,                       selected_byte};
            `FUNCT3_HALF:   o_load_data = {{16{selected_halfword[15]}}, selected_halfword};
            `FUNCT3_HALF_U: o_load_data = {16'b0,                       selected_halfword};
            `FUNCT3_WORD:   o_load_data = i_raw_word;
            default:        o_load_data = 32'b0;
        endcase
    end

endmodule
