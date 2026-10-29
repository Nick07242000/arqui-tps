`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de jal
// -----------------------------------------------------------------------------
module tb_jal;
`include "tb_common.vh"

    initial begin
        begin_test("jal hacia adelante: salta y guarda el enlace (pc + 4)");
        emit(instr_jal(1, 12));            // 0: salta a la palabra 3, x1 = 4
        emit(instr_addi(3, 0, 1));         // 1: se saltea
        emit(instr_addi(3, 0, 2));         // 2: se saltea
        emit(instr_addi(4, 0, 5));         // 3: destino
        emit(HALT_WORD);                   // 4
        run_program;
        check_register(1, 32'd4);
        check_register(3, 32'd0);
        check_register(4, 32'd5);
        check_pc(32'd16);
        end_test;

        begin_test("jal desde un pc distinto de cero: enlace = pc + 4");
        emit(instr_addi(5, 0, 1));         // 0
        emit(instr_addi(6, 0, 2));         // 1
        emit(instr_jal(1, 8));             // 2: pc = 8, salta a la palabra 4, x1 = 12
        emit(instr_addi(3, 0, 1));         // 3: se saltea
        emit(instr_addi(4, 0, 5));         // 4: destino
        emit(HALT_WORD);                   // 5
        run_program;
        check_register(1, 32'd12);
        check_register(3, 32'd0);
        check_register(4, 32'd5);
        check_register(5, 32'd1);
        check_register(6, 32'd2);
        end_test;

        begin_test("jal hacia atras");
        emit(instr_jal(0, 8));             // 0: salta a la palabra 2
        emit(HALT_WORD);                   // 1: destino del salto hacia atras
        emit(instr_addi(4, 0, 3));         // 2
        emit(instr_jal(1, -8));            // 3: vuelve a la palabra 1, x1 = 16
        emit(HALT_WORD);                   // 4: no debe alcanzarse
        run_program;
        check_register(4, 32'd3);
        check_register(1, 32'd16);
        check_pc(32'd4);
        end_test;

        begin_test("jal a la instruccion siguiente (offset +4)");
        emit(instr_jal(1, 4));             // 0: x1 = 4
        emit(instr_addi(3, 0, 1));         // 1: si se ejecuta
        emit(HALT_WORD);                   // 2
        run_program;
        check_register(1, 32'd4);
        check_register(3, 32'd1);
        end_test;

        begin_test("jal x0 salta pero no escribe x0");
        emit(instr_addi(1, 0, 9));         // 0
        emit(instr_jal(0, 8));             // 1: salta a la palabra 3
        emit(instr_addi(3, 0, 1));         // 2: se saltea
        emit(instr_add(1, 0, 0));          // 3: x1 = x0 + x0, debe ser 0
        emit(HALT_WORD);                   // 4
        run_program;
        check_register(1, 32'd0);
        check_register(3, 32'd0);
        end_test;

        begin_test("jal con offset +2048 (hacia adelante)");
        emit(instr_jal(1, 2048));          // 0: salta a la palabra 512, x1 = 4
        emit(instr_addi(3, 0, 1));         // 1: se saltea
        emit(HALT_WORD);                   // 2: no debe alcanzarse
        emit_nops(509);                    // 3-511
        emit(instr_addi(4, 0, 7));         // 512
        emit(HALT_WORD);                   // 513
        run_program;
        check_register(1, 32'd4);
        check_register(3, 32'd0);
        check_register(4, 32'd7);
        check_pc(32'd2052);
        end_test;

        begin_test("jal con offset -2048 (hacia atras)");
        emit(instr_jal(0, 2048));          // 0: salta a la palabra 512
        emit(instr_addi(5, 0, 9));         // 1: destino del salto hacia atras
        emit(HALT_WORD);                   // 2
        emit_nops(509);                    // 3-511
        emit(instr_addi(4, 0, 7));         // 512
        emit(instr_jal(6, -2048));         // 513: vuelve a la palabra 1, x6 = 2056
        run_program;
        check_register(4, 32'd7);
        check_register(5, 32'd9);
        check_register(6, 32'd2056);
        check_pc(32'd8);
        end_test;

        finish_suite("tb_jal (jal)");
    end

endmodule
