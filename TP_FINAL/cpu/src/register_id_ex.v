`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Latch ID/EX
// -----------------------------------------------------------------------------
module register_id_ex (
    input  wire        i_clk,
    input  wire        i_reset,          // reset sincrono: deja el latch vacio
    input  wire        i_enable,         // captura solo cuando el CPU avanza

    // ---- Identificacion de la instruccion -----------------------------------
    input  wire        i_valid,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_instruction,

    // ---- Datos --------------------------------------------------------------
    input  wire [31:0] i_rs1_value,
    input  wire [31:0] i_rs2_value,
    input  wire [31:0] i_immediate,
    input  wire [4:0]  i_rs1_addr,
    input  wire [4:0]  i_rs2_addr,
    input  wire [4:0]  i_rd_addr,

    // ---- Controles ----------------------------------------------------------
    input  wire [3:0]  i_alu_op,
    input  wire        i_alu_src_b_is_imm,
    input  wire        i_reg_write,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire        i_is_branch,
    input  wire        i_is_jal,
    input  wire        i_is_jalr,
    input  wire        i_is_halt,
    input  wire        i_is_illegal,
    input  wire [2:0]  i_funct3,

    output reg         o_valid,
    output reg  [31:0] o_pc,
    output reg  [31:0] o_instruction,

    output reg  [31:0] o_rs1_value,
    output reg  [31:0] o_rs2_value,
    output reg  [31:0] o_immediate,
    output reg  [4:0]  o_rs1_addr,
    output reg  [4:0]  o_rs2_addr,
    output reg  [4:0]  o_rd_addr,

    output reg  [3:0]  o_alu_op,
    output reg         o_alu_src_b_is_imm,
    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg         o_is_branch,
    output reg         o_is_jal,
    output reg         o_is_jalr,
    output reg         o_is_halt,
    output reg         o_is_illegal,
    output reg  [2:0]  o_funct3
);

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_valid            <= 1'b0;
            o_pc               <= 32'b0;
            o_instruction      <= 32'b0;
            o_rs1_value        <= 32'b0;
            o_rs2_value        <= 32'b0;
            o_immediate        <= 32'b0;
            o_rs1_addr         <= 5'b0;
            o_rs2_addr         <= 5'b0;
            o_rd_addr          <= 5'b0;
            o_alu_op           <= 4'b0;
            o_alu_src_b_is_imm <= 1'b0;
            o_reg_write        <= 1'b0;
            o_mem_read         <= 1'b0;
            o_mem_write        <= 1'b0;
            o_is_branch        <= 1'b0;
            o_is_jal           <= 1'b0;
            o_is_jalr          <= 1'b0;
            o_is_halt          <= 1'b0;
            o_is_illegal       <= 1'b0;
            o_funct3           <= 3'b0;
        end else if (i_enable) begin
            o_valid            <= i_valid;
            o_pc               <= i_pc;
            o_instruction      <= i_instruction;
            o_rs1_value        <= i_rs1_value;
            o_rs2_value        <= i_rs2_value;
            o_immediate        <= i_immediate;
            o_rs1_addr         <= i_rs1_addr;
            o_rs2_addr         <= i_rs2_addr;
            o_rd_addr          <= i_rd_addr;
            o_alu_op           <= i_alu_op;
            o_alu_src_b_is_imm <= i_alu_src_b_is_imm;
            o_reg_write        <= i_reg_write;
            o_mem_read         <= i_mem_read;
            o_mem_write        <= i_mem_write;
            o_is_branch        <= i_is_branch;
            o_is_jal           <= i_is_jal;
            o_is_jalr          <= i_is_jalr;
            o_is_halt          <= i_is_halt;
            o_is_illegal       <= i_is_illegal;
            o_funct3           <= i_funct3;
        end
    end

endmodule
