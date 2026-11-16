`timescale 1ns / 1ps

module tb_uart_rx;

    localparam CLK_HZ                = 27_000_000;
    localparam BAUD_RATE             = 115_200;
    localparam CLK_PERIOD_NS         = 10;
    localparam NOMINAL_BIT_PERIOD_NS = 234 * CLK_PERIOD_NS;     // 27 MHz / 115200 redondeado

    reg        clk     = 1'b0;
    reg        reset   = 1'b1;
    reg        rx_pin  = 1'b1;
    wire [7:0] byte_data;
    wire       byte_valid;
    wire       framing_error;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) dut (
        .i_clk           (clk),
        .i_reset         (reset),
        .i_rx_pin        (rx_pin),
        .o_byte_data     (byte_data),
        .o_byte_valid    (byte_valid),
        .o_framing_error (framing_error)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Utilidades de verificacion
    // -------------------------------------------------------------------------
    integer check_count = 0;
    integer error_count = 0;

    task report_error(input [8*64-1:0] description);
        begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %0s", $time, description);
        end
    endtask

    task check(input condition, input [8*64-1:0] description);
        begin
            check_count = check_count + 1;
            if (!condition)
                report_error(description);
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor de la salida y scoreboard
    // -------------------------------------------------------------------------
    reg [7:0] received_bytes [0:1023];
    reg [7:0] expected_bytes [0:1023];
    integer   received_count        = 0;
    integer   expected_count        = 0;
    integer   framing_error_count   = 0;
    reg       previous_byte_valid   = 1'b0;
    reg       previous_framing_error = 1'b0;

    always @(posedge clk) begin
        previous_byte_valid    <= byte_valid;
        previous_framing_error <= framing_error;

        if (byte_valid) begin
            received_bytes[received_count] = byte_data;
            received_count                 = received_count + 1;
            if (previous_byte_valid)
                report_error("o_byte_valid debe durar un solo ciclo");
        end

        if (framing_error) begin
            framing_error_count = framing_error_count + 1;
            if (previous_framing_error)
                report_error("o_framing_error debe durar un solo ciclo");
        end

        if (byte_valid && framing_error)
            report_error("un byte no puede ser valido y tener framing error");
    end

    task check_scoreboard(input [8*64-1:0] group_name);
        integer byte_index;
        integer mismatches;
        begin
            mismatches = 0;
            check(received_count == expected_count, "cantidad de bytes recibidos distinta de la enviada");

            for (byte_index = 0; byte_index < expected_count && byte_index < received_count; byte_index = byte_index + 1)
                if (received_bytes[byte_index] !== expected_bytes[byte_index]) begin
                    mismatches = mismatches + 1;
                    $display("  byte %0d: esperado %h, recibido %h", byte_index,
                             expected_bytes[byte_index], received_bytes[byte_index]);
                end

            check(mismatches == 0, "hay bytes recibidos distintos de los enviados");
            $display("  %0s: %0d bytes enviados, %0d recibidos", group_name, expected_count, received_count);
        end
    endtask

    // -------------------------------------------------------------------------
    // Emisor de comportamiento
    // -------------------------------------------------------------------------
    integer bit_period_ns = NOMINAL_BIT_PERIOD_NS;     // se cambia para probar tolerancia de baudios

    task drive_bit(input value);
        begin
            rx_pin = value;
            #(bit_period_ns);
        end
    endtask

    task send_frame(input [7:0] data, input stop_value);
        integer bit_index;
        begin
            drive_bit(1'b0);                                        // start
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                drive_bit(data[bit_index]);                         // menos significativo primero
            drive_bit(stop_value);
        end
    endtask

    // Envia una trama correcta y anota el byte como esperado
    task send_good_byte(input [7:0] data);
        begin
            expected_bytes[expected_count] = data;
            expected_count                 = expected_count + 1;
            send_frame(data, 1'b1);
        end
    endtask

    task idle_for_bits(input integer bit_count);
        begin
            rx_pin = 1'b1;
            #(bit_count * NOMINAL_BIT_PERIOD_NS);
        end
    endtask

    task apply_reset;
        begin
            @(posedge clk);
            reset <= 1'b1;
            repeat (3) @(posedge clk);
            reset <= 1'b0;
        end
    endtask

    // Envia 16 bytes seguidos con el periodo de bit pedido y vuelve al nominal
    task send_with_bit_period(input integer period_ns, input [8*64-1:0] group_name);
        integer byte_index;
        begin
            bit_period_ns = period_ns;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                send_good_byte(8'h3B + byte_index * 8'h11);
            bit_period_ns = NOMINAL_BIT_PERIOD_NS;
            idle_for_bits(2);
            check_scoreboard(group_name);
        end
    endtask

    // -------------------------------------------------------------------------
    // Pruebas
    // -------------------------------------------------------------------------
    integer byte_value;
    reg [7:0] last_good_byte;

    initial begin
        $display("tb_uart_rx: inicio");
        apply_reset;
        #7;                                                         // la linea cambia entre flancos de clock

        // ---- Linea en reposo: no aparece nada ------------------------------
        idle_for_bits(5);
        check(received_count == 0 && framing_error_count == 0, "la linea en reposo no debe generar bytes ni errores");

        // ---- Bytes representativos con pausa entre tramas ------------------
        send_good_byte(8'h55); idle_for_bits(2);
        send_good_byte(8'hAA); idle_for_bits(2);
        send_good_byte(8'h00); idle_for_bits(2);
        send_good_byte(8'hFF); idle_for_bits(2);
        send_good_byte(8'hA5); idle_for_bits(2);
        send_good_byte(8'h01); idle_for_bits(2);                    // el bit menos significativo llega primero
        send_good_byte(8'h80); idle_for_bits(2);                    // el mas significativo llega ultimo
        check_scoreboard("bytes representativos");

        // ---- Tramas pegadas, sin ningun ciclo de reposo entre ellas --------
        for (byte_value = 0; byte_value < 20; byte_value = byte_value + 1)
            send_good_byte(8'hC0 + byte_value);
        idle_for_bits(2);
        check_scoreboard("tramas consecutivas");

        // ---- Secuencia larga: los 256 valores seguidos ---------------------
        for (byte_value = 0; byte_value < 256; byte_value = byte_value + 1)
            send_good_byte(byte_value);
        idle_for_bits(2);
        check_scoreboard("secuencia de 256 bytes");

        // ---- Tolerancia a la velocidad del emisor --------------------------
        send_with_bit_period(2387, "emisor 2 % mas lento");
        send_with_bit_period(2293, "emisor 2 % mas rapido");
        send_with_bit_period(2434, "emisor 4 % mas lento");
        send_with_bit_period(2246, "emisor 4 % mas rapido");

        // ---- Framing error: el byte se descarta y el receptor se recupera ----
        last_good_byte = expected_bytes[expected_count - 1];
        send_frame(8'h5A, 1'b0);                                    // stop en 0
        idle_for_bits(2);
        check(framing_error_count == 1, "un stop en 0 debe producir un framing error");
        check(received_count == expected_count, "una trama con framing error no debe entregarse");
        check(byte_data === last_good_byte, "o_byte_data no debe cambiar con una trama descartada");
        send_good_byte(8'hC3);
        idle_for_bits(2);
        check_scoreboard("recuperacion tras framing error");

        // ---- Break: linea en 0 por mas de cinco tramas -> un solo error ------
        rx_pin = 1'b0;
        #(5 * 10 * NOMINAL_BIT_PERIOD_NS);
        rx_pin = 1'b1;
        idle_for_bits(2);
        check(framing_error_count == 2, "un break debe producir un unico framing error");
        send_good_byte(8'h96);
        idle_for_bits(2);
        check_scoreboard("recuperacion tras break");

        // ---- Glitch mas corto que medio bit: se ignora ---------------------
        rx_pin = 1'b0;
        #(50 * CLK_PERIOD_NS);
        rx_pin = 1'b1;
        idle_for_bits(2);
        rx_pin = 1'b0;
        #(100 * CLK_PERIOD_NS);                                     // casi medio bit (117 ciclos)
        rx_pin = 1'b1;
        idle_for_bits(2);
        check(framing_error_count == 2, "un glitch no debe producir framing error");
        send_good_byte(8'h69);
        idle_for_bits(2);
        check_scoreboard("rechazo de glitches");

        // ---- Reset en medio de una trama: se aborta sin entregar nada -------
        drive_bit(1'b0);                                            // start
        drive_bit(1'b1);
        drive_bit(1'b1);
        drive_bit(1'b1);
        rx_pin = 1'b1;                                              // el resto de la trama llegaria en 1
        apply_reset;
        idle_for_bits(12);
        check(framing_error_count == 2, "el reset en medio de una trama no debe dejar errores");
        send_good_byte(8'hE1);
        idle_for_bits(2);
        check_scoreboard("reset durante la recepcion");

        if (error_count == 0)
            $display("tb_uart_rx: PASS (%0d verificaciones)", check_count);
        else
            $display("tb_uart_rx: FAIL (%0d errores en %0d verificaciones)", error_count, check_count);

        $finish;
    end

    // Evita que una falla deje la simulacion colgada
    initial begin
        #(CLK_PERIOD_NS * 3_000_000);
        $display("tb_uart_rx: TIMEOUT");
        $finish;
    end

endmodule
