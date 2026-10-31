`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Deteccion de riesgos de datos que el forwarding no puede resolver (load-use)
// -----------------------------------------------------------------------------
module hazard_unit (
    // ---- Instruccion en ID --------------------------------------------------
    input  wire       i_if_id_valid,
    input  wire [4:0] i_id_rs1_addr,
    input  wire [4:0] i_id_rs2_addr,
    input  wire       i_id_uses_rs1,     // rs1 es una fuente real, no un campo de inmediato
    input  wire       i_id_uses_rs2,

    // ---- Instruccion en EX --------------------------------------------------
    input  wire       i_id_ex_valid,
    input  wire       i_id_ex_mem_read,
    input  wire [4:0] i_id_ex_rd_addr,

    output wire       o_stall
);

    localparam [4:0] ZERO_REG_ADDR = 5'b00000;

    wire load_in_ex_writes_register = i_id_ex_valid
                                   && i_id_ex_mem_read
                                   && (i_id_ex_rd_addr != ZERO_REG_ADDR);

    wire rs1_depends_on_load = i_id_uses_rs1 && (i_id_rs1_addr == i_id_ex_rd_addr);
    wire rs2_depends_on_load = i_id_uses_rs2 && (i_id_rs2_addr == i_id_ex_rd_addr);

    assign o_stall = i_if_id_valid
                  && load_in_ex_writes_register
                  && (rs1_depends_on_load || rs2_depends_on_load);

endmodule
