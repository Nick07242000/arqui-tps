`timescale 1ns/1ps

module top_tb;

    // ------------------------------------------------------------------
    // Plan de pruebas:
    //   1. Dirigidos  - cableado hacia los registros y la ALU (enables,
    //                   reset, y su orden de prioridad)
    //   2. Aleatorio  - cobertura amplia con vectores random en sw/btn
    // ------------------------------------------------------------------

    // Parametros
    parameter DATA_WIDTH = 8;
    parameter OP_WIDTH   = 6;
    parameter NUM_TESTS  = 200;
    parameter CLK_PERIOD = 10;

    // Valores usados como vectores de test
    localparam [DATA_WIDTH-1:0] ALL_ONES  = {DATA_WIDTH{1'b1}};
    localparam [DATA_WIDTH-1:0] ALL_ZEROS = 0;

    // Patrones de boton
    localparam [3:0] BTN_NONE   = 4'b1111; // ningun boton presionado
    localparam [3:0] BTN_EN_A   = 4'b1110; // solo reg_a habilitado
    localparam [3:0] BTN_EN_B   = 4'b1101; // solo reg_b habilitado
    localparam [3:0] BTN_EN_OP  = 4'b1011; // solo reg_op habilitado
    localparam [3:0] BTN_EN_ALL = 4'b1000; // los tres registros habilitados
    localparam [3:0] BTN_RST    = 4'b0111; // reset global

    // Senales de conexion con el DUT
    reg                   clk;
    reg  [DATA_WIDTH-1:0] sw;
    reg  [3:0]            btn;
    wire [DATA_WIDTH-1:0] led;
    wire [3:0]            led_aux;

    top #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH  (OP_WIDTH)
    ) dut (
        .clk     (clk),
        .sw      (sw),
        .btn     (btn),
        .led     (led),
        .led_aux (led_aux)
    );

    // Reloj
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Modelo de referencia
    wire [DATA_WIDTH-1:0] ref_sw_active_high = ~sw;

    wire ref_en_a  = ~btn[0];
    wire ref_en_b  = ~btn[1];
    wire ref_en_op = ~btn[2];
    wire ref_rst   = ~btn[3];

    wire [DATA_WIDTH-1:0] ref_val_a;
    wire [DATA_WIDTH-1:0] ref_val_b;
    wire [OP_WIDTH-1:0]   ref_val_op;

    register #(
        .WIDTH(DATA_WIDTH)
    ) ref_reg_a (
        .clk (clk),
        .rst (ref_rst),
        .en  (ref_en_a),
        .d   (ref_sw_active_high),
        .q   (ref_val_a)
    );

    register #(
        .WIDTH(DATA_WIDTH)
    ) ref_reg_b (
        .clk (clk),
        .rst (ref_rst),
        .en  (ref_en_b),
        .d   (ref_sw_active_high),
        .q   (ref_val_b)
    );

    register #(
        .WIDTH(OP_WIDTH)
    ) ref_reg_op (
        .clk (clk),
        .rst (ref_rst),
        .en  (ref_en_op),
        .d   (ref_sw_active_high[OP_WIDTH-1:0]),
        .q   (ref_val_op)
    );

    wire [DATA_WIDTH-1:0] ref_alu_result;
    wire                  ref_alu_zero;
    wire                  ref_alu_carry;
    wire                  ref_alu_overflow;

    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) ref_alu (
        .a        (ref_val_a),
        .b        (ref_val_b),
        .alu_op   (ref_val_op),
        .result   (ref_alu_result),
        .zero     (ref_alu_zero),
        .carry    (ref_alu_carry),
        .overflow (ref_alu_overflow)
    );

    wire [DATA_WIDTH-1:0] ref_led     = ref_alu_result;
    wire [3:0]            ref_led_aux = {1'b0, ref_alu_overflow, ref_alu_zero, ref_alu_carry};

    // Variables de control
    integer errors;
    integer total;
    integer i;
    integer rnd_sw;
    integer rnd_btn;

    // Aplica un estimulo, espera un flanco de clock y compara
    task apply_and_check;

        input [DATA_WIDTH-1:0] t_sw;
        input [3:0]            t_btn;

        begin

            @(negedge clk);
            sw  = t_sw;
            btn = t_btn;

            @(posedge clk);
            #1; // estabiliza

            total = total + 1;

            if ((led !== ref_led) || (led_aux !== ref_led_aux)) begin
                errors = errors + 1;
                $display(
                    "FALLO: sw=%h btn=%b -> led=%h (esperado %h) led_aux=%b (esperado %b)",
                    t_sw, t_btn, led, ref_led, led_aux, ref_led_aux
                );
            end
        end
    endtask

    // Inicio de la simulacion
    initial begin

        sw     = ALL_ZEROS;
        btn    = BTN_NONE;
        errors = 0;
        total  = 0;

        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);

        $display("Testbench top (DATA_WIDTH=%0d, OP_WIDTH=%0d)", DATA_WIDTH, OP_WIDTH);

        // 1. CASOS DIRIGIDOS: cableado hacia los registros y la ALU

        // Ningun boton presionado: nada deberia cambiar
        apply_and_check(ALL_ONES,  BTN_NONE);
        apply_and_check(ALL_ZEROS, BTN_NONE);

        // Cargar solo reg_a
        apply_and_check(8'hA5, BTN_EN_A);

        // Cargar solo reg_b
        apply_and_check(8'h3C, BTN_EN_B);

        // Cargar solo reg_op (OP_ADD = 6'b100000)
        apply_and_check(8'h20, BTN_EN_OP);

        // Cargar los tres registros a la vez
        apply_and_check(8'h0F, BTN_EN_ALL);

        // Reset global: debe limpiar
        apply_and_check(ALL_ONES, BTN_RST);

        // 2. PRUEBAS ALEATORIAS
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            rnd_sw  = $random;
            rnd_btn = $random;
            apply_and_check(rnd_sw[DATA_WIDTH-1:0], rnd_btn[3:0]);
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