`timescale 1ns/1ps

module tb_registers;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 5;
    localparam REG_COUNT  = 32;

    // -------------------------------------------------------------------------
    // Senales del DUT
    // -------------------------------------------------------------------------
    reg                    clk = 0;
    reg                    reset;
    reg                    cpu_en;
    reg  [ADDR_WIDTH-1:0]  read_addr_a;
    reg  [ADDR_WIDTH-1:0]  read_addr_b;
    wire [DATA_WIDTH-1:0]  read_data_a;
    wire [DATA_WIDTH-1:0]  read_data_b;
    reg                    write_enable;
    reg  [ADDR_WIDTH-1:0]  write_addr;
    reg  [DATA_WIDTH-1:0]  write_data;
    reg  [ADDR_WIDTH-1:0]  debug_read_addr;
    wire [DATA_WIDTH-1:0]  debug_read_data;

    registers #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .REG_COUNT (REG_COUNT),
        .BYPASS_ENABLE(0)
    ) dut (
        .i_clk             (clk),
        .i_reset           (reset),
        .i_cpu_en          (cpu_en),
        .i_read_addr_a     (read_addr_a),
        .i_read_addr_b     (read_addr_b),
        .o_read_data_a     (read_data_a),
        .o_read_data_b     (read_data_b),
        .i_write_enable    (write_enable),
        .i_write_addr      (write_addr),
        .i_write_data      (write_data),
        .i_debug_read_addr (debug_read_addr),
        .o_debug_read_data (debug_read_data)
    );

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Utilidades
    // -------------------------------------------------------------------------
    integer error_count = 0;
    integer test_count  = 0;
    integer idx;

    task check(input [DATA_WIDTH-1:0] observed,
               input [DATA_WIDTH-1:0] expected,
               input [255:0]          description);
        begin
            test_count = test_count + 1;
            if (observed !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %0s | esperado=0x%08h observado=0x%08h",
                         description, expected, observed);
            end
        end
    endtask

    // Valor distinto y reproducible para cada registro
    function [DATA_WIDTH-1:0] pattern_for(input integer reg_number);
        pattern_for = 32'hA5A50000 + (reg_number * 32'h0101);
    endfunction

    // Un ciclo de escritura completo (aplica en bajada, se captura en subida)
    task write_register(input [ADDR_WIDTH-1:0] addr,
                        input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            write_enable = 1;
            write_addr   = addr;
            write_data   = data;
            @(negedge clk);
            write_enable = 0;
        end
    endtask

    task apply_reset;
        begin
            @(negedge clk);
            reset = 1;
            @(negedge clk);
            reset = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia de pruebas
    // -------------------------------------------------------------------------
    initial begin
        reset           = 0;
        cpu_en          = 1;
        read_addr_a     = 0;
        read_addr_b     = 0;
        write_enable    = 0;
        write_addr      = 0;
        write_data      = 0;
        debug_read_addr = 0;

        // --- Prueba 1: reset deja todos los registros en cero ---------------
        apply_reset;
        for (idx = 0; idx < REG_COUNT; idx = idx + 1) begin
            read_addr_a = idx;
            #1 check(read_data_a, 32'h0, "reset: registro en cero");
        end

        // --- Prueba 2: escribir y leer los 31 registros modificables --------
        for (idx = 1; idx < REG_COUNT; idx = idx + 1)
            write_register(idx, pattern_for(idx));

        for (idx = 1; idx < REG_COUNT; idx = idx + 1) begin
            read_addr_a = idx;
            #1 check(read_data_a, pattern_for(idx), "lectura puerto A tras escritura");
        end

        // --- Prueba 3: dos lecturas simultaneas e independientes ------------
        read_addr_a = 5'd3;
        read_addr_b = 5'd17;
        #1;
        check(read_data_a, pattern_for(3),  "lectura simultanea puerto A");
        check(read_data_b, pattern_for(17), "lectura simultanea puerto B");

        // --- Prueba 4: x0 se lee como cero y descarta escrituras ------------
        write_register(5'd0, 32'hDEADBEEF);
        read_addr_a = 5'd0;
        read_addr_b = 5'd0;
        #1;
        check(read_data_a, 32'h0, "x0 puerto A tras escritura");
        check(read_data_b, 32'h0, "x0 puerto B tras escritura");

        // --- Prueba 5: bypass WB->ID (lectura y escritura del mismo registro)
        @(negedge clk);
        read_addr_a  = 5'd9;
        read_addr_b  = 5'd9;
        write_enable = 1;
        write_addr   = 5'd9;
        write_data   = 32'h12345678;
        #1;
        check(read_data_a, 32'h12345678, "bypass puerto A");
        check(read_data_b, 32'h12345678, "bypass puerto B");
        @(negedge clk);
        write_enable = 0;
        #1 check(read_data_a, 32'h12345678, "dato persiste tras el bypass");

        // --- Prueba 6: bypass no aplica a x0 --------------------------------
        @(negedge clk);
        read_addr_a  = 5'd0;
        write_enable = 1;
        write_addr   = 5'd0;
        write_data   = 32'hFFFFFFFF;
        #1 check(read_data_a, 32'h0, "sin bypass sobre x0");
        @(negedge clk);
        write_enable = 0;

        // --- Prueba 7: sin write_enable no se modifica el registro ----------
        @(negedge clk);
        write_addr   = 5'd4;
        write_data   = 32'hBADBAD00;
        write_enable = 0;
        @(negedge clk);
        read_addr_a = 5'd4;
        #1 check(read_data_a, pattern_for(4), "sin write_enable no escribe");

        // --- Prueba 8: sin cpu_en no se escribe ni hay bypass ---------------
        @(negedge clk);
        cpu_en       = 0;
        read_addr_a  = 5'd5;
        write_enable = 1;
        write_addr   = 5'd5;
        write_data   = 32'hCAFEF00D;
        #1 check(read_data_a, pattern_for(5), "sin cpu_en no hay bypass");
        @(negedge clk);
        write_enable = 0;
        cpu_en       = 1;
        #1 check(read_data_a, pattern_for(5), "sin cpu_en no escribe");

        // --- Prueba 9: escrituras consecutivas al mismo registro ------------
        write_register(5'd6, 32'h00000001);
        write_register(5'd6, 32'h00000002);
        write_register(5'd6, 32'h00000003);
        read_addr_a = 5'd6;
        #1 check(read_data_a, 32'h00000003, "ultima escritura prevalece");

        // --- Prueba 10: puerto de debug ve el valor almacenado --------------
        debug_read_addr = 5'd6;
        #1 check(debug_read_data, 32'h00000003, "debug lee registro");
        debug_read_addr = 5'd0;
        #1 check(debug_read_data, 32'h0, "debug lee x0 como cero");

        // --- Prueba 11: debug no usa bypass ---------------------------------
        @(negedge clk);
        debug_read_addr = 5'd7;
        write_enable    = 1;
        write_addr      = 5'd7;
        write_data      = 32'h77777777;
        #1 check(debug_read_data, pattern_for(7), "debug sin bypass");
        @(negedge clk);
        write_enable = 0;

        // --- Prueba 12: reset posterior limpia todo y tiene prioridad -------
        @(negedge clk);
        reset        = 1;
        write_enable = 1;
        write_addr   = 5'd10;
        write_data   = 32'hFFFFFFFF;
        @(negedge clk);
        reset        = 0;
        write_enable = 0;
        for (idx = 0; idx < REG_COUNT; idx = idx + 1) begin
            read_addr_a = idx;
            #1 check(read_data_a, 32'h0, "reset posterior: registro en cero");
        end

        // --- Resumen --------------------------------------------------------
        $display("----------------------------------------------");
        if (error_count == 0)
            $display("PASS: %0d verificaciones, 0 errores", test_count);
        else
            $display("FAIL: %0d errores de %0d verificaciones", error_count, test_count);
        $finish;
    end

endmodule
