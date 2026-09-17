`timescale 1ns / 1ps

module tb_uart_rx;
    parameter DATA_BITS = 8;
    parameter OVERSAMPLE_RATE = 16;

    reg                  clk = 0;
    reg                  reset = 0;
    reg                  rx = 1;
    reg                  baud_tick = 0;
    wire                 rx_done;
    wire [DATA_BITS-1:0] data_out;

    uart_rx #(
        .DATA_BITS(DATA_BITS),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE)
    ) uut (
        .i_clk(clk),
        .i_reset(reset),
        .i_rx(rx),
        .i_baud_tick(baud_tick),
        .o_rx_done(rx_done),
        .o_data_out(data_out)
    );

    always #5 clk = ~clk;
    always #10 baud_tick = ~baud_tick; // Baud rate simulado acelerado

    // Tarea para inyectar un byte serie
    task inject_rx_byte(input [7:0] byte_to_send);
        integer i, k;
        begin
            // Start bit (0)
            rx = 0;
            for (k = 0; k < OVERSAMPLE_RATE; k = k + 1) @(posedge baud_tick);

            // Data bits (LSB primero)
            for (i = 0; i < 8; i = i + 1) begin
                rx = byte_to_send[i];
                for (k = 0; k < OVERSAMPLE_RATE; k = k + 1) @(posedge baud_tick);
            end

            // Stop bit (1)
            rx = 1;
            for (k = 0; k < OVERSAMPLE_RATE; k = k + 1) @(posedge baud_tick);
        end
    endtask

    initial begin
        reset = 1; #50; reset = 0; #50;

        // Enviar byte de prueba 0x3C
        inject_rx_byte(8'h3C);

        wait(rx_done);
        if (data_out !== 8'h3C) 
            $error("[FAIL] Error en recepcion RX. Esperado: 0x3C, Obtenido: 0x%h", data_out);

        $display("=== [UART RX] Pruebas Finalizadas ===");
        $finish;
    end
endmodule