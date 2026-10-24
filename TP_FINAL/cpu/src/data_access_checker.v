`timescale 1ns / 1ps
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Chequeo de un acceso a datos (etapa MEM): rango y alineacion
// -----------------------------------------------------------------------------
module data_access_checker #(
    parameter ADDR_WIDTH = 10          // ancho del indice de palabra de data_memory
) (
    input  wire        i_access_valid, // hay un load o store valido en MEM
    input  wire [2:0]  i_funct3,       // tamano del acceso (byte, media palabra, palabra)
    input  wire [31:0] i_byte_address, // direccion efectiva en bytes

    output wire        o_is_out_of_range,
    output wire        o_is_misaligned
);

    localparam BYTE_ADDR_WIDTH = ADDR_WIDTH + 2;

    // ---- Rango: todos los bits altos de la direccion deben ser cero ---------
    wire address_is_in_range = (i_byte_address[31:BYTE_ADDR_WIDTH] == 0);

    // ---- Alineacion segun el tamano del acceso ------------------------------
    reg access_is_aligned;

    always @(*) begin
        case (i_funct3)
            `FUNCT3_HALF, `FUNCT3_HALF_U: access_is_aligned = (i_byte_address[0]   == 1'b0);
            `FUNCT3_WORD:                 access_is_aligned = (i_byte_address[1:0] == 2'b00);
            default:                      access_is_aligned = 1'b1;   // byte
        endcase
    end

    // ---- Solo se senalan accesos validos (una burbuja nunca activa flags) ---
    assign o_is_out_of_range = i_access_valid && !address_is_in_range;
    assign o_is_misaligned   = i_access_valid && !access_is_aligned;

endmodule