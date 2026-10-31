`timescale 1ns / 1ps
`include "forwarding_defs.vh"

// -----------------------------------------------------------------------------
// Forwarding hacia la etapa EX
// -----------------------------------------------------------------------------
module forwarding_unit (
    // ---- Fuentes de la instruccion que esta en EX ---------------------------
    input  wire [4:0] i_id_ex_rs1_addr,
    input  wire [4:0] i_id_ex_rs2_addr,

    // ---- Instruccion en MEM (latch EX/MEM) ----------------------------------
    input  wire       i_ex_mem_valid,
    input  wire       i_ex_mem_reg_write,
    input  wire       i_ex_mem_mem_read,
    input  wire [4:0] i_ex_mem_rd_addr,

    // ---- Instruccion en WB (latch MEM/WB) -----------------------------------
    input  wire       i_mem_wb_valid,
    input  wire       i_mem_wb_reg_write,
    input  wire [4:0] i_mem_wb_rd_addr,

    output wire [1:0] o_forward_a_select,   // operando rs1
    output wire [1:0] o_forward_b_select    // operando rs2
);

    localparam [4:0] ZERO_REG_ADDR = 5'b00000;

    // -------------------------------------------------------------------------
    // Que etapas pueden entregar un dato
    // -------------------------------------------------------------------------
    // EX/MEM: un load todavia no tiene su dato, el resultado es solo la direccion
    wire ex_mem_can_forward = i_ex_mem_valid
                           && i_ex_mem_reg_write
                           && !i_ex_mem_mem_read
                           && (i_ex_mem_rd_addr != ZERO_REG_ADDR);

    wire mem_wb_can_forward = i_mem_wb_valid
                           && i_mem_wb_reg_write
                           && (i_mem_wb_rd_addr != ZERO_REG_ADDR);

    // -------------------------------------------------------------------------
    // Coincidencia con cada operando
    // -------------------------------------------------------------------------
    wire a_matches_ex_mem = ex_mem_can_forward && (i_ex_mem_rd_addr == i_id_ex_rs1_addr);
    wire a_matches_mem_wb = mem_wb_can_forward && (i_mem_wb_rd_addr == i_id_ex_rs1_addr);

    wire b_matches_ex_mem = ex_mem_can_forward && (i_ex_mem_rd_addr == i_id_ex_rs2_addr);
    wire b_matches_mem_wb = mem_wb_can_forward && (i_mem_wb_rd_addr == i_id_ex_rs2_addr);

    // -------------------------------------------------------------------------
    // Seleccion: gana la instruccion mas reciente (EX/MEM antes que MEM/WB)
    // -------------------------------------------------------------------------
    assign o_forward_a_select = a_matches_ex_mem ? `FORWARD_FROM_EX_MEM :
                                a_matches_mem_wb ? `FORWARD_FROM_MEM_WB :
                                                   `FORWARD_NONE;

    assign o_forward_b_select = b_matches_ex_mem ? `FORWARD_FROM_EX_MEM :
                                b_matches_mem_wb ? `FORWARD_FROM_MEM_WB :
                                                   `FORWARD_NONE;

endmodule
