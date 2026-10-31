`timescale 1ns / 1ps

module tb_cpu_core;

    localparam MEM_ADDR_WIDTH    = 10;
    localparam MAX_PROGRAM_WORDS = 64;

    // ---- Reloj y control ----------------------------------------------------
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg cpu_reset = 1'b0;
    reg cpu_en    = 1'b0;

    // ---- Conexion CPU <-> memorias ------------------------------------------
    wire                      imem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] imem_word_addr;
    wire [31:0]               imem_read_data;
    reg                       imem_write_enable = 1'b0;
    reg  [MEM_ADDR_WIDTH-1:0] imem_write_addr   = {MEM_ADDR_WIDTH{1'b0}};
    reg  [31:0]               imem_write_data   = 32'b0;

    wire                      dmem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] dmem_word_addr;
    wire [3:0]                dmem_write_byte_enable;
    wire [31:0]               dmem_write_data;
    wire [31:0]               dmem_read_data;
    reg  [MEM_ADDR_WIDTH-1:0] dmem_debug_word_addr = {MEM_ADDR_WIDTH{1'b0}};
    wire [31:0]               dmem_debug_read_data;

    reg  [4:0]                debug_reg_addr = 5'b0;
    wire [31:0]               debug_reg_data;

    program_memory #(.ADDR_WIDTH(MEM_ADDR_WIDTH)) imem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_addr),
        .i_write_data      (imem_write_data)
    );

    data_memory #(.ADDR_WIDTH(MEM_ADDR_WIDTH)) dmem (
        .i_clk                (clk),
        .i_read_enable        (dmem_read_enable),
        .i_word_addr          (dmem_word_addr),
        .i_write_byte_enable  (dmem_write_byte_enable),
        .i_write_data         (dmem_write_data),
        .o_read_data          (dmem_read_data),
        .i_debug_word_addr    (dmem_debug_word_addr),
        .o_debug_read_data    (dmem_debug_read_data)
    );

    cpu_core #(.MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)) dut (
        .i_clk                    (clk),
        .i_cpu_reset              (cpu_reset),
        .i_cpu_en                 (cpu_en),
        .o_imem_read_enable       (imem_read_enable),
        .o_imem_word_addr         (imem_word_addr),
        .i_imem_read_data         (imem_read_data),
        .o_dmem_read_enable       (dmem_read_enable),
        .o_dmem_word_addr         (dmem_word_addr),
        .o_dmem_write_byte_enable (dmem_write_byte_enable),
        .o_dmem_write_data        (dmem_write_data),
        .i_dmem_read_data         (dmem_read_data),
        .i_debug_reg_addr         (debug_reg_addr),
        .o_debug_reg_data         (debug_reg_data)
    );

    // ---- Decodificadores de referencia (re-decodifican la instruccion de cada latch)
    wire [3:0] ref_ex_alu_op;
    wire       ref_ex_alu_src_b_is_imm;
    wire       ref_ex_reg_write,  ref_ex_mem_read,  ref_ex_mem_write;
    wire       ref_ex_is_branch,  ref_ex_is_jal,    ref_ex_is_jalr;
    wire       ref_ex_is_halt,    ref_ex_is_illegal;
    wire       ref_mem_reg_write, ref_mem_mem_read, ref_mem_mem_write;
    wire       ref_wb_reg_write,  ref_wb_mem_read,  ref_wb_mem_write;

    control_unit ref_decoder_ex (
        .i_instruction      (dut.id_ex_instruction),
        .o_alu_op           (ref_ex_alu_op),
        .o_alu_src_b_is_imm (ref_ex_alu_src_b_is_imm),
        .o_imm_type         (),
        .o_reg_write        (ref_ex_reg_write),
        .o_mem_read         (ref_ex_mem_read),
        .o_mem_write        (ref_ex_mem_write),
        .o_is_branch        (ref_ex_is_branch),
        .o_is_jal           (ref_ex_is_jal),
        .o_is_jalr          (ref_ex_is_jalr),
        .o_is_halt          (ref_ex_is_halt),
        .o_is_illegal       (ref_ex_is_illegal),
        .o_uses_rs1         (),
        .o_uses_rs2         ()
    );

    control_unit ref_decoder_mem (
        .i_instruction      (dut.ex_mem_instruction),
        .o_alu_op           (),
        .o_alu_src_b_is_imm (),
        .o_imm_type         (),
        .o_reg_write        (ref_mem_reg_write),
        .o_mem_read         (ref_mem_mem_read),
        .o_mem_write        (ref_mem_mem_write),
        .o_is_branch        (),
        .o_is_jal           (),
        .o_is_jalr          (),
        .o_is_halt          (),
        .o_is_illegal       (),
        .o_uses_rs1         (),
        .o_uses_rs2         ()
    );

    control_unit ref_decoder_wb (
        .i_instruction      (dut.mem_wb_instruction),
        .o_alu_op           (),
        .o_alu_src_b_is_imm (),
        .o_imm_type         (),
        .o_reg_write        (ref_wb_reg_write),
        .o_mem_read         (ref_wb_mem_read),
        .o_mem_write        (ref_wb_mem_write),
        .o_is_branch        (),
        .o_is_jal           (),
        .o_is_jalr          (),
        .o_is_halt          (),
        .o_is_illegal       (),
        .o_uses_rs1         (),
        .o_uses_rs2         ()
    );


    // =========================================================================
    // Programa, resultados esperados y contadores
    // =========================================================================
    reg [31:0] program_image [0:MAX_PROGRAM_WORDS-1];
    integer    program_length;

    reg [31:0] expected_register [0:31];
    reg [31:0] expected_memory   [0:3];
    integer    expected_memory_words;
    integer    expected_register_writes;
    integer    expected_stores;

    integer register_writes_per_instruction [0:MAX_PROGRAM_WORDS-1];
    integer stores_per_instruction          [0:MAX_PROGRAM_WORDS-1];
    integer total_register_writes;
    integer total_stores;

    integer current_step;
    integer error_count;


    // =========================================================================
    // Monitores: una escritura efectiva por flanco de reloj
    // =========================================================================
    always @(posedge clk) begin
        if (!cpu_reset && cpu_en
            && dut.wb_register_write_enable && dut.wb_register_write_addr != 5'd0) begin
            total_register_writes = total_register_writes + 1;
            register_writes_per_instruction[dut.mem_wb_pc[7:2]] =
                register_writes_per_instruction[dut.mem_wb_pc[7:2]] + 1;
        end

        if (!cpu_reset && dmem_write_byte_enable != 4'b0000) begin
            total_stores = total_stores + 1;
            stores_per_instruction[dut.ex_mem_pc[7:2]] =
                stores_per_instruction[dut.ex_mem_pc[7:2]] + 1;
        end
    end


    // =========================================================================
    // Utilidades de verificacion
    // =========================================================================
    task check_true(input condition, input [8*56-1:0] description);
        begin
            if (!condition) begin
                error_count = error_count + 1;
                $display("  [FAIL] paso %0d: %0s", current_step, description);
            end
        end
    endtask

    task check_equal(input [8*40-1:0] description, input [31:0] observed, input [31:0] expected);
        begin
            if (observed !== expected) begin
                error_count = error_count + 1;
                $display("  [FAIL] paso %0d: %0s = 0x%08h, esperado 0x%08h",
                         current_step, description, observed, expected);
            end
        end
    endtask

    task read_register(input [4:0] register_index, output [31:0] register_value);
        begin
            debug_reg_addr = register_index;
            #1 register_value = debug_reg_data;
        end
    endtask

    task read_data_memory_word(input [MEM_ADDR_WIDTH-1:0] word_index, output [31:0] word_value);
        begin
            @(negedge clk);
            dmem_debug_word_addr = word_index;
            @(negedge clk);
            word_value = dmem_debug_read_data;
        end
    endtask


    // =========================================================================
    // Carga del programa y reset (el testbench hace de Debug Unit)
    // =========================================================================
    task clear_program_image;
        integer word_index;
        begin
            for (word_index = 0; word_index < MAX_PROGRAM_WORDS; word_index = word_index + 1)
                program_image[word_index] = 32'b0;
        end
    endtask

    task write_program_image_to_memory;
        integer word_index;
        begin
            for (word_index = 0; word_index < MAX_PROGRAM_WORDS; word_index = word_index + 1) begin
                @(negedge clk);
                imem_write_enable = 1'b1;
                imem_write_addr   = word_index;
                imem_write_data   = program_image[word_index];
            end
            @(negedge clk);
            imem_write_enable = 1'b0;
        end
    endtask

    task reset_cpu;
        begin
            @(negedge clk);
            cpu_en    = 1'b0;
            cpu_reset = 1'b1;
            @(negedge clk);
            @(negedge clk);
            cpu_reset = 1'b0;
        end
    endtask

    task clear_event_counters;
        integer word_index;
        begin
            total_register_writes = 0;
            total_stores          = 0;
            for (word_index = 0; word_index < MAX_PROGRAM_WORDS; word_index = word_index + 1) begin
                register_writes_per_instruction[word_index] = 0;
                stores_per_instruction[word_index]          = 0;
            end
        end
    endtask


    // =========================================================================
    // Escenario A: instrucciones independientes
    // =========================================================================
    task set_program_a;
        begin
            clear_program_image;
            program_image[ 0] = 32'h00500093;   // addi  x1,  x0, 5
            program_image[ 1] = 32'hffd00113;   // addi  x2,  x0, -3
            program_image[ 2] = 32'h00c00193;   // addi  x3,  x0, 12
            program_image[ 3] = 32'h12345237;   // lui   x4,  0x12345
            program_image[ 4] = 32'h00400293;   // addi  x5,  x0, 4
            program_image[ 5] = 32'h80000337;   // lui   x6,  0x80000
            program_image[ 6] = 32'h003083b3;   // add   x7,  x1, x3
            program_image[ 7] = 32'h40208433;   // sub   x8,  x1, x2
            program_image[ 8] = 32'h004174b3;   // and   x9,  x2, x4
            program_image[ 9] = 32'h0060e533;   // or    x10, x1, x6
            program_image[10] = 32'h0021c5b3;   // xor   x11, x3, x2
            program_image[11] = 32'h00509633;   // sll   x12, x1, x5
            program_image[12] = 32'h005356b3;   // srl   x13, x6, x5
            program_image[13] = 32'h40535733;   // sra   x14, x6, x5
            program_image[14] = 32'h001127b3;   // slt   x15, x2, x1
            program_image[15] = 32'h00113833;   // sltu  x16, x2, x1
            program_image[16] = 32'h00f17893;   // andi  x17, x2, 0x0f
            program_image[17] = 32'h0700e913;   // ori   x18, x1, 0x70
            program_image[18] = 32'hfff1c993;   // xori  x19, x3, -1
            program_image[19] = 32'hffe12a13;   // slti  x20, x2, -2
            program_image[20] = 32'h0060ba93;   // sltiu x21, x1, 6
            program_image[21] = 32'h00309b13;   // slli  x22, x1, 3
            program_image[22] = 32'h01f35b93;   // srli  x23, x6, 31
            program_image[23] = 32'h41f35c13;   // srai  x24, x6, 31
            program_image[24] = 32'h00402023;   // sw    x4,  0(x0)
            program_image[25] = 32'h00201223;   // sh    x2,  4(x0)
            program_image[26] = 32'h00100323;   // sb    x1,  6(x0)
            program_image[27] = 32'h003003a3;   // sb    x3,  7(x0)
            program_image[28] = 32'h00002c83;   // lw    x25, 0(x0)
            program_image[29] = 32'h00402d03;   // lw    x26, 4(x0)
            program_image[30] = 32'h00400d83;   // lb    x27, 4(x0)
            program_image[31] = 32'h003c80b3;   // add   x1,  x25, x3   (consume el lw de 3 lugares atras)
            program_image[32] = 32'h00404e03;   // lbu   x28, 4(x0)
            program_image[33] = 32'h00401e83;   // lh    x29, 4(x0)
            program_image[34] = 32'h00405f03;   // lhu   x30, 4(x0)
            program_image[35] = 32'h00700f83;   // lb    x31, 7(x0)
            program_image[36] = 32'h01a02423;   // sw    x26, 8(x0)
            program_image[37] = 32'h01902623;   // sw    x25, 12(x0)
            program_image[38] = 32'h00728013;   // addi  x0,  x5, 7     (escritura a x0 descartada)
            program_length = 39;

            expected_register[ 0] = 32'h00000000;  expected_register[ 1] = 32'h1234500C;
            expected_register[ 2] = 32'hFFFFFFFD;  expected_register[ 3] = 32'h0000000C;
            expected_register[ 4] = 32'h12345000;  expected_register[ 5] = 32'h00000004;
            expected_register[ 6] = 32'h80000000;  expected_register[ 7] = 32'h00000011;
            expected_register[ 8] = 32'h00000008;  expected_register[ 9] = 32'h12345000;
            expected_register[10] = 32'h80000005;  expected_register[11] = 32'hFFFFFFF1;
            expected_register[12] = 32'h00000050;  expected_register[13] = 32'h08000000;
            expected_register[14] = 32'hF8000000;  expected_register[15] = 32'h00000001;
            expected_register[16] = 32'h00000000;  expected_register[17] = 32'h0000000D;
            expected_register[18] = 32'h00000075;  expected_register[19] = 32'hFFFFFFF3;
            expected_register[20] = 32'h00000001;  expected_register[21] = 32'h00000001;
            expected_register[22] = 32'h00000028;  expected_register[23] = 32'h00000001;
            expected_register[24] = 32'hFFFFFFFF;  expected_register[25] = 32'h12345000;
            expected_register[26] = 32'h0C05FFFD;  expected_register[27] = 32'hFFFFFFFD;
            expected_register[28] = 32'h000000FD;  expected_register[29] = 32'hFFFFFFFD;
            expected_register[30] = 32'h0000FFFD;  expected_register[31] = 32'h0000000C;

            expected_memory[0] = 32'h12345000;     expected_memory[1] = 32'h0C05FFFD;
            expected_memory[2] = 32'h0C05FFFD;     expected_memory[3] = 32'h12345000;
            expected_memory_words    = 4;
            expected_register_writes = 32;
            expected_stores          = 6;
        end
    endtask


    // =========================================================================
    // Escenario B: accesos fuera de rango
    // =========================================================================
    task set_program_b;
        integer register_index;
        begin
            clear_program_image;
            program_image[0] = 32'h000010b7;    // lui   x1, 1          (x1 = 0x1000, fuera de rango)
            program_image[1] = 32'h05500113;    // addi  x2, x0, 0x55
            program_image[2] = 32'h01100193;    // addi  x3, x0, 0x11
            program_image[3] = 32'h00000013;    // nop
            program_image[4] = 32'h00000013;    // nop
            program_image[5] = 32'h00302023;    // sw    x3, 0(x0)      (dmem[0] = 0x11)
            program_image[6] = 32'h0020a023;    // sw    x2, 0(x1)      (fuera de rango: no se escribe)
            program_image[7] = 32'h0000a203;    // lw    x4, 0(x1)      (fuera de rango: devuelve 0)
            program_image[8] = 32'h00002283;    // lw    x5, 0(x0)      (en rango: 0x11)
            program_length = 9;

            for (register_index = 0; register_index < 32; register_index = register_index + 1)
                expected_register[register_index] = 32'h00000000;
            expected_register[1] = 32'h00001000;
            expected_register[2] = 32'h00000055;
            expected_register[3] = 32'h00000011;
            expected_register[5] = 32'h00000011;

            expected_memory[0]       = 32'h00000011;
            expected_memory_words    = 1;
            expected_register_writes = 5;
            expected_stores          = 1;
        end
    endtask


    // =========================================================================
    // Chequeos por ciclo
    // =========================================================================
    // Una instruccion que entro a IF en el paso N esta en la etapa k en el paso N+k
    task check_stage_occupancy(
        input [8*6-1:0] stage_name,
        input integer   steps_after_fetch,
        input           observed_valid,
        input [31:0]    observed_pc,
        input [31:0]    observed_instruction
    );
        integer instruction_index;
        begin
            instruction_index = current_step - steps_after_fetch;
            if (instruction_index < 0) begin
                if (observed_valid !== 1'b0) begin
                    error_count = error_count + 1;
                    $display("  [FAIL] paso %0d: %0s deberia estar vacia", current_step, stage_name);
                end
            end else begin
                if (observed_valid !== 1'b1 ||
                    observed_pc !== 4 * instruction_index ||
                    observed_instruction !== program_image[instruction_index]) begin
                    error_count = error_count + 1;
                    $display("  [FAIL] paso %0d: %0s deberia tener la instruccion %0d (valid=%b pc=0x%08h instr=0x%08h)",
                             current_step, stage_name, instruction_index,
                             observed_valid, observed_pc, observed_instruction);
                end
            end
        end
    endtask

    // Los datos y controles de cada latch deben corresponder a su propia instruccion
    task check_latch_contents_match_instruction;
        begin
            if (dut.id_ex_valid) begin
                check_true({dut.id_ex_alu_op, dut.id_ex_alu_src_b_is_imm,
                            dut.id_ex_reg_write, dut.id_ex_mem_read, dut.id_ex_mem_write,
                            dut.id_ex_is_branch, dut.id_ex_is_jal, dut.id_ex_is_jalr,
                            dut.id_ex_is_halt, dut.id_ex_is_illegal}
                        === {ref_ex_alu_op, ref_ex_alu_src_b_is_imm,
                             ref_ex_reg_write, ref_ex_mem_read, ref_ex_mem_write,
                             ref_ex_is_branch, ref_ex_is_jal, ref_ex_is_jalr,
                             ref_ex_is_halt, ref_ex_is_illegal},
                        "controles de ID/EX distintos a su instruccion");
                check_true(dut.id_ex_rs1_addr === dut.id_ex_instruction[19:15] &&
                           dut.id_ex_rs2_addr === dut.id_ex_instruction[24:20] &&
                           dut.id_ex_rd_addr  === dut.id_ex_instruction[11:7]  &&
                           dut.id_ex_funct3   === dut.id_ex_instruction[14:12],
                           "campos rs1/rs2/rd/funct3 de ID/EX incoherentes");
            end

            if (dut.ex_mem_valid) begin
                check_true({dut.ex_mem_reg_write, dut.ex_mem_mem_read, dut.ex_mem_mem_write}
                        === {ref_mem_reg_write, ref_mem_mem_read, ref_mem_mem_write},
                        "controles de EX/MEM distintos a su instruccion");
                check_true(dut.ex_mem_rd_addr === dut.ex_mem_instruction[11:7] &&
                           dut.ex_mem_funct3  === dut.ex_mem_instruction[14:12],
                           "campos rd/funct3 de EX/MEM incoherentes");
            end

            if (dut.mem_wb_valid) begin
                check_true({dut.mem_wb_reg_write, dut.mem_wb_mem_read, dut.mem_wb_mem_write}
                        === {ref_wb_reg_write, ref_wb_mem_read, ref_wb_mem_write},
                        "controles de MEM/WB distintos a su instruccion");
                check_true(dut.mem_wb_rd_addr === dut.mem_wb_instruction[11:7] &&
                           dut.mem_wb_funct3  === dut.mem_wb_instruction[14:12],
                           "campos rd/funct3 de MEM/WB incoherentes");
            end
        end
    endtask

    task check_pipeline_state;
        begin
            check_equal("PC", dut.if_pc, 4 * current_step);
            check_stage_occupancy("IF/ID",  1, dut.if_id_valid,  dut.if_id_pc,  dut.if_id_instruction);
            check_stage_occupancy("ID/EX",  2, dut.id_ex_valid,  dut.id_ex_pc,  dut.id_ex_instruction);
            check_stage_occupancy("EX/MEM", 3, dut.ex_mem_valid, dut.ex_mem_pc, dut.ex_mem_instruction);
            check_stage_occupancy("MEM/WB", 4, dut.mem_wb_valid, dut.mem_wb_pc, dut.mem_wb_instruction);
            check_latch_contents_match_instruction;
        end
    endtask

    task print_stage(input [8*4-1:0] label, input is_valid, input [31:0] pc);
        begin
            if (is_valid) $write(" | %0s %2d", label, pc >> 2);
            else          $write(" | %0s --", label);
        end
    endtask

    task print_trace_line(input is_paused);
        begin
            $write("  paso %2d", current_step);
            print_stage("IF",  1'b1,             dut.if_pc);
            print_stage("ID",  dut.if_id_valid,  dut.if_id_pc);
            print_stage("EX",  dut.id_ex_valid,  dut.id_ex_pc);
            print_stage("MEM", dut.ex_mem_valid, dut.ex_mem_pc);
            print_stage("WB",  dut.mem_wb_valid, dut.mem_wb_pc);
            if (is_paused) $write("   <- i_cpu_en = 0");
            $write("\n");
        end
    endtask


    // =========================================================================
    // Ejecucion y chequeos finales
    // =========================================================================
    // Cada iteracion del lazo es un intervalo de reloj; current_step cuenta los
    // flancos con i_cpu_en = 1 desde el reset
    task run_program(input integer enabled_steps, input integer pause_at_step, input integer pause_intervals);
        integer paused_intervals;
        reg     pause_now;
        begin
            current_step     = 0;
            paused_intervals = 0;
            clear_event_counters;

            while (current_step <= enabled_steps) begin
                @(negedge clk);
                pause_now = (current_step == pause_at_step) && (paused_intervals < pause_intervals);
                check_pipeline_state;
                print_trace_line(pause_now);

                if (pause_now) begin
                    cpu_en           = 1'b0;
                    paused_intervals = paused_intervals + 1;
                end else begin
                    cpu_en       = 1'b1;
                    current_step = current_step + 1;
                end
            end
            cpu_en       = 1'b0;
            current_step = enabled_steps;
        end
    endtask

    task check_write_events_happen_once;
        integer instruction_index;
        begin
            for (instruction_index = 0; instruction_index < MAX_PROGRAM_WORDS; instruction_index = instruction_index + 1) begin
                if (register_writes_per_instruction[instruction_index] > 1 ||
                    stores_per_instruction[instruction_index] > 1) begin
                    error_count = error_count + 1;
                    $display("  [FAIL] la instruccion %0d escribio mas de una vez (registro: %0d, memoria: %0d)",
                             instruction_index,
                             register_writes_per_instruction[instruction_index],
                             stores_per_instruction[instruction_index]);
                end
            end
            check_equal("escrituras de registro", total_register_writes, expected_register_writes);
            check_equal("escrituras de memoria",  total_stores,          expected_stores);
        end
    endtask

    task check_final_state;
        integer     index;
        reg [31:0]  observed_value;
        begin
            for (index = 0; index < 32; index = index + 1) begin
                read_register(index, observed_value);
                if (observed_value !== expected_register[index]) begin
                    error_count = error_count + 1;
                    $display("  [FAIL] x%0d = 0x%08h, esperado 0x%08h", index, observed_value, expected_register[index]);
                end
            end
            for (index = 0; index < expected_memory_words; index = index + 1) begin
                read_data_memory_word(index, observed_value);
                if (observed_value !== expected_memory[index]) begin
                    error_count = error_count + 1;
                    $display("  [FAIL] dmem[%0d] = 0x%08h, esperado 0x%08h", index, observed_value, expected_memory[index]);
                end
            end
        end
    endtask

    task check_pipeline_is_empty_after_reset;
        begin
            check_true(dut.if_id_valid === 1'b0 && dut.id_ex_valid === 1'b0 &&
                       dut.ex_mem_valid === 1'b0 && dut.mem_wb_valid === 1'b0,
                       "tras el reset algun latch conserva valid = 1");
            check_equal("PC tras reset", dut.if_pc, 32'd0);
        end
    endtask

    task run_scenario(input integer extra_steps, input integer pause_at_step, input integer pause_intervals);
        begin
            write_program_image_to_memory;
            reset_cpu;
            check_pipeline_is_empty_after_reset;
            run_program(program_length + extra_steps, pause_at_step, pause_intervals);
            check_write_events_happen_once;
            check_final_state;
        end
    endtask


    // =========================================================================
    // Secuencia principal
    // =========================================================================
    initial begin
        error_count = 0;

        $display("\n=== Escenario A: 39 instrucciones independientes (pausa en el paso 27) ===");
        set_program_a;
        run_scenario(6, 27, 3);

        $display("\n=== Escenario B: accesos fuera de rango tras un reset ===");
        set_program_b;
        run_scenario(6, -1, 0);

        if (error_count == 0)
            $display("\nRESULTADO: PASS (0 errores)\n");
        else
            $display("\nRESULTADO: FAIL (%0d errores)\n", error_count);
        $finish;
    end

    // Cortafuegos ante un cuelgue de la simulacion
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
