`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Multiplexor generico de N entradas
// -----------------------------------------------------------------------------
module mux #(
    parameter DATA_WIDTH  = 32,
    parameter INPUT_COUNT = 2       // minimo 2
) (
    input  wire [INPUT_COUNT*DATA_WIDTH-1:0] i_inputs,
    input  wire [$clog2(INPUT_COUNT)-1:0]    i_select,
    output wire [DATA_WIDTH-1:0]             o_output
);

    assign o_output = (i_select < INPUT_COUNT)
                    ? i_inputs[i_select*DATA_WIDTH +: DATA_WIDTH]
                    : {DATA_WIDTH{1'b0}};

endmodule
