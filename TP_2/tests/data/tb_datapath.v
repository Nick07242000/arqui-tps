`timescale 1ns / 1ps

module tb_datapath;
    parameter DATA_WIDTH = 8;
    parameter OP_WIDTH   = 6;

    reg                   clk = 0;
    reg                   reset = 0;
    reg  [DATA_WIDTH-1:0] switch_data = 0;
    reg                   en_a_m = 0, en_b_m = 0, en_op_m = 0;
    reg  [DATA_WIDTH-1:0] uart_data = 0;
    reg                   en_a_u = 0, en_b_u = 0, en_op_u = 0;

    wire [DATA_WIDTH-1:0] o_a, o_b;
    wire [OP_WIDTH-1:0]   o_op;

    datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH(OP_WIDTH)
    ) uut (
        .i_clk(clk), .i_reset(reset),
        .i_switch_data(switch_data),
        .i_enable_a_manual(en_a_m), .i_enable_b_manual(en_b_m), .i_enable_op_manual(en_op_m),
        .i_uart_data(uart_data),
        .i_enable_a(en_a_u), .i_enable_b(en_b_u), .i_enable_op(en_enable_op_u),
        .o_a(o_a), .o_b(o_b), .o_op(o_op)
    );

    always #5 clk = ~clk;

    initial begin
        reset = 1; #10; reset = 0; #10;

        // Carga por UART en Reg A[cite: 3]
        uart_data = 8'h55; en_a_u = 1; #10; en_a_u = 0;
        if (o_a !== 8'h55) $error("[FAIL] Carga UART en Reg A");

        // Prioridad Manual sobre UART en Reg A[cite: 3]
        switch_data = 8'hAA; en_a_m = 1; uart_data = 8'h11; en_a_u = 1; #10;
        en_a_m = 0; en_a_u = 0;
        if (o_a !== 8'hAA) $error("[FAIL] Modo manual no tuvo prioridad");

        $display("=== [DATAPATH] Pruebas Finalizadas ===");
        $finish;
    end
endmodule