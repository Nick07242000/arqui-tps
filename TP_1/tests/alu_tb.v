`timescale 1ns/1ps

module alu_tb;

    // ------------------------------------------------------------------
    // Plan de pruebas:
    //   1. Aleatorio        - cobertura amplia con vectores random
    //   2. SRL/SRA          - casos particulares de shift
    //   3. Overflow/trunc.  - comportamiento en los bordes aritmeticos
    //   4. Algebraicas      - identidades (a+0=a, a^a=0, etc.)
    //   5. Conmutatividad   - ALU(a,b) == ALU(b,a) para ops conmutativas
    // ------------------------------------------------------------------

    // Parametros del testbench
    parameter DATA_WIDTH = 8;
    parameter NUM_TESTS  = 200;

    localparam SHIFT_WIDTH = (DATA_WIDTH <= 2) ? 1 : $clog2(DATA_WIDTH);

    localparam OP_ADD = 6'b100000;
    localparam OP_SUB = 6'b100010;
    localparam OP_AND = 6'b100100;
    localparam OP_OR  = 6'b100101;
    localparam OP_XOR = 6'b100110;
    localparam OP_NOR = 6'b100111;
    localparam OP_SRL = 6'b000010;
    localparam OP_SRA = 6'b000011;

    // Valores usados como vectores de test (evitan repetir expresiones
    // de replicacion en cada llamada a check_case).
    localparam [DATA_WIDTH-1:0] ALL_ONES  = {DATA_WIDTH{1'b1}};             // 0xFF... (-1 con signo)
    localparam [DATA_WIDTH-1:0] ALL_ZEROS = {DATA_WIDTH{1'b0}};             // 0x00
    localparam [DATA_WIDTH-1:0] MSB_ONE   = {1'b1, {(DATA_WIDTH-1){1'b0}}}; // 0x80... (MIN_NEG con signo)
    localparam [DATA_WIDTH-1:0] LSB_ONE   = {{(DATA_WIDTH-1){1'b0}}, 1'b1}; // 0x01
    localparam [DATA_WIDTH-1:0] MAX_POS   = {1'b0, {(DATA_WIDTH-1){1'b1}}}; // 0x7F... (max. positivo con signo)

    // Senales de conexion con el DUT
    reg  [DATA_WIDTH-1:0] a;
    reg  [DATA_WIDTH-1:0] b;
    reg  [5:0]            alu_op;

    wire [DATA_WIDTH-1:0] result;
    wire                  zero;
    wire                  carry;
    wire                  overflow;

    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .a        (a),
        .b        (b),
        .alu_op   (alu_op),
        .result   (result),
        .zero     (zero),
        .carry    (carry),
        .overflow (overflow)
    );

    // Modelo de referencia
    function [DATA_WIDTH-1:0] alu_ref;

        input [DATA_WIDTH-1:0] in_a;
        input [DATA_WIDTH-1:0] in_b;
        input [5:0]            op;

        begin
            case (op)
                OP_ADD: alu_ref = in_a + in_b;
                OP_SUB: alu_ref = in_a - in_b;
                OP_AND: alu_ref = in_a & in_b;
                OP_OR: alu_ref = in_a | in_b;
                OP_XOR: alu_ref = in_a ^ in_b;
                OP_NOR: alu_ref = ~(in_a | in_b);
                OP_SRL: alu_ref = in_a >> in_b[SHIFT_WIDTH-1:0];
                OP_SRA: alu_ref = $signed(in_a) >>> in_b[SHIFT_WIDTH-1:0];
                default: alu_ref = {DATA_WIDTH{1'b0}};
            endcase
        end
    endfunction

    // Modelo de referencia de las banderas carry/overflow.
    function [1:0] alu_ref_flags;

        input [DATA_WIDTH-1:0] in_a;
        input [DATA_WIDTH-1:0] in_b;
        input [5:0]            op;

        reg [DATA_WIDTH:0] ext;
        reg                c;
        reg                v;

        begin
            c = 1'b0;
            v = 1'b0;

            case (op)
                OP_ADD: begin
                    ext = in_a + in_b;
                    c   = ext[DATA_WIDTH];
                    v   = (in_a[DATA_WIDTH-1] == in_b[DATA_WIDTH-1]) &&
                          (ext[DATA_WIDTH-1] != in_a[DATA_WIDTH-1]);
                end

                OP_SUB: begin
                    c   = (in_a < in_b); // hubo "prestamo" (borrow)
                    ext = in_a - in_b;
                    v   = (in_a[DATA_WIDTH-1] != in_b[DATA_WIDTH-1]) &&
                          (ext[DATA_WIDTH-1] != in_a[DATA_WIDTH-1]);
                end

                default: ; // sin carry/overflow definido para el resto
            endcase

            alu_ref_flags = {v, c};
        end
    endfunction

    // Tabla de operaciones validas para los tests aleatorios
    reg [5:0] valid_ops [0:7];

    // Tabla de operaciones a verificar en el test de conmutatividad
    reg [5:0] comm_ops [0:3];

    // Variables de simulacion
    integer errors;
    integer total;
    integer i;
    integer rnd;

    reg [DATA_WIDTH-1:0] ra, rb; // operandos para el test aleatorio
    reg [5:0]            rop;   // operacion para el test aleatorio

    // Compara contra el resultado esperado
    task check_case;

        input [DATA_WIDTH-1:0] t_a;
        input [DATA_WIDTH-1:0] t_b;
        input [DATA_WIDTH-1:0] t_expected;
        input [5:0]            t_op;

        reg [1:0] t_flags;
        reg       t_zero, t_carry, t_overflow;

        begin
            a      = t_a;
            b      = t_b;
            alu_op = t_op;

            #10; // estabilizar

            total = total + 1;
            t_flags    = alu_ref_flags(t_a, t_b, t_op);
            t_zero     = (t_expected == {DATA_WIDTH{1'b0}});
            t_carry    = t_flags[0];
            t_overflow = t_flags[1];

            if ((result   !== t_expected) ||
                (zero     !== t_zero)     ||
                (carry    !== t_carry)    ||
                (overflow !== t_overflow)) begin

                errors = errors + 1;
                $display(
                    "FALLO (caso #%0d): a=%h b=%h op=%b -> result=%h zero=%b carry=%b overflow=%b (esperado result=%h zero=%b carry=%b overflow=%b)",
                    total, a, b, t_op, result, zero, carry, overflow, t_expected, t_zero, t_carry, t_overflow
                );
            end
        end
    endtask

    // Test de conmutatividad ALU(a,b) == ALU(b,a)

    task check_commutative;

        input [DATA_WIDTH-1:0] t_a;
        input [DATA_WIDTH-1:0] t_b;
        input [5:0]            t_op;

        reg [DATA_WIDTH-1:0] r1;
        reg [DATA_WIDTH-1:0] r2;

        begin
            a      = t_a;
            b      = t_b;
            alu_op = t_op;

            #10; // estabilizar

            r1 = result;

            a = t_b;
            b = t_a;

            #10; // estabilizar

            r2 = result;
            total = total + 1;

            if (r1 !== r2) begin
                errors = errors + 1;
                $display(
                    "FALLO conmutatividad: a=%h b=%h op=%b -> alu(a,b)=%h alu(b,a)=%h",
                    t_a, t_b, t_op, r1, r2
                );
            end
        end
    endtask

    // Inicio de la simulacion
    initial begin

        // Cargar operaciones validas para el test aleatorio
        valid_ops[0] = OP_ADD;
        valid_ops[1] = OP_SUB;
        valid_ops[2] = OP_AND;
        valid_ops[3] = OP_OR;
        valid_ops[4] = OP_XOR;
        valid_ops[5] = OP_NOR;
        valid_ops[6] = OP_SRL;
        valid_ops[7] = OP_SRA;

        // Cargar operaciones a verificar en el test de conmutatividad
        comm_ops[0] = OP_ADD;
        comm_ops[1] = OP_AND;
        comm_ops[2] = OP_OR;
        comm_ops[3] = OP_XOR;

        errors = 0;
        total  = 0;

        // Dump de formas de onda
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, alu_tb);

        $display(
            "Testbench ALU (DATA_WIDTH=%0d) - %0d pruebas aleatorias",
            DATA_WIDTH, NUM_TESTS
        );

        // 1. TESTS ALEATORIOS

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            rnd = $random; ra  = rnd[DATA_WIDTH-1:0];
            rnd = $random; rb  = rnd[DATA_WIDTH-1:0];
            rnd = $random; rop = valid_ops[rnd[2:0]];

            check_case(ra, rb, alu_ref(ra, rb, rop), rop);
        end

        // 2. TESTS ESPECIFICOS DE SRL / SRA

        // Shift de 0: el resultado debe ser igual a A.
        check_case(ALL_ONES, ALL_ZEROS, ALL_ONES, OP_SRL);
        check_case(ALL_ONES, ALL_ZEROS, ALL_ONES, OP_SRA);

        // SRL: el bit de signo no se propaga. SRA: el bit de signo si se propaga.
        check_case(MSB_ONE, LSB_ONE, {2'b01, {(DATA_WIDTH-2){1'b0}}}, OP_SRL);
        check_case(MSB_ONE, LSB_ONE, {2'b11, {(DATA_WIDTH-2){1'b0}}}, OP_SRA);

        // Shift maximo permitido.
        check_case(ALL_ONES, DATA_WIDTH-1, LSB_ONE, OP_SRL);

        // 3. OVERFLOW / TRUNCAMIENTO

        // MAX + 1 -> 0 (se descarta el carry).
        check_case(ALL_ONES, LSB_ONE, ALL_ZEROS, OP_ADD);

        // 0 - 1 -> MAX (aritmetica modular de DATA_WIDTH bits).
        check_case(ALL_ZEROS, LSB_ONE, ALL_ONES, OP_SUB);

        // Overflow con signo en ADD: MAX_POS + 1 -> se pasa a negativo.
        check_case(MAX_POS, LSB_ONE, MSB_ONE, OP_ADD);

        // Overflow con signo en SUB: MIN_NEG - 1 -> se pasa a positivo.
        check_case(MSB_ONE, LSB_ONE, MAX_POS, OP_SUB);

        // 4. PROPIEDADES ALGEBRAICAS

        check_case(ALL_ONES, ALL_ZEROS, ALL_ONES,  OP_ADD); // a + 0 = a
        check_case(ALL_ONES, ALL_ZEROS, ALL_ONES,  OP_OR);  // a | 0 = a
        check_case(ALL_ONES, ALL_ZEROS, ALL_ONES,  OP_XOR); // a ^ 0 = a
        check_case(ALL_ONES, ALL_ZEROS, ALL_ZEROS, OP_AND); // a & 0 = 0
        check_case(ALL_ONES, ALL_ONES,  ALL_ZEROS, OP_XOR); // a ^ a = 0
        check_case(ALL_ONES, ALL_ONES,  ALL_ZEROS, OP_SUB); // a - a = 0
        check_case(ALL_ONES, ALL_ONES,  ALL_ONES,  OP_AND); // a & a = a
        check_case(ALL_ONES, ALL_ONES,  ALL_ONES,  OP_OR);  // a | a = a

        // 5. CONMUTATIVIDAD

        for (i = 0; i < 4; i = i + 1) begin
            check_commutative(ALL_ONES, ALL_ZEROS, comm_ops[i]);
        end

        // RESULTADO

        if (errors == 0) begin
            $display(
                "Resultado: 0 fallos de %0d pruebas",
                total
            );
        end
        else begin
            $display(
                "Resultado: %0d fallos de %0d pruebas",
                errors, total
            );
        end

        $finish;

    end
endmodule