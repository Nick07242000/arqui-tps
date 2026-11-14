`timescale 1ns / 1ps
`include "program_loader_defs.vh"

// -----------------------------------------------------------------------------
// Testbench de program_loader conectado a una program_memory real.
// Emula a la Debug Unit: entrega i_load_start, LEN y los bytes del payload.
// -----------------------------------------------------------------------------
module tb_program_loader;

    localparam ADDR_WIDTH        = 10;
    localparam MEMORY_DEPTH      = 1 << ADDR_WIDTH;
    localparam RX_TIMEOUT_CYCLES = 200;
    localparam CLK_PERIOD        = 10;

    // ---- Senales -------------------------------------------------------------
    reg         clk = 1'b0;
    reg         reset;

    reg         load_start;
    reg  [15:0] payload_length_bytes;
    reg         byte_valid;
    reg  [7:0]  byte_data;

    wire                  imem_write_enable;
    wire [ADDR_WIDTH-1:0] imem_write_word_addr;
    wire [31:0]           imem_write_data;

    wire                  cpu_reset;
    wire                  program_valid;
    wire [ADDR_WIDTH:0]   n_words;
    wire                  load_finished;
    wire [1:0]            load_error_code;

    reg                   imem_read_enable;
    reg  [ADDR_WIDTH-1:0] imem_read_word_addr;
    wire [31:0]           imem_read_data;

    always #(CLK_PERIOD / 2) clk = ~clk;

    program_loader #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .RX_TIMEOUT_CYCLES (RX_TIMEOUT_CYCLES)
    ) dut (
        .i_clk                  (clk),
        .i_reset                (reset),
        .i_load_start           (load_start),
        .i_payload_length_bytes (payload_length_bytes),
        .i_byte_valid           (byte_valid),
        .i_byte_data            (byte_data),
        .o_imem_write_enable    (imem_write_enable),
        .o_imem_write_word_addr (imem_write_word_addr),
        .o_imem_write_data      (imem_write_data),
        .o_cpu_reset            (cpu_reset),
        .o_program_valid        (program_valid),
        .o_n_words              (n_words),
        .o_load_finished        (load_finished),
        .o_load_error_code      (load_error_code)
    );

    program_memory #(.ADDR_WIDTH(ADDR_WIDTH)) instruction_memory (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_read_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_word_addr),
        .i_write_data      (imem_write_data)
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

    // ---- Datos de prueba -----------------------------------------------------
    reg [31:0] sent_image      [0:MEMORY_DEPTH+7];   // lo que se transmite
    reg [31:0] expected_memory [0:MEMORY_DEPTH-1];   // lo que debe haber en program_memory
    integer    byte_gap_cycles = 0;                  // silencio entre bytes (UART real: ~2343)

    task fill_sent_image(input [31:0] seed);
        integer i;
        begin
            for (i = 0; i < MEMORY_DEPTH + 8; i = i + 1)
                sent_image[i] = seed ^ (i * 32'h9E3779B1);
        end
    endtask

    task commit_to_expected_memory(input integer word_count);
        integer i;
        begin
            for (i = 0; i < word_count; i = i + 1)
                expected_memory[i] = sent_image[i];
        end
    endtask

    // ---- Monitores ----------------------------------------------------------
    integer finished_pulse_count = 0;
    reg     cpu_reset_was_asserted = 1'b0;      // se limpia al iniciar cada carga

    always @(posedge clk) begin
        if (load_finished)
            finished_pulse_count <= finished_pulse_count + 1;

        if (cpu_reset)
            cpu_reset_was_asserted <= 1'b1;

        if (imem_write_enable && program_valid) begin
            checks_failed = checks_failed + 1;
            $display("  FAIL: escritura de program_memory sobre un programa todavia valido");
        end

        if (imem_write_enable && !cpu_reset) begin
            checks_failed = checks_failed + 1;
            $display("  FAIL: escritura de program_memory con la CPU fuera de reset");
        end
        if (program_valid && cpu_reset) begin
            checks_failed = checks_failed + 1;
            $display("  FAIL: programa valido mientras la carga sigue en curso");
        end
    end

    // ---- Tareas de bajo nivel (emulan a la Debug Unit) ----------------------
    integer finished_pulses_at_start = 0;

    task start_load(input [15:0] length_bytes);
        begin
            finished_pulses_at_start = finished_pulse_count;
            cpu_reset_was_asserted   = 1'b0;
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
            repeat (byte_gap_cycles) @(posedge clk);
        end
    endtask

    task send_word_count(input [15:0] word_count);
        begin
            send_byte(word_count[7:0]);
            send_byte(word_count[15:8]);
        end
    endtask

    task send_words(input integer word_count);
        integer i;
        begin
            for (i = 0; i < word_count; i = i + 1) begin
                send_byte(sent_image[i][7:0]);
                send_byte(sent_image[i][15:8]);
                send_byte(sent_image[i][23:16]);
                send_byte(sent_image[i][31:24]);
            end
        end
    endtask

    // Espera el pulso de fin de la ultima carga iniciada con start_load
    task wait_for_finish;
        begin
            while (finished_pulse_count == finished_pulses_at_start) @(posedge clk);
        end
    endtask

    task idle_cycles(input integer cycles);
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    task apply_reset;
        begin
            reset <= 1'b1;
            @(posedge clk);
            reset <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ---- Tareas de alto nivel ------------------------------------------------
    // Carga correcta de word_count palabras (un solo mensaje)
    task load_valid_image(input integer word_count);
        begin
            start_load(2 + 4 * word_count);
            send_word_count(word_count);
            send_words(word_count);
            wait_for_finish;
            commit_to_expected_memory(word_count);
        end
    endtask

    task read_program_word(input [ADDR_WIDTH-1:0] word_addr, output [31:0] word);
        begin
            imem_read_word_addr <= word_addr;
            imem_read_enable    <= 1'b1;
            @(posedge clk);
            imem_read_enable    <= 1'b0;
            @(posedge clk);
            word = imem_read_data;
        end
    endtask

    task check_memory_matches_expected(input [8*64-1:0] description);
        integer    i;
        integer    mismatches;
        reg [31:0] word;
        begin
            mismatches = 0;
            for (i = 0; i < MEMORY_DEPTH; i = i + 1) begin
                read_program_word(i, word);
                if (word !== expected_memory[i]) mismatches = mismatches + 1;
            end
            check(mismatches == 0, description);
        end
    endtask

    task check_load_result(
        input                 expected_valid,
        input [ADDR_WIDTH:0]  expected_n_words,
        input [1:0]           expected_error,
        input [8*64-1:0]      description
    );
        begin
            check(program_valid    === expected_valid,   description);
            check(n_words          === expected_n_words, description);
            check(load_error_code  === expected_error,   description);
            check(cpu_reset        === 1'b0,             description);
        end
    endtask

    task check_cpu_was_reset(input expected, input [8*64-1:0] description);
        begin
            check(cpu_reset_was_asserted === expected, description);
        end
    endtask

    // ---- Pruebas -------------------------------------------------------------
    integer i;

    initial begin
        reset                = 1'b0;
        load_start           = 1'b0;
        payload_length_bytes = 16'd0;
        byte_valid           = 1'b0;
        byte_data            = 8'd0;
        imem_read_enable     = 1'b0;
        imem_read_word_addr  = {ADDR_WIDTH{1'b0}};
        for (i = 0; i < MEMORY_DEPTH; i = i + 1) expected_memory[i] = 32'd0;

        @(posedge clk);
        apply_reset;

        // ---------------------------------------------------------------------
        $display("[1] Estado despues del reset");
        check(program_valid === 1'b0 && n_words === 0, "sin programa valido tras el reset");
        check(cpu_reset === 1'b0 && load_finished === 1'b0, "sin carga en curso tras el reset");

        // ---------------------------------------------------------------------
        $display("[2] Carga valida de 3 palabras");
        fill_sent_image(32'hA5A5_0000);
        start_load(2 + 4 * 3);
        send_word_count(3);
        idle_cycles(2);
        check(cpu_reset === 1'b1, "CPU en reset al reescribirse la imagen");
        check(program_valid === 1'b0, "programa invalido hasta terminar");
        send_words(3);
        wait_for_finish;
        commit_to_expected_memory(3);
        check_load_result(1'b1, 3, `LOAD_ERROR_NONE, "carga de 3 palabras");
        check_cpu_was_reset(1'b1, "la carga valida reseteo la CPU");
        check_memory_matches_expected("palabras leidas identicas a las enviadas (3)");

        // ---------------------------------------------------------------------
        $display("[3] Carga a capacidad completa (1024 palabras)");
        fill_sent_image(32'h1357_9BDF);
        load_valid_image(MEMORY_DEPTH);
        check_load_result(1'b1, MEMORY_DEPTH, `LOAD_ERROR_NONE, "carga de 1024 palabras");
        check_memory_matches_expected("palabras leidas identicas a las enviadas (1024)");

        // ---------------------------------------------------------------------
        $display("[4] Reprogramacion: el programa anterior se pierde al validarse el encabezado");
        fill_sent_image(32'hC0DE_0000);
        start_load(2 + 4 * 2);
        send_word_count(2);
        idle_cycles(2);
        check(program_valid === 1'b0 && n_words === 0, "programa anterior invalidado");
        check(cpu_reset === 1'b1, "CPU en reset mientras se reescribe");
        send_words(2);
        wait_for_finish;
        commit_to_expected_memory(2);
        check_load_result(1'b1, 2, `LOAD_ERROR_NONE, "recarga de 2 palabras");
        check_memory_matches_expected("primeras palabras nuevas, resto de la imagen anterior sin borrar");

        // ---------------------------------------------------------------------
        $display("[5] Bytes separados como en la UART real");
        byte_gap_cycles = 20;
        fill_sent_image(32'h0F0F_F0F0);
        load_valid_image(5);
        byte_gap_cycles = 0;
        check_load_result(1'b1, 5, `LOAD_ERROR_NONE, "carga con silencio entre bytes");
        check_memory_matches_expected("memoria correcta con bytes espaciados");

        // ---------------------------------------------------------------------
        $display("[6] N_WORDS = 0: se rechaza y se conserva el programa");
        fill_sent_image(32'hBAD0_0000);
        start_load(2);
        send_word_count(0);
        wait_for_finish;
        check_load_result(1'b1, 5, `LOAD_ERROR_ARGUMENT, "N_WORDS = 0 conserva el programa de 5 palabras");
        check_cpu_was_reset(1'b0, "N_WORDS = 0 no resetea la CPU");
        check_memory_matches_expected("memoria intacta tras N_WORDS = 0");

        // ---------------------------------------------------------------------
        $display("[7] N_WORDS mayor que la capacidad: se rechaza, se consume el mensaje y se conserva el programa");
        fill_sent_image(32'hBAD1_0000);
        start_load(2 + 4 * (MEMORY_DEPTH + 1));
        send_word_count(MEMORY_DEPTH + 1);
        idle_cycles(5);
        check(finished_pulse_count == finished_pulses_at_start,
              "tras el error sigue consumiendo el mensaje");
        send_words(MEMORY_DEPTH + 1);
        wait_for_finish;
        check_load_result(1'b1, 5, `LOAD_ERROR_ARGUMENT, "N_WORDS = 1025 conserva el programa");
        check_cpu_was_reset(1'b0, "N_WORDS = 1025 no resetea la CPU");
        check_memory_matches_expected("memoria intacta tras N_WORDS = 1025");

        fill_sent_image(32'h600D_0000);
        load_valid_image(4);
        check_load_result(1'b1, 4, `LOAD_ERROR_NONE, "carga valida inmediatamente despues del error");

        // ---------------------------------------------------------------------
        $display("[8] LEN no coincide con N_WORDS: se conserva el programa");
        fill_sent_image(32'hBAD2_0000);
        start_load(2 + 4 * 5);                // LEN promete 5 palabras
        send_word_count(4);                   // el encabezado declara 4
        send_words(5);
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_LENGTH, "LEN mayor que 2 + 4 * N_WORDS");
        check_cpu_was_reset(1'b0, "LEN mayor no resetea la CPU");
        check_memory_matches_expected("memoria intacta con LEN mayor");

        start_load(2 + 4 * 3);                // LEN promete 3 palabras
        send_word_count(4);                   // el encabezado declara 4
        send_words(3);
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_LENGTH, "LEN menor que 2 + 4 * N_WORDS");
        check_cpu_was_reset(1'b0, "LEN menor no resetea la CPU");
        check_memory_matches_expected("memoria intacta con LEN menor");

        // ---------------------------------------------------------------------
        $display("[9] LEN demasiado corto para contener el encabezado");
        start_load(0);
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_LENGTH, "LEN = 0 conserva el programa");
        check_cpu_was_reset(1'b0, "LEN = 0 no resetea la CPU");

        start_load(1);
        send_byte(8'h04);
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_LENGTH, "LEN = 1 conserva el programa");
        check_cpu_was_reset(1'b0, "LEN = 1 no resetea la CPU");
        check_memory_matches_expected("memoria intacta con LEN corto");

        // ---------------------------------------------------------------------
        $display("[10] Mensaje truncado: antes del encabezado valido se conserva el programa, despues se pierde");
        fill_sent_image(32'h7002_0000);
        check(program_valid === 1'b1 && n_words === 4, "programa previo valido");

        start_load(2 + 4 * 8);
        send_byte(8'h08);                     // solo medio encabezado
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_TIMEOUT, "truncado en el encabezado conserva el programa");
        check_cpu_was_reset(1'b0, "truncado en el encabezado no resetea la CPU");

        start_load(2 + 4 * 8);                // ni un solo byte
        wait_for_finish;
        check_load_result(1'b1, 4, `LOAD_ERROR_TIMEOUT, "carga sin ningun byte conserva el programa");
        check_cpu_was_reset(1'b0, "carga sin bytes no resetea la CPU");
        check_memory_matches_expected("memoria intacta tras truncados en el encabezado");

        start_load(2 + 4 * 8);
        send_word_count(8);
        send_words(3);
        send_byte(sent_image[3][7:0]);        // media palabra y silencio
        wait_for_finish;
        commit_to_expected_memory(3);         // las 3 palabras completas si se escribieron
        check_load_result(1'b0, 0, `LOAD_ERROR_TIMEOUT, "truncado en las palabras invalida el programa");
        check_cpu_was_reset(1'b1, "truncado en las palabras habia reseteado la CPU");
        check_memory_matches_expected("solo las palabras completas llegaron a la memoria");

        // ---------------------------------------------------------------------
        $display("[11] Sin programa previo, un encabezado invalido deja el sistema sin programa");
        start_load(2);
        send_word_count(0);
        wait_for_finish;
        check_load_result(1'b0, 0, `LOAD_ERROR_ARGUMENT, "encabezado invalido sin programa previo");
        check_cpu_was_reset(1'b0, "encabezado invalido no resetea la CPU");

        // ---------------------------------------------------------------------
        $display("[12] i_load_start durante una carga se ignora");
        fill_sent_image(32'h7004_0000);
        start_load(2 + 4 * 4);
        send_word_count(4);
        send_words(2);
        start_load(2 + 4 * 1);                // no debe reiniciar la carga
        for (i = 2; i < 4; i = i + 1) begin
            send_byte(sent_image[i][7:0]);
            send_byte(sent_image[i][15:8]);
            send_byte(sent_image[i][23:16]);
            send_byte(sent_image[i][31:24]);
        end
        wait_for_finish;
        commit_to_expected_memory(4);
        check_load_result(1'b1, 4, `LOAD_ERROR_NONE, "start ignorado en plena carga");
        check_memory_matches_expected("memoria correcta tras start ignorado");

        // ---------------------------------------------------------------------
        $display("[13] Reset de sistema durante la carga y despues de ella");
        begin : reset_cases
            integer pulses_before;
            pulses_before = finished_pulse_count;

            start_load(2 + 4 * 3);
            send_word_count(3);
            send_words(1);
            apply_reset;
            idle_cycles(RX_TIMEOUT_CYCLES + 20);
            check(finished_pulse_count == pulses_before, "el reset aborta sin avisar fin de carga");
            check_load_result(1'b0, 0, `LOAD_ERROR_NONE, "estado limpio tras reset en plena carga");

            fill_sent_image(32'h7005_0000);
            load_valid_image(3);
            check(program_valid === 1'b1, "carga valida tras el reset");
            start_load(2 + 4 * 3);            // reset a mitad del encabezado
            send_byte(8'h03);
            apply_reset;
            idle_cycles(RX_TIMEOUT_CYCLES + 20);
            check_load_result(1'b0, 0, `LOAD_ERROR_NONE, "reset de sistema invalida el programa");
        end

        // ---------------------------------------------------------------------
        if (checks_failed == 0)
            $display("\nRESULTADO: PASS (%0d verificaciones)", checks_run);
        else
            $display("\nRESULTADO: FAIL (%0d fallas en %0d verificaciones)", checks_failed, checks_run);
        $finish;
    end

    // Evita que una falla deje la simulacion colgada
    initial begin
        #(CLK_PERIOD * 400000);
        $display("RESULTADO: FAIL (la simulacion no termino)");
        $finish;
    end

endmodule
