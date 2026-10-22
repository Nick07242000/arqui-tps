`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Memoria de datos: 1024 palabras de 32 bits
// -----------------------------------------------------------------------------
module data_memory #(
    parameter ADDR_WIDTH = 10
) (
    input  wire                    i_clk,

    // Puerto A (CPU, etapa MEM)
    input  wire                    i_read_enable,
    input  wire [ADDR_WIDTH-1:0]   i_word_addr,
    input  wire [3:0]              i_write_byte_enable,
    input  wire [31:0]             i_write_data,
    output wire [31:0]             o_read_data,

    // Puerto B (Debug Unit)
    input  wire [ADDR_WIDTH-1:0]   i_debug_word_addr,
    output wire [31:0]             o_debug_read_data
);

    localparam MEMORY_DEPTH = 1 << ADDR_WIDTH;
    localparam BYTE_LANES   = 4;

    genvar lane;
    generate
        for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin : byte_bank
            reg [7:0] bank [0:MEMORY_DEPTH-1];
            reg [7:0] cpu_read_byte;
            reg [7:0] debug_read_byte;

            integer init_index;
            initial begin
                for (init_index = 0; init_index < MEMORY_DEPTH; init_index = init_index + 1)
                    bank[init_index] = 8'h00;
                cpu_read_byte   = 8'h00;
                debug_read_byte = 8'h00;
            end

            always @(posedge i_clk) begin
                if (i_write_byte_enable[lane])
                    bank[i_word_addr] <= i_write_data[8*lane +: 8];

                if (i_read_enable)
                    cpu_read_byte <= bank[i_word_addr];

                debug_read_byte <= bank[i_debug_word_addr];
            end

            assign o_read_data[8*lane +: 8]       = cpu_read_byte;
            assign o_debug_read_data[8*lane +: 8] = debug_read_byte;
        end
    endgenerate

endmodule
