`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Nucleo del CPU RISC-V segmentado en cinco etapas: IF - ID - EX - MEM - WB
// -----------------------------------------------------------------------------
module cpu_core #(
    parameter MEM_ADDR_WIDTH = 10          // ancho del indice de palabra de las memorias
) (
    input  wire                      i_clk,
    input  wire                      i_cpu_reset,
    input  wire                      i_cpu_en,

    // ---- Memoria de programa (lectura sincrona) -----------------------------
    output wire                      o_imem_read_enable,
    output wire [MEM_ADDR_WIDTH-1:0] o_imem_word_addr,
    input  wire [31:0]               i_imem_read_data,

    // ---- Memoria de datos (puerto A) ----------------------------------------
    output wire                      o_dmem_read_enable,
    output wire [MEM_ADDR_WIDTH-1:0] o_dmem_word_addr,
    output wire [3:0]                o_dmem_write_byte_enable,
    output wire [31:0]               o_dmem_write_data,
    input  wire [31:0]               i_dmem_read_data,

    // ---- Consulta de registros (solo lectura) -------------------------------
    input  wire [4:0]                i_debug_reg_addr,
    output wire [31:0]               o_debug_reg_data
);

    // Escritura de WB hacia el banco de registros (se asigna en la etapa WB)
    wire        wb_register_write_enable;
    wire [4:0]  wb_register_write_addr;
    wire [31:0] wb_register_write_data;


    // =========================================================================
    // IF - Instruction Fetch
    // =========================================================================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus_4 = if_pc + 32'd4;
    wire        if_is_valid  = 1'b1;       // US-4.3: dependera del fin de la imagen

    register #(.DATA_WIDTH(32)) program_counter (
        .i_clk    (i_clk),
        .i_reset  (i_cpu_reset),
        .i_enable (i_cpu_en),
        .i_data   (if_pc_plus_4),
        .o_data   (if_pc)
    );

    assign o_imem_read_enable = i_cpu_en;
    assign o_imem_word_addr   = if_pc[MEM_ADDR_WIDTH+1:2];

    // ---- Latch IF/ID --------------------------------------------------------
    wire        if_id_valid;
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instruction = i_imem_read_data;

    register_if_id if_id_latch (
        .i_clk    (i_clk),
        .i_reset  (i_cpu_reset),
        .i_enable (i_cpu_en),
        .i_valid  (if_is_valid),
        .i_pc     (if_pc),
        .o_valid  (if_id_valid),
        .o_pc     (if_id_pc)
    );


    // =========================================================================
    // ID - Instruction Decode
    // =========================================================================
    wire [4:0]  id_rs1_addr = if_id_instruction[19:15];
    wire [4:0]  id_rs2_addr = if_id_instruction[24:20];
    wire [4:0]  id_rd_addr  = if_id_instruction[11:7];
    wire [2:0]  id_funct3   = if_id_instruction[14:12];

    wire [3:0]  id_alu_op;
    wire        id_alu_src_b_is_imm;
    wire [2:0]  id_imm_type;
    wire        id_reg_write;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_is_branch;
    wire        id_is_jal;
    wire        id_is_jalr;
    wire        id_is_halt;
    wire        id_is_illegal;

    control_unit instruction_decoder (
        .i_instruction      (if_id_instruction),
        .o_alu_op           (id_alu_op),
        .o_alu_src_b_is_imm (id_alu_src_b_is_imm),
        .o_imm_type         (id_imm_type),
        .o_reg_write        (id_reg_write),
        .o_mem_read         (id_mem_read),
        .o_mem_write        (id_mem_write),
        .o_is_branch        (id_is_branch),
        .o_is_jal           (id_is_jal),
        .o_is_jalr          (id_is_jalr),
        .o_is_halt          (id_is_halt),
        .o_is_illegal       (id_is_illegal),
        .o_uses_rs1         (),            // US-3.2: deteccion de load-use
        .o_uses_rs2         ()
    );

    wire [31:0] id_immediate;

    immediate_generator immediate_gen (
        .i_instruction (if_id_instruction),
        .i_imm_type    (id_imm_type),
        .o_immediate   (id_immediate)
    );

    wire [31:0] id_rs1_value;
    wire [31:0] id_rs2_value;

    registers register_file (
        .i_clk             (i_clk),
        .i_reset           (i_cpu_reset),
        .i_cpu_en          (i_cpu_en),
        .i_read_addr_a     (id_rs1_addr),
        .i_read_addr_b     (id_rs2_addr),
        .o_read_data_a     (id_rs1_value),
        .o_read_data_b     (id_rs2_value),
        .i_write_enable    (wb_register_write_enable),
        .i_write_addr      (wb_register_write_addr),
        .i_write_data      (wb_register_write_data),
        .i_debug_read_addr (i_debug_reg_addr),
        .o_debug_read_data (o_debug_reg_data)
    );

    // ---- Latch ID/EX --------------------------------------------------------
    wire        id_ex_valid;
    wire [31:0] id_ex_pc;
    wire [31:0] id_ex_instruction;
    wire [31:0] id_ex_rs1_value;
    wire [31:0] id_ex_rs2_value;
    wire [31:0] id_ex_immediate;
    wire [4:0]  id_ex_rs1_addr;
    wire [4:0]  id_ex_rs2_addr;
    wire [4:0]  id_ex_rd_addr;
    wire [3:0]  id_ex_alu_op;
    wire        id_ex_alu_src_b_is_imm;
    wire        id_ex_reg_write;
    wire        id_ex_mem_read;
    wire        id_ex_mem_write;
    wire        id_ex_is_branch;
    wire        id_ex_is_jal;
    wire        id_ex_is_jalr;
    wire        id_ex_is_halt;
    wire        id_ex_is_illegal;
    wire [2:0]  id_ex_funct3;

    register_id_ex id_ex_latch (
        .i_clk              (i_clk),
        .i_reset            (i_cpu_reset),
        .i_enable           (i_cpu_en),
        .i_valid            (if_id_valid),
        .i_pc               (if_id_pc),
        .i_instruction      (if_id_instruction),
        .i_rs1_value        (id_rs1_value),
        .i_rs2_value        (id_rs2_value),
        .i_immediate        (id_immediate),
        .i_rs1_addr         (id_rs1_addr),
        .i_rs2_addr         (id_rs2_addr),
        .i_rd_addr          (id_rd_addr),
        .i_alu_op           (id_alu_op),
        .i_alu_src_b_is_imm (id_alu_src_b_is_imm),
        .i_reg_write        (id_reg_write),
        .i_mem_read         (id_mem_read),
        .i_mem_write        (id_mem_write),
        .i_is_branch        (id_is_branch),
        .i_is_jal           (id_is_jal),
        .i_is_jalr          (id_is_jalr),
        .i_is_halt          (id_is_halt),
        .i_is_illegal       (id_is_illegal),
        .i_funct3           (id_funct3),
        .o_valid            (id_ex_valid),
        .o_pc               (id_ex_pc),
        .o_instruction      (id_ex_instruction),
        .o_rs1_value        (id_ex_rs1_value),
        .o_rs2_value        (id_ex_rs2_value),
        .o_immediate        (id_ex_immediate),
        .o_rs1_addr         (id_ex_rs1_addr),
        .o_rs2_addr         (id_ex_rs2_addr),
        .o_rd_addr          (id_ex_rd_addr),
        .o_alu_op           (id_ex_alu_op),
        .o_alu_src_b_is_imm (id_ex_alu_src_b_is_imm),
        .o_reg_write        (id_ex_reg_write),
        .o_mem_read         (id_ex_mem_read),
        .o_mem_write        (id_ex_mem_write),
        .o_is_branch        (id_ex_is_branch),
        .o_is_jal           (id_ex_is_jal),
        .o_is_jalr          (id_ex_is_jalr),
        .o_is_halt          (id_ex_is_halt),
        .o_is_illegal       (id_ex_is_illegal),
        .o_funct3           (id_ex_funct3)
    );


    // =========================================================================
    // EX - Execute
    // =========================================================================
    wire [31:0] ex_alu_operand_b;
    wire [31:0] ex_alu_result;
    wire [31:0] ex_return_address = id_ex_pc + 32'd4;
    wire        ex_result_is_return_address = id_ex_is_jal || id_ex_is_jalr;
    wire [31:0] ex_result;

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(2)) alu_operand_b_mux (
        .i_inputs ({id_ex_immediate, id_ex_rs2_value}),
        .i_select (id_ex_alu_src_b_is_imm),
        .o_output (ex_alu_operand_b)
    );

    alu main_alu (
        .i_operand_a (id_ex_rs1_value),
        .i_operand_b (ex_alu_operand_b),
        .i_alu_op    (id_ex_alu_op),
        .o_result    (ex_alu_result)
    );

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(2)) ex_result_mux (
        .i_inputs ({ex_return_address, ex_alu_result}),
        .i_select (ex_result_is_return_address),
        .o_output (ex_result)
    );

    // ---- Latch EX/MEM -------------------------------------------------------
    wire        ex_mem_valid;
    wire [31:0] ex_mem_pc;
    wire [31:0] ex_mem_instruction;
    wire [31:0] ex_mem_result;
    wire [31:0] ex_mem_store_data;
    wire [4:0]  ex_mem_rd_addr;
    wire        ex_mem_reg_write;
    wire        ex_mem_mem_read;
    wire        ex_mem_mem_write;
    wire [2:0]  ex_mem_funct3;

    register_ex_mem ex_mem_latch (
        .i_clk         (i_clk),
        .i_reset       (i_cpu_reset),
        .i_enable      (i_cpu_en),
        .i_valid       (id_ex_valid),
        .i_pc          (id_ex_pc),
        .i_instruction (id_ex_instruction),
        .i_result      (ex_result),
        .i_store_data  (id_ex_rs2_value),
        .i_rd_addr     (id_ex_rd_addr),
        .i_reg_write   (id_ex_reg_write),
        .i_mem_read    (id_ex_mem_read),
        .i_mem_write   (id_ex_mem_write),
        .i_funct3      (id_ex_funct3),
        .o_valid       (ex_mem_valid),
        .o_pc          (ex_mem_pc),
        .o_instruction (ex_mem_instruction),
        .o_result      (ex_mem_result),
        .o_store_data  (ex_mem_store_data),
        .o_rd_addr     (ex_mem_rd_addr),
        .o_reg_write   (ex_mem_reg_write),
        .o_mem_read    (ex_mem_mem_read),
        .o_mem_write   (ex_mem_mem_write),
        .o_funct3      (ex_mem_funct3)
    );


    // =========================================================================
    // MEM - Memory Access
    // =========================================================================
    wire mem_has_access = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
    wire mem_access_is_out_of_range;

    data_access_checker #(.ADDR_WIDTH(MEM_ADDR_WIDTH)) access_checker (
        .i_access_valid    (mem_has_access),
        .i_funct3          (ex_mem_funct3),
        .i_byte_address    (ex_mem_result),
        .o_is_out_of_range (mem_access_is_out_of_range),
        .o_is_misaligned   ()              // E5: flag sticky de GET_STATUS
    );

    // El store solo se escribe si el CPU avanza, es valido y esta en rango
    wire mem_store_is_enabled = i_cpu_en && !i_cpu_reset
                             && ex_mem_valid && ex_mem_mem_write
                             && !mem_access_is_out_of_range;

    store_data_formatter store_formatter (
        .i_mem_write         (mem_store_is_enabled),
        .i_funct3            (ex_mem_funct3),
        .i_byte_offset       (ex_mem_result[1:0]),
        .i_store_data        (ex_mem_store_data),
        .o_write_byte_enable (o_dmem_write_byte_enable),
        .o_write_data        (o_dmem_write_data)
    );

    assign o_dmem_read_enable = i_cpu_en;
    assign o_dmem_word_addr   = ex_mem_result[MEM_ADDR_WIDTH+1:2];

    // ---- Latch MEM/WB -------------------------------------------------------
    wire        mem_wb_valid;
    wire [31:0] mem_wb_pc;
    wire [31:0] mem_wb_instruction;
    wire [31:0] mem_wb_result;
    wire [4:0]  mem_wb_rd_addr;
    wire        mem_wb_reg_write;
    wire        mem_wb_mem_read;
    wire        mem_wb_mem_write;
    wire [2:0]  mem_wb_funct3;
    wire        mem_wb_access_out_of_range;
    wire [31:0] mem_wb_raw_data = i_dmem_read_data;

    register_mem_wb mem_wb_latch (
        .i_clk                 (i_clk),
        .i_reset               (i_cpu_reset),
        .i_enable              (i_cpu_en),
        .i_valid               (ex_mem_valid),
        .i_pc                  (ex_mem_pc),
        .i_instruction         (ex_mem_instruction),
        .i_result              (ex_mem_result),
        .i_rd_addr             (ex_mem_rd_addr),
        .i_reg_write           (ex_mem_reg_write),
        .i_mem_read            (ex_mem_mem_read),
        .i_mem_write           (ex_mem_mem_write),
        .i_funct3              (ex_mem_funct3),
        .i_access_out_of_range (mem_access_is_out_of_range),
        .o_valid               (mem_wb_valid),
        .o_pc                  (mem_wb_pc),
        .o_instruction         (mem_wb_instruction),
        .o_result              (mem_wb_result),
        .o_rd_addr             (mem_wb_rd_addr),
        .o_reg_write           (mem_wb_reg_write),
        .o_mem_read            (mem_wb_mem_read),
        .o_mem_write           (mem_wb_mem_write),
        .o_funct3              (mem_wb_funct3),
        .o_access_out_of_range (mem_wb_access_out_of_range)
    );


    // =========================================================================
    // WB - Write Back
    // =========================================================================
    wire [31:0] wb_extended_load_data;
    wire [31:0] wb_load_data = mem_wb_access_out_of_range ? 32'b0 : wb_extended_load_data;

    load_data_extender load_extender (
        .i_funct3      (mem_wb_funct3),
        .i_byte_offset (mem_wb_result[1:0]),
        .i_raw_word    (mem_wb_raw_data),
        .o_load_data   (wb_extended_load_data)
    );

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(2)) wb_data_mux (
        .i_inputs ({wb_load_data, mem_wb_result}),
        .i_select (mem_wb_mem_read),
        .o_output (wb_register_write_data)
    );

    assign wb_register_write_enable = mem_wb_valid && mem_wb_reg_write;
    assign wb_register_write_addr   = mem_wb_rd_addr;

endmodule
