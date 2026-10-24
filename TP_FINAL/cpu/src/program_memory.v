`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Memoria de programa: 1024 palabras de 32 bits
// -----------------------------------------------------------------------------
module program_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
) (
    input  wire                    i_clk,

    // Puerto de lectura (CPU, etapa IF)
    input  wire                    i_read_enable,
    input  wire [ADDR_WIDTH-1:0]   i_read_word_addr,
    output reg  [DATA_WIDTH-1:0]   o_read_data,

    // Puerto de escritura (Debug Unit, solo durante la carga)
    input  wire                    i_write_enable,
    input  wire [ADDR_WIDTH-1:0]   i_write_word_addr,
    input  wire [DATA_WIDTH-1:0]   i_write_data
);

    localparam MEMORY_DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] memory [0:MEMORY_DEPTH-1];

    // Valor inicial definido para que la simulacion no propague 'x'
    integer init_index;
    initial begin
        for (init_index = 0; init_index < MEMORY_DEPTH; init_index = init_index + 1)
            memory[init_index] = {DATA_WIDTH{1'b0}};
        o_read_data = {DATA_WIDTH{1'b0}};
    end

    always @(posedge i_clk) begin
        if (i_write_enable)
            memory[i_write_word_addr] <= i_write_data;

        // Si lee y escribe la misma direccion en el mismo ciclo, devuelve el dato viejo
        if (i_read_enable)
            o_read_data <= memory[i_read_word_addr];
    end

endmodule
