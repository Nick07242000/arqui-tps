`timescale 1ns / 1ps
`include "done_reason_defs.vh"

module tb_halt_and_drain;

    localparam MEM_ADDR_WIDTH    = 10;
    localparam CLOCK_PERIOD_NS   = 10;
    localparam MAX_RUN_CYCLES    = 3000;
    localparam CYCLES_AFTER_DONE = 5;      // ciclos extra para comprobar que done es estable

    // Un HALT en la posicion h, sin stalls ni saltos, deja el pipeline vacio
    // h + 5 ciclos despues de comenzar (5 = IF, ID, EX, MEM y WB)
    localparam CYCLES_TO_DRAIN   = 5;

    localparam [31:0] HALT_WORD  = 32'h0000000B;

    // =========================================================================
    // Reloj y senales
    // =========================================================================
    reg clk = 1'b0;
    always #(CLOCK_PERIOD_NS / 2) clk = ~clk;

    // ---- Control emulado de la Debug Unit -----------------------------------
    reg         system_reset;
    reg         cpu_reset_request;
    reg         cpu_enable;
    reg         loader_start;
    reg  [15:0] loader_payload_length;
    reg         loader_byte_valid;
    reg  [7:0]  loader_byte_data;

    wire                    loader_cpu_reset;
    wire                    program_valid;
    wire [MEM_ADDR_WIDTH:0] n_words;
    wire                    load_finished;
    wire [1:0]              load_error_code;

    wire cpu_reset = system_reset || cpu_reset_request || loader_cpu_reset;

    // ---- Memorias -----------------------------------------------------------
    wire                      imem_write_enable;
    wire [MEM_ADDR_WIDTH-1:0] imem_write_word_addr;
    wire [31:0]               imem_write_data;
    wire                      imem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] imem_word_addr;
    wire [31:0]               imem_read_data;

    wire                      dmem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] dmem_word_addr;
    wire [3:0]                dmem_write_byte_enable;
    wire [31:0]               dmem_write_data;
    wire [31:0]               dmem_read_data;
    reg  [MEM_ADDR_WIDTH-1:0] debug_dmem_word_addr;
    wire [31:0]               debug_dmem_read_data;

    // ---- Observacion del CPU ------------------------------------------------
    reg  [4:0]  debug_reg_addr;
    wire [31:0] debug_reg_data;
    wire [31:0] cpu_pc;
    wire        cpu_halting;
    wire        cpu_done;
    wire [1:0]  cpu_done_reason;

    // =========================================================================
    // Instancias
    // =========================================================================
    program_loader loader (
        .i_clk                  (clk),
        .i_reset                (system_reset),
        .i_load_start           (loader_start),
        .i_payload_length_bytes (loader_payload_length),
        .i_byte_valid           (loader_byte_valid),
        .i_byte_data            (loader_byte_data),
        .o_imem_write_enable    (imem_write_enable),
        .o_imem_write_word_addr (imem_write_word_addr),
        .o_imem_write_data      (imem_write_data),
        .o_cpu_reset            (loader_cpu_reset),
        .o_program_valid        (program_valid),
        .o_n_words              (n_words),
        .o_load_finished        (load_finished),
        .o_load_error_code      (load_error_code)
    );

    program_memory program_mem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_word_addr),
        .i_write_data      (imem_write_data)
    );

    data_memory data_mem (
        .i_clk               (clk),
        .i_read_enable       (dmem_read_enable),
        .i_word_addr         (dmem_word_addr),
        .i_write_byte_enable (dmem_write_byte_enable),
        .i_write_data        (dmem_write_data),
        .o_read_data         (dmem_read_data),
        .i_debug_word_addr   (debug_dmem_word_addr),
        .o_debug_read_data   (debug_dmem_read_data)
    );

    cpu_core dut (
        .i_clk                    (clk),
        .i_cpu_reset              (cpu_reset),
        .i_cpu_en                 (cpu_enable),
        .o_imem_read_enable       (imem_read_enable),
        .o_imem_word_addr         (imem_word_addr),
        .i_imem_read_data         (imem_read_data),
        .o_dmem_read_enable       (dmem_read_enable),
        .o_dmem_word_addr         (dmem_word_addr),
        .o_dmem_write_byte_enable (dmem_write_byte_enable),
        .o_dmem_write_data        (dmem_write_data),
        .i_dmem_read_data         (dmem_read_data),
        .i_debug_reg_addr         (debug_reg_addr),
        .o_debug_reg_data         (debug_reg_data),
        .i_n_words                (n_words),
        .o_pc                     (cpu_pc),
        .o_halting                (cpu_halting),
        .o_done                   (cpu_done),
        .o_done_reason            (cpu_done_reason)
    );

    // =========================================================================
    // Codificacion de instrucciones
    // =========================================================================
    function [31:0] encode_addi(input [4:0] rd, input [4:0] rs1, input [11:0] immediate);
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function [31:0] encode_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function [31:0] encode_lw(input [4:0] rd, input [4:0] rs1, input [11:0] immediate);
        encode_lw = {immediate, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function [31:0] encode_sw(input [4:0] rs2, input [4:0] rs1, input [11:0] immediate);
        encode_sw = {immediate[11:5], rs2, rs1, 3'b010, immediate[4:0], 7'b0100011};
    endfunction

    function [31:0] encode_branch(input [2:0] funct3, input [4:0] rs1, input [4:0] rs2,
                                  input [31:0] byte_offset);
        encode_branch = {byte_offset[12], byte_offset[10:5], rs2, rs1, funct3,
                         byte_offset[4:1], byte_offset[11], 7'b1100011};
    endfunction

    function [31:0] encode_jal(input [4:0] rd, input [31:0] byte_offset);
        encode_jal = {byte_offset[20], byte_offset[10:1], byte_offset[11],
                      byte_offset[19:12], rd, 7'b1101111};
    endfunction

    // =========================================================================
    // Contabilidad de pruebas
    // =========================================================================
    reg [8*64-1:0] current_test_name;
    integer        checks_passed;
    integer        checks_failed;
    integer        failures_at_test_start;
    integer        tests_total;
    integer        tests_failed;

    task begin_test(input [8*64-1:0] test_name);
        begin
            current_test_name      = test_name;
            failures_at_test_start = checks_failed;
            tests_total            = tests_total + 1;
        end
    endtask

    task end_test;
        begin
            if (checks_failed == failures_at_test_start) begin
                $display("PASS  %0s", current_test_name);
            end else begin
                tests_failed = tests_failed + 1;
                $display("FAIL  %0s", current_test_name);
            end
        end
    endtask

    task check_equal(input [8*40-1:0] what, input [31:0] actual, input [31:0] expected);
        begin
            if (actual === expected) begin
                checks_passed = checks_passed + 1;
            end else begin
                checks_failed = checks_failed + 1;
                $display("  FALLA [%0s] %0s: obtenido 0x%08h, esperado 0x%08h",
                         current_test_name, what, actual, expected);
            end
        end
    endtask

    // =========================================================================
    // Sincronizacion y acceso al estado
    // =========================================================================
    // Las entradas se cambian 1 ns despues del flanco y las salidas se leen ahi
    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check_register(input [4:0] register_index, input [31:0] expected_value);
        reg [8*40-1:0] label;
        begin
            $sformat(label, "x%0d", register_index);
            debug_reg_addr = register_index;
            #1;
            check_equal(label, debug_reg_data, expected_value);
        end
    endtask

    // La memoria de datos conserva su contenido entre programas: se limpia por
    // jerarquia para que una comparacion no pase con datos de una prueba anterior
    task clear_data_memory_words(input integer word_count);
        integer word_index;
        begin
            for (word_index = 0; word_index < word_count; word_index = word_index + 1) begin
                data_mem.byte_bank[0].bank[word_index] = 8'h00;
                data_mem.byte_bank[1].bank[word_index] = 8'h00;
                data_mem.byte_bank[2].bank[word_index] = 8'h00;
                data_mem.byte_bank[3].bank[word_index] = 8'h00;
            end
        end
    endtask

    task check_data_word(input integer word_index, input [31:0] expected_value);
        reg [8*40-1:0] label;
        begin
            $sformat(label, "dmem[%0d]", word_index);
            debug_dmem_word_addr = word_index;
            tick;
            check_equal(label, debug_dmem_read_data, expected_value);
        end
    endtask

    reg [31:0] register_snapshot [0:31];

    task capture_registers;
        integer register_index;
        begin
            for (register_index = 0; register_index < 32; register_index = register_index + 1) begin
                debug_reg_addr = register_index;
                #1;
                register_snapshot[register_index] = debug_reg_data;
            end
        end
    endtask

    task check_registers_match_snapshot;
        integer register_index;
        begin
            for (register_index = 0; register_index < 32; register_index = register_index + 1) begin
                debug_reg_addr = register_index;
                #1;
                check_equal("registro estable tras done", debug_reg_data,
                            register_snapshot[register_index]);
            end
        end
    endtask

    // =========================================================================
    // Carga y ejecucion
    // =========================================================================
    reg [31:0] program_image [0:(1 << MEM_ADDR_WIDTH) - 1];
    integer    cycles_to_done;

    task send_byte(input [7:0] value);
        begin
            loader_byte_valid = 1'b1;
            loader_byte_data  = value;
            tick;
            loader_byte_valid = 1'b0;
        end
    endtask

    // Envia program_image como un mensaje LOAD_PROGRAM completo
    task send_program(input integer word_count);
        integer    word_index;
        integer    lane;
        reg [31:0] current_word;
        begin
            cpu_enable            = 1'b0;
            loader_payload_length = 2 + 4 * word_count;
            loader_start          = 1'b1;
            tick;
            loader_start = 1'b0;

            send_byte(word_count[7:0]);
            send_byte(word_count[15:8]);
            for (word_index = 0; word_index < word_count; word_index = word_index + 1) begin
                current_word = program_image[word_index];
                for (lane = 0; lane < 4; lane = lane + 1)
                    send_byte(current_word[8*lane +: 8]);
            end

            tick;
            check_equal("carga valida",      program_valid,   1);
            check_equal("error de carga",    load_error_code, 0);
            check_equal("N_WORDS cargado",   n_words,         word_count);
        end
    endtask

    task reset_cpu;
        begin
            cpu_enable        = 1'b0;
            cpu_reset_request = 1'b1;
            tick;
            cpu_reset_request = 1'b0;
        end
    endtask

    // Un ciclo de clock con cpu_en en alto y unos ciclos de pausa (modo STEP)
    task step_cpu;
        begin
            cpu_enable = 1'b1;
            tick;
            cpu_enable = 1'b0;
            repeat (3) tick;
        end
    endtask

    // Con done en alto el CPU no debe cambiar aunque siga habilitado
    task check_state_is_stable_after_done;
        reg [31:0] pc_at_done;
        reg [1:0]  reason_at_done;
        begin
            pc_at_done     = cpu_pc;
            reason_at_done = cpu_done_reason;
            capture_registers;
            repeat (CYCLES_AFTER_DONE) tick;
            check_equal("done estable",   cpu_done,        1);
            check_equal("PC estable",     cpu_pc,          pc_at_done);
            check_equal("motivo estable", cpu_done_reason, reason_at_done);
            check_registers_match_snapshot;
        end
    endtask

    task run_until_done;
        begin
            cycles_to_done = 0;
            cpu_enable     = 1'b1;
            while (!cpu_done && cycles_to_done < MAX_RUN_CYCLES) begin
                tick;
                cycles_to_done = cycles_to_done + 1;
            end

            check_equal("termino antes del limite", cpu_done, 1);
            check_equal("etapas validas al terminar",
                        {dut.if_id_valid, dut.id_ex_valid, dut.ex_mem_valid, dut.mem_wb_valid}, 0);
            check_state_is_stable_after_done;
            cpu_enable = 1'b0;
        end
    endtask

    // Despues de HALT no puede entrar ninguna instruccion valida a IF/ID ni a ID/EX
    always @(posedge clk) begin
        if (cpu_halting && (dut.if_id_valid || dut.id_ex_valid)) begin
            checks_failed = checks_failed + 1;
            $display("  FALLA [%0s] entro una instruccion valida al pipeline despues de HALT",
                     current_test_name);
        end
    end

    // =========================================================================
    // Pruebas
    // =========================================================================
    task test_halt_alone;
        begin
            begin_test("HALT como unica instruccion");
            program_image[0] = HALT_WORD;
            send_program(1);
            run_until_done;
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("halting",           cpu_halting,     1);
            check_equal("ciclos hasta done", cycles_to_done,  0 + CYCLES_TO_DRAIN);
            check_equal("PC retenido",       cpu_pc,          4);
            end_test;
        end
    endtask

    task test_instructions_before_halt_complete;
        begin
            begin_test("las instrucciones previas a HALT completan sus escrituras");
            program_image[0] = encode_addi(1, 0, 5);
            program_image[1] = encode_addi(2, 0, 7);
            program_image[2] = encode_add(3, 1, 2);
            program_image[3] = HALT_WORD;
            send_program(4);
            run_until_done;
            check_register(1, 5);
            check_register(2, 7);
            check_register(3, 12);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("ciclos hasta done", cycles_to_done,  3 + CYCLES_TO_DRAIN);
            end_test;
        end
    endtask

    task test_store_right_before_halt;
        begin
            begin_test("un store inmediatamente anterior a HALT se completa");
            clear_data_memory_words(16);
            program_image[0] = encode_addi(1, 0, 85);
            program_image[1] = encode_sw(1, 0, 16);
            program_image[2] = HALT_WORD;
            send_program(3);
            run_until_done;
            check_data_word(4, 85);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("ciclos hasta done", cycles_to_done,  2 + CYCLES_TO_DRAIN);
            end_test;
        end
    endtask

    task test_load_use_before_halt;
        begin
            begin_test("load-use seguido de HALT: el stall no pierde el HALT");
            clear_data_memory_words(16);
            program_image[0] = encode_addi(1, 0, 21);
            program_image[1] = encode_sw(1, 0, 0);
            program_image[2] = encode_lw(2, 0, 0);
            program_image[3] = encode_add(3, 2, 2);
            program_image[4] = HALT_WORD;
            send_program(5);
            run_until_done;
            check_register(3, 42);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("ciclos hasta done", cycles_to_done,  4 + 1 + CYCLES_TO_DRAIN);  // 1 stall
            end_test;
        end
    endtask

    task test_instructions_after_halt_have_no_effect;
        begin
            begin_test("las instrucciones posteriores a HALT no producen efectos");
            clear_data_memory_words(16);
            program_image[0] = encode_addi(1, 0, 1);
            program_image[1] = HALT_WORD;
            program_image[2] = encode_addi(2, 0, 2);
            program_image[3] = encode_addi(3, 0, 3);
            program_image[4] = encode_sw(1, 0, 32);
            send_program(5);
            run_until_done;
            check_register(1, 1);
            check_register(2, 0);
            check_register(3, 0);
            check_data_word(8, 0);
            check_equal("motivo",      cpu_done_reason, `DONE_REASON_HALT);
            check_equal("PC retenido", cpu_pc,          16);    // HALT en 4, mas 12
            end_test;
        end
    endtask

    task test_halt_on_discarded_branch_path;
        begin
            begin_test("un HALT en el camino descartado de un branch no detiene el CPU");
            program_image[0] = encode_branch(3'b000, 0, 0, 12);   // beq x0, x0 -> palabra 3
            program_image[1] = HALT_WORD;                         // descartado
            program_image[2] = encode_addi(5, 0, 99);             // descartado
            program_image[3] = encode_addi(1, 0, 1);
            program_image[4] = HALT_WORD;
            send_program(5);
            run_until_done;
            check_register(1, 1);
            check_register(5, 0);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("ciclos hasta done", cycles_to_done,  2 + 2 + CYCLES_TO_DRAIN);  // 2 de penalizacion
            end_test;
        end
    endtask

    task test_words_that_are_not_halt;
        begin
            begin_test("solo la palabra 0x0000000B es HALT");
            program_image[0] = 32'h0000008B;                      // custom-0 con rd = 1
            program_image[1] = 32'h0000100B;                      // custom-0 con funct3 = 1
            program_image[2] = encode_addi(1, 0, 5);
            program_image[3] = HALT_WORD;
            send_program(4);
            run_until_done;
            check_register(1, 5);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_HALT);
            check_equal("ciclos hasta done", cycles_to_done,  3 + CYCLES_TO_DRAIN);
            end_test;
        end
    endtask

    task test_image_without_halt;
        begin
            begin_test("imagen sin HALT: termina por fin de imagen");
            program_image[0] = encode_addi(1, 0, 3);
            program_image[1] = encode_addi(2, 0, 4);
            program_image[2] = encode_add(3, 1, 2);
            send_program(3);
            run_until_done;
            check_register(3, 7);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_END_OF_IMAGE);
            check_equal("halting",           cpu_halting,     0);
            check_equal("PC retenido",       cpu_pc,          12);
            check_equal("ciclos hasta done", cycles_to_done,  2 + CYCLES_TO_DRAIN);
            end_test;
        end
    endtask

    // El fin de imagen no es permanente: el branch en EX devuelve el PC a la imagen
    task test_loop_over_image_end;
        begin
            begin_test("un branch tomado en el borde de la imagen sigue iterando");
            program_image[0] = encode_addi(1, 0, 3);
            program_image[1] = encode_addi(1, 1, -1);
            program_image[2] = encode_addi(2, 2, 1);
            program_image[3] = encode_branch(3'b001, 1, 0, -8);   // bne x1, x0 -> palabra 1
            send_program(4);
            run_until_done;
            check_register(1, 0);
            check_register(2, 3);
            check_equal("motivo",      cpu_done_reason, `DONE_REASON_END_OF_IMAGE);
            check_equal("PC retenido", cpu_pc,          16);
            end_test;
        end
    endtask

    task test_jump_outside_image;
        begin
            begin_test("un salto fuera de la imagen termina por fin de imagen");
            program_image[0] = encode_addi(1, 0, 1);
            program_image[1] = encode_jal(0, 32);                 // destino 36, fuera de la imagen
            program_image[2] = encode_addi(2, 0, 2);              // descartado
            send_program(3);
            run_until_done;
            check_register(1, 1);
            check_register(2, 0);
            check_equal("motivo",      cpu_done_reason, `DONE_REASON_END_OF_IMAGE);
            check_equal("PC retenido", cpu_pc,          36);
            end_test;
        end
    endtask

    task test_reprogramming_with_shorter_images;
        begin
            begin_test("reprogramar con imagenes mas cortas no ejecuta residuos");

            // Programa A: 8 palabras con un HALT en la palabra 3
            program_image[0] = encode_addi(1, 0, 1);
            program_image[1] = encode_addi(2, 0, 2);
            program_image[2] = encode_addi(3, 0, 3);
            program_image[3] = HALT_WORD;
            program_image[4] = encode_addi(4, 0, 4);
            program_image[5] = encode_addi(5, 0, 5);
            program_image[6] = encode_addi(6, 0, 6);
            program_image[7] = encode_addi(7, 0, 7);
            send_program(8);
            run_until_done;
            check_register(3, 3);
            check_register(4, 0);
            check_equal("A: motivo", cpu_done_reason, `DONE_REASON_HALT);

            // Programa B: 3 palabras sin HALT; el HALT de A queda como residuo
            // justo en la palabra 3, donde el PC se detiene al llegar al final
            program_image[0] = encode_addi(10, 0, 10);
            program_image[1] = encode_addi(11, 0, 11);
            program_image[2] = encode_addi(12, 0, 12);
            send_program(3);
            check_equal("B: PC tras la carga",     cpu_pc,   0);
            check_equal("B: done antes de correr", cpu_done, 0);
            run_until_done;
            check_register(12, 12);
            check_register(4, 0);
            check_register(7, 0);
            check_equal("B: motivo",            cpu_done_reason, `DONE_REASON_END_OF_IMAGE);
            check_equal("B: halting",           cpu_halting,     0);
            check_equal("B: ciclos hasta done", cycles_to_done,  2 + CYCLES_TO_DRAIN);

            // Programa C: solo HALT; las palabras 1 a 7 de A ya no se ejecutan
            program_image[0] = HALT_WORD;
            send_program(1);
            run_until_done;
            check_register(10, 0);
            check_register(1, 0);
            check_equal("C: motivo", cpu_done_reason, `DONE_REASON_HALT);
            end_test;
        end
    endtask

    task test_reset_clears_halt_and_reruns;
        reg [31:0] first_run_cycles;
        begin
            begin_test("RESET limpia HALT y la imagen se ejecuta de nuevo igual");
            program_image[0] = encode_addi(1, 0, 5);
            program_image[1] = encode_addi(2, 1, 1);
            program_image[2] = HALT_WORD;
            send_program(3);
            run_until_done;
            first_run_cycles = cycles_to_done;
            check_register(2, 6);

            reset_cpu;
            check_equal("halting tras RESET", cpu_halting, 0);
            check_equal("done tras RESET",    cpu_done,    0);
            check_equal("PC tras RESET",      cpu_pc,      0);
            check_register(2, 0);

            run_until_done;
            check_register(2, 6);
            check_equal("motivo",              cpu_done_reason, `DONE_REASON_HALT);
            check_equal("mismos ciclos",       cycles_to_done,  first_run_cycles);
            end_test;
        end
    endtask

    // Con cpu_en en 0 el HALT puede quedar en EX sin confirmarse
    task test_single_step_with_pauses;
        begin
            begin_test("paso a paso: HALT en EX no se confirma con el CPU pausado");
            program_image[0] = encode_addi(1, 0, 1);
            program_image[1] = HALT_WORD;
            send_program(2);

            repeat (3) step_cpu;                 // HALT queda en EX
            repeat (4) tick;                     // CPU pausado
            check_equal("halting pausado", cpu_halting, 0);
            check_equal("done pausado",    cpu_done,    0);

            step_cpu;                            // el HALT se confirma
            check_equal("halting tras el paso", cpu_halting, 1);
            check_equal("done con HALT en MEM", cpu_done,    0);

            step_cpu;
            check_equal("done con HALT en WB", cpu_done, 0);

            step_cpu;                            // el pipeline queda vacio
            check_equal("done al vaciar", cpu_done,        1);
            check_equal("motivo",         cpu_done_reason, `DONE_REASON_HALT);
            check_register(1, 1);
            end_test;
        end
    endtask

    // Limite de la memoria: pc[31:2] = 1024 contra N_WORDS = 1024
    task test_image_of_maximum_length;
        integer word_index;
        begin
            begin_test("imagen de 1024 palabras sin HALT");
            for (word_index = 0; word_index < 1024; word_index = word_index + 1)
                program_image[word_index] = encode_addi(1, 1, 1);
            send_program(1024);
            run_until_done;
            check_register(1, 1024);
            check_equal("motivo",            cpu_done_reason, `DONE_REASON_END_OF_IMAGE);
            check_equal("PC retenido",       cpu_pc,          4096);
            check_equal("ciclos hasta done", cycles_to_done,  1023 + CYCLES_TO_DRAIN);
            end_test;
        end
    endtask

    // =========================================================================
    // Secuencia principal
    // =========================================================================
    initial begin
        checks_passed         = 0;
        checks_failed         = 0;
        tests_total           = 0;
        tests_failed          = 0;
        current_test_name     = "inicio";
        system_reset          = 1'b1;
        cpu_reset_request     = 1'b0;
        cpu_enable            = 1'b0;
        loader_start          = 1'b0;
        loader_payload_length = 16'd0;
        loader_byte_valid     = 1'b0;
        loader_byte_data      = 8'd0;
        debug_reg_addr        = 5'd0;
        debug_dmem_word_addr  = {MEM_ADDR_WIDTH{1'b0}};

        repeat (3) tick;
        system_reset = 1'b0;
        tick;

        test_halt_alone;
        test_instructions_before_halt_complete;
        test_store_right_before_halt;
        test_load_use_before_halt;
        test_instructions_after_halt_have_no_effect;
        test_halt_on_discarded_branch_path;
        test_words_that_are_not_halt;
        test_image_without_halt;
        test_loop_over_image_end;
        test_jump_outside_image;
        test_reprogramming_with_shorter_images;
        test_reset_clears_halt_and_reruns;
        test_single_step_with_pauses;
        test_image_of_maximum_length;

        $display("--------------------------------------------------------------");
        $display("Pruebas: %0d, con fallas: %0d | Verificaciones: %0d ok, %0d con falla",
                 tests_total, tests_failed, checks_passed, checks_failed);
        if (checks_failed == 0) $display("RESULTADO: TODO OK");
        else                    $display("RESULTADO: HAY FALLAS");
        $finish;
    end

    // Corta si algo se cuelga
    initial begin
        #(CLOCK_PERIOD_NS * 100000);
        $display("RESULTADO: TIMEOUT DEL TESTBENCH");
        $finish;
    end

endmodule
