`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Latch MEM/WB
// -----------------------------------------------------------------------------
module register_mem_wb (
    input  wire        i_clk,
    input  wire        i_reset,          // reset sincrono: deja el latch vacio
    input  wire        i_enable,         // captura solo cuando el CPU avanza

    // ---- Identificacion de la instruccion -----------------------------------
    input  wire        i_valid,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_instruction,

    // ---- Datos --------------------------------------------------------------
    input  wire [31:0] i_result,         // ALU/link; en loads, direccion efectiva
    input  wire [4:0]  i_rd_addr,

    // ---- Controles ----------------------------------------------------------
    input  wire        i_reg_write,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire [2:0]  i_funct3,
    input  wire        i_access_out_of_range,

    output reg         o_valid,
    output reg  [31:0] o_pc,
    output reg  [31:0] o_instruction,

    output reg  [31:0] o_result,
    output reg  [4:0]  o_rd_addr,

    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg  [2:0]  o_funct3,
    output reg         o_access_out_of_range
);

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_valid               <= 1'b0;
            o_pc                  <= 32'b0;
            o_instruction         <= 32'b0;
            o_result              <= 32'b0;
            o_rd_addr             <= 5'b0;
            o_reg_write           <= 1'b0;
            o_mem_read            <= 1'b0;
            o_mem_write           <= 1'b0;
            o_funct3              <= 3'b0;
            o_access_out_of_range <= 1'b0;
        end else if (i_enable) begin
            o_valid               <= i_valid;
            o_pc                  <= i_pc;
            o_instruction         <= i_instruction;
            o_result              <= i_result;
            o_rd_addr             <= i_rd_addr;
            o_reg_write           <= i_reg_write;
            o_mem_read            <= i_mem_read;
            o_mem_write           <= i_mem_write;
            o_funct3              <= i_funct3;
            o_access_out_of_range <= i_access_out_of_range;
        end
    end

endmodule
