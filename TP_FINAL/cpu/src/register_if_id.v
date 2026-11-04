`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Latch IF/ID
// -----------------------------------------------------------------------------
module register_if_id (
    input  wire        i_clk,
    input  wire        i_reset,          // reset sincrono: deja el latch vacio
    input  wire        i_enable,         // captura solo cuando el front-end avanza
    input  wire        i_insert_bubble,  // en vez de capturar, deja una burbuja

    input  wire        i_valid,
    input  wire [31:0] i_pc,

    output reg         o_valid,
    output reg  [31:0] o_pc
);

    // La burbuja deja el latch igual que el reset, pero solo si el front-end avanza
    wire clear_latch = i_reset || (i_enable && i_insert_bubble);

    always @(posedge i_clk) begin
        if (clear_latch) begin
            o_valid <= 1'b0;
            o_pc    <= 32'b0;
        end else if (i_enable) begin
            o_valid <= i_valid;
            o_pc    <= i_pc;
        end
    end

endmodule
