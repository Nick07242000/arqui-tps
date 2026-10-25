`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.3 - Programa de referencia
//
// Carga programs/reference_program.hex (ensamblado con build_program.sh),
// lo ejecuta hasta HALT y compara registros, memoria, PC y ciclos con los
// valores calculados a mano (ver programa_referencia.md).
// Ejecutar desde la carpeta raiz del proyecto.
// -----------------------------------------------------------------------------
module tb_reference_program;
`include "tb_common.vh"

    reg [8*64-1:0] program_hex_file = "programs/reference_program.hex";

    localparam [31:0] LOAD_ADDRESS_SUM_1_TO_10   = 32'h0000_0040;
    localparam [31:0] LOAD_ADDRESS_SUM_FIBONACCI = 32'h0000_0044;
    localparam [31:0] ADDRESS_TEST_WORD          = 32'h0000_0048;

    localparam PROGRAM_WORD_COUNT = 54;

    task load_program_from_file;
        begin
            $readmemh(program_hex_file, program_words, 0, PROGRAM_WORD_COUNT - 1);
            program_length = PROGRAM_WORD_COUNT;
        end
    endtask

    integer fibonacci_index;
    reg [31:0] expected_fibonacci [0:9];

    initial begin
        expected_fibonacci[0] = 32'd0;   expected_fibonacci[1] = 32'd1;
        expected_fibonacci[2] = 32'd1;   expected_fibonacci[3] = 32'd2;
        expected_fibonacci[4] = 32'd3;   expected_fibonacci[5] = 32'd5;
        expected_fibonacci[6] = 32'd8;   expected_fibonacci[7] = 32'd13;
        expected_fibonacci[8] = 32'd21;  expected_fibonacci[9] = 32'd34;

        begin_test("programa de referencia: registros, memoria, PC y ciclos");
        load_program_from_file;
        run_program;

        // ---- Resumen de la ejecucion --------------------------------------
        check_pc(32'h0000_00B8);                // direccion de HALT (palabra 46)
        check_run_stats(198, 213);              // 198 instrucciones + 15 ciclos de espera de loads
        check_flags(1'b0, 1'b0, 1'b0);

        // ---- A. Aritmetica y logica -------------------------------------------
        check_register(0,  32'd0);
        check_register(2,  32'd10);
        check_register(3,  32'd3);
        check_register(4,  32'd13);             // add
        check_register(5,  32'd7);              // sub
        check_register(6,  32'd2);              // and
        check_register(7,  32'd11);             // or
        check_register(8,  32'd9);              // xor
        check_register(9,  32'd80);             // sll
        check_register(10, 32'd1);              // srl

        // ---- B. Suma 1..10 -------------------------------------------------------
        check_register(11, 32'd0);              // contador agotado
        check_register(12, 32'd55);

        // ---- C. Fibonacci ----------------------------------------------------------
        check_register(13, 32'd55);             // fib(10)
        check_register(14, 32'd89);             // fib(11)
        check_register(15, 32'd40);             // puntero final
        check_register(16, 32'd0);
        check_register(17, 32'd89);

        // ---- D. Llamada a funcion -------------------------------------------------
        check_register(1,  32'h0000_0078);      // direccion de retorno
        check_register(18, 32'd40);
        check_register(19, 32'd0);
        check_register(20, 32'd88);
        check_register(21, 32'd34);             // ultimo elemento leido

        // ---- E. Accesos de byte y media palabra ------------------------------
        check_register(22, 32'h80FF7F01);
        check_register(25, 32'hFFFFFF80);       // lb
        check_register(26, 32'h00000080);       // lbu
        check_register(27, 32'hFFFF80FF);       // lh
        check_register(28, 32'h000080FF);       // lhu
        check_register(30, 32'h80FF5501);       // lw tras el sb

        // ---- F. Con signo / sin signo ------------------------------------------
        check_register(29, 32'hFFFFFFF0);
        check_register(23, 32'hFFFFFFFE);       // sra
        check_register(24, 32'd1);              // sltu
        check_register(31, 32'd0);              // slt

        // ---- Memoria de datos ---------------------------------------------------
        for (fibonacci_index = 0; fibonacci_index < 10; fibonacci_index = fibonacci_index + 1)
            check_memory_word(fibonacci_index, expected_fibonacci[fibonacci_index]);
        for (fibonacci_index = 10; fibonacci_index < 16; fibonacci_index = fibonacci_index + 1)
            check_memory_word(fibonacci_index, 32'd0);                      // sin escrituras extra
        check_memory_word(LOAD_ADDRESS_SUM_1_TO_10   >> 2, 32'd55);
        check_memory_word(LOAD_ADDRESS_SUM_FIBONACCI >> 2, 32'd88);
        check_memory_word(ADDRESS_TEST_WORD          >> 2, 32'h80FF5501);
        check_memory_word((ADDRESS_TEST_WORD >> 2) + 1,    32'd0);          // sin escrituras extra
        end_test;

        finish_suite("tb_reference_program (programa de referencia)");
    end

endmodule
