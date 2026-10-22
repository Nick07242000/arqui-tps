`timescale 1ns / 1ps
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Prepara un store (sb/sh/sw)
// -----------------------------------------------------------------------------
module store_data_formatter (
    input  wire        i_mem_write,
    input  wire [2:0]  i_funct3,
    input  wire [1:0]  i_byte_offset,        // addr[1:0]
    input  wire [31:0] i_store_data,
    output reg  [3:0]  o_write_byte_enable,
    output reg  [31:0] o_write_data
);

    always @(*) begin
        o_write_byte_enable = 4'b0000;
        o_write_data        = i_store_data;

        if (i_mem_write) begin
            case (i_funct3)
                `FUNCT3_BYTE: begin
                    o_write_data        = {4{i_store_data[7:0]}};
                    o_write_byte_enable = 4'b0001 << i_byte_offset;
                end

                `FUNCT3_HALF: begin
                    o_write_data        = {2{i_store_data[15:0]}};
                    o_write_byte_enable = i_byte_offset[1] ? 4'b1100 : 4'b0011;
                end

                `FUNCT3_WORD: begin
                    o_write_byte_enable = 4'b1111;
                end

                default: ;   // funct3 no soportado: no escribe
            endcase
        end
    end

endmodule
