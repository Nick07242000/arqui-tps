`timescale 1ns / 1ps
`include "riscv_defs.vh"

module tb_structural_hazards;

    localparam MEM_ADDR_WIDTH    = 10;
    localparam MAX_PROGRAM_WORDS = 64;
    localparam MAX_TRACE_CYCLES  = 256;

    // ---- Programa de copia usado por T1 y T4 --------------------------------
    localparam COPY_WORD_COUNT          = 8;
    localparam COPY_MEMORY_ACCESSES     = 3 * COPY_WORD_COUNT;   // rellenar: sw | copiar: lw + sw
    localparam SOURCE_BYTE_ADDRESS      = 0;
    localparam DESTINATION_BYTE_ADDRESS = 128;
    localparam SOURCE_WORD_BASE         = SOURCE_BYTE_ADDRESS / 4;
    localparam DESTINATION_WORD_BASE    = DESTINATION_BYTE_ADDRESS / 4;
    localparam COPY_PROGRAM_CYCLES      = 180;
    localparam SNAPSHOT_WORDS           = 64;

    localparam [4:0] X0 = 5'd0, X1 = 5'd1, X2 = 5'd2, X3 = 5'd3,
                     X4 = 5'd4, X5 = 5'd5, X6 = 5'd6, X7 = 5'd7, X31 = 5'd31;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    `include "test_check_helpers.vh"
    `include "test_instruction_encoders.vh"

    // =========================================================================
    // Sistema bajo prueba
    // =========================================================================
    reg  cpu_reset  = 1'b0;
    reg  cpu_enable = 1'b0;

    wire                      imem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] imem_word_addr;
    wire [31:0]               imem_read_data;

    wire                      dmem_read_enable;
    wire [MEM_ADDR_WIDTH-1:0] dmem_word_addr;
    wire [3:0]                dmem_write_byte_enable;
    wire [31:0]               dmem_write_data;
    wire [31:0]               dmem_read_data;

    // Puertos que usara la Debug Unit
    reg                       debug_imem_write_enable = 1'b0;
    reg  [MEM_ADDR_WIDTH-1:0] debug_imem_write_addr   = 0;
    reg  [31:0]               debug_imem_write_data   = 0;
    reg  [MEM_ADDR_WIDTH-1:0] debug_dmem_word_addr    = 0;
    wire [31:0]               debug_dmem_read_data;
    reg  [4:0]                debug_reg_addr          = 0;
    wire [31:0]               debug_reg_data;

    cpu_core #(.MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)) cpu (
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
        .o_debug_reg_data         (debug_reg_data)
    );

    program_memory #(.ADDR_WIDTH(MEM_ADDR_WIDTH)) program_mem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (debug_imem_write_enable),
        .i_write_word_addr (debug_imem_write_addr),
        .i_write_data      (debug_imem_write_data)
    );

    data_memory #(.ADDR_WIDTH(MEM_ADDR_WIDTH)) data_mem (
        .i_clk               (clk),
        .i_read_enable       (dmem_read_enable),
        .i_word_addr         (dmem_word_addr),
        .i_write_byte_enable (dmem_write_byte_enable),
        .i_write_data        (dmem_write_data),
        .o_read_data         (dmem_read_data),
        .i_debug_word_addr   (debug_dmem_word_addr),
        .o_debug_read_data   (debug_dmem_read_data)
    );

    // =========================================================================
    // Monitores: miran cada ciclo en que el CPU avanza
    // =========================================================================
    wire data_access_in_mem = cpu.ex_mem_valid
                           && (cpu.ex_mem_mem_read || cpu.ex_mem_mem_write);

    reg  debug_follows_cpu_data_address = 1'b0;   // T4: la DU lee la palabra que toca el CPU

    integer enabled_cycles;           // ciclos que avanzo el CPU desde el ultimo reset
    integer data_access_cycles;       // ciclos con un load/store valido en MEM
    integer overlapped_cycles;        // ... en los que ademas IF leia la memoria de programa
    integer same_word_debug_cycles;   // stores del CPU con el puerto B leyendo esa misma palabra
    reg [31:0] pc_trace [0:MAX_TRACE_CYCLES-1];

    always @(posedge clk) begin
        if (cpu_reset) begin
            enabled_cycles         = 0;
            data_access_cycles     = 0;
            overlapped_cycles      = 0;
            same_word_debug_cycles = 0;
        end else if (cpu_enable) begin
            if (enabled_cycles < MAX_TRACE_CYCLES)
                pc_trace[enabled_cycles] = cpu.if_pc;
            enabled_cycles = enabled_cycles + 1;

            if (data_access_in_mem) begin
                data_access_cycles = data_access_cycles + 1;
                if (imem_read_enable)
                    overlapped_cycles = overlapped_cycles + 1;
            end

            if (dmem_write_byte_enable != 4'b0000 && debug_dmem_word_addr == dmem_word_addr)
                same_word_debug_cycles = same_word_debug_cycles + 1;
        end
    end

    // Actividad de la Debug Unit durante la ejecucion (T4)
    always @(negedge clk) begin
        if (debug_follows_cpu_data_address) begin
            debug_dmem_word_addr <= dmem_word_addr;
            debug_reg_addr       <= debug_reg_addr + 5'd1;
        end
    end

    // =========================================================================
    // Acciones de la Debug Unit emulada
    // =========================================================================
    task write_program_word(input [MEM_ADDR_WIDTH-1:0] i_word_index, input [31:0] i_word);
        begin
            debug_imem_write_enable = 1'b1;
            debug_imem_write_addr   = i_word_index;
            debug_imem_write_data   = i_word;
            @(negedge clk);
            debug_imem_write_enable = 1'b0;
        end
    endtask

    task read_register(input [4:0] i_index, output [31:0] o_value);
        begin
            debug_reg_addr = i_index;
            #1;
            o_value = debug_reg_data;
        end
    endtask

    // La memoria de datos responde un ciclo despues de recibir la direccion
    task read_data_word(input [MEM_ADDR_WIDTH-1:0] i_word_index, output [31:0] o_value);
        begin
            debug_dmem_word_addr = i_word_index;
            @(negedge clk);
            o_value = debug_dmem_read_data;
        end
    endtask

    task expect_register(
        input [4:0]                     i_index,
        input [31:0]                    i_expected,
        input [8*DESCRIPTION_CHARS-1:0] i_description
    );
        reg [31:0] observed_value;
        begin
            read_register(i_index, observed_value);
            check_equal(i_description, observed_value, i_expected);
        end
    endtask

    task expect_data_word(
        input [MEM_ADDR_WIDTH-1:0]      i_word_index,
        input [31:0]                    i_expected,
        input [8*DESCRIPTION_CHARS-1:0] i_description
    );
        reg [31:0] observed_value;
        begin
            read_data_word(i_word_index, observed_value);
            check_equal(i_description, observed_value, i_expected);
        end
    endtask

    // =========================================================================
    // Armado y ejecucion de programas
    // =========================================================================
    reg [31:0] program_image [0:MAX_PROGRAM_WORDS-1];
    integer    program_length;

    task emit(input [31:0] i_instruction);
        begin
            program_image[program_length] = i_instruction;
            program_length = program_length + 1;
        end
    endtask

    // Desplazamiento en bytes desde la instruccion que se esta emitiendo hasta un destino
    function integer byte_offset_to(input integer i_target_index);
        byte_offset_to = (i_target_index - program_length) * 4;
    endfunction

    task emit_park_loop;
        begin
            emit(asm_jal(X0, 0));
        end
    endtask

    task load_program_through_debug_port;
        integer word_index;
        begin
            for (word_index = 0; word_index < program_length; word_index = word_index + 1)
                write_program_word(word_index, program_image[word_index]);
        end
    endtask

    task reset_cpu;
        begin
            cpu_enable = 1'b0;
            cpu_reset  = 1'b1;
            @(negedge clk);
            cpu_reset  = 1'b0;
        end
    endtask

    task run_cycles(input integer i_cycle_count);
        begin
            cpu_enable = 1'b1;
            repeat (i_cycle_count) @(negedge clk);
            cpu_enable = 1'b0;
        end
    endtask

    // Atajo de simulacion: el reset no borra la memoria de datos (decision de diseno), asi que
    // las pruebas que comparan contenido la ponen en cero para no heredar resultados anteriores
    task clear_data_memory_words(input integer i_word_count);
        integer word_index;
        begin
            for (word_index = 0; word_index < i_word_count; word_index = word_index + 1) begin
                data_mem.byte_bank[0].bank[word_index] = 8'h00;
                data_mem.byte_bank[1].bank[word_index] = 8'h00;
                data_mem.byte_bank[2].bank[word_index] = 8'h00;
                data_mem.byte_bank[3].bank[word_index] = 8'h00;
            end
        end
    endtask

    task load_and_run(input integer i_cycle_count);
        begin
            reset_cpu;
            load_program_through_debug_port;
            run_cycles(i_cycle_count);
        end
    endtask

    // Rellena origen[i] = 1 + 3i y despues lo copia a destino. Mezcla stores, loads,
    // load-use y saltos para que IF y MEM trabajen a la vez durante todo el programa.
    task build_fill_and_copy_program;
        integer fill_loop_start;
        integer copy_loop_start;
        begin
            program_length = 0;

            emit(asm_addi(X1, X0, SOURCE_BYTE_ADDRESS));
            emit(asm_addi(X2, X0, 1));
            emit(asm_addi(X3, X0, COPY_WORD_COUNT));
            fill_loop_start = program_length;
            emit(asm_sw  (X2, X1, 0));
            emit(asm_addi(X2, X2, 3));
            emit(asm_addi(X1, X1, 4));
            emit(asm_addi(X3, X3, -1));
            emit(asm_bne (X3, X0, byte_offset_to(fill_loop_start)));

            emit(asm_addi(X1, X0, SOURCE_BYTE_ADDRESS));
            emit(asm_addi(X2, X0, DESTINATION_BYTE_ADDRESS));
            emit(asm_addi(X3, X0, COPY_WORD_COUNT));
            copy_loop_start = program_length;
            emit(asm_lw  (X4, X1, 0));
            emit(asm_sw  (X4, X2, 0));
            emit(asm_addi(X1, X1, 4));
            emit(asm_addi(X2, X2, 4));
            emit(asm_addi(X3, X3, -1));
            emit(asm_bne (X3, X0, byte_offset_to(copy_loop_start)));

            emit_park_loop;
        end
    endtask

    // =========================================================================
    // T1 - Fetch y acceso a datos en el mismo ciclo
    // =========================================================================
    task test_fetch_overlaps_data_access;
        integer word_index;
        begin
            $display("\n[T1] Fetch y acceso a datos en el mismo ciclo (rellenar y copiar un bloque)");
            build_fill_and_copy_program;
            clear_data_memory_words(SNAPSHOT_WORDS);
            load_and_run(COPY_PROGRAM_CYCLES);

            for (word_index = 0; word_index < COPY_WORD_COUNT; word_index = word_index + 1) begin
                expect_data_word(SOURCE_WORD_BASE + word_index, 1 + 3 * word_index,
                                 "origen[i] = 1 + 3i");
                expect_data_word(DESTINATION_WORD_BASE + word_index, 1 + 3 * word_index,
                                 "destino[i] = origen[i]");
            end

            check_equal("accesos a dmem ejecutados (8 sw + 8 lw + 8 sw)",
                        data_access_cycles, COPY_MEMORY_ACCESSES);
            check_equal("accesos a dmem que coincidieron con un fetch",
                        overlapped_cycles, COPY_MEMORY_ACCESSES);
        end
    endtask

    // =========================================================================
    // T2 - WB escribe un registro mientras ID lo lee
    // =========================================================================
    task test_register_write_and_read_in_same_cycle;
        begin
            $display("\n[T2] WB escribe y ID lee el mismo registro en el mismo ciclo");
            program_length = 0;

            // El consumidor esta a distancia 3: cuando entra en ID, el productor esta en WB
            emit(asm_addi(X1, X0, 7));
            emit(NOP_INSTRUCTION);
            emit(NOP_INSTRUCTION);
            emit(asm_add (X2, X1, X1));         // lee x1 por los dos puertos

            emit(asm_addi(X6, X0, 9));
            emit(NOP_INSTRUCTION);
            emit(NOP_INSTRUCTION);
            emit(asm_sub (X7, X0, X6));         // lee x6 solo por el puerto B

            // Escribir x0 en WB no debe verse en una lectura de x0 en el mismo ciclo
            emit(asm_addi(X0, X0, 5));
            emit(NOP_INSTRUCTION);
            emit(NOP_INSTRUCTION);
            emit(asm_add (X3, X0, X0));
            emit_park_loop;

            load_and_run(30);

            expect_register(X2, 32'd14,        "x2 = x1 + x1 (bypass, puertos A y B)");
            expect_register(X7, 32'hFFFFFFF7,  "x7 = 0 - x6 (bypass, puerto B)");
            expect_register(X3, 32'd0,         "x3 = x0 + x0 (x0 no se adelanta)");
            expect_register(X0, 32'd0,         "x0 sigue en cero");
        end
    endtask

    // =========================================================================
    // T3 - Store y load consecutivos sobre la misma palabra
    // =========================================================================
    task test_back_to_back_store_and_load;
        localparam TEST_BYTE_ADDRESS = 100;
        localparam TEST_WORD_INDEX   = TEST_BYTE_ADDRESS / 4;
        begin
            $display("\n[T3] Store y load consecutivos sobre la misma palabra");
            program_length = 0;

            emit(asm_addi(X1, X0, TEST_BYTE_ADDRESS));
            emit(asm_addi(X2, X0, 8'h55));
            emit(asm_sw  (X0, X1, 0));          // limpia la palabra
            emit(asm_sb  (X2, X1, 1));          // byte 1 = 0x55
            emit(asm_lw  (X4, X1, 0));          // load justo despues del store
            emit(asm_lw  (X5, X1, 0));          // load justo antes del siguiente store
            emit(asm_sw  (X2, X1, 0));          // reescribe toda la palabra
            emit(asm_lw  (X6, X1, 0));
            emit_park_loop;

            load_and_run(30);

            expect_register(X4, 32'h00005500, "lw tras sb ve el byte recien escrito");
            expect_register(X5, 32'h00005500, "lw antes de un sw ve el valor anterior");
            expect_register(X6, 32'h00000055, "lw tras sw ve el valor nuevo");
            expect_data_word(TEST_WORD_INDEX, 32'h00000055, "palabra final en memoria");
        end
    endtask

    // =========================================================================
    // T4 - La Debug Unit leyendo durante la ejecucion no cambia el resultado
    // =========================================================================
    reg [31:0] reference_pc_trace   [0:COPY_PROGRAM_CYCLES-1];
    reg [31:0] reference_registers  [0:31];
    reg [31:0] reference_data_words [0:SNAPSHOT_WORDS-1];

    task save_reference_state;
        integer index;
        begin
            for (index = 0; index < COPY_PROGRAM_CYCLES; index = index + 1)
                reference_pc_trace[index] = pc_trace[index];
            for (index = 0; index < 32; index = index + 1)
                read_register(index, reference_registers[index]);
            for (index = 0; index < SNAPSHOT_WORDS; index = index + 1)
                read_data_word(index, reference_data_words[index]);
        end
    endtask

    task count_differences_from_reference(
        output integer o_pc_differences,
        output integer o_register_differences,
        output integer o_data_differences
    );
        integer index;
        reg [31:0] observed_value;
        begin
            o_pc_differences       = 0;
            o_register_differences = 0;
            o_data_differences     = 0;

            for (index = 0; index < COPY_PROGRAM_CYCLES; index = index + 1)
                if (pc_trace[index] !== reference_pc_trace[index])
                    o_pc_differences = o_pc_differences + 1;

            for (index = 0; index < 32; index = index + 1) begin
                read_register(index, observed_value);
                if (observed_value !== reference_registers[index])
                    o_register_differences = o_register_differences + 1;
            end

            for (index = 0; index < SNAPSHOT_WORDS; index = index + 1) begin
                read_data_word(index, observed_value);
                if (observed_value !== reference_data_words[index])
                    o_data_differences = o_data_differences + 1;
            end
        end
    endtask

    task test_debug_reads_do_not_disturb_execution;
        integer pc_differences;
        integer register_differences;
        integer data_differences;
        begin
            $display("\n[T4] Lecturas de la Debug Unit durante la ejecucion");
            build_fill_and_copy_program;

            // Referencia: el mismo programa sin actividad de debug
            clear_data_memory_words(SNAPSHOT_WORDS);
            load_and_run(COPY_PROGRAM_CYCLES);
            save_reference_state;

            // Con la Debug Unit leyendo en cada ciclo la palabra que el CPU esta tocando
            clear_data_memory_words(SNAPSHOT_WORDS);
            debug_follows_cpu_data_address = 1'b1;
            load_and_run(COPY_PROGRAM_CYCLES);
            debug_follows_cpu_data_address = 1'b0;
            @(negedge clk);

            check_equal("stores con lectura del puerto B sobre la misma palabra",
                        same_word_debug_cycles, 2 * COPY_WORD_COUNT);

            count_differences_from_reference(pc_differences, register_differences, data_differences);
            check_equal("ciclos con PC distinto al de la referencia", pc_differences, 0);
            check_equal("registros distintos a la referencia", register_differences, 0);
            check_equal("palabras de dmem distintas a la referencia", data_differences, 0);
        end
    endtask

    // =========================================================================
    // T5 - La Debug Unit escribe la memoria de programa con el CPU pausado
    // =========================================================================
    task test_program_write_while_cpu_is_paused;
        localparam CYCLES_BEFORE_PAUSE = 4;
        localparam IN_FLIGHT_WORD      = 3;   // instruccion que queda en IF/ID al pausar
        reg [31:0] pc_before_writes;
        reg [31:0] in_flight_instruction_before_writes;
        reg        if_id_valid_before_writes;
        begin
            $display("\n[T5] La Debug Unit escribe la memoria de programa con el CPU pausado");
            program_length = 0;

            emit(asm_addi(X1, X0, 1));
            emit(asm_addi(X2, X0, 2));
            emit(asm_addi(X3, X0, 3));
            emit(asm_addi(X4, X0, 4));          // word 3: en vuelo al pausar
            emit(asm_addi(X5, X0, 5));          // word 4: todavia no leida
            emit(asm_addi(X6, X0, 6));          // word 5: todavia no leida
            emit_park_loop;

            reset_cpu;
            load_program_through_debug_port;
            run_cycles(CYCLES_BEFORE_PAUSE);

            pc_before_writes                    = cpu.if_pc;
            in_flight_instruction_before_writes = imem_read_data;
            if_id_valid_before_writes           = cpu.if_id_valid;
            check_equal("PC al pausar", pc_before_writes, CYCLES_BEFORE_PAUSE * 4);
            check_equal("instruccion en vuelo al pausar",
                        in_flight_instruction_before_writes, program_image[IN_FLIGHT_WORD]);

            // CPU pausado: la DU pisa la palabra en vuelo y reescribe las dos siguientes
            write_program_word(IN_FLIGHT_WORD,     asm_addi(X31, X0, 2047));
            write_program_word(IN_FLIGHT_WORD + 1, asm_addi(X5, X0, 50));
            write_program_word(IN_FLIGHT_WORD + 2, asm_addi(X6, X0, 60));

            check_equal("el PC no cambio durante las escrituras", cpu.if_pc, pc_before_writes);
            check_equal("la instruccion en vuelo no cambio",
                        imem_read_data, in_flight_instruction_before_writes);
            check_equal("IF/ID mantiene su validez", cpu.if_id_valid, if_id_valid_before_writes);

            run_cycles(20);

            expect_register(X4,  32'd4,  "x4: la instruccion en vuelo se ejecuto intacta");
            expect_register(X31, 32'd0,  "x31: la palabra pisada nunca se ejecuto");
            expect_register(X5,  32'd50, "x5: la palabra reescrita se leyo con el valor nuevo");
            expect_register(X6,  32'd60, "x6: la palabra reescrita se leyo con el valor nuevo");
        end
    endtask

    // =========================================================================
    // Secuencia de pruebas
    // =========================================================================
    initial begin
        @(negedge clk);

        test_fetch_overlaps_data_access;
        test_register_write_and_read_in_same_cycle;
        test_back_to_back_store_and_load;
        test_debug_reads_do_not_disturb_execution;
        test_program_write_while_cpu_is_paused;

        print_summary;
        $finish;
    end

    // Evita que una prueba colgada deje la simulacion corriendo para siempre
    initial begin
        #2000000;
        $display("TIMEOUT: la simulacion no termino");
        $finish;
    end

endmodule
