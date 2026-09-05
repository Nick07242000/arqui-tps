`timescale 1ns/1ps

module register_tb;

    // Parametros del testbench
    parameter WIDTH      = 8;
    parameter CLK_PERIOD = 10;
    parameter NUM_TESTS  = 100;

    // Valores usados como vectores de test
    localparam [WIDTH-1:0] ALL_ONES  = {WIDTH{1'b1}};   // 0xFF...
    localparam [WIDTH-1:0] ALL_ZEROS = 0;               // 0x00
    localparam [WIDTH-1:0] MSB_ONE   = 1 << (WIDTH-1);  // 0x80... (bit mas significativo en alto)

    // Senales de conexion con el DUT
    reg              clk;
    reg              rst;
    reg              en;
    reg  [WIDTH-1:0] d;
    wire [WIDTH-1:0] q;

    register #(
        .WIDTH(WIDTH)
    ) dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .d   (d),
        .q   (q)
    );

    // Reloj
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Modelo de referencia
    function [WIDTH-1:0] register_ref;

        input             in_rst;
        input             in_en;
        input [WIDTH-1:0] in_d;
        input [WIDTH-1:0] in_prev;

        begin
            if (in_rst)
                register_ref = ALL_ZEROS;
            else if (in_en)
                register_ref = in_d;
            else
                register_ref = in_prev; // sin reset ni enable: se sostiene el valor
        end
    endfunction

    // Estado actual del modelo de referencia
    reg [WIDTH-1:0] expected = ALL_ZEROS;

    // Variables de control
    integer errors;
    integer total;
    integer i;
    integer rnd_d;
    integer rnd_ctrl;

    // Aplica un estimulo, espera un flanco de clock y compara
    task apply_and_check;

        input             t_rst;
        input             t_en;
        input [WIDTH-1:0] t_d;

        begin

            @(negedge clk);
            rst = t_rst;
            en  = t_en;
            d   = t_d;

            expected = register_ref(t_rst, t_en, t_d, expected);

            @(posedge clk);
            #1; // estabiliza

            total = total + 1;

            if (q !== expected) begin
                errors = errors + 1;
                $display(
                    "FALLO: rst=%b en=%b d=%h -> q=%h (esperado %h)",
                    t_rst, t_en, t_d, q, expected
                );
            end
        end
    endtask

    // Inicio de la simulacion
    initial begin

        rst = 1'b1;
        en  = 1'b0;
        d   = ALL_ZEROS;

        errors = 0;
        total  = 0;

        $dumpfile("register_tb.vcd");
        $dumpvars(0, register_tb);

        $display("Testbench register (WIDTH=%0d)", WIDTH);

        // 1. CASOS DIRIGIDOS

        // Reset inicial: q debe quedar en 0
        apply_and_check(1'b1, 1'b0, ALL_ONES);

        // rst=0, en=0: debe sostener el valor actual aunque d cambie
        apply_and_check(1'b0, 1'b0, ALL_ONES);

        // en=1: debe cargar el dato presente en d
        apply_and_check(1'b0, 1'b1, ALL_ONES);

        // en=0 nuevamente: debe sostener el valor cargado antes
        apply_and_check(1'b0, 1'b0, ALL_ZEROS);

        // Cargar un patron distinto (bit mas significativo en alto)
        apply_and_check(1'b0, 1'b1, MSB_ONE);

        // en=0: debe sostener ese ultimo valor (todo unos salvo el LSB)
        apply_and_check(1'b0, 1'b0, ALL_ONES - 1'b1);

        // Reset con enable activo al mismo tiempo: el reset tiene prioridad
        apply_and_check(1'b1, 1'b1, ALL_ONES);

        // 2. PRUEBAS ALEATORIAS

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            rnd_d    = $random;
            rnd_ctrl = $random;
            apply_and_check(rnd_ctrl[1], rnd_ctrl[0], rnd_d[WIDTH-1:0]);
        end

        // RESULTADO

        if (errors == 0) begin
            $display("Resultado: 0 fallos de %0d pruebas", total);
        end
        else begin
            $display("Resultado: %0d fallos de %0d pruebas", errors, total);
        end

        $finish;

    end
endmodule