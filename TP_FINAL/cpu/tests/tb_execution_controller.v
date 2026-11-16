`timescale 1ns / 1ps
`include "riscv_defs.vh"
`include "execution_defs.vh"
`include "program_loader_defs.vh"
`include "done_reason_defs.vh"

module tb_execution_controller;

    localparam ADDR_WIDTH              = 10;
    localparam CLOCK_PERIOD_NS         = 10;
    localparam LOADER_TIMEOUT_CYCLES   = 200;
    localparam RESPONSE_TIMEOUT_CYCLES = 20;
    localparam MAX_STEPS               = 100;

    // Foto del CPU: 32 registros + PC, validez y datos de cada etapa
    localparam REGISTER_FILE_BITS = 32 * 32;
    localparam SNAPSHOT_BITS      = REGISTER_FILE_BITS + 320;   // los bits que sobran quedan en 0

    // =========================================================================
    // Senales
    // =========================================================================
    reg  clk          = 1'b0;
    reg  system_reset = 1'b1;

    // ---- Debug Unit emulada -------------------------------------------------
    reg         run_request     = 1'b0;
    reg         step_request    = 1'b0;
    reg         reset_request   = 1'b0;
    reg         load_start      = 1'b0;
    reg  [15:0] load_length     = 16'd0;
    reg         load_byte_valid = 1'b0;
    reg  [7:0]  load_byte_data  = 8'd0;
    reg  [4:0]  debug_reg_addr  = 5'd0;
    reg  [ADDR_WIDTH-1:0] debug_dmem_addr = {ADDR_WIDTH{1'b0}};

    // ---- program_loader -----------------------------------------------------
    wire                  imem_write_enable;
    wire [ADDR_WIDTH-1:0] imem_write_word_addr;
    wire [31:0]           imem_write_data;
    wire                  loader_cpu_reset;
    wire                  program_valid;
    wire [ADDR_WIDTH:0]   n_words;
    wire                  load_finished;
    wire [1:0]            load_error_code;

    // ---- execution_controller -----------------------------------------------
    wire       cpu_enable;
    wire       controller_cpu_reset;
    wire [2:0] system_state;
    wire       command_finished;
    wire [1:0] command_result;

    // ---- CPU y memorias -----------------------------------------------------
    wire cpu_reset = system_reset || controller_cpu_reset || loader_cpu_reset;

    wire                  imem_read_enable;
    wire [ADDR_WIDTH-1:0] imem_read_word_addr;
    wire [31:0]           imem_read_data;
    wire                  dmem_read_enable;
    wire [ADDR_WIDTH-1:0] dmem_word_addr;
    wire [3:0]            dmem_write_byte_enable;
    wire [31:0]           dmem_write_data;
    wire [31:0]           dmem_read_data;
    wire [31:0]           debug_dmem_data;
    wire [31:0]           debug_reg_data;
    wire [31:0]           cpu_pc;
    wire                  cpu_halting;
    wire                  cpu_done;
    wire [1:0]            cpu_done_reason;

    always #(CLOCK_PERIOD_NS / 2) clk = ~clk;

    // =========================================================================
    // Modulos bajo prueba
    // =========================================================================
    program_loader #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .RX_TIMEOUT_CYCLES (LOADER_TIMEOUT_CYCLES)
    ) loader (
        .i_clk                  (clk),
        .i_reset                (system_reset),
        .i_load_start           (load_start),
        .i_payload_length_bytes (load_length),
        .i_byte_valid           (load_byte_valid),
        .i_byte_data            (load_byte_data),
        .o_imem_write_enable    (imem_write_enable),
        .o_imem_write_word_addr (imem_write_word_addr),
        .o_imem_write_data      (imem_write_data),
        .o_cpu_reset            (loader_cpu_reset),
        .o_program_valid        (program_valid),
        .o_n_words              (n_words),
        .o_load_finished        (load_finished),
        .o_load_error_code      (load_error_code)
    );

    execution_controller controller (
        .i_clk              (clk),
        .i_reset            (system_reset),
        .i_run_request      (run_request),
        .i_step_request     (step_request),
        .i_reset_request    (reset_request),
        .i_load_finished    (load_finished),
        .i_load_error_code  (load_error_code),
        .i_program_valid    (program_valid),
        .i_cpu_done         (cpu_done),
        .o_cpu_enable       (cpu_enable),
        .o_cpu_reset        (controller_cpu_reset),
        .o_system_state     (system_state),
        .o_command_finished (command_finished),
        .o_command_result   (command_result)
    );

    cpu_core #(.MEM_ADDR_WIDTH(ADDR_WIDTH)) cpu (
        .i_clk                    (clk),
        .i_cpu_reset              (cpu_reset),
        .i_cpu_en                 (cpu_enable),
        .o_imem_read_enable       (imem_read_enable),
        .o_imem_word_addr         (imem_read_word_addr),
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

    program_memory #(.ADDR_WIDTH(ADDR_WIDTH)) program_mem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_read_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_word_addr),
        .i_write_data      (imem_write_data)
    );

    data_memory #(.ADDR_WIDTH(ADDR_WIDTH)) data_mem (
        .i_clk               (clk),
        .i_read_enable       (dmem_read_enable),
        .i_word_addr         (dmem_word_addr),
        .i_write_byte_enable (dmem_write_byte_enable),
        .i_write_data        (dmem_write_data),
        .o_read_data         (dmem_read_data),
        .i_debug_word_addr   (debug_dmem_addr),
        .o_debug_read_data   (debug_dmem_data)
    );

    // =========================================================================
    // Verificaciones
    // =========================================================================
    integer error_count = 0;
    integer check_count = 0;

    task check(input condition, input [8*64-1:0] description);
        begin
            check_count = check_count + 1;
            if (!condition) begin
                error_count = error_count + 1;
                $display("[FAIL] %0s (t=%0t)", description, $time);
            end
        end
    endtask

    task idle(input integer cycles);
        begin
            repeat (cycles) @(negedge clk);
        end
    endtask

    // =========================================================================
    // Monitores permanentes
    // =========================================================================
    reg     command_in_flight = 1'b0;   // el testbench espera la respuesta de una orden
    integer enabled_cycle_count = 0;    // ciclos en que el CPU avanzo
    integer store_write_count   = 0;    // ciclos con escritura en la memoria de datos
    integer unexpected_enable_count = 0;
    integer write_while_paused_count = 0;

    always @(posedge clk) begin
        if (cpu_enable && !cpu_reset)
            enabled_cycle_count = enabled_cycle_count + 1;

        if (dmem_write_byte_enable != 4'b0000)
            store_write_count = store_write_count + 1;

        // cpu_enable solo puede estar en alto durante un STEP o en RUNNING
        if (cpu_enable && !command_in_flight && system_state != `EXEC_STATE_RUNNING)
            unexpected_enable_count = unexpected_enable_count + 1;

        // Con el CPU pausado no se escribe la memoria de datos
        if (dmem_write_byte_enable != 4'b0000 && !cpu_enable)
            write_while_paused_count = write_while_paused_count + 1;
    end

    // =========================================================================
    // Foto del estado del CPU
    // =========================================================================
    // Una etapa con valid = 0 esta vacia: sus campos no se comparan
    function [31:0] only_if_valid(input valid, input [31:0] value);
        only_if_valid = valid ? value : 32'd0;
    endfunction

    // Atajo de simulacion: lee los registros por jerarquia (cpu.register_file.registers)
    task capture_cpu_state(output [SNAPSHOT_BITS-1:0] snapshot);
        integer index;
        reg [REGISTER_FILE_BITS-1:0] register_file_bits;
        begin
            for (index = 0; index < 32; index = index + 1)
                register_file_bits[32*index +: 32] = cpu.register_file.registers[index];

            snapshot = {register_file_bits,
                        cpu.if_pc, cpu_halting,
                        cpu.if_id_valid, cpu.id_ex_valid, cpu.ex_mem_valid, cpu.mem_wb_valid,
                        only_if_valid(cpu.if_id_valid, cpu.if_id_pc),
                        only_if_valid(cpu.id_ex_valid, cpu.id_ex_pc),
                        only_if_valid(cpu.id_ex_valid, cpu.id_ex_instruction),
                        only_if_valid(cpu.ex_mem_valid, cpu.ex_mem_pc),
                        only_if_valid(cpu.ex_mem_valid, cpu.ex_mem_result),
                        only_if_valid(cpu.ex_mem_valid && cpu.ex_mem_mem_write, cpu.ex_mem_store_data),
                        only_if_valid(cpu.mem_wb_valid, cpu.mem_wb_pc),
                        only_if_valid(cpu.mem_wb_valid, cpu.mem_wb_result)};
        end
    endtask

    function [31:0] register_value(input [4:0] index);
        register_value = (index == 5'd0) ? 32'd0 : cpu.register_file.registers[index];
    endfunction

    function pipeline_is_empty(input dummy);
        pipeline_is_empty = !cpu.if_id_valid && !cpu.id_ex_valid
                         && !cpu.ex_mem_valid && !cpu.mem_wb_valid;
    endfunction

    // Traza de referencia: foto despues de cada ciclo habilitado del modo continuo
    reg [SNAPSHOT_BITS-1:0] reference_trace [0:MAX_STEPS-1];
    integer                 reference_trace_length = 0;
    reg                     trace_recording = 1'b0;
    reg                     cpu_advanced_last_cycle = 1'b0;
    reg [SNAPSHOT_BITS-1:0] trace_snapshot;

    always @(posedge clk)
        cpu_advanced_last_cycle <= cpu_enable && !cpu_reset;

    always @(negedge clk) begin
        if (trace_recording && cpu_advanced_last_cycle) begin
            capture_cpu_state(trace_snapshot);
            reference_trace[reference_trace_length] = trace_snapshot;
            reference_trace_length = reference_trace_length + 1;
        end
    end

    // =========================================================================
    // Ordenes de la Debug Unit emulada
    // =========================================================================
    reg [1:0] last_result;
    reg [2:0] state_after_command;
    integer   last_latency_cycles;

    task execute_command(input run, input step, input reset);
        integer waited;
        begin
            @(negedge clk);
            command_in_flight = 1'b1;
            run_request   = run;
            step_request  = step;
            reset_request = reset;
            @(negedge clk);
            run_request   = 1'b0;
            step_request  = 1'b0;
            reset_request = 1'b0;

            waited = 0;
            while (!command_finished && waited < RESPONSE_TIMEOUT_CYCLES) begin
                @(negedge clk);
                waited = waited + 1;
            end
            check(command_finished, "la orden recibe respuesta");

            last_result         = command_result;
            state_after_command = system_state;
            last_latency_cycles = waited + 1;
            command_in_flight   = 1'b0;
        end
    endtask

    task send_run;   begin execute_command(1'b1, 1'b0, 1'b0); end endtask
    task send_step;  begin execute_command(1'b0, 1'b1, 1'b0); end endtask
    task send_reset; begin execute_command(1'b0, 1'b0, 1'b1); end endtask

    task wait_until_state(input [2:0] target_state, input integer max_cycles);
        integer waited;
        begin
            waited = 0;
            while (system_state != target_state && waited < max_cycles) begin
                @(negedge clk);
                waited = waited + 1;
            end
            check(system_state == target_state, "el sistema llega al estado esperado");
        end
    endtask

    task apply_system_reset;
        begin
            system_reset = 1'b1;
            idle(3);
            system_reset = 1'b0;
            idle(2);
        end
    endtask

    // =========================================================================
    // Carga de programa (bytes que la Debug Unit le entrega al loader)
    // =========================================================================
    reg [31:0] program_image [0:63];
    integer    program_length;

    task send_byte(input [7:0] value);
        begin
            @(negedge clk);
            load_byte_valid = 1'b1;
            load_byte_data  = value;
            @(negedge clk);
            load_byte_valid = 1'b0;
        end
    endtask

    task send_load_message(input [15:0] payload_length,
                           input [15:0] declared_words,
                           input integer words_sent);
        integer word_index;
        begin
            @(negedge clk);
            load_start  = 1'b1;
            load_length = payload_length;
            @(negedge clk);
            load_start  = 1'b0;

            send_byte(declared_words[7:0]);
            send_byte(declared_words[15:8]);
            for (word_index = 0; word_index < words_sent; word_index = word_index + 1) begin
                send_byte(program_image[word_index][7:0]);
                send_byte(program_image[word_index][15:8]);
                send_byte(program_image[word_index][23:16]);
                send_byte(program_image[word_index][31:24]);
            end
        end
    endtask

    task load_program;
        begin
            send_load_message(2 + 4 * program_length, program_length, program_length);
            idle(5);
        end
    endtask

    // =========================================================================
    // Programas de prueba (mini-ensamblador local)
    // =========================================================================
    function [31:0] asm_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        asm_addi = {imm, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_OP_IMM};
    endfunction

    function [31:0] asm_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        asm_add = {`FUNCT7_BASE, rs2, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_R_TYPE};
    endfunction

    function [31:0] asm_lw(input [4:0] rd, input [11:0] imm, input [4:0] rs1);
        asm_lw = {imm, rs1, `FUNCT3_WORD, rd, `OPCODE_LOAD};
    endfunction

    function [31:0] asm_sw(input [4:0] rs2, input [11:0] imm, input [4:0] rs1);
        asm_sw = {imm[11:5], rs2, rs1, `FUNCT3_WORD, imm[4:0], `OPCODE_STORE};
    endfunction

    function [31:0] asm_beq(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
        asm_beq = {offset[12], offset[10:5], rs2, rs1, `FUNCT3_BEQ,
                   offset[4:1], offset[11], `OPCODE_BRANCH};
    endfunction

    function [31:0] asm_jal(input [4:0] rd, input [20:0] offset);
        asm_jal = {offset[20], offset[10:1], offset[11], offset[19:12], rd, `OPCODE_JAL};
    endfunction

    // Forwarding, store, load-use (stall), branch tomado (flush) y HALT.
    // Resultado esperado: x1=5 x2=8 x3=8 x4=13 x7=1, mem[0]=8; x5, x6 y x8 quedan en 0
    task build_mixed_program;
        begin
            program_image[0]  = asm_addi(1, 0, 5);
            program_image[1]  = asm_addi(2, 1, 3);
            program_image[2]  = asm_sw(2, 0, 0);
            program_image[3]  = asm_lw(3, 0, 0);
            program_image[4]  = asm_add(4, 3, 1);
            program_image[5]  = asm_beq(4, 4, 12);
            program_image[6]  = asm_addi(5, 0, 99);        // anulada por el branch
            program_image[7]  = asm_addi(6, 0, 99);        // anulada por el branch
            program_image[8]  = asm_addi(7, 0, 1);
            program_image[9]  = `HALT_INSTRUCTION;
            program_image[10] = asm_addi(8, 0, 77);        // posterior a HALT: no se ejecuta
            program_length    = 11;
        end
    endtask

    // Termina por HALT: x10 = 42
    task build_short_program;
        begin
            program_image[0] = asm_addi(10, 0, 42);
            program_image[1] = `HALT_INSTRUCTION;
            program_length   = 2;
        end
    endtask

    // Sin HALT: termina por fin de imagen
    task build_no_halt_program;
        begin
            program_image[0] = asm_addi(11, 0, 7);
            program_image[1] = asm_addi(12, 0, 9);
            program_length   = 2;
        end
    endtask

    // Lazo infinito: x1 aumenta mientras el CPU corre
    task build_endless_loop_program;
        begin
            program_image[0] = asm_addi(1, 1, 1);
            program_image[1] = asm_jal(0, -4);
            program_length   = 2;
        end
    endtask

    task read_data_memory_word(input [ADDR_WIDTH-1:0] word_addr, output [31:0] value);
        begin
            debug_dmem_addr = word_addr;
            idle(2);
            value = debug_dmem_data;
        end
    endtask

    // =========================================================================
    // Pruebas
    // =========================================================================
    reg [SNAPSHOT_BITS-1:0] snapshot_before;
    reg [SNAPSHOT_BITS-1:0] snapshot_after;
    reg [31:0]              memory_value;
    integer                 cycles_before;
    integer                 stores_before;
    integer                 steps_to_done;

    task test_empty_system_rejects_execution;
        begin
            $display("[TEST] sin programa: RUN y STEP se rechazan");
            check(system_state == `EXEC_STATE_EMPTY, "tras el reset el estado es EMPTY");
            cycles_before = enabled_cycle_count;

            send_step;
            check(last_result == `EXEC_RESULT_NO_PROGRAM, "STEP en EMPTY responde NO_PROGRAM");
            send_run;
            check(last_result == `EXEC_RESULT_NO_PROGRAM, "RUN en EMPTY responde NO_PROGRAM");
            check(state_after_command == `EXEC_STATE_EMPTY, "el rechazo no cambia el estado");

            send_reset;
            check(last_result == `EXEC_RESULT_OK, "RESET en EMPTY responde OK");
            check(state_after_command == `EXEC_STATE_EMPTY, "RESET sin programa deja EMPTY");
            check(enabled_cycle_count == cycles_before, "el CPU nunca avanzo");
        end
    endtask

    task test_loaded_program_is_ready;
        begin
            $display("[TEST] la carga deja el sistema en READY");
            build_mixed_program;
            load_program;
            check(system_state == `EXEC_STATE_READY, "carga completa -> READY");
            check(program_valid && n_words == program_length, "programa valido con N_WORDS correcto");
            check(cpu_pc == 32'd0 && pipeline_is_empty(1'b0), "CPU en reset: PC = 0 y pipeline vacio");
            check(!cpu_done, "done no se activa antes de ejecutar");
        end
    endtask

    task test_pause_keeps_cpu_state;
        begin
            $display("[TEST] con el CPU pausado nada cambia");
            capture_cpu_state(snapshot_before);
            cycles_before = enabled_cycle_count;
            idle(50);
            capture_cpu_state(snapshot_after);
            check(snapshot_after === snapshot_before, "50 ciclos de reloj sin orden no alteran el CPU");
            check(enabled_cycle_count == cycles_before, "cpu_enable permanece en 0");
        end
    endtask

    task test_single_step_advances_one_cycle;
        begin
            $display("[TEST] STEP avanza exactamente un ciclo");
            cycles_before = enabled_cycle_count;
            send_step;
            check(last_result == `EXEC_RESULT_OK, "STEP desde READY responde OK");
            check(state_after_command == `EXEC_STATE_PAUSED, "STEP desde READY -> PAUSED");
            check(enabled_cycle_count == cycles_before + 1, "un STEP habilita un solo ciclo");
            $display("       latencia de respuesta de STEP: %0d ciclos", last_latency_cycles);
            check(last_latency_cycles <= 4, "la respuesta llega en pocos ciclos");
            check(cpu_pc == 32'd4 && cpu.if_id_valid && cpu.if_id_pc == 32'd0 && !cpu.id_ex_valid,
                  "IF busco la primera instruccion");

            send_step;
            check(cpu_pc == 32'd8 && cpu.if_id_pc == 32'd4 && cpu.id_ex_valid && cpu.id_ex_pc == 32'd0,
                  "la primera instruccion paso a ID/EX");

            capture_cpu_state(snapshot_before);
            idle(20);
            capture_cpu_state(snapshot_after);
            check(snapshot_after === snapshot_before, "la foto posterior al paso es estable");
        end
    endtask

    // Paso a paso debe producir, ciclo a ciclo, el mismo estado que el modo continuo
    task test_stepping_matches_continuous_run;
        integer step_index;
        integer stall_steps;
        integer flush_steps;
        reg     stall_before;
        reg     redirect_before;
        reg     flush_before;
        reg [31:0] pc_before;
        reg [31:0] redirect_pc_before;
        begin
            $display("[TEST] paso a paso equivale al modo continuo, ciclo a ciclo");

            // ---- Referencia: ejecucion continua ----
            send_reset;
            check(state_after_command == `EXEC_STATE_READY, "RESET -> READY");
            check(cpu_pc == 32'd0 && pipeline_is_empty(1'b0) && register_value(1) == 32'd0,
                  "RESET deja PC, pipeline y registros en el estado inicial");

            reference_trace_length = 0;
            trace_recording = 1'b1;
            cycles_before = enabled_cycle_count;
            stores_before = store_write_count;
            send_run;
            check(last_result == `EXEC_RESULT_OK && state_after_command == `EXEC_STATE_RUNNING,
                  "RUN responde OK de inmediato con estado RUNNING");
            wait_until_state(`EXEC_STATE_DONE, 500);
            idle(5);
            trace_recording = 1'b0;

            check(cpu_done && cpu_done_reason == `DONE_REASON_HALT, "el modo continuo termina por HALT");
            check(pipeline_is_empty(1'b0), "pipeline vacio al terminar");
            check(register_value(1) == 5 && register_value(2) == 8 && register_value(3) == 8
               && register_value(4) == 13 && register_value(7) == 1,
                  "registros finales correctos");
            check(register_value(5) == 0 && register_value(6) == 0 && register_value(8) == 0,
                  "las instrucciones anuladas y las posteriores a HALT no escriben");
            read_data_memory_word(0, memory_value);
            check(memory_value == 32'd8, "mem[0] = 8");
            check(store_write_count - stores_before == 1, "el store se escribe una sola vez");

            // ---- Mismo programa, un STEP por ciclo ----
            send_reset;
            check(state_after_command == `EXEC_STATE_READY, "RESET antes de repetir -> READY");
            read_data_memory_word(0, memory_value);
            check(memory_value == 32'd8, "RESET conserva la memoria de datos");

            step_index  = 0;
            stall_steps = 0;
            flush_steps = 0;
            stores_before = store_write_count;

            while (system_state != `EXEC_STATE_DONE && step_index < MAX_STEPS) begin
                stall_before       = cpu.load_use_stall;
                flush_before       = cpu.front_end_flush;
                redirect_before    = cpu.ex_redirect;
                redirect_pc_before = cpu.ex_redirect_pc;
                pc_before          = cpu.if_pc;
                cycles_before      = enabled_cycle_count;

                send_step;
                step_index = step_index + 1;

                check(last_result == `EXEC_RESULT_OK, "cada STEP responde OK");
                check(enabled_cycle_count == cycles_before + 1, "cada STEP habilita exactamente un ciclo");

                capture_cpu_state(snapshot_after);
                if (snapshot_after !== reference_trace[step_index-1])
                    $display("       diferencia en el paso %0d", step_index);
                check(snapshot_after === reference_trace[step_index-1],
                      "el paso coincide con el ciclo del modo continuo");

                // Un stall o un flush consumen un paso como cualquier otro ciclo
                if (stall_before) begin
                    stall_steps = stall_steps + 1;
                    check(cpu.if_pc == pc_before, "durante el stall el PC no avanza");
                    check(!cpu.id_ex_valid, "durante el stall ID/EX recibe una burbuja");
                end
                if (flush_before) begin
                    flush_steps = flush_steps + 1;
                    check(!cpu.if_id_valid && !cpu.id_ex_valid, "el flush anula IF/ID e ID/EX");
                end
                if (redirect_before)
                    check(cpu.if_pc == redirect_pc_before, "el branch tomado redirige el PC");

                if (system_state != `EXEC_STATE_DONE)
                    check(system_state == `EXEC_STATE_PAUSED, "entre pasos el estado es PAUSED");
            end

            steps_to_done = step_index;
            check(system_state == `EXEC_STATE_DONE, "el ultimo paso lleva a DONE");
            check(cpu_done && cpu_done_reason == `DONE_REASON_HALT, "paso a paso termina por HALT");
            check(pipeline_is_empty(1'b0), "pipeline vacio al terminar (paso a paso)");
            check(stall_steps == 1, "se ejercito un stall load-use");
            check(flush_steps == 2, "se ejercitaron dos flush: branch tomado y HALT");
            check(store_write_count - stores_before == 1, "paso a paso escribe el store una sola vez");
            $display("       pasos hasta DONE: %0d | ciclos habilitados en continuo: %0d (stall: %0d, flush: %0d)",
                     steps_to_done, reference_trace_length, stall_steps, flush_steps);
            check(reference_trace_length == steps_to_done + 1,
                  "RUN gasta un unico ciclo extra al detectar done");
            check(reference_trace[reference_trace_length-1] === reference_trace[steps_to_done-1],
                  "el ciclo extra de RUN no cambia el estado");
        end
    endtask

    task test_execution_commands_in_done_state;
        begin
            $display("[TEST] en DONE, RUN y STEP se rechazan");
            cycles_before = enabled_cycle_count;
            send_step;
            check(last_result == `EXEC_RESULT_WRONG_STATE, "STEP en DONE responde WRONG_STATE");
            send_run;
            check(last_result == `EXEC_RESULT_WRONG_STATE, "RUN en DONE responde WRONG_STATE");
            check(state_after_command == `EXEC_STATE_DONE, "el rechazo no cambia el estado");
            check(enabled_cycle_count == cycles_before, "el CPU no avanza");
        end
    endtask

    task test_run_after_partial_stepping;
        integer step_index;
        begin
            $display("[TEST] RUN despues de algunos pasos continua desde donde quedo");
            send_reset;
            cycles_before = enabled_cycle_count;
            stores_before = store_write_count;

            for (step_index = 0; step_index < 3; step_index = step_index + 1)
                send_step;
            check(state_after_command == `EXEC_STATE_PAUSED, "tres pasos -> PAUSED");

            send_run;
            check(last_result == `EXEC_RESULT_OK && state_after_command == `EXEC_STATE_RUNNING,
                  "RUN desde PAUSED -> RUNNING");
            wait_until_state(`EXEC_STATE_DONE, 500);
            idle(5);

            capture_cpu_state(snapshot_after);
            check(snapshot_after === reference_trace[reference_trace_length-1],
                  "el estado final coincide con el de la ejecucion continua");
            check(enabled_cycle_count - cycles_before == reference_trace_length,
                  "ciclos totales = pasos + ciclos continuos");
            check(store_write_count - stores_before == 1, "cambiar de modo no duplica ni pierde el store");
        end
    endtask

    task test_halt_waits_for_next_step;
        integer step_count;
        begin
            $display("[TEST] HALT en EX con el CPU pausado: halting solo cambia al avanzar");
            send_reset;
            step_count = 0;
            while (!cpu.ex_halt_commit && step_count < MAX_STEPS) begin
                send_step;
                step_count = step_count + 1;
            end
            check(cpu.ex_halt_commit, "HALT llego a EX");
            check(!cpu_halting, "halting todavia no se activo");

            capture_cpu_state(snapshot_before);
            idle(10);
            capture_cpu_state(snapshot_after);
            check(snapshot_after === snapshot_before && !cpu_halting,
                  "10 ciclos pausado con HALT en EX no cambian nada");

            send_step;
            check(cpu_halting, "el siguiente STEP confirma HALT");
            check(!cpu.if_id_valid && !cpu.id_ex_valid, "el mismo ciclo anula IF/ID e ID/EX");
        end
    endtask

    task test_step_until_end_of_image;
        integer step_count;
        begin
            $display("[TEST] sin HALT: paso a paso termina por fin de imagen");
            build_no_halt_program;
            load_program;
            check(system_state == `EXEC_STATE_READY, "nueva carga -> READY");

            step_count = 0;
            while (system_state != `EXEC_STATE_DONE && step_count < MAX_STEPS) begin
                send_step;
                step_count = step_count + 1;
            end
            check(system_state == `EXEC_STATE_DONE, "llega a DONE");
            check(cpu_done_reason == `DONE_REASON_END_OF_IMAGE, "motivo: END_OF_IMAGE");
            check(cpu_pc == 32'd8, "el PC queda en 4 * N_WORDS");
            check(step_count == 6, "N + 4 pasos para una imagen recta de N instrucciones");
            check(register_value(11) == 7 && register_value(12) == 9, "registros finales correctos");
        end
    endtask

    task test_reset_aborts_running_program;
        begin
            $display("[TEST] RESET aborta una ejecucion continua");
            build_endless_loop_program;
            load_program;
            check(system_state == `EXEC_STATE_READY, "carga del lazo -> READY");

            send_run;
            idle(60);
            check(system_state == `EXEC_STATE_RUNNING, "el lazo sigue corriendo");
            check(register_value(1) > 5, "x1 aumenta mientras corre");

            send_step;
            check(last_result == `EXEC_RESULT_BUSY, "STEP en RUNNING responde BUSY");
            send_run;
            check(last_result == `EXEC_RESULT_BUSY, "RUN en RUNNING responde BUSY");
            check(state_after_command == `EXEC_STATE_RUNNING, "BUSY no cambia el estado");

            send_reset;
            check(last_result == `EXEC_RESULT_OK, "RESET en RUNNING responde OK");
            check(state_after_command == `EXEC_STATE_READY, "RESET aborta y deja READY");
            check(cpu_pc == 32'd0 && pipeline_is_empty(1'b0) && register_value(1) == 32'd0,
                  "el CPU vuelve al estado inicial");

            cycles_before = enabled_cycle_count;
            idle(20);
            check(enabled_cycle_count == cycles_before, "tras el abort el CPU queda detenido");

            send_step;
            check(state_after_command == `EXEC_STATE_PAUSED && cpu.if_id_valid,
                  "despues del abort se puede avanzar paso a paso");
        end
    endtask

    task test_controller_stays_responsive_while_paused;
        integer step_index;
        begin
            $display("[TEST] con el CPU pausado, control y carga siguen operativos");
            build_mixed_program;
            load_program;
            for (step_index = 0; step_index < 4; step_index = step_index + 1)
                send_step;
            check(state_after_command == `EXEC_STATE_PAUSED, "CPU pausado a mitad de ejecucion");

            capture_cpu_state(snapshot_before);
            cycles_before = enabled_cycle_count;
            idle(2000);
            capture_cpu_state(snapshot_after);
            check(snapshot_after === snapshot_before && enabled_cycle_count == cycles_before,
                  "2000 ciclos de pausa sin cambios");

            send_step;
            check(last_result == `EXEC_RESULT_OK, "tras una pausa larga STEP responde");
            send_reset;
            check(last_result == `EXEC_RESULT_OK && state_after_command == `EXEC_STATE_READY,
                  "tras una pausa larga RESET responde");
            send_step;
            check(state_after_command == `EXEC_STATE_PAUSED, "CPU pausado otra vez");

            build_short_program;
            load_program;
            check(system_state == `EXEC_STATE_READY, "LOAD con el CPU pausado -> READY");
            check(cpu_pc == 32'd0 && pipeline_is_empty(1'b0), "la carga deja el CPU en reset");

            send_run;
            wait_until_state(`EXEC_STATE_DONE, 200);
            check(cpu_done_reason == `DONE_REASON_HALT && register_value(10) == 42,
                  "el programa nuevo corre completo");
        end
    endtask

    task test_load_result_updates_state;
        begin
            $display("[TEST] el resultado de la carga actualiza el estado");

            // Encabezado invalido con el programa anterior intacto
            send_load_message(16'd2, 16'd0, 0);
            idle(5);
            check(load_error_code == `LOAD_ERROR_ARGUMENT, "N_WORDS = 0 se rechaza");
            check(program_valid && system_state == `EXEC_STATE_DONE,
                  "carga rechazada: el programa y el estado no cambian");

            // Carga interrumpida despues de un encabezado valido
            build_mixed_program;
            send_load_message(2 + 4 * 3, 16'd3, 1);
            idle(LOADER_TIMEOUT_CYCLES + 50);
            check(load_error_code == `LOAD_ERROR_TIMEOUT, "la carga truncada da timeout");
            check(!program_valid && system_state == `EXEC_STATE_EMPTY,
                  "carga interrumpida -> EMPTY");
            send_run;
            check(last_result == `EXEC_RESULT_NO_PROGRAM, "RUN sin programa valido se rechaza");

            load_program;
            check(system_state == `EXEC_STATE_READY, "una carga completa vuelve a READY");
        end
    endtask

    // =========================================================================
    // Secuencia principal
    // =========================================================================
    initial begin
        apply_system_reset;

        test_empty_system_rejects_execution;
        test_loaded_program_is_ready;
        test_pause_keeps_cpu_state;
        test_single_step_advances_one_cycle;
        test_stepping_matches_continuous_run;
        test_execution_commands_in_done_state;
        test_run_after_partial_stepping;
        test_halt_waits_for_next_step;
        test_step_until_end_of_image;
        test_reset_aborts_running_program;
        test_controller_stays_responsive_while_paused;
        test_load_result_updates_state;

        check(unexpected_enable_count == 0, "cpu_enable nunca se activo fuera de RUN o STEP");
        check(write_while_paused_count == 0, "nunca se escribio la memoria con el CPU pausado");

        $display("------------------------------------------------------------");
        if (error_count == 0)
            $display("PASS: %0d verificaciones", check_count);
        else
            $display("FAIL: %0d errores en %0d verificaciones", error_count, check_count);
        $finish;
    end

    // Evita que una prueba trabada deje la simulacion colgada
    initial begin
        #(CLOCK_PERIOD_NS * 200000);
        $display("FAIL: la simulacion no termino a tiempo");
        $finish;
    end

endmodule
