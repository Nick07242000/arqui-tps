`timescale 1ns / 1ps
`include "riscv_defs.vh"

module cpu_core_control_hazards_tb;

    // =========================================================================
    // Reloj, control y conexion CPU <-> memorias
    // =========================================================================
    reg clk       = 1'b0;
    reg cpu_reset = 1'b1;
    reg cpu_en    = 1'b0;

    always #5 clk = ~clk;

    wire        imem_read_enable;
    wire [9:0]  imem_read_addr;
    wire [31:0] imem_read_data;

    reg         imem_write_enable = 1'b0;
    reg  [9:0]  imem_write_addr   = 10'd0;
    reg  [31:0] imem_write_data   = 32'd0;

    wire        dmem_read_enable;
    wire [9:0]  dmem_word_addr;
    wire [3:0]  dmem_write_byte_enable;
    wire [31:0] dmem_write_data;
    wire [31:0] dmem_read_data;

    reg  [9:0]  dmem_debug_addr = 10'd0;
    wire [31:0] dmem_debug_data;

    reg  [4:0]  debug_reg_addr = 5'd0;
    wire [31:0] debug_reg_data;

    program_memory imem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_read_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_addr),
        .i_write_data      (imem_write_data)
    );

    data_memory dmem (
        .i_clk               (clk),
        .i_read_enable       (dmem_read_enable),
        .i_word_addr         (dmem_word_addr),
        .i_write_byte_enable (dmem_write_byte_enable),
        .i_write_data        (dmem_write_data),
        .o_read_data         (dmem_read_data),
        .i_debug_word_addr   (dmem_debug_addr),
        .o_debug_read_data   (dmem_debug_data)
    );

    cpu_core dut (
        .i_clk                    (clk),
        .i_cpu_reset              (cpu_reset),
        .i_cpu_en                 (cpu_en),
        .o_imem_read_enable       (imem_read_enable),
        .o_imem_word_addr         (imem_read_addr),
        .i_imem_read_data         (imem_read_data),
        .o_dmem_read_enable       (dmem_read_enable),
        .o_dmem_word_addr         (dmem_word_addr),
        .o_dmem_write_byte_enable (dmem_write_byte_enable),
        .o_dmem_write_data        (dmem_write_data),
        .i_dmem_read_data         (dmem_read_data),
        .i_debug_reg_addr         (debug_reg_addr),
        .o_debug_reg_data         (debug_reg_data)
    );

    // =========================================================================
    // Ensamblador minimo: los argumentos siguen el orden del texto assembler
    // =========================================================================
    localparam [4:0] X0 = 5'd0, X1 = 5'd1, X2 = 5'd2, X3 = 5'd3, X4 = 5'd4,
                     X5 = 5'd5, X6 = 5'd6, X7 = 5'd7, X9 = 5'd9;

    function [31:0] encode_i_type(input [6:0] opcode, input [2:0] funct3,
                                  input [4:0] rd, input [4:0] rs1, input integer imm);
        reg [11:0] imm12;
        begin
            imm12 = imm;
            encode_i_type = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] addi(input [4:0] rd, input [4:0] rs1, input integer imm);
        addi = encode_i_type(`OPCODE_OP_IMM, `FUNCT3_ADD_SUB, rd, rs1, imm);
    endfunction

    function [31:0] lw(input [4:0] rd, input integer imm, input [4:0] rs1);
        lw = encode_i_type(`OPCODE_LOAD, `FUNCT3_WORD, rd, rs1, imm);
    endfunction

    function [31:0] jalr(input [4:0] rd, input integer imm, input [4:0] rs1);
        jalr = encode_i_type(`OPCODE_JALR, `FUNCT3_JALR, rd, rs1, imm);
    endfunction

    function [31:0] sw(input [4:0] rs2, input integer imm, input [4:0] rs1);
        reg [11:0] imm12;
        begin
            imm12 = imm;
            sw = {imm12[11:5], rs2, rs1, `FUNCT3_WORD, imm12[4:0], `OPCODE_STORE};
        end
    endfunction

    function [31:0] encode_b_type(input [2:0] funct3, input [4:0] rs1,
                                  input [4:0] rs2, input integer offset);
        reg [12:0] imm13;
        begin
            imm13 = offset;
            encode_b_type = {imm13[12], imm13[10:5], rs2, rs1, funct3,
                             imm13[4:1], imm13[11], `OPCODE_BRANCH};
        end
    endfunction

    function [31:0] beq(input [4:0] rs1, input [4:0] rs2, input integer offset);
        beq = encode_b_type(`FUNCT3_BEQ, rs1, rs2, offset);
    endfunction

    function [31:0] bne(input [4:0] rs1, input [4:0] rs2, input integer offset);
        bne = encode_b_type(`FUNCT3_BNE, rs1, rs2, offset);
    endfunction

    function [31:0] jal(input [4:0] rd, input integer offset);
        reg [20:0] imm21;
        begin
            imm21 = offset;
            jal = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, `OPCODE_JAL};
        end
    endfunction

    function [31:0] add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        add = {`FUNCT7_BASE, rs2, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_R_TYPE};
    endfunction

    // =========================================================================
    // Carga del programa y ejecucion
    // =========================================================================
    localparam PROGRAM_WORDS = 64;

    reg [31:0] test_program [0:PROGRAM_WORDS-1];
    integer    program_length;

    task begin_program;
        integer word_index;
        begin
            for (word_index = 0; word_index < PROGRAM_WORDS; word_index = word_index + 1)
                test_program[word_index] = 32'd0;
            program_length = 0;
        end
    endtask

    task emit(input [31:0] instruction);
        begin
            test_program[program_length] = instruction;
            program_length = program_length + 1;
        end
    endtask

    task write_program_to_memory;
        integer word_index;
        begin
            for (word_index = 0; word_index < PROGRAM_WORDS; word_index = word_index + 1) begin
                @(negedge clk);
                imem_write_enable = 1'b1;
                imem_write_addr   = word_index;
                imem_write_data   = test_program[word_index];
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
            repeat (2) @(negedge clk);
            cpu_reset = 1'b0;
            clear_monitor;
        end
    endtask

    task run_enabled_cycles(input integer cycle_total);
        begin
            cpu_en = 1'b1;
            repeat (cycle_total) @(negedge clk);
            cpu_en = 1'b0;
            @(negedge clk);
        end
    endtask

    // Mismo numero de ciclos habilitados, pero con pausas al azar (como STEP)
    integer pause_seed = 32'h0000_1234;

    task run_enabled_cycles_with_pauses(input integer cycle_total);
        integer enabled_so_far;
        begin
            enabled_so_far = 0;
            while (enabled_so_far < cycle_total) begin
                cpu_en = $random(pause_seed) & 1;
                if (cpu_en) enabled_so_far = enabled_so_far + 1;
                @(negedge clk);
            end
            cpu_en = 1'b0;
            @(negedge clk);
        end
    endtask

    task run_program(input integer cycle_total);
        begin
            write_program_to_memory;
            reset_cpu;
            run_enabled_cycles(cycle_total);
        end
    endtask

    // =========================================================================
    // Monitor: cuantas veces llego cada PC a EX como instruccion valida
    // =========================================================================
    localparam [31:0] NEVER = 32'hFFFF_FFFF;

    integer cycle_count;
    integer ex_count       [0:255];
    integer ex_first_cycle [0:255];
    integer monitor_index;

    task clear_monitor;
        begin
            cycle_count = 0;
            for (monitor_index = 0; monitor_index < 256; monitor_index = monitor_index + 1) begin
                ex_count[monitor_index]       = 0;
                ex_first_cycle[monitor_index] = NEVER;
            end
        end
    endtask

    always @(posedge clk) begin
        if (cpu_en && !cpu_reset) begin
            cycle_count = cycle_count + 1;
            if (dut.id_ex_valid) begin
                ex_count[dut.id_ex_pc[9:2]] = ex_count[dut.id_ex_pc[9:2]] + 1;
                if (ex_first_cycle[dut.id_ex_pc[9:2]] == NEVER)
                    ex_first_cycle[dut.id_ex_pc[9:2]] = cycle_count;
            end
        end
    end

    // =========================================================================
    // Invariantes que se vigilan durante todos los tests
    // =========================================================================
    integer error_count = 0;
    integer check_count = 0;
    reg [8*48-1:0] current_test_name;

    // Stall y flush nunca pueden coincidir
    always @(posedge clk) begin
        if (!cpu_reset && dut.load_use_stall && dut.front_end_flush) begin
            $display("FAIL [%0s] stall y flush simultaneos (t=%0t)", current_test_name, $time);
            error_count = error_count + 1;
        end
    end

    // Con cpu_en = 0 ningun latch ni el PC pueden cambiar
    reg [265:0] pipeline_snapshot_before_edge;
    reg         previous_edge_was_paused = 1'b0;

    wire [265:0] pipeline_snapshot = {
        dut.if_pc,
        dut.if_id_valid,  dut.if_id_pc,
        dut.id_ex_valid,  dut.id_ex_pc,  dut.id_ex_instruction,
        dut.ex_mem_valid, dut.ex_mem_pc,
        dut.mem_wb_valid, dut.mem_wb_pc
    };

    always @(posedge clk) begin
        if (previous_edge_was_paused && pipeline_snapshot !== pipeline_snapshot_before_edge) begin
            $display("FAIL [%0s] el pipeline cambio con cpu_en = 0 (t=%0t)", current_test_name, $time);
            error_count = error_count + 1;
        end
        pipeline_snapshot_before_edge = pipeline_snapshot;
        previous_edge_was_paused      = !cpu_en && !cpu_reset;
    end

    // Tras un flush efectivo, IF/ID e ID/EX quedan como burbuja
    reg flush_was_applied = 1'b0;

    always @(posedge clk) begin
        if (flush_was_applied && (dut.if_id_valid || dut.id_ex_valid)) begin
            $display("FAIL [%0s] el flush no dejo burbuja en IF/ID e ID/EX (t=%0t)",
                     current_test_name, $time);
            error_count = error_count + 1;
        end
        flush_was_applied <= cpu_en && !cpu_reset && dut.front_end_flush;
    end

    // =========================================================================
    // Verificaciones
    // =========================================================================
    task fail(input [8*64-1:0] message);
        begin
            $display("FAIL [%0s] %0s", current_test_name, message);
            error_count = error_count + 1;
        end
    endtask

    task expect_register(input [4:0] register_index, input [31:0] expected_value);
        begin
            debug_reg_addr = register_index;
            #1;
            check_count = check_count + 1;
            if (debug_reg_data !== expected_value) begin
                $display("FAIL [%0s] x%0d = %h, esperado %h",
                         current_test_name, register_index, debug_reg_data, expected_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task expect_data_word(input integer word_index, input [31:0] expected_value);
        begin
            dmem_debug_addr = word_index;
            repeat (2) @(posedge clk);
            #1;
            check_count = check_count + 1;
            if (dmem_debug_data !== expected_value) begin
                $display("FAIL [%0s] dmem[%0d] = %h, esperado %h",
                         current_test_name, word_index, dmem_debug_data, expected_value);
                error_count = error_count + 1;
            end
        end
    endtask

    // Veces que la instruccion de esa direccion llego a EX como valida
    task expect_ex_count(input integer pc, input integer expected_count);
        begin
            check_count = check_count + 1;
            if (ex_count[pc / 4] !== expected_count) begin
                $display("FAIL [%0s] PC 0x%0h llego a EX %0d veces, esperado %0d",
                         current_test_name, pc, ex_count[pc / 4], expected_count);
                error_count = error_count + 1;
            end
        end
    endtask

    // Ciclos entre la primera vez que cada PC estuvo en EX
    task expect_ex_gap(input integer first_pc, input integer second_pc, input integer expected_gap);
        integer measured_gap;
        begin
            check_count = check_count + 1;
            if (ex_first_cycle[first_pc / 4] == NEVER || ex_first_cycle[second_pc / 4] == NEVER) begin
                $display("FAIL [%0s] PC 0x%0h o 0x%0h nunca llego a EX",
                         current_test_name, first_pc, second_pc);
                error_count = error_count + 1;
            end else begin
                measured_gap = ex_first_cycle[second_pc / 4] - ex_first_cycle[first_pc / 4];
                if (measured_gap !== expected_gap) begin
                    $display("FAIL [%0s] ciclos de EX 0x%0h -> 0x%0h = %0d, esperado %0d",
                             current_test_name, first_pc, second_pc, measured_gap, expected_gap);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    integer errors_before_test;

    task begin_test(input [8*48-1:0] test_name);
        begin
            current_test_name  = test_name;
            errors_before_test = error_count;
            begin_program;
        end
    endtask

    task end_test;
        begin
            if (error_count == errors_before_test)
                $display("ok   %0s", current_test_name);
        end
    endtask

    // =========================================================================
    // Tests
    // =========================================================================

    // beq tomado. x1 llega por forwarding EX/MEM; x2 se lee del banco.
    // Con un forwarding roto, x1 valdria 0 y el branch no se tomaria.
    task test_beq_taken_forward_from_ex_mem;
        begin
            begin_test("beq tomado, forwarding EX/MEM en rs1");
            emit(addi(X2, X0, 5));      // 0x00
            emit(addi(X7, X0, 0));      // 0x04  relleno
            emit(addi(X7, X0, 0));      // 0x08  relleno
            emit(addi(X1, X0, 5));      // 0x0C
            emit(beq (X1, X2, 12));     // 0x10  -> 0x1C
            emit(addi(X3, X0, 111));    // 0x14  anulada
            emit(addi(X4, X0, 222));    // 0x18  anulada
            emit(addi(X5, X0, 7));      // 0x1C  destino
            run_program(40);

            expect_register(X1, 5);
            expect_register(X3, 0);
            expect_register(X4, 0);
            expect_register(X5, 7);
            expect_ex_count('h14, 0);
            expect_ex_count('h18, 0);
            expect_ex_count('h1C, 1);
            expect_ex_gap('h10, 'h1C, 3);   // 2 ciclos de penalizacion
            end_test;
        end
    endtask

    // beq tomado. x2 llega por forwarding MEM/WB; x1 se lee del banco.
    task test_beq_taken_forward_from_mem_wb;
        begin
            begin_test("beq tomado, forwarding MEM/WB en rs2");
            emit(addi(X1, X0, 6));      // 0x00
            emit(addi(X7, X0, 0));      // 0x04  relleno
            emit(addi(X7, X0, 0));      // 0x08  relleno
            emit(addi(X2, X0, 6));      // 0x0C
            emit(addi(X7, X0, 0));      // 0x10  relleno: x2 pasa a MEM/WB
            emit(beq (X1, X2, 12));     // 0x14  -> 0x20
            emit(addi(X3, X0, 111));    // 0x18  anulada
            emit(addi(X4, X0, 222));    // 0x1C  anulada
            emit(addi(X5, X0, 7));      // 0x20  destino
            run_program(40);

            expect_register(X3, 0);
            expect_register(X4, 0);
            expect_register(X5, 7);
            expect_ex_count('h18, 0);
            expect_ex_count('h1C, 0);
            expect_ex_gap('h14, 'h20, 3);
            end_test;
        end
    endtask

    // beq NO tomado. Con un forwarding roto, x1 valdria 0 (igual a x2) y se tomaria.
    task test_beq_not_taken_no_penalty;
        begin
            begin_test("beq no tomado, sin penalizacion");
            emit(addi(X1, X0, 5));      // 0x00
            emit(beq (X1, X2, 12));     // 0x04  x1=5, x2=0 -> no se toma
            emit(addi(X3, X0, 111));    // 0x08
            emit(addi(X4, X0, 222));    // 0x0C
            emit(addi(X5, X0, 7));      // 0x10
            run_program(30);

            expect_register(X3, 111);
            expect_register(X4, 222);
            expect_register(X5, 7);
            expect_ex_count('h08, 1);
            expect_ex_count('h0C, 1);
            expect_ex_gap('h04, 'h08, 1);   // el siguiente entra a EX sin demora
            end_test;
        end
    endtask

    // bne tomado hacia PC+8: la direccion que el fetch ya habia pedido por error
    // debe anularse y volver a buscarse, ejecutandose una sola vez.
    task test_bne_taken_and_not_taken;
        begin
            begin_test("bne tomado a PC+8 y bne no tomado");
            emit(addi(X1, X0, 1));      // 0x00
            emit(addi(X2, X0, 2));      // 0x04
            emit(bne (X1, X2, 8));      // 0x08  -> 0x10
            emit(addi(X3, X0, 111));    // 0x0C  anulada
            emit(bne (X1, X1, 8));      // 0x10  no se toma
            emit(addi(X4, X0, 44));     // 0x14
            emit(addi(X5, X0, 55));     // 0x18
            run_program(40);

            expect_register(X3, 0);
            expect_register(X4, 44);
            expect_register(X5, 55);
            expect_ex_count('h0C, 0);
            expect_ex_count('h10, 1);
            expect_ex_gap('h08, 'h10, 3);
            expect_ex_gap('h10, 'h14, 1);
            end_test;
        end
    endtask

    // Lazo hacia atras: la condicion depende de la instruccion anterior (ALU -> branch)
    task test_backward_loop;
        begin
            begin_test("lazo hacia atras con dependencia ALU-branch");
            emit(addi(X1, X0, 5));      // 0x00  contador
            emit(addi(X2, X0, 0));      // 0x04  suma
            emit(add (X2, X2, X1));     // 0x08  lazo:
            emit(addi(X1, X1, -1));     // 0x0C
            emit(bne (X1, X0, -8));     // 0x10  -> 0x08
            emit(addi(X3, X0, 99));     // 0x14  despues del lazo
            run_program(60);

            expect_register(X1, 0);
            expect_register(X2, 15);    // 5+4+3+2+1
            expect_register(X3, 99);
            expect_ex_count('h08, 5);
            expect_ex_count('h10, 5);
            expect_ex_count('h14, 1);   // anulada 4 veces, ejecutada 1
            end_test;
        end
    endtask

    // El mismo lazo con pausas al azar de cpu_en debe terminar igual
    task test_loop_with_cpu_pauses;
        begin
            begin_test("lazo con pausas de cpu_en (estilo STEP)");
            emit(addi(X1, X0, 5));
            emit(addi(X2, X0, 0));
            emit(add (X2, X2, X1));
            emit(addi(X1, X1, -1));
            emit(bne (X1, X0, -8));
            emit(addi(X3, X0, 99));
            write_program_to_memory;
            reset_cpu;
            run_enabled_cycles_with_pauses(60);

            expect_register(X1, 0);
            expect_register(X2, 15);
            expect_register(X3, 99);
            expect_ex_count('h08, 5);
            expect_ex_count('h14, 1);
            end_test;
        end
    endtask

    // lw seguido de beq que lo usa: primero stall, despues redirect
    task test_load_then_branch;
        begin
            begin_test("lw seguido de beq (stall y flush)");
            emit(addi(X1, X0, 9));      // 0x00
            emit(sw  (X1, 256, X0));    // 0x04  dmem[64] = 9
            emit(lw  (X2, 256, X0));    // 0x08
            emit(beq (X2, X1, 12));     // 0x0C  espera al load, -> 0x18
            emit(addi(X3, X0, 1));      // 0x10  anulada
            emit(addi(X4, X0, 2));      // 0x14  anulada
            emit(addi(X5, X0, 3));      // 0x18  destino
            run_program(40);

            expect_register(X2, 9);
            expect_register(X3, 0);
            expect_register(X4, 0);
            expect_register(X5, 3);
            expect_data_word(64, 9);
            expect_ex_count('h10, 0);
            expect_ex_count('h14, 0);
            expect_ex_gap('h08, 'h0C, 2);   // 1 ciclo de stall
            expect_ex_gap('h0C, 'h18, 3);
            end_test;
        end
    endtask

    // jal: guarda PC+4, salta, y el store y la escritura del camino
    // descartado no tienen ningun efecto
    task test_jal_annuls_wrong_path;
        begin
            begin_test("jal anula store y escritura del camino erroneo");
            emit(addi(X6, X0, 55));     // 0x00
            emit(jal (X1, 12));         // 0x04  -> 0x10, x1 = 0x08
            emit(sw  (X6, 512, X0));    // 0x08  anulado: dmem[128] debe seguir en 0
            emit(addi(X2, X0, 77));     // 0x0C  anulada
            emit(addi(X3, X0, 1));      // 0x10  destino
            run_program(30);

            expect_register(X1, 'h08);
            expect_register(X2, 0);
            expect_register(X3, 1);
            expect_data_word(128, 0);
            expect_ex_count('h08, 0);
            expect_ex_count('h0C, 0);
            expect_ex_gap('h04, 'h10, 3);
            end_test;
        end
    endtask

    // jalr: la base llega por forwarding y el offset impar se corrige a par
    task test_jalr_forwarded_base_and_odd_offset;
        begin
            begin_test("jalr con base adelantada y offset impar");
            emit(addi(X5, X0, 20));     // 0x00
            emit(jalr(X1, 1, X5));      // 0x04  destino 21 -> 20, x1 = 0x08
            emit(addi(X2, X0, 1));      // 0x08  anulada
            emit(addi(X3, X0, 2));      // 0x0C  anulada
            emit(addi(X4, X0, 3));      // 0x10  se saltea
            emit(jal (X7, 4));          // 0x14  destino: su link (PC+4) delata el PC real
            emit(addi(X6, X0, 4));      // 0x18
            run_program(30);

            expect_register(X1, 'h08);
            expect_register(X2, 0);
            expect_register(X3, 0);
            expect_register(X4, 0);
            expect_register(X7, 'h18);  // con el bit 0 sin anular daria 0x19
            expect_register(X6, 4);
            expect_ex_count('h10, 0);
            expect_ex_gap('h04, 'h14, 3);
            end_test;
        end
    endtask

    // Llamada y retorno: jal guarda el retorno en x1 y jalr lo usa
    task test_call_and_return;
        begin
            begin_test("llamada con jal y retorno con jalr");
            emit(jal (X1, 16));         // 0x00  llamada -> 0x10, x1 = 0x04
            emit(addi(X2, X0, 22));     // 0x04  se ejecuta tras el retorno
            emit(jal (X0, 20));         // 0x08  -> 0x1C
            emit(addi(X9, X0, 1));      // 0x0C  nunca se alcanza
            emit(addi(X3, X0, 33));     // 0x10  cuerpo de la funcion
            emit(jalr(X0, 0, X1));      // 0x14  retorno -> 0x04
            emit(addi(X9, X0, 2));      // 0x18  anulada
            emit(addi(X4, X0, 44));     // 0x1C  fin
            run_program(50);

            expect_register(X1, 'h04);
            expect_register(X2, 22);
            expect_register(X3, 33);
            expect_register(X4, 44);
            expect_register(X9, 0);
            expect_ex_count('h04, 1);
            expect_ex_count('h10, 1);   // el jal de 0x08 anula su busqueda
            expect_ex_count('h18, 0);
            expect_ex_count('h1C, 1);
            end_test;
        end
    endtask

    // Un jump que esta en el camino erroneo no puede redirigir el PC
    task test_wrong_path_jump_is_ignored;
        begin
            begin_test("un jal del camino erroneo no redirige");
            emit(beq (X0, X0, 12));     // 0x00  siempre tomado -> 0x0C
            emit(jal (X1, 100));        // 0x04  anulado
            emit(jal (X2, 200));        // 0x08  anulado
            emit(addi(X3, X0, 3));      // 0x0C  destino
            run_program(30);

            expect_register(X1, 0);
            expect_register(X2, 0);
            expect_register(X3, 3);
            expect_ex_count('h04, 0);
            expect_ex_count('h08, 0);
            end_test;
        end
    endtask

    // El destino de un branch tomado es otro branch tomado
    task test_back_to_back_taken_branches;
        begin
            begin_test("dos branches tomados consecutivos");
            emit(beq (X0, X0, 8));      // 0x00  -> 0x08
            emit(addi(X9, X0, 1));      // 0x04  anulada
            emit(beq (X0, X0, 8));      // 0x08  -> 0x10
            emit(addi(X9, X0, 2));      // 0x0C  anulada
            emit(addi(X3, X0, 3));      // 0x10  destino
            run_program(30);

            expect_register(X9, 0);
            expect_register(X3, 3);
            expect_ex_gap('h00, 'h08, 3);
            expect_ex_gap('h08, 'h10, 3);
            end_test;
        end
    endtask

    // jal sobre si mismo: lazo infinito que no debe ejecutar nada posterior
    task test_jump_to_self;
        begin
            begin_test("jal sobre si mismo");
            emit(addi(X1, X0, 1));      // 0x00
            emit(jal (X0, 0));          // 0x04  salta a 0x04
            emit(addi(X2, X0, 2));      // 0x08  nunca se ejecuta
            run_program(30);

            expect_register(X1, 1);
            expect_register(X2, 0);
            expect_ex_count('h08, 0);
            if (ex_count['h04 / 4] < 5) fail("el lazo sobre si mismo no se repitio");
            end_test;
        end
    endtask

    // =========================================================================
    // Secuencia principal
    // =========================================================================
    initial begin
        clear_monitor;
        begin_program;

        test_beq_taken_forward_from_ex_mem;
        test_beq_taken_forward_from_mem_wb;
        test_beq_not_taken_no_penalty;
        test_bne_taken_and_not_taken;
        test_backward_loop;
        test_loop_with_cpu_pauses;
        test_load_then_branch;
        test_jal_annuls_wrong_path;
        test_jalr_forwarded_base_and_odd_offset;
        test_call_and_return;
        test_wrong_path_jump_is_ignored;
        test_back_to_back_taken_branches;
        test_jump_to_self;

        if (error_count == 0)
            $display("\ncpu_core_control_hazards_tb: PASS (%0d verificaciones)", check_count);
        else
            $display("\ncpu_core_control_hazards_tb: FAIL (%0d errores, %0d verificaciones)",
                     error_count, check_count);
        $finish;
    end

    // Corta una simulacion que se cuelgue
    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
