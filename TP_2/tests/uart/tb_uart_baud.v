`timescale 1ns / 1ps

module tb_baud_rate_generator;
    reg  clk = 0;
    reg  reset = 0;
    wire tick;

    // Configuración reducida: TICK_COUNT = 100 / (10 * 2) = 5 ciclos
    baud_rate_generator #(
        .CLK_FREQ(100),
        .BAUD_RATE(10),
        .OVERSAMPLE_RATE(2)
    ) uut (
        .i_clk(clk),
        .i_reset(reset),
        .o_tick(tick)
    );

    always #5 clk = ~clk; // Periodo de 10ns

    integer tick_count_val = 0;

    initial begin
        reset = 1; #20; reset = 0;

        // Contar 3 pulsos para validar la periodicidad
        while (tick_count_val < 3) begin
            @(posedge clk);
            if (tick) tick_count_val = tick_count_val + 1;
        end

        $display("=== [BAUD RATE GENERATOR] Pruebas Finalizadas ===");
        $finish;
    end
endmodule