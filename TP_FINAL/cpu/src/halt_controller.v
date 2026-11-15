`timescale 1ns / 1ps
`include "done_reason_defs.vh"

// -----------------------------------------------------------------------------
// Fin de ejecucion: confirma HALT en EX, detiene la busqueda de instrucciones
// y declara done cuando el pipeline quedo vacio
// -----------------------------------------------------------------------------
module halt_controller #(
    parameter ADDR_WIDTH = 10          // ancho del indice de palabra de program_memory
) (
    input  wire                  i_clk,
    input  wire                  i_reset,           // reset sincrono (cpu_rst)
    input  wire                  i_enable,          // el CPU avanza en este ciclo

    // ---- Busqueda de instrucciones ------------------------------------------
    input  wire [31:0]           i_fetch_pc,        // PC que se busca en IF
    input  wire [ADDR_WIDTH:0]   i_n_words,         // largo de la imagen cargada

    // ---- Estado de cada etapa -----------------------------------------------
    input  wire                  i_if_id_valid,
    input  wire                  i_id_ex_valid,
    input  wire                  i_id_ex_is_halt,
    input  wire                  i_ex_mem_valid,
    input  wire                  i_mem_wb_valid,

    // ---- Resultado ----------------------------------------------------------
    output wire                  o_halt_commit,     // HALT valido en EX: hay que anular IF e ID
    output reg                   o_halting,         // HALT confirmado, se mantiene hasta el reset
    output wire                  o_fetch_stopped,   // IF no produce instrucciones validas
    output wire                  o_done,
    output wire [1:0]            o_done_reason      // ver done_reason_defs.vh
);

    // Valor inicial definido para que la simulacion no propague 'x'
    initial o_halting = 1'b0;

    // -------------------------------------------------------------------------
    // HALT: se confirma en EX
    // -------------------------------------------------------------------------
    // Una instruccion en ID todavia puede estar en el camino equivocado de un
    // branch que se resuelve en este mismo ciclo; en EX ya no puede ser descartada.
    assign o_halt_commit = i_id_ex_valid && i_id_ex_is_halt;

    // Solo cambia cuando el CPU avanza, igual que el flush que acompana al HALT
    always @(posedge i_clk) begin
        if (i_reset)
            o_halting <= 1'b0;
        else if (i_enable && o_halt_commit)
            o_halting <= 1'b1;
    end

    // -------------------------------------------------------------------------
    // Fin de la busqueda: HALT confirmado o PC fuera de la imagen cargada
    // -------------------------------------------------------------------------
    // El fin de imagen no es permanente: un branch o jump en EX puede devolver
    // el PC al interior de la imagen.
    wire pc_is_inside_image = (i_fetch_pc[31:2] < i_n_words);

    assign o_fetch_stopped = o_halting || !pc_is_inside_image;

    // -------------------------------------------------------------------------
    // Fin de la ejecucion: sin busqueda y sin instrucciones validas en vuelo
    // -------------------------------------------------------------------------
    wire pipeline_is_empty = !i_if_id_valid
                          && !i_id_ex_valid
                          && !i_ex_mem_valid
                          && !i_mem_wb_valid;

    assign o_done = o_fetch_stopped && pipeline_is_empty;

    // HALT tiene prioridad: si es la ultima palabra de la imagen, el PC tambien
    // queda fuera de ella
    assign o_done_reason = !o_done   ? `DONE_REASON_NONE :
                           o_halting ? `DONE_REASON_HALT :
                                       `DONE_REASON_END_OF_IMAGE;

endmodule
