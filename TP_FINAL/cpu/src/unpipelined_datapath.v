`timescale 1ns / 1ps
`include "riscv_defs.vh"

// -----------------------------------------------------------------------------
// Datapath no segmentado de referencia
// -----------------------------------------------------------------------------
module unpipelined_datapath #(
    parameter ADDR_WIDTH = 10          // ancho del indice de palabra de las memorias
) (
    input  wire                  i_clk,
    input  wire                  i_reset,                  // reset sincrono (cpu_rst)
    input  wire                  i_cpu_en,                 // habilita el avance del CPU

    // ---- Carga de programa (Debug Unit) -------------------------------------
    input  wire                  i_program_write_enable,
    input  wire [ADDR_WIDTH-1:0] i_program_write_word_addr,
    input  wire [31:0]           i_program_write_data,

    // ---- Consultas de debug (solo lectura) ----------------------------------
    input  wire [4:0]            i_debug_register_addr,
    output wire [31:0]           o_debug_register_data,
    input  wire [ADDR_WIDTH-1:0] i_debug_data_word_addr,
    output wire [31:0]           o_debug_data_word,

    // ---- Estado observable --------------------------------------------------
    output wire [31:0]           o_pc,
    output wire [31:0]           o_instruction,
    output wire                  o_halted,                 // la instruccion actual es HALT
    output wire                  o_instruction_retired,    // la instruccion actual termina en este ciclo
    output wire                  o_illegal_instruction,
    output wire                  o_data_out_of_range,
    output wire                  o_data_misaligned
);

    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------
    localparam [31:0] RESET_PC               = 32'd0;
    localparam [31:0] INSTRUCTION_SIZE_BYTES = 32'd4;

    // Entradas de los multiplexores (posicion dentro del bus i_inputs)
    localparam [1:0] NEXT_PC_SEQUENTIAL = 2'd0;   // pc + 4
    localparam [1:0] NEXT_PC_RELATIVE   = 2'd1;   // pc + inmediato (branch, jal)
    localparam [1:0] NEXT_PC_JALR       = 2'd2;   // rs1 + inmediato

    localparam [1:0] WRITEBACK_ALU      = 2'd0;
    localparam [1:0] WRITEBACK_LOAD     = 2'd1;
    localparam [1:0] WRITEBACK_PC_PLUS4 = 2'd2;

    // -------------------------------------------------------------------------
    // Senales compartidas entre secciones
    // -------------------------------------------------------------------------
    wire [31:0] pc;
    wire [31:0] next_pc;
    wire [31:0] instruction;
    wire        advance_enable;    // el PC avanza y la instruccion actual termina

    // -------------------------------------------------------------------------
    // Campos de la instruccion
    // -------------------------------------------------------------------------
    wire [4:0] rs1_addr = instruction[19:15];
    wire [4:0] rs2_addr = instruction[24:20];
    wire [4:0] rd_addr  = instruction[11:7];
    wire [2:0] funct3   = instruction[14:12];

    // -------------------------------------------------------------------------
    // Decodificacion
    // -------------------------------------------------------------------------
    wire [3:0] alu_op;
    wire       alu_src_b_is_imm;
    wire [2:0] imm_type;
    wire       reg_write;
    wire       is_load;
    wire       is_store;
    wire       is_branch;
    wire       is_jal;
    wire       is_jalr;
    wire       is_halt;
    wire       is_illegal;

    control_unit control_unit_inst (
        .i_instruction      (instruction),
        .o_alu_op           (alu_op),
        .o_alu_src_b_is_imm (alu_src_b_is_imm),
        .o_imm_type         (imm_type),
        .o_reg_write        (reg_write),
        .o_mem_read         (is_load),
        .o_mem_write        (is_store),
        .o_is_branch        (is_branch),
        .o_is_jal           (is_jal),
        .o_is_jalr          (is_jalr),
        .o_is_halt          (is_halt),
        .o_is_illegal       (is_illegal),
        .o_uses_rs1         (),
        .o_uses_rs2         ()
    );

    // -------------------------------------------------------------------------
    // Control de avance: un load ocupa dos ciclos, HALT congela el CPU
    // -------------------------------------------------------------------------
    wire load_data_is_ready;
    wire load_needs_extra_cycle = is_load && !load_data_is_ready;

    register #(.DATA_WIDTH(1)) load_wait_register (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_enable (i_cpu_en),
        .i_data   (load_needs_extra_cycle),
        .o_data   (load_data_is_ready)
    );

    wire instruction_completes = !is_halt && !load_needs_extra_cycle;

    assign advance_enable = i_cpu_en && instruction_completes;

    // -------------------------------------------------------------------------
    // IF: PC y memoria de programa
    // -------------------------------------------------------------------------
    register #(.DATA_WIDTH(32), .RESET_VALUE(RESET_PC)) pc_register (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_enable (advance_enable),
        .i_data   (next_pc),
        .o_data   (pc)
    );

    wire [ADDR_WIDTH-1:0] fetch_word_addr = i_reset ? RESET_PC[ADDR_WIDTH+1:2]
                                                    : next_pc[ADDR_WIDTH+1:2];

    program_memory #(.ADDR_WIDTH(ADDR_WIDTH)) program_memory_inst (
        .i_clk             (i_clk),
        .i_read_enable     (i_reset || advance_enable),
        .i_read_word_addr  (fetch_word_addr),
        .o_read_data       (instruction),
        .i_write_enable    (i_program_write_enable),
        .i_write_word_addr (i_program_write_word_addr),
        .i_write_data      (i_program_write_data)
    );

    // -------------------------------------------------------------------------
    // ID: banco de registros e inmediato
    // -------------------------------------------------------------------------
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] writeback_data;

    registers #(.BYPASS_ENABLE(0)) register_file (
        .i_clk             (i_clk),
        .i_reset           (i_reset),
        .i_cpu_en          (i_cpu_en),
        .i_read_addr_a     (rs1_addr),
        .i_read_addr_b     (rs2_addr),
        .o_read_data_a     (rs1_data),
        .o_read_data_b     (rs2_data),
        .i_write_enable    (reg_write && instruction_completes),
        .i_write_addr      (rd_addr),
        .i_write_data      (writeback_data),
        .i_debug_read_addr (i_debug_register_addr),
        .o_debug_read_data (o_debug_register_data)
    );

    wire [31:0] immediate;

    immediate_generator immediate_generator_inst (
        .i_instruction (instruction),
        .i_imm_type    (imm_type),
        .o_immediate   (immediate)
    );

    // -------------------------------------------------------------------------
    // EX: ALU
    // -------------------------------------------------------------------------
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(2)) alu_operand_b_mux (
        .i_inputs ({immediate, rs2_data}),
        .i_select (alu_src_b_is_imm),
        .o_output (alu_operand_b)
    );

    alu alu_inst (
        .i_operand_a (rs1_data),
        .i_operand_b (alu_operand_b),
        .i_alu_op    (alu_op),
        .o_result    (alu_result)
    );

    // -------------------------------------------------------------------------
    // Siguiente PC: secuencial, branch/jal o jalr
    // -------------------------------------------------------------------------
    wire operands_are_equal   = (rs1_data == rs2_data);
    wire branch_condition_met = (funct3 == `FUNCT3_BNE) ? !operands_are_equal
                                                        :  operands_are_equal;
    wire branch_is_taken      = is_branch && branch_condition_met;

    wire [31:0] pc_plus_4         = pc + INSTRUCTION_SIZE_BYTES;
    wire [31:0] pc_plus_immediate = pc + immediate;
    wire [31:0] jalr_target       = {alu_result[31:1], 1'b0};

    wire [1:0] next_pc_select = is_jalr                   ? NEXT_PC_JALR
                              : (is_jal || branch_is_taken) ? NEXT_PC_RELATIVE
                              :                             NEXT_PC_SEQUENTIAL;

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(3)) next_pc_mux (
        .i_inputs ({jalr_target, pc_plus_immediate, pc_plus_4}),
        .i_select (next_pc_select),
        .o_output (next_pc)
    );

    // -------------------------------------------------------------------------
    // MEM: acceso a la memoria de datos
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] data_word_addr = alu_result[ADDR_WIDTH+1:2];
    wire [1:0]            byte_offset    = alu_result[1:0];

    data_access_checker #(.ADDR_WIDTH(ADDR_WIDTH)) data_access_checker_inst (
        .i_access_valid    (is_load || is_store),
        .i_funct3          (funct3),
        .i_byte_address    (alu_result),
        .o_is_out_of_range (o_data_out_of_range),
        .o_is_misaligned   (o_data_misaligned)
    );

    // Un store fuera de rango se suprime; solo escribe si el CPU avanza
    wire store_is_effective = is_store && i_cpu_en && !o_data_out_of_range;

    wire [3:0]  write_byte_enable;
    wire [31:0] write_data;

    store_data_formatter store_data_formatter_inst (
        .i_mem_write          (store_is_effective),
        .i_funct3             (funct3),
        .i_byte_offset        (byte_offset),
        .i_store_data         (rs2_data),
        .o_write_byte_enable  (write_byte_enable),
        .o_write_data         (write_data)
    );

    wire [31:0] raw_read_word;

    data_memory #(.ADDR_WIDTH(ADDR_WIDTH)) data_memory_inst (
        .i_clk               (i_clk),
        .i_read_enable       (is_load && i_cpu_en),
        .i_word_addr         (data_word_addr),
        .i_write_byte_enable (write_byte_enable),
        .i_write_data        (write_data),
        .o_read_data         (raw_read_word),
        .i_debug_word_addr   (i_debug_data_word_addr),
        .o_debug_read_data   (o_debug_data_word)
    );

    // -------------------------------------------------------------------------
    // WB: seleccion del resultado que se escribe en rd
    // -------------------------------------------------------------------------
    wire [31:0] extended_load_data;

    load_data_extender load_data_extender_inst (
        .i_funct3      (funct3),
        .i_byte_offset (byte_offset),
        .i_raw_word    (raw_read_word),
        .o_load_data   (extended_load_data)
    );

    // Un load fuera de rango devuelve cero
    wire [31:0] load_data = o_data_out_of_range ? 32'b0 : extended_load_data;

    wire [1:0] writeback_select = (is_jal || is_jalr) ? WRITEBACK_PC_PLUS4
                                : is_load             ? WRITEBACK_LOAD
                                :                       WRITEBACK_ALU;

    mux #(.DATA_WIDTH(32), .INPUT_COUNT(3)) writeback_mux (
        .i_inputs ({pc_plus_4, load_data, alu_result}),
        .i_select (writeback_select),
        .o_output (writeback_data)
    );

    // -------------------------------------------------------------------------
    // Estado observable
    // -------------------------------------------------------------------------
    assign o_pc                  = pc;
    assign o_instruction         = instruction;
    assign o_halted              = is_halt;
    assign o_instruction_retired = advance_enable;
    assign o_illegal_instruction = is_illegal;

endmodule
