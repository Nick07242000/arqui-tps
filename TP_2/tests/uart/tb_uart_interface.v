`timescale 1ns / 1ps

module tb_uart_interface;
    reg        clk = 0;
    reg        reset = 0;
    wire       tx_to_rx;
    reg        rd_uart = 0;
    reg        wr_uart = 0;
    reg  [7:0] write_data = 0;
    wire       rx_empty;
    wire       tx_busy;
    wire [7:0] read_data;

    // Instancia con baudrate acelerado para simulación
    uart_interface #(
        .CLK_FREQ(27_000_000),
        .BAUD_RATE(1_000_000)
    ) uut (
        .i_clk(clk), .i_reset(reset),
        .i_rx(tx_to_rx), // Conexión Loopback[cite: 7, 8, 9]
        .i_rd_uart(rd_uart), .i_wr_uart(wr_uart),
        .i_write_data(write_data),
        .o_tx(tx_to_rx),
        .o_rx_empty(rx_empty), .o_tx_busy(tx_busy),
        .o_read_data(read_data)
    );

    always #18.5 clk = ~clk; // ~27 MHz

    integer i;
    reg [7:0] test_val;

    initial begin
        reset = 1; #100; reset = 0; #100;

        // Prueba aleatoria mediante Loopback
        for (i = 0; i < 5; i = i + 1) begin
            test_val = $random;
            write_data = test_val;
            wr_uart = 1; #37; wr_uart = 0;

            // Esperar a recibir el dato
            wait(!rx_empty);
            if (read_data !== test_val) 
                $error("[FAIL] Error Loopback. Enviado: 0x%h, Recibido: 0x%h", test_val, read_data);

            // Leer dato para limpiar buffer[cite: 7]
            rd_uart = 1; #37; rd_uart = 0; #100;
        end

        $display("=== [UART INTERFACE] Pruebas Finalizadas ===");
        $finish;
    end
endmodule