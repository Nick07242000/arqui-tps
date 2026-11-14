`timescale 1ns / 1ps
`include "program_loader_defs.vh"

// -----------------------------------------------------------------------------
// Testbench de integracion de la US-4.2: program_loader + memorias + cpu_core.
// Carga y ejecuta el programa A, luego reprograma con el programa B sin
// resintetizar. Emula a la Debug Unit: envia los bytes de LOAD_PROGRAM y
// acepta RUN solo si hay un programa valido.
// -----------------------------------------------------------------------------
module tb_program_reload;

    localparam CLK_PERIOD        = 10;
    localparam RX_TIMEOUT_CYCLES = 300;
    localparam RUN_CYCLES        = 60;
    localparam [31:0] JUMP_TO_SELF = 32'h0000006F;      // jal x0, 0: fin de programa (sin HALT todavia)

    // ---- Senales -------------------------------------------------------------
    reg         clk = 1'b0;
    reg         system_reset;
    reg         manual_cpu_reset;
    reg         cpu_enable;

    reg         load_start;
    reg  [15:0] payload_length_bytes;
    reg         byte_valid;
    reg  [7:0]  byte_data;

    wire        loader_imem_write_enable;
    wire [9:0]  loader_imem_write_word_addr;
    wire [31:0] loader_imem_write_data;
    wire        loader_cpu_reset;
    wire        program_valid;
    wire [10:0] n_words;
    wire        load_finished;
    wire [1:0]  load_error_code;

    wire        imem_read_enable;
    wire [9:0]  imem_read_word_addr;
    wire [31:0] imem_read_data;

    wire        dmem_read_enable;
    wire [9:0]  dmem_word_addr;
    wire [3:0]  dmem_write_byte_enable;
    wire [31:0] dmem_write_data;
    wire [31:0] dmem_read_data;

    reg  [4:0]  debug_reg_addr;
    wire [31:0] debug_reg_data;
    reg  [9:0]  debug_dmem_word_addr;
    wire [31:0] debug_dmem_data;

    wire        cpu_reset = manual_cpu_reset | loader_cpu_reset;

    always #(CLK_PERIOD / 2) clk = ~clk;

    // ---- Sistema bajo prueba ------------------------------------------------
    program_loader #(.RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)) loader (
        .i_clk                  (clk),
        .i_reset                (system_reset),
        .i_load_start           (load_start),
        .i_payload_length_bytes (payload_length_bytes),
        .i_byte_valid           (byte_valid),
        .i_byte_data            (byte_data),
        .o_imem_write_enable    (loader_imem_write_enable),
        .o_imem_write_word_addr (loader_imem_write_word_addr),
        .o_imem_write_data      (loader_imem_write_data),
        .o_cpu_reset            (loader_cpu_reset),
        .o_program_valid        (program_valid),
        .o_n_words              (n_words),
        .o_load_finished        (load_finished),
        .o_load_error_code      (load_error_code)
    );

    program_memory instruction_memory (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_read_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (loader_imem_write_enable),
        .i_write_word_addr (loader_imem_write_word_addr),
        .i_write_data      (loader_imem_write_data)
    );

    data_memory data_mem (
        .i_clk               (clk),
        .i_read_enable       (dmem_read_enable),
        .i_word_addr         (dmem_word_addr),
        .i_write_byte_enable (dmem_write_byte_enable),
        .i_write_data        (dmem_write_data),
        .o_read_data         (dmem_read_data),
        .i_debug_word_addr   (debug_dmem_word_addr),
        .o_debug_read_data   (debug_dmem_data)
    );

    cpu_core cpu (
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
        .o_debug_reg_data         (debug_reg_data)
    );

    // ---- Resultados ----------------------------------------------------------
    integer checks_run    = 0;
    integer checks_failed = 0;

    task check(input condition, input [8*64-1:0] description);
        begin
            checks_run = checks_run + 1;
            if (!condition) begin
                checks_failed = checks_failed + 1;
                $display("  FAIL: %0s", description);
            end
        end
    endtask

    // ---- Mini-ensamblador (solo lo que usan los programas de prueba) --------
    function [31:0] encode_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        encode_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function [31:0] encode_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function [31:0] encode_lw(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        encode_lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function [31:0] encode_sw(input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
        encode_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction

    // ---- Programas -----------------------------------------------------------
    reg [31:0] image [0:15];
    integer    image_word_count;

    // Programa A: x3 = 10 + 32, guarda x3 en dmem[0] y deja 7 en x5
    task build_program_a;
        begin
            image[0] = encode_addi(5'd1, 5'd0, 12'd10);
            image[1] = encode_addi(5'd2, 5'd0, 12'd32);
            image[2] = encode_add (5'd3, 5'd1, 5'd2);
            image[3] = encode_sw  (5'd3, 5'd0, 12'd0);
            image[4] = encode_addi(5'd5, 5'd0, 12'd7);
            image[5] = JUMP_TO_SELF;
            image_word_count = 6;
        end
    endtask

    // Programa B (mas corto): lee lo que dejo A en dmem[0], suma 1 y lo guarda en dmem[1]
    task build_program_b;
        begin
            image[0] = encode_lw  (5'd6, 5'd0, 12'd0);
            image[1] = encode_addi(5'd7, 5'd6, 12'd1);
            image[2] = encode_sw  (5'd7, 5'd0, 12'd4);
            image[3] = JUMP_TO_SELF;
            image_word_count = 4;
        end
    endtask

    // ---- Emulacion de la Debug Unit -----------------------------------------
    integer finished_pulse_count    = 0;
    integer finished_pulses_at_start = 0;

    always @(posedge clk)
        if (load_finished) finished_pulse_count <= finished_pulse_count + 1;

    task start_load(input [15:0] length_bytes);
        begin
            finished_pulses_at_start = finished_pulse_count;
            load_start           <= 1'b1;
            payload_length_bytes <= length_bytes;
            @(posedge clk);
            load_start           <= 1'b0;
        end
    endtask

    task send_byte(input [7:0] data);
        begin
            byte_data  <= data;
            byte_valid <= 1'b1;
            @(posedge clk);
            byte_valid <= 1'b0;
        end
    endtask

    task send_header_and_words(input integer word_count, input integer words_to_send);
        integer i;
        begin
            send_byte(word_count[7:0]);
            send_byte(word_count[15:8]);
            for (i = 0; i < words_to_send; i = i + 1) begin
                send_byte(image[i][7:0]);
                send_byte(image[i][15:8]);
                send_byte(image[i][23:16]);
                send_byte(image[i][31:24]);
            end
        end
    endtask

    task wait_for_finish;
        begin
            while (finished_pulse_count == finished_pulses_at_start) @(posedge clk);
        end
    endtask

    task load_image;
        begin
            start_load(2 + 4 * image_word_count);
            send_header_and_words(image_word_count, image_word_count);
            wait_for_finish;
        end
    endtask

    // Lectura directa del arreglo de la memoria (atajo solo de simulacion)
    task check_program_memory_holds_image(input [8*64-1:0] description);
        integer i;
        integer mismatches;
        begin
            mismatches = 0;
            for (i = 0; i < image_word_count; i = i + 1)
                if (instruction_memory.memory[i] !== image[i]) mismatches = mismatches + 1;
            check(mismatches == 0, description);
        end
    endtask

    // RUN: solo se acepta si hay un programa valido
    task request_run(output accepted);
        begin
            accepted = program_valid;
            if (accepted) begin
                cpu_enable <= 1'b1;
                repeat (RUN_CYCLES) @(posedge clk);
                cpu_enable <= 1'b0;
                @(posedge clk);
            end
        end
    endtask

    // ---- Consultas (puertos de debug del CPU y de data_memory) --------------
    task read_register(input [4:0] index, output [31:0] value);
        begin
            debug_reg_addr = index;
            #1;
            value = debug_reg_data;
        end
    endtask

    task read_data_word(input [9:0] word_index, output [31:0] value);
        begin
            debug_dmem_word_addr = word_index;
            repeat (2) @(posedge clk);
            #1;
            value = debug_dmem_data;
        end
    endtask

    task check_register(input [4:0] index, input [31:0] expected, input [8*64-1:0] description);
        reg [31:0] value;
        begin
            read_register(index, value);
            check(value === expected, description);
        end
    endtask

    task check_data_word(input [9:0] word_index, input [31:0] expected, input [8*64-1:0] description);
        reg [31:0] value;
        begin
            read_data_word(word_index, value);
            check(value === expected, description);
        end
    endtask

    task check_all_registers_are_zero(input [8*64-1:0] description);
        integer    index;
        integer    non_zero;
        reg [31:0] value;
        begin
            non_zero = 0;
            for (index = 0; index < 32; index = index + 1) begin
                read_register(index, value);
                if (value !== 32'd0) non_zero = non_zero + 1;
            end
            check(non_zero == 0, description);
        end
    endtask

    // ---- Pruebas -------------------------------------------------------------
    reg run_accepted;

    initial begin
        system_reset         = 1'b0;
        manual_cpu_reset     = 1'b0;
        cpu_enable           = 1'b0;
        load_start           = 1'b0;
        payload_length_bytes = 16'd0;
        byte_valid           = 1'b0;
        byte_data            = 8'd0;
        debug_reg_addr       = 5'd0;
        debug_dmem_word_addr = 10'd0;

        // ---------------------------------------------------------------------
        $display("[0] Codificaciones del mini-ensamblador contra binutils RISC-V");
        check(encode_addi(5'd1, 5'd0, 12'd10)  === 32'h00A00093, "addi x1, x0, 10");
        check(encode_addi(5'd2, 5'd0, 12'd32)  === 32'h02000113, "addi x2, x0, 32");
        check(encode_add (5'd3, 5'd1, 5'd2)    === 32'h002081B3, "add  x3, x1, x2");
        check(encode_sw  (5'd3, 5'd0, 12'd0)   === 32'h00302023, "sw   x3, 0(x0)");
        check(encode_addi(5'd5, 5'd0, 12'd7)   === 32'h00700293, "addi x5, x0, 7");
        check(encode_lw  (5'd6, 5'd0, 12'd0)   === 32'h00002303, "lw   x6, 0(x0)");
        check(encode_addi(5'd7, 5'd6, 12'd1)   === 32'h00130393, "addi x7, x6, 1");
        check(encode_sw  (5'd7, 5'd0, 12'd4)   === 32'h00702223, "sw   x7, 4(x0)");

        // Estado inicial definido, como al encender la placa
        @(posedge clk);
        system_reset <= 1'b1; manual_cpu_reset <= 1'b1;
        @(posedge clk);
        system_reset <= 1'b0; manual_cpu_reset <= 1'b0;
        @(posedge clk);

        // ---------------------------------------------------------------------
        $display("[1] RUN sin programa se rechaza");
        request_run(run_accepted);
        check(run_accepted === 1'b0, "RUN rechazado sin programa cargado");

        // ---------------------------------------------------------------------
        $display("[2] Carga y ejecucion del programa A");
        build_program_a;
        load_image;
        check(program_valid === 1'b1 && n_words === 6, "programa A valido, N_WORDS = 6");
        check_program_memory_holds_image("program_memory contiene el programa A");
        request_run(run_accepted);
        check(run_accepted === 1'b1, "RUN aceptado con programa valido");
        check_register(5'd1, 32'd10, "A: x1 = 10");
        check_register(5'd2, 32'd32, "A: x2 = 32");
        check_register(5'd3, 32'd42, "A: x3 = 42");
        check_register(5'd5, 32'd7,  "A: x5 = 7");
        check_data_word(10'd0, 32'd42, "A: dmem[0] = 42");

        // ---------------------------------------------------------------------
        $display("[3] Encabezado invalido: se conservan el programa A y el estado de la CPU");
        start_load(2);
        send_header_and_words(0, 0);                    // N_WORDS = 0
        wait_for_finish;
        check(load_error_code === `LOAD_ERROR_ARGUMENT, "N_WORDS = 0: codigo ARGUMENT");
        check(program_valid === 1'b1 && n_words === 6, "programa A sigue valido, N_WORDS = 6");
        check_program_memory_holds_image("program_memory conserva el programa A");
        check_register(5'd3, 32'd42, "x3 conserva el resultado de A (CPU sin resetear)");
        check_register(5'd5, 32'd7,  "x5 conserva el resultado de A (CPU sin resetear)");
        request_run(run_accepted);
        check(run_accepted === 1'b1, "RUN aceptado: A sigue siendo un programa valido");
        check_register(5'd3, 32'd42, "A sigue ejecutandose correctamente");

        // ---------------------------------------------------------------------
        $display("[4] Carga de B interrumpida tras un encabezado valido: CPU detenida y programa invalido");
        build_program_b;
        start_load(2 + 4 * image_word_count);
        send_header_and_words(image_word_count, 2);     // llegan 2 de 4 palabras
        cpu_enable <= 1'b1;                             // enable "indebido" durante la carga
        repeat (60) @(posedge clk);
        cpu_enable <= 1'b0;
        check_all_registers_are_zero("la carga reseteo los registros y la CPU no avanzo");
        wait_for_finish;
        check(program_valid === 1'b0 && n_words === 0, "carga truncada: sin programa valido");
        check(load_error_code === `LOAD_ERROR_TIMEOUT, "carga truncada: codigo TIMEOUT");
        request_run(run_accepted);
        check(run_accepted === 1'b0, "RUN rechazado con la carga incompleta");
        check_all_registers_are_zero("la CPU no ejecuto nada tras la carga incompleta");
        check_data_word(10'd0, 32'd42, "dmem conserva su contenido durante la carga");

        // ---------------------------------------------------------------------
        $display("[5] Reprogramacion con el programa B (mas corto)");
        load_image;
        check(program_valid === 1'b1 && n_words === 4, "programa B valido, N_WORDS = 4");
        check_program_memory_holds_image("program_memory contiene el programa B");
        request_run(run_accepted);
        check(run_accepted === 1'b1, "RUN aceptado con B");
        check_register(5'd6, 32'd42, "B: x6 = 42 (dato que dejo A en dmem)");
        check_register(5'd7, 32'd43, "B: x7 = 43");
        check_register(5'd5, 32'd0,  "B: x5 = 0 (registros de A limpiados por la carga)");
        check_register(5'd3, 32'd0,  "B: x3 = 0 (registros de A limpiados por la carga)");
        check_data_word(10'd0, 32'd42, "B: dmem[0] sigue en 42");
        check_data_word(10'd1, 32'd43, "B: dmem[1] = 43");

        // ---------------------------------------------------------------------
        $display("[6] Nueva reprogramacion con A: se repite el resultado original");
        build_program_a;
        load_image;
        request_run(run_accepted);
        check(run_accepted === 1'b1, "RUN aceptado con A otra vez");
        check_register(5'd3, 32'd42, "A (2da vez): x3 = 42");
        check_register(5'd5, 32'd7,  "A (2da vez): x5 = 7");
        check_register(5'd6, 32'd0,  "A (2da vez): x6 = 0 (registros de B limpiados)");

        // ---------------------------------------------------------------------
        if (checks_failed == 0)
            $display("\nRESULTADO: PASS (%0d verificaciones)", checks_run);
        else
            $display("\nRESULTADO: FAIL (%0d fallas en %0d verificaciones)", checks_failed, checks_run);
        $finish;
    end

    // Evita que una falla deje la simulacion colgada
    initial begin
        #(CLK_PERIOD * 100000);
        $display("RESULTADO: FAIL (la simulacion no termino)");
        $finish;
    end

endmodule
