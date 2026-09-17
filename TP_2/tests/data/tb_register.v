`timescale 1ns / 1ps

module tb_register;
    parameter WIDTH = 8;

    reg              clk = 0;
    reg              reset = 0;
    reg              enable = 0;
    reg  [WIDTH-1:0] data_in = 0;
    wire [WIDTH-1:0] data_out;

    register #(.WIDTH(WIDTH)) uut (
        .i_clk(clk),
        .i_reset(reset),
        .i_enable(enable),
        .i_data(data_in),
        .o_data(data_out)
    );

    always #5 clk = ~clk;

    initial begin
        // Reset inicial
        reset = 1; #10; reset = 0; #10;

        // Intentar escribir sin enable (debe mantener 0)
        data_in = 8'hAA; enable = 0; #10;
        if (data_out !== 8'h00) $error("[FAIL] Escribio sin enable");

        // Escritura con enable
        enable = 1; #10;
        if (data_out !== 8'hAA) $error("[FAIL] Error de escritura");

        // Prioridad de Reset sobre Enable[cite: 4]
        reset = 1; #10;
        if (data_out !== 8'h00) $error("[FAIL] Reset no tuvo prioridad");

        $display("=== [REGISTER] Pruebas Finalizadas ===");
        $finish;
    end
endmodule