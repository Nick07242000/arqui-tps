`timescale 1ns/1ps

module tb_datapath;

    localparam DATA_WIDTH = 8;
    localparam OP_WIDTH   = 6;

    // Opcodes de la ALU usados en las pruebas
    localparam OP_ADD = 6'b100000;
    localparam OP_SUB = 6'b100010;

    reg clk;
    reg reset;

    reg [DATA_WIDTH-1:0] switch_data;
    reg enable_a_manual, enable_b_manual, enable_op_manual;

    reg [DATA_WIDTH-1:0] uart_data;
    reg enable_a, enable_b, enable_op;

    wire [DATA_WIDTH-1:0] a, b;
    wire [OP_WIDTH-1:0]   op;
    wire [DATA_WIDTH-1:0] result;
    wire zero, carry, overflow;

    integer errors = 0;

    datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH(OP_WIDTH)
    ) dut (
        .i_clk               (clk),
        .i_reset             (reset),
        .i_switch_data       (switch_data),
        .i_enable_a_manual   (enable_a_manual),
        .i_enable_b_manual   (enable_b_manual),
        .i_enable_op_manual  (enable_op_manual),
        .i_uart_data         (uart_data),
        .i_enable_a          (enable_a),
        .i_enable_b          (enable_b),
        .i_enable_op         (enable_op),
        .o_a                 (a),
        .o_b                 (b),
        .o_op                (op),
        .o_result            (result),
        .o_zero              (zero),
        .o_carry             (carry),
        .o_overflow          (overflow)
    );

    always #5 clk = ~clk;

    // Compara un valor obtenido contra el esperado e informa el resultado.
    task check(input [8*48:1] name, input integer got, input integer expected);
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FALLO: %0s (obtenido=%0d esperado=%0d)", name, got, expected);
            end else begin
                $display("OK:    %0s", name);
            end
        end
    endtask

    // Carga un registro en modo manual (which: 0=A, 1=B, 2=OP).
    task load_manual(input integer which, input [DATA_WIDTH-1:0] value);
        begin
            switch_data      = value;
            enable_a_manual  = (which == 0);
            enable_b_manual  = (which == 1);
            enable_op_manual = (which == 2);
            @(posedge clk);
            #1;
            enable_a_manual  = 0;
            enable_b_manual  = 0;
            enable_op_manual = 0;
        end
    endtask

    // Carga un registro como lo haria el controlador via UART (which: 0=A, 1=B, 2=OP).
    task load_uart(input integer which, input [DATA_WIDTH-1:0] value);
        begin
            uart_data = value;
            enable_a  = (which == 0);
            enable_b  = (which == 1);
            enable_op = (which == 2);
            @(posedge clk);
            #1;
            enable_a  = 0;
            enable_b  = 0;
            enable_op = 0;
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        switch_data = 0; enable_a_manual = 0; enable_b_manual = 0; enable_op_manual = 0;
        uart_data   = 0; enable_a = 0; enable_b = 0; enable_op = 0;

        // --- Reset ---
        repeat (2) @(posedge clk);
        #1;
        check("reset limpia A",   a,   0);
        check("reset limpia B",   b,   0);
        check("reset limpia OP",  op,  0);
        reset = 0;

        // --- Carga manual, cada registro independiente del resto ---
        load_manual(0, 8'd10);
        check("carga manual de A",        a, 10);
        check("B no se altera al cargar A", b, 0);

        load_manual(1, 8'd4);
        check("carga manual de B", b, 4);

        // Los 2 bits altos de switch_data no deben llegar al registro OP.
        load_manual(2, {2'b11, OP_ADD});
        check("carga manual de OP (truncada a OP_WIDTH)", op, OP_ADD);

        // --- Sin ningun enable activo no debe cambiar nada ---
        switch_data = 8'hFF;
        uart_data   = 8'hFF;
        repeat (3) @(posedge clk);
        #1;
        check("sin enable: A se mantiene",  a,  10);
        check("sin enable: B se mantiene",  b,  4);
        check("sin enable: OP se mantiene", op, OP_ADD);

        // --- La ALU debe reflejar combinacionalmente lo cargado ---
        check("ALU: resultado de A+B", result, 14);
        check("ALU: zero en 0",        zero,   0);
        check("ALU: carry en 0",       carry,  0);
        check("ALU: overflow en 0",    overflow, 0);

        // --- Carga via UART/controlador ---
        load_uart(0, 8'd200);
        load_uart(1, 8'd100);
        load_uart(2, OP_ADD);
        #1;
        check("carga UART de A", a, 200);
        check("carga UART de B", b, 100);
        // 200 + 100 = 300, desborda 8 bits: resultado = 300 - 256 = 44, con acarreo.
        check("ALU: resultado con acarreo", result, 44);
        check("ALU: carry activado",        carry,  1);

        // --- Overflow con signo: dos positivos que dan un resultado negativo ---
        load_uart(0, 8'd100);
        load_uart(1, 8'd100);
        load_uart(2, OP_ADD);
        #1;
        check("ALU: overflow con signo activado", overflow, 1);
        check("ALU: sin acarreo en este caso",     carry,    0);

        // --- Flag zero ---
        load_uart(0, 8'd5);
        load_uart(1, 8'd5);
        load_uart(2, OP_SUB);
        #1;
        check("ALU: resultado de A-A", result, 0);
        check("ALU: flag zero activado", zero, 1);

        // --- Prioridad: si manual y UART piden cargar A a la vez, gana manual ---
        switch_data     = 8'hAA;
        uart_data       = 8'h55;
        enable_a_manual = 1;
        enable_a        = 1;
        @(posedge clk);
        #1;
        enable_a_manual = 0;
        enable_a        = 0;
        check("prioridad: manual gana sobre UART", a, 8'hAA);

        if (errors == 0)
            $display("\nDATAPATH: TODOS LOS TESTS PASARON");
        else
            $display("\nDATAPATH: %0d TEST(S) FALLARON", errors);

        $finish;
    end

endmodule