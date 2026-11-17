`timescale 1ns / 1ps
`include "protocol_defs.vh"
`include "execution_defs.vh"

module tb_command_protocol;

    // ---- Configuracion (UART rapida y timeouts cortos para acortar la simulacion)
    localparam CLK_HZ            = 27_000_000;
    localparam BAUD_RATE         = 1_350_000;
    localparam BIT_PERIOD_CYCLES = (CLK_HZ + BAUD_RATE / 2) / BAUD_RATE;
    localparam FRAME_CYCLES      = 10 * BIT_PERIOD_CYCLES;
    localparam RX_TIMEOUT_CYCLES = 8000;
    localparam ADDR_WIDTH        = 10;
    localparam MEMORY_DEPTH      = 1 << ADDR_WIDTH;
    localparam MAX_LOAD_LENGTH   = 2 + 4 * MEMORY_DEPTH;

    localparam RESPONSE_WAIT_LIMIT = 1_500_000;
    localparam RESPONSE_CAPACITY   = 16384;

    // ---- Senales ------------------------------------------------------------
    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg         uart_rx_pin = 1'b1;
    reg         cpu_done = 1'b0;
    reg         completion_gate = 1'b1;        // en 0 el controlador "no contesta" (prueba de ERR_INTERNAL)

    wire [7:0]  rx_byte_data;
    wire        rx_byte_valid;
    wire        rx_framing_error;

    wire        run_request, step_request, reset_request;
    wire        controller_command_finished;
    wire [1:0]  command_result;
    wire [2:0]  system_state;

    wire        load_start, load_byte_valid, load_finished;
    wire [15:0] load_payload_length_bytes;
    wire [7:0]  load_byte_data;
    wire [1:0]  load_error_code;
    wire        program_valid;
    wire [ADDR_WIDTH:0] n_words;
    wire        imem_write_enable;
    wire [ADDR_WIDTH-1:0] imem_write_word_addr;
    wire [31:0] imem_write_data;

    wire [7:0]  command_code;
    wire [15:0] memory_start_word, memory_word_count;

    wire        response_request, response_finished;
    wire [7:0]  response_status;
    wire [15:0] response_payload_length_bytes;
    wire [15:0] payload_byte_index;
    reg  [7:0]  payload_byte = 8'd0;

    wire        tx_send_request, tx_busy, serial_line_to_pc;
    wire [7:0]  tx_byte_data;
    wire [7:0]  pc_byte_data;
    wire        pc_byte_valid;

    always #18.5 clk = ~clk;

    // ---- Sistema bajo prueba ------------------------------------------------
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) board_receiver (
        .i_clk(clk), .i_reset(reset), .i_rx_pin(uart_rx_pin),
        .o_byte_data(rx_byte_data), .o_byte_valid(rx_byte_valid), .o_framing_error(rx_framing_error)
    );

    command_parser #(.ADDR_WIDTH(ADDR_WIDTH), .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)) parser (
        .i_clk(clk), .i_reset(reset),
        .i_rx_byte_valid(rx_byte_valid), .i_rx_byte_data(rx_byte_data), .i_rx_framing_error(rx_framing_error),
        .i_system_state(system_state),
        .o_run_request(run_request), .o_step_request(step_request), .o_reset_request(reset_request),
        .i_command_finished(controller_command_finished & completion_gate),
        .i_command_result(command_result),
        .o_load_start(load_start), .o_load_payload_length_bytes(load_payload_length_bytes),
        .o_load_byte_valid(load_byte_valid), .o_load_byte_data(load_byte_data),
        .i_load_finished(load_finished), .i_load_error_code(load_error_code),
        .o_command_code(command_code),
        .o_memory_start_word(memory_start_word), .o_memory_word_count(memory_word_count),
        .o_response_request(response_request), .o_response_status(response_status),
        .o_response_payload_length_bytes(response_payload_length_bytes),
        .i_response_finished(response_finished)
    );

    program_loader #(.ADDR_WIDTH(ADDR_WIDTH), .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)) loader (
        .i_clk(clk), .i_reset(reset),
        .i_load_start(load_start), .i_payload_length_bytes(load_payload_length_bytes),
        .i_byte_valid(load_byte_valid), .i_byte_data(load_byte_data),
        .o_imem_write_enable(imem_write_enable), .o_imem_write_word_addr(imem_write_word_addr),
        .o_imem_write_data(imem_write_data),
        .o_cpu_reset(), .o_program_valid(program_valid), .o_n_words(n_words),
        .o_load_finished(load_finished), .o_load_error_code(load_error_code)
    );

    program_memory #(.ADDR_WIDTH(ADDR_WIDTH)) program_mem (
        .i_clk(clk),
        .i_read_enable(1'b0), .i_read_word_addr({ADDR_WIDTH{1'b0}}), .o_read_data(),
        .i_write_enable(imem_write_enable), .i_write_word_addr(imem_write_word_addr),
        .i_write_data(imem_write_data)
    );

    execution_controller exec (
        .i_clk(clk), .i_reset(reset),
        .i_run_request(run_request), .i_step_request(step_request), .i_reset_request(reset_request),
        .i_load_finished(load_finished), .i_load_error_code(load_error_code),
        .i_program_valid(program_valid), .i_cpu_done(cpu_done),
        .o_cpu_enable(), .o_cpu_reset(),
        .o_system_state(system_state),
        .o_command_finished(controller_command_finished), .o_command_result(command_result)
    );

    response_sender sender (
        .i_clk(clk), .i_reset(reset),
        .i_response_request(response_request), .i_response_status(response_status),
        .i_response_payload_length_bytes(response_payload_length_bytes),
        .o_response_finished(response_finished),
        .o_payload_byte_index(payload_byte_index), .i_payload_byte(payload_byte),
        .o_tx_send_request(tx_send_request), .o_tx_byte_data(tx_byte_data), .i_tx_busy(tx_busy)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) board_transmitter (
        .i_clk(clk), .i_reset(reset), .i_send_request(tx_send_request), .i_byte_data(tx_byte_data),
        .o_tx_pin(serial_line_to_pc), .o_busy(tx_busy)
    );

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) pc_receiver (
        .i_clk(clk), .i_reset(reset), .i_rx_pin(serial_line_to_pc),
        .o_byte_data(pc_byte_data), .o_byte_valid(pc_byte_valid), .o_framing_error()
    );

    // ---- Proveedor de payload de prueba (la US-5.3 lo reemplaza) ------------
    // LOAD/RESET/RUN/STEP devuelven el estado; los GET_* un patron conocido.
    // Tarda un ciclo en responder, como el puerto B de data_memory.
    function [7:0] pattern_byte(input [7:0] command, input [15:0] start_word, input [15:0] index);
        begin
            pattern_byte = command ^ index[7:0] ^ index[15:8]
                         ^ ((command == `COMMAND_GET_MEMORY) ? start_word[7:0] : 8'h00);
        end
    endfunction

    always @(posedge clk) begin
        case (command_code)
            `COMMAND_LOAD_PROGRAM, `COMMAND_RESET, `COMMAND_RUN, `COMMAND_STEP:
                payload_byte <= {5'b0, system_state};
            default:
                payload_byte <= pattern_byte(command_code, memory_start_word, payload_byte_index);
        endcase
    end

    // ---- Captura de lo que recibe la PC y de las ordenes emitidas -----------
    reg [7:0] response_bytes [0:RESPONSE_CAPACITY-1];
    integer   response_count        = 0;
    integer   response_read_pointer = 0;

    integer run_count = 0, step_count = 0, reset_count = 0, load_start_count = 0;

    always @(posedge clk) begin
        if (pc_byte_valid) begin
            response_bytes[response_count] = pc_byte_data;
            response_count = response_count + 1;
        end
        if (run_request)   run_count        = run_count + 1;
        if (step_request)  step_count       = step_count + 1;
        if (reset_request) reset_count      = reset_count + 1;
        if (load_start)    load_start_count = load_start_count + 1;
    end

    // =========================================================================
    // Herramientas de la PC simulada
    // =========================================================================
    integer failures = 0;
    integer tests    = 0;

    task check(input condition, input [8*64-1:0] description);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("    FALLA: %0s (t=%0t)", description, $time);
            end
        end
    endtask

    task begin_test(input [8*100-1:0] name);
        begin
            tests = tests + 1;
            $display("[%0d] %0s", tests, name);
        end
    endtask

    // ---- Transmision serie hacia la FPGA ------------------------------------
    task send_serial_byte(input [7:0] value, input stop_bit_value);
        integer bit_index;
        begin
            uart_rx_pin = 1'b0;                                 // start
            repeat (BIT_PERIOD_CYCLES) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_pin = value[bit_index];
                repeat (BIT_PERIOD_CYCLES) @(posedge clk);
            end
            uart_rx_pin = stop_bit_value;                       // 0 provoca un framing error
            repeat (BIT_PERIOD_CYCLES) @(posedge clk);
            uart_rx_pin = 1'b1;
        end
    endtask

    reg [7:0] message_payload [0:MAX_LOAD_LENGTH+8];

    // Envia [CMD][LEN][primeros bytes de message_payload]; LEN y bytes reales pueden diferir
    task send_message(input [7:0] command, input [15:0] declared_length, input integer actual_payload_bytes);
        integer byte_index;
        begin
            send_serial_byte(command,               1'b1);
            send_serial_byte(declared_length[7:0],  1'b1);
            send_serial_byte(declared_length[15:8], 1'b1);
            for (byte_index = 0; byte_index < actual_payload_bytes; byte_index = byte_index + 1)
                send_serial_byte(message_payload[byte_index], 1'b1);
        end
    endtask

    task send_empty_message(input [7:0] command);
        begin
            send_message(command, 16'd0, 0);
        end
    endtask

    task wait_cycles(input integer cycles);
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    // Tras un error que fuerza resincronizar, la FPGA ignora todo hasta un silencio
    task wait_for_resync;
        begin
            wait_cycles(RX_TIMEOUT_CYCLES + 4 * FRAME_CYCLES);
        end
    endtask

    // ---- Recepcion de respuestas --------------------------------------------
    integer last_payload_base;
    integer last_response_length;

    task wait_for_response_bytes(input integer needed_bytes);
        integer waited;
        begin
            waited = 0;
            while (response_count < response_read_pointer + needed_bytes && waited < RESPONSE_WAIT_LIMIT) begin
                @(posedge clk);
                waited = waited + 1;
            end
        end
    endtask

    task expect_response(input [7:0] expected_status, input [15:0] expected_length);
        begin
            wait_for_response_bytes(3);
            if (response_count < response_read_pointer + 3) begin
                failures = failures + 1;
                $display("    FALLA: no llego la respuesta (t=%0t)", $time);
            end else begin
                last_response_length = response_bytes[response_read_pointer + 1]
                                     + 256 * response_bytes[response_read_pointer + 2];
                check(response_bytes[response_read_pointer] == expected_status, "STATUS de la respuesta");
                if (response_bytes[response_read_pointer] != expected_status)
                    $display("      STATUS recibido = %02h, esperado = %02h", response_bytes[response_read_pointer], expected_status);
                check(last_response_length == expected_length, "LEN de la respuesta");
                wait_for_response_bytes(3 + last_response_length);
                last_payload_base     = response_read_pointer + 3;
                response_read_pointer = response_read_pointer + 3 + last_response_length;
                wait_cycles(2 * FRAME_CYCLES);
                check(response_count == response_read_pointer, "no llegan bytes de mas");
            end
        end
    endtask

    task expect_ok_state(input [2:0] expected_state);
        begin
            expect_response(`STATUS_OK, 16'd1);
            check(response_bytes[last_payload_base] == {5'b0, expected_state}, "state del payload");
            if (response_bytes[last_payload_base] != {5'b0, expected_state})
                $display("      state recibido = %0d, esperado = %0d", response_bytes[last_payload_base], expected_state);
        end
    endtask

    task expect_pattern_ok(input [7:0] command, input [15:0] start_word, input [15:0] length);
        integer byte_index;
        integer mismatches;
        begin
            expect_response(`STATUS_OK, length);
            mismatches = 0;
            for (byte_index = 0; byte_index < length; byte_index = byte_index + 1)
                if (response_bytes[last_payload_base + byte_index] !== pattern_byte(command, start_word, byte_index))
                    mismatches = mismatches + 1;
            check(mismatches == 0, "contenido del payload");
        end
    endtask

    // ---- Programas de prueba ------------------------------------------------
    function [31:0] program_word(input [7:0] seed, input integer index);
        begin
            program_word = {seed, index[15:8], index[7:0], 8'hA5};
        end
    endfunction

    // message_payload = [N_WORDS field:2 LE][actual_words palabras LE]
    task prepare_load_payload(input [15:0] words_field, input integer actual_words, input [7:0] seed);
        integer word_index;
        reg [31:0] word;
        begin
            message_payload[0] = words_field[7:0];
            message_payload[1] = words_field[15:8];
            for (word_index = 0; word_index < actual_words; word_index = word_index + 1) begin
                word = program_word(seed, word_index);
                message_payload[2 + 4*word_index + 0] = word[7:0];
                message_payload[2 + 4*word_index + 1] = word[15:8];
                message_payload[2 + 4*word_index + 2] = word[23:16];
                message_payload[2 + 4*word_index + 3] = word[31:24];
            end
        end
    endtask

    task check_program_memory(input [7:0] seed, input integer words);
        integer word_index;
        integer mismatches;
        begin
            mismatches = 0;
            for (word_index = 0; word_index < words; word_index = word_index + 1)
                if (program_mem.memory[word_index] !== program_word(seed, word_index))
                    mismatches = mismatches + 1;
            check(mismatches == 0, "program_memory contiene la imagen enviada");
        end
    endtask

    // Carga valida completa y comprobacion de lo que quedo escrito
    task load_valid_program(input [7:0] seed, input integer words);
        begin
            prepare_load_payload(words, words, seed);
            send_message(`COMMAND_LOAD_PROGRAM, 2 + 4 * words, 2 + 4 * words);
            expect_ok_state(`EXEC_STATE_READY);
            check_program_memory(seed, words);
            check(n_words == words && program_valid, "N_WORDS y program_valid actualizados");
        end
    endtask

    // ---- Verificacion de que un mensaje rechazado no tuvo efectos -----------
    integer snap_run, snap_step, snap_reset, snap_load;
    reg [2:0]  snap_state;
    reg [ADDR_WIDTH:0] snap_n_words;
    reg        snap_program_valid;

    task take_snapshot;
        begin
            snap_run = run_count;  snap_step = step_count;  snap_reset = reset_count;  snap_load = load_start_count;
            snap_state = system_state;  snap_n_words = n_words;  snap_program_valid = program_valid;
        end
    endtask

    task check_no_effect;
        begin
            check(run_count == snap_run && step_count == snap_step && reset_count == snap_reset,
                  "no se emitio RUN/STEP/RESET");
            check(load_start_count == snap_load, "no se inicio una carga");
            check(system_state == snap_state, "el estado del sistema no cambio");
            check(n_words == snap_n_words && program_valid == snap_program_valid, "el programa cargado no cambio");
        end
    endtask

    // Mensaje que debe rechazarse con un STATUS dado, sin efecto alguno
    task expect_rejected(input [7:0] command, input [15:0] declared_length, input integer actual_bytes,
                         input [7:0] expected_status);
        begin
            take_snapshot;
            send_message(command, declared_length, actual_bytes);
            expect_response(expected_status, 16'd0);
            check_no_effect;
        end
    endtask

    // Rechazo que decide el execution_controller: la orden si se emite, pero no cambia nada
    task expect_controller_rejection(input [7:0] command, input [7:0] expected_status);
        begin
            take_snapshot;
            send_empty_message(command);
            expect_response(expected_status, 16'd0);
            check(system_state == snap_state, "el estado del sistema no cambio");
            check(n_words == snap_n_words && program_valid == snap_program_valid, "el programa cargado no cambio");
        end
    endtask

    // Rechazo que decide el program_loader: la carga arranca, pero el programa anterior sigue intacto
    task expect_load_rejection(input [15:0] declared_length, input integer actual_bytes, input [7:0] expected_status);
        begin
            take_snapshot;
            send_message(`COMMAND_LOAD_PROGRAM, declared_length, actual_bytes);
            expect_response(expected_status, 16'd0);
            check(system_state == snap_state, "el estado del sistema no cambio");
            check(n_words == snap_n_words && program_valid == snap_program_valid, "el programa cargado no cambio");
        end
    endtask

    task set_memory_arguments(input [15:0] start_word, input [15:0] word_count);
        begin
            message_payload[0] = start_word[7:0];   message_payload[1] = start_word[15:8];
            message_payload[2] = word_count[7:0];   message_payload[3] = word_count[15:8];
        end
    endtask

    integer i;

    // =========================================================================
    // Pruebas
    // =========================================================================
    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;
        wait_cycles(10);

        // ---------------------------------------------------------------------
        begin_test("EMPTY: RUN/STEP sin programa -> ERR_NO_PROGRAM");
        check(system_state == `EXEC_STATE_EMPTY, "arranca en EMPTY");
        expect_controller_rejection(`COMMAND_RUN,  `STATUS_ERR_NO_PROGRAM);
        expect_controller_rejection(`COMMAND_STEP, `STATUS_ERR_NO_PROGRAM);

        begin_test("EMPTY: RESET y consultas se aceptan");
        send_empty_message(`COMMAND_RESET);      expect_ok_state(`EXEC_STATE_EMPTY);
        send_empty_message(`COMMAND_GET_STATUS); expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);
        send_empty_message(`COMMAND_GET_REGS);   expect_pattern_ok(`COMMAND_GET_REGS, 0, 16'd128);

        // ---------------------------------------------------------------------
        begin_test("LOAD_PROGRAM valido (3 palabras) -> OK, state READY");
        load_valid_program(8'h11, 3);

        begin_test("LOAD_PROGRAM con encabezado invalido: se rechaza y se conserva el programa");
        prepare_load_payload(16'd0, 0, 8'h22);                       // N_WORDS = 0
        expect_load_rejection(16'd2, 2, `STATUS_ERR_ARG);
        check_program_memory(8'h11, 3);

        prepare_load_payload(16'd1025, 1, 8'h22);                    // N_WORDS > capacidad, LEN <= maximo
        expect_load_rejection(16'd6, 6, `STATUS_ERR_ARG);
        check_program_memory(8'h11, 3);

        prepare_load_payload(16'd2, 3, 8'h22);                       // LEN no coincide con N_WORDS
        expect_load_rejection(16'd14, 14, `STATUS_ERR_LEN);
        check_program_memory(8'h11, 3);

        message_payload[0] = 8'h01;                                  // LEN menor que el encabezado
        expect_load_rejection(16'd1, 1, `STATUS_ERR_LEN);
        expect_load_rejection(16'd0, 0, `STATUS_ERR_LEN);
        check_program_memory(8'h11, 3);

        // ---------------------------------------------------------------------
        begin_test("STEP en READY -> OK, state PAUSED");
        send_empty_message(`COMMAND_STEP);
        expect_ok_state(`EXEC_STATE_PAUSED);

        begin_test("Consultas en PAUSED: STATUS, REGS, PIPELINE");
        send_empty_message(`COMMAND_GET_STATUS);   expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);
        send_empty_message(`COMMAND_GET_REGS);     expect_pattern_ok(`COMMAND_GET_REGS, 0, 16'd128);
        send_empty_message(`COMMAND_GET_PIPELINE); expect_pattern_ok(`COMMAND_GET_PIPELINE, 0, 16'd73);

        begin_test("GET_MEMORY: rangos validos, incluidos los bordes");
        set_memory_arguments(16'd2, 16'd3);
        send_message(`COMMAND_GET_MEMORY, 16'd4, 4);
        expect_pattern_ok(`COMMAND_GET_MEMORY, 16'd2, 16'd12);
        set_memory_arguments(16'd1000, 16'd24);                      // llega justo al final
        send_message(`COMMAND_GET_MEMORY, 16'd4, 4);
        expect_pattern_ok(`COMMAND_GET_MEMORY, 16'd1000, 16'd96);
        set_memory_arguments(16'd1023, 16'd1);                       // ultima palabra
        send_message(`COMMAND_GET_MEMORY, 16'd4, 4);
        expect_pattern_ok(`COMMAND_GET_MEMORY, 16'd1023, 16'd4);

        begin_test("GET_MEMORY: argumentos invalidos -> ERR_ARG");
        set_memory_arguments(16'd0, 16'd0);        expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);
        set_memory_arguments(16'd1020, 16'd8);     expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);
        set_memory_arguments(16'd1024, 16'd1);     expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);
        set_memory_arguments(16'd0, 16'd1025);     expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);
        set_memory_arguments(16'hFFFF, 16'hFFFF);  expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);
        set_memory_arguments(16'hFFFF, 16'd2);     expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);   // la suma desborda a 0x10001
        set_memory_arguments(16'hFFFE, 16'd1026);  expect_rejected(`COMMAND_GET_MEMORY, 16'd4, 4, `STATUS_ERR_ARG);   // la suma desborda a 0x10400

        begin_test("LEN incompatible con el comando -> ERR_LEN");
        expect_rejected(`COMMAND_GET_MEMORY, 16'd0, 0, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_GET_MEMORY, 16'd3, 3, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_GET_MEMORY, 16'd5, 5, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_GET_REGS,   16'd1, 1, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_GET_STATUS, 16'd2, 2, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_RUN,        16'd1, 1, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_STEP,       16'd9, 9, `STATUS_ERR_LEN);
        expect_rejected(`COMMAND_RESET,      16'd4, 4, `STATUS_ERR_LEN);

        begin_test("Comando desconocido -> ERR_CMD, sin perder la sincronizacion");
        message_payload[0] = 8'h03;  message_payload[1] = 8'h00;  message_payload[2] = 8'h00;
        expect_rejected(8'h00, 16'd0, 0, `STATUS_ERR_CMD);
        expect_rejected(8'h09, 16'd0, 0, `STATUS_ERR_CMD);
        expect_rejected(8'hFF, 16'd0, 0, `STATUS_ERR_CMD);
        expect_rejected(8'h7F, 16'd3, 3, `STATUS_ERR_CMD);            // el payload parece un RUN y no se ejecuta
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        // ---------------------------------------------------------------------
        begin_test("RUN en PAUSED -> OK, state RUNNING");
        send_empty_message(`COMMAND_RUN);
        expect_ok_state(`EXEC_STATE_RUNNING);

        begin_test("RUNNING: STATUS se atiende, el resto responde ERR_BUSY");
        send_empty_message(`COMMAND_GET_STATUS);  expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);
        expect_rejected(`COMMAND_GET_REGS,     16'd0, 0, `STATUS_ERR_BUSY);
        expect_rejected(`COMMAND_GET_PIPELINE, 16'd0, 0, `STATUS_ERR_BUSY);
        set_memory_arguments(16'd0, 16'd4);
        expect_rejected(`COMMAND_GET_MEMORY,   16'd4, 4, `STATUS_ERR_BUSY);
        set_memory_arguments(16'd0, 16'd0);                          // un argumento malo se informa antes que el estado
        expect_rejected(`COMMAND_GET_MEMORY,   16'd4, 4, `STATUS_ERR_ARG);
        expect_controller_rejection(`COMMAND_RUN,  `STATUS_ERR_BUSY);
        expect_controller_rejection(`COMMAND_STEP, `STATUS_ERR_BUSY);

        begin_test("RUNNING: LOAD_PROGRAM -> ERR_BUSY, la imagen no se toca");
        prepare_load_payload(16'd1, 1, 8'hEE);
        expect_rejected(`COMMAND_LOAD_PROGRAM, 16'd6, 6, `STATUS_ERR_BUSY);
        check_program_memory(8'h11, 3);

        begin_test("Fin de la ejecucion: RUN/STEP en DONE -> ERR_STATE");
        cpu_done = 1'b1;
        wait_cycles(10);
        check(system_state == `EXEC_STATE_DONE, "el sistema pasa a DONE");
        send_empty_message(`COMMAND_GET_REGS);  expect_pattern_ok(`COMMAND_GET_REGS, 0, 16'd128);
        expect_controller_rejection(`COMMAND_RUN,  `STATUS_ERR_STATE);
        expect_controller_rejection(`COMMAND_STEP, `STATUS_ERR_STATE);
        cpu_done = 1'b0;

        begin_test("Reprogramacion: LOAD_PROGRAM en DONE reemplaza la imagen (5 palabras)");
        load_valid_program(8'h33, 5);

        begin_test("RESET: desde READY, y como abort desde RUNNING");
        send_empty_message(`COMMAND_RESET);  expect_ok_state(`EXEC_STATE_READY);
        send_empty_message(`COMMAND_RUN);    expect_ok_state(`EXEC_STATE_RUNNING);
        send_empty_message(`COMMAND_RESET);  expect_ok_state(`EXEC_STATE_READY);
        check_program_memory(8'h33, 5);

        // ---------------------------------------------------------------------
        begin_test("Carga truncada -> ERR_TIMEOUT y el sistema queda en EMPTY");
        prepare_load_payload(16'd4, 4, 8'h44);
        send_message(`COMMAND_LOAD_PROGRAM, 16'd18, 7);              // faltan 11 bytes
        expect_response(`STATUS_ERR_TIMEOUT, 16'd0);
        check(system_state == `EXEC_STATE_EMPTY && !program_valid, "sin programa valido");
        expect_controller_rejection(`COMMAND_RUN, `STATUS_ERR_NO_PROGRAM);

        begin_test("Framing error durante LOAD_PROGRAM: el byte perdido deja la carga incompleta");
        prepare_load_payload(16'd4, 4, 8'h66);
        send_serial_byte(`COMMAND_LOAD_PROGRAM, 1'b1);
        send_serial_byte(8'd18,  1'b1);
        send_serial_byte(8'd0,   1'b1);
        for (i = 0; i < 18; i = i + 1) begin
            send_serial_byte(message_payload[i], (i == 7) ? 1'b0 : 1'b1);   // el byte 7 llega con stop en 0
            if (i == 7) wait_cycles(BIT_PERIOD_CYCLES);                     // la linea vuelve a reposo antes del siguiente
        end
        expect_response(`STATUS_ERR_TIMEOUT, 16'd0);
        check(system_state == `EXEC_STATE_EMPTY && !program_valid, "sin programa valido");

        begin_test("Encabezado truncado -> ERR_TIMEOUT");
        take_snapshot;
        send_serial_byte(`COMMAND_GET_REGS, 1'b1);                   // solo CMD
        expect_response(`STATUS_ERR_TIMEOUT, 16'd0);
        send_serial_byte(`COMMAND_GET_REGS, 1'b1);                   // CMD y LEN bajo
        send_serial_byte(8'h00, 1'b1);
        expect_response(`STATUS_ERR_TIMEOUT, 16'd0);
        check_no_effect;
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        begin_test("Payload truncado -> ERR_TIMEOUT");
        set_memory_arguments(16'd0, 16'd4);
        take_snapshot;
        send_message(`COMMAND_GET_MEMORY, 16'd4, 2);                 // llegan 2 de 4 bytes
        expect_response(`STATUS_ERR_TIMEOUT, 16'd0);
        check_no_effect;
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        // ---------------------------------------------------------------------
        begin_test("LEN > maximo: ERR_LEN inmediato y se ignora el resto del mensaje");
        message_payload[0] = 8'h03; message_payload[1] = 8'h00; message_payload[2] = 8'h00;
        message_payload[3] = 8'h04; message_payload[4] = 8'h00; message_payload[5] = 8'h00;   // parecen RUN y STEP
        take_snapshot;
        send_message(`COMMAND_RUN, 16'd5000, 6);
        wait_cycles(2 * FRAME_CYCLES);                               // mucho menos que RX_TIMEOUT_CYCLES
        check(response_count >= response_read_pointer + 3, "la respuesta llega sin esperar al timeout");
        expect_response(`STATUS_ERR_LEN, 16'd0);
        wait_for_resync;
        check_no_effect;
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        begin_test("LEN maximo exacto (4098): se acepta, 1024 palabras cargadas");
        load_valid_program(8'h55, MEMORY_DEPTH);

        begin_test("LEN = maximo + 1: ERR_LEN");
        take_snapshot;
        send_message(`COMMAND_LOAD_PROGRAM, MAX_LOAD_LENGTH + 1, 0);
        expect_response(`STATUS_ERR_LEN, 16'd0);
        wait_for_resync;
        check_no_effect;  check_program_memory(8'h55, MEMORY_DEPTH);

        // ---------------------------------------------------------------------
        begin_test("Framing error a mitad de mensaje -> ERR_FRAMING y resincronizacion");
        take_snapshot;
        send_serial_byte(`COMMAND_GET_MEMORY, 1'b1);
        send_serial_byte(8'h04, 1'b1);
        send_serial_byte(8'h00, 1'b0);                               // stop en 0
        expect_response(`STATUS_ERR_FRAMING, 16'd0);
        send_serial_byte(8'h03, 1'b1);                               // el resto del mensaje roto no se interpreta
        send_serial_byte(8'h00, 1'b1);
        send_serial_byte(8'h00, 1'b1);
        wait_for_resync;
        check_no_effect;
        check(response_count == response_read_pointer, "el resto del mensaje roto no genera respuestas");
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        begin_test("Framing error en el primer byte -> ERR_FRAMING");
        send_serial_byte(`COMMAND_RUN, 1'b0);
        expect_response(`STATUS_ERR_FRAMING, 16'd0);
        wait_for_resync;
        check_no_effect;

        // ---------------------------------------------------------------------
        begin_test("Mensaje fragmentado (pausas menores al timeout) -> se procesa");
        set_memory_arguments(16'd8, 16'd2);
        send_serial_byte(`COMMAND_GET_MEMORY, 1'b1);   wait_cycles(RX_TIMEOUT_CYCLES / 3);
        send_serial_byte(8'h04, 1'b1);                 wait_cycles(RX_TIMEOUT_CYCLES / 3);
        send_serial_byte(8'h00, 1'b1);                 wait_cycles(RX_TIMEOUT_CYCLES / 3);
        for (i = 0; i < 4; i = i + 1) begin
            send_serial_byte(message_payload[i], 1'b1);  wait_cycles(RX_TIMEOUT_CYCLES / 3);
        end
        expect_pattern_ok(`COMMAND_GET_MEMORY, 16'd8, 16'd8);

        // ---------------------------------------------------------------------
        begin_test("El controlador no contesta -> ERR_INTERNAL y el protocolo sigue vivo");
        send_empty_message(`COMMAND_RESET);  expect_ok_state(`EXEC_STATE_READY);
        completion_gate = 1'b0;
        send_empty_message(`COMMAND_STEP);
        expect_response(`STATUS_ERR_INTERNAL, 16'd0);
        completion_gate = 1'b1;
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        begin_test("Reset de sistema deja el protocolo en reposo");
        reset = 1'b1;  wait_cycles(3);  reset = 1'b0;
        wait_cycles(2 * FRAME_CYCLES);
        check(system_state == `EXEC_STATE_EMPTY, "EMPTY tras el reset");
        send_empty_message(`COMMAND_GET_STATUS);
        expect_pattern_ok(`COMMAND_GET_STATUS, 0, 16'd17);

        // ---------------------------------------------------------------------
        if (failures == 0) $display("\nTB_COMMAND_PROTOCOL: PASS (%0d pruebas)", tests);
        else               $display("\nTB_COMMAND_PROTOCOL: FAIL (%0d fallas en %0d pruebas)", failures, tests);
        $finish;
    end

    // Corta la simulacion si algo se cuelga
    initial begin
        #2_000_000_000;
        $display("TB_COMMAND_PROTOCOL: FAIL (timeout global)");
        $finish;
    end

endmodule
