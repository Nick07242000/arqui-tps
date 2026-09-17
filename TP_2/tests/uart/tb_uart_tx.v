`timescale 1ns / 1ps

module tb_uart_tx;
    parameter DATA_BITS = 8;
    parameter OVERSAMPLE_RATE = 16;

    reg                   clk = 0;
    reg                   reset = 0;
    reg                   tx_start = 0;
    reg                   baud_tick = 0;
    reg  [DATA_BITS-1:0]  data_in = 0;
    wire                  tx_done;
    wire                  tx;

    uart_tx #(
        .DATA_BITS(DATA_BITS),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE)
    ) uut (
        .i_clk(clk),
        .i_reset(reset),
        .i_tx_start(tx_start),
        .i_baud_tick(baud_tick),
        .i_data_in(data_in),
        .o_tx_done(tx_done),
        .o_tx(tx)
    );

    always #5 clk = ~clk;

    // Generador manual de baud_tick
    always #20 baud_tick = ~baud_tick;

    initial begin
        reset = 1; #50; reset = 0; #50;

        // Iniciar transmisión de 0xA5 (10100101b)
        data_in = 8'hA5;
        tx_start = 1; #10; tx_start = 0;

        // Esperar la bandera de transmisión finalizada
        wait(tx_done);
        #50;

        $display("=== [UART TX] Pruebas Finalizadas ===");
        $finish;
    end
endmodule