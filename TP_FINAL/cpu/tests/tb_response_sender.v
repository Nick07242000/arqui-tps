`timescale 1ns / 1ps

module tb_response_sender;

    localparam CLK_HZ              = 27_000_000;
    localparam BAUD_RATE           = 1_350_000;
    localparam BIT_PERIOD_CYCLES   = (CLK_HZ + BAUD_RATE / 2) / BAUD_RATE;
    localparam FRAME_CYCLES        = 10 * BIT_PERIOD_CYCLES;
    localparam PAYLOAD_PATTERN     = 8'hA0;                 // byte i del payload = PATTERN + i
    localparam RECEIVED_CAPACITY   = 8192;

    // ---- Senales ------------------------------------------------------------
    reg         clk = 1'b0;
    reg         reset = 1'b1;

    reg         response_request = 1'b0;
    reg  [7:0]  response_status = 8'd0;
    reg  [15:0] response_payload_length_bytes = 16'd0;
    wire        response_finished;

    wire [15:0] payload_byte_index;
    reg  [7:0]  payload_byte = 8'd0;

    wire        tx_send_request;
    wire [7:0]  tx_byte_data;
    wire        tx_busy;
    wire        serial_line;

    wire [7:0]  rx_byte_data;
    wire        rx_byte_valid;

    always #18.5 clk = ~clk;

    // ---- Modulos ------------------------------------------------------------
    response_sender dut (
        .i_clk                           (clk),
        .i_reset                         (reset),
        .i_response_request              (response_request),
        .i_response_status               (response_status),
        .i_response_payload_length_bytes (response_payload_length_bytes),
        .o_response_finished             (response_finished),
        .o_payload_byte_index            (payload_byte_index),
        .i_payload_byte                  (payload_byte),
        .o_tx_send_request               (tx_send_request),
        .o_tx_byte_data                  (tx_byte_data),
        .i_tx_busy                       (tx_busy)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) transmitter (
        .i_clk          (clk),
        .i_reset        (reset),
        .i_send_request (tx_send_request),
        .i_byte_data    (tx_byte_data),
        .o_tx_pin       (serial_line),
        .o_busy         (tx_busy)
    );

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) pc_receiver (
        .i_clk           (clk),
        .i_reset         (reset),
        .i_rx_pin        (serial_line),
        .o_byte_data     (rx_byte_data),
        .o_byte_valid    (rx_byte_valid),
        .o_framing_error ()
    );

    // El proveedor de payload tarda un ciclo, como el puerto B de data_memory
    always @(posedge clk)
        payload_byte <= PAYLOAD_PATTERN + payload_byte_index[7:0];

    // ---- Captura de lo que recibe la PC -------------------------------------
    reg [7:0] received_bytes [0:RECEIVED_CAPACITY-1];
    integer   received_count = 0;
    integer   finished_count = 0;
    integer   received_count_at_finish = 0;

    always @(posedge clk) begin
        if (rx_byte_valid) begin
            received_bytes[received_count] = rx_byte_data;
            received_count = received_count + 1;
        end
        if (response_finished) begin
            finished_count = finished_count + 1;
            received_count_at_finish = received_count;
        end
    end

    // ---- Verificacion -------------------------------------------------------
    integer failures = 0;

    task check(input condition, input [8*60-1:0] description);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("  FALLA: %0s (t=%0t)", description, $time);
            end
        end
    endtask

    task pulse_request(input [7:0] status, input [15:0] payload_length_bytes);
        begin
            @(negedge clk);
            response_status               = status;
            response_payload_length_bytes = payload_length_bytes;
            response_request              = 1'b1;
            @(negedge clk);
            response_request              = 1'b0;
        end
    endtask

    // Envia una respuesta, espera su fin y comprueba el flujo completo recibido
    task run_response(input [7:0] status, input [15:0] payload_length_bytes, input [8*40-1:0] name);
        integer first_byte;
        integer byte_index;
        integer finished_before;
        integer wait_cycles;
        begin
            first_byte      = received_count;
            finished_before = finished_count;
            pulse_request(status, payload_length_bytes);

            wait_cycles = 0;
            while (finished_count == finished_before && wait_cycles < (payload_length_bytes + 8) * (FRAME_CYCLES + 10)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            repeat (2 * FRAME_CYCLES) @(posedge clk);

            $display("[%0s] STATUS=%02h LEN=%0d", name, status, payload_length_bytes);
            check(finished_count == finished_before + 1,                     "o_response_finished un solo pulso");
            check(received_count - first_byte == 3 + payload_length_bytes,   "cantidad de bytes recibidos");
            check(received_count_at_finish - first_byte == 3 + payload_length_bytes,
                                                                             "el ultimo byte llego antes de finished");
            check(received_bytes[first_byte]     == status,                  "byte STATUS");
            check(received_bytes[first_byte + 1] == payload_length_bytes[7:0],  "LEN bajo");
            check(received_bytes[first_byte + 2] == payload_length_bytes[15:8], "LEN alto");
            for (byte_index = 0; byte_index < payload_length_bytes; byte_index = byte_index + 1)
                if (received_bytes[first_byte + 3 + byte_index] !== PAYLOAD_PATTERN + byte_index[7:0]) begin
                    failures = failures + 1;
                    $display("  FALLA: payload[%0d] = %02h, esperado %02h", byte_index,
                             received_bytes[first_byte + 3 + byte_index], PAYLOAD_PATTERN + byte_index[7:0]);
                end
        end
    endtask

    integer count_before_ignored;

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (5) @(posedge clk);

        run_response(8'h05, 16'd0,    "error sin payload (ERR_BUSY)");
        run_response(8'h00, 16'd1,    "OK con 1 byte (state)");
        run_response(8'h00, 16'd17,   "OK con 17 bytes (GET_STATUS)");
        run_response(8'h00, 16'd300,  "OK con 300 bytes (LEN cruza 8 bits)");
        run_response(8'h00, 16'd4096, "OK con 4096 bytes (GET_MEMORY maximo)");

        // Respuestas una tras otra, sin pausa
        run_response(8'h07, 16'd0, "respuesta consecutiva 1");
        run_response(8'h02, 16'd0, "respuesta consecutiva 2");

        // Un pedido con el emisor ocupado se ignora y no altera la trama en curso
        $display("[pedido con el emisor ocupado]");
        count_before_ignored = received_count;
        pulse_request(8'h00, 16'd2);
        repeat (FRAME_CYCLES * 2) @(posedge clk);
        pulse_request(8'h09, 16'd0);                       // llega a mitad de la respuesta anterior
        repeat (12 * FRAME_CYCLES) @(posedge clk);
        check(received_count - count_before_ignored == 5, "solo sale la respuesta aceptada (3 + 2 bytes)");
        check(received_bytes[count_before_ignored] == 8'h00, "la trama aceptada no se altero");

        // Reset a mitad de una respuesta: el emisor vuelve a quedar libre
        $display("[reset a mitad de respuesta]");
        pulse_request(8'h00, 16'd128);
        repeat (5 * FRAME_CYCLES) @(posedge clk);
        reset = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (2 * FRAME_CYCLES) @(posedge clk);
        run_response(8'h00, 16'd3, "respuesta despues del reset");

        if (failures == 0) $display("\nTB_RESPONSE_SENDER: PASS");
        else               $display("\nTB_RESPONSE_SENDER: FAIL (%0d fallas)", failures);
        $finish;
    end

    // Corta la simulacion si algo se cuelga
    initial begin
        #400_000_000;
        $display("TB_RESPONSE_SENDER: FAIL (timeout global)");
        $finish;
    end

endmodule
