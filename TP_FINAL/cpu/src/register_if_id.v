`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Latch IF/ID
// -----------------------------------------------------------------------------
module register_if_id (
    input  wire        i_clk,
    input  wire        i_reset,          // reset sincrono: deja el latch vacio
    input  wire        i_enable,         // captura solo cuando el CPU avanza

    input  wire        i_valid,
    input  wire [31:0] i_pc,

    output reg         o_valid,
    output reg  [31:0] o_pc
);

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_valid <= 1'b0;
            o_pc    <= 32'b0;
        end else if (i_enable) begin
            o_valid <= i_valid;
            o_pc    <= i_pc;
        end
    end

endmodule
