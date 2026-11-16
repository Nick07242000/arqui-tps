`timescale 1ns / 1ps

module tb_uart_tx;

    localparam CLK_HZ            = 27_000_000;
    localparam BAUD_RATE         = 115_200;
    localparam BIT_PERIOD_CYCLES = 234;                          // 27 MHz / 115200 redondeado
    localparam FRAME_BITS        = 10;
    localparam FRAME_CYCLES      = BIT_PERIOD_CYCLES * FRAME_BITS;
    localparam CLK_PERIOD_NS     = 10;

    reg        clk          = 1'b0;
    reg        reset        = 1'b1;
    reg        send_request = 1'b0;
    reg  [7:0] byte_data    = 8'h00;
    wire       tx_pin;
    wire       busy;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) dut (
        .i_clk          (clk),
        .i_reset        (reset),
        .i_send_request (send_request),
        .i_byte_data    (byte_data),
        .o_tx_pin       (tx_pin),
        .o_busy         (busy)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Utilidades de verificacion
    // -------------------------------------------------------------------------
    integer check_count = 0;
    integer error_count = 0;

    task check(input condition, input [8*64-1:0] description);
        begin
            check_count = check_count + 1;
            if (!condition) begin
                error_count = error_count + 1;
                $display("[%0t] ERROR: %0s", $time, description);
            end
        end
    endtask

    task apply_reset;
        begin
            @(posedge clk);
            reset <= 1'b1;
            repeat (3) @(posedge clk);
            reset <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Pide un byte. Al volver, estamos en el flanco en que el transmisor acepta el pedido
    task request_byte(input [7:0] data);
        begin
            @(posedge clk);
            byte_data    <= data;
            send_request <= 1'b1;
            @(posedge clk);
            send_request <= 1'b0;
        end
    endtask

    // Verifica los 2340 ciclos de la trama y el ciclo siguiente. Si interfere = 1, mientras
    // la trama esta en curso se piden otros bytes (con otro dato) que deben ignorarse.
    task check_frame(input [7:0] data, input interfere);
        reg [FRAME_BITS-1:0] expected_frame;
        integer              cycle_index;
        begin
            expected_frame = {1'b1, data, 1'b0};

            for (cycle_index = 1; cycle_index <= FRAME_CYCLES; cycle_index = cycle_index + 1) begin
                // Pedidos de interferencia: justo tras aceptar, a mitad de trama y en el ultimo ciclo
                if (interfere && (cycle_index == 1 || cycle_index == 1000 || cycle_index == FRAME_CYCLES)) begin
                    byte_data    <= ~data;
                    send_request <= 1'b1;
                end else begin
                    send_request <= 1'b0;
                end

                @(posedge clk);
                check(tx_pin === expected_frame[(cycle_index - 1) / BIT_PERIOD_CYCLES],
                      "la linea no coincide con la trama esperada");
                check(busy === 1'b1, "busy debe valer 1 durante toda la trama");
            end

            send_request <= 1'b0;
            @(posedge clk);
            check(busy   === 1'b0, "busy debe bajar justo al terminar el bit de stop");
            check(tx_pin === 1'b1, "la linea debe quedar en reposo (1) al terminar");
        end
    endtask

    task check_line_stays_idle(input integer cycles);
        integer cycle_index;
        begin
            for (cycle_index = 0; cycle_index < cycles; cycle_index = cycle_index + 1) begin
                @(posedge clk);
                check(tx_pin === 1'b1 && busy === 1'b0, "la linea debe seguir en reposo sin pedidos");
            end
        end
    endtask

    task send_and_check(input [7:0] data);
        begin
            request_byte(data);
            check_frame(data, 1'b0);
        end
    endtask

    // -------------------------------------------------------------------------
    // Pruebas
    // -------------------------------------------------------------------------
    integer test_index;

    initial begin
        $display("tb_uart_tx: inicio");

        // ---- Estado tras el reset ------------------------------------------
        apply_reset;
        check_line_stays_idle(100);

        // ---- Bytes representativos: patrones alternados, extremos y un solo bit ----
        send_and_check(8'h55);
        send_and_check(8'hAA);
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'hA5);
        send_and_check(8'h01);    // solo el bit menos significativo: sale primero
        send_and_check(8'h80);    // solo el bit mas significativo: sale ultimo
        check_line_stays_idle(50);

        // ---- Pedidos con el transmisor ocupado: se ignoran, la trama no se altera ----
        request_byte(8'h3C);
        check_frame(8'h3C, 1'b1);
        check_line_stays_idle(3 * BIT_PERIOD_CYCLES);       // no debe salir ninguna trama extra

        // ---- Reset en medio de una trama: la linea vuelve a reposo y el envio siguiente es correcto ----
        request_byte(8'h00);                                // linea en 0 durante casi toda la trama
        repeat (700) @(posedge clk);
        check(tx_pin === 1'b0, "antes del reset la linea debe estar en 0");
        reset <= 1'b1;
        @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        check(tx_pin === 1'b1 && busy === 1'b0, "el reset debe devolver la linea a reposo");
        check_line_stays_idle(100);
        send_and_check(8'hC3);

        // ---- Varios bytes seguidos -----------------------------------------
        for (test_index = 0; test_index < 8; test_index = test_index + 1)
            send_and_check(8'h10 + test_index * 8'h1F);

        if (error_count == 0)
            $display("tb_uart_tx: PASS (%0d comparaciones)", check_count);
        else
            $display("tb_uart_tx: FAIL (%0d errores en %0d comparaciones)", error_count, check_count);

        $finish;
    end

    // Evita que una falla deje la simulacion colgada
    initial begin
        #(CLK_PERIOD_NS * 500_000);
        $display("tb_uart_tx: TIMEOUT");
        $finish;
    end

endmodule
