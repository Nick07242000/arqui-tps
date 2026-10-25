`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Registro generico con reset sincrono y habilitacion de carga
// -----------------------------------------------------------------------------
module register #(
    parameter                   DATA_WIDTH  = 32,
    parameter [DATA_WIDTH-1:0]  RESET_VALUE = {DATA_WIDTH{1'b0}}
) (
    input  wire                  i_clk,
    input  wire                  i_reset,
    input  wire                  i_enable,
    input  wire [DATA_WIDTH-1:0] i_data,
    output reg  [DATA_WIDTH-1:0] o_data
);

    // Valor inicial definido para que la simulacion no propague 'x'
    initial o_data = RESET_VALUE;

    always @(posedge i_clk) begin
        if (i_reset)
            o_data <= RESET_VALUE;
        else if (i_enable)
            o_data <= i_data;
    end

endmodule
