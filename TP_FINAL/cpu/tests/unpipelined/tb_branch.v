`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de branches
// beq, bne: tomado / no tomado, hacia adelante / atras, offsets largos
// -----------------------------------------------------------------------------
module tb_branch;
`include "tb_common.vh"

    // Programa base de cada caso (una palabra = 4 bytes):
    //   0-1  x1 = operand_a          4  branch (salta +8 si se toma)
    //   2-3  x2 = operand_b          5  x3 = 1   (se saltea si el branch se toma)
    //                                6  x4 = 2   (siempre se ejecuta)
    //                                7  HALT
    localparam [31:0] FINAL_PC = 32'd28;

    task branch_case(input [NAME_BITS-1:0] name, input [31:0] branch_instruction,
                     input [31:0] operand_a, input [31:0] operand_b, input expect_taken);
        begin
            begin_test(name);
            emit_load_immediate(1, operand_a);
            emit_load_immediate(2, operand_b);
            emit(branch_instruction);
            emit(instr_addi(3, 0, 1));
            emit(instr_addi(4, 0, 2));
            emit(HALT_WORD);
            run_program;
            check_register(3, expect_taken ? 32'd0 : 32'd1);
            check_register(4, 32'd2);
            check_pc(FINAL_PC);
            end_test;
        end
    endtask

    initial begin
        // ---- beq -------------------------------------------------------------
        branch_case("beq iguales (5, 5): se toma",          instr_beq(1, 2, 8), 32'd5,        32'd5,        1'b1);
        branch_case("beq distintos (5, 6): no se toma",     instr_beq(1, 2, 8), 32'd5,        32'd6,        1'b0);
        branch_case("beq ceros (0, 0): se toma",            instr_beq(1, 2, 8), 32'd0,        32'd0,        1'b1);
        branch_case("beq todos unos: se toma",              instr_beq(1, 2, 8), 32'hFFFFFFFF, 32'hFFFFFFFF, 1'b1);
        branch_case("beq 0x80000000 vs 0: no se toma",      instr_beq(1, 2, 8), 32'h80000000, 32'd0,        1'b0);
        branch_case("beq difieren solo en el bit 0",        instr_beq(1, 2, 8), 32'h00000001, 32'h80000001, 1'b0);
        branch_case("beq mismo registro (x1, x1): se toma", instr_beq(1, 1, 8), 32'd7,        32'd0,        1'b1);

        // ---- bne -------------------------------------------------------------
        branch_case("bne iguales (5, 5): no se toma",       instr_bne(1, 2, 8), 32'd5,        32'd5,        1'b0);
        branch_case("bne distintos (5, 6): se toma",        instr_bne(1, 2, 8), 32'd5,        32'd6,        1'b1);
        branch_case("bne ceros (0, 0): no se toma",         instr_bne(1, 2, 8), 32'd0,        32'd0,        1'b0);
        branch_case("bne 0xFFFFFFFF vs 0: se toma",         instr_bne(1, 2, 8), 32'hFFFFFFFF, 32'd0,        1'b1);
        branch_case("bne compara bits, no signo",           instr_bne(1, 2, 8), 32'h80000000, 32'd1,        1'b1);
        branch_case("bne mismo registro (x1, x1): no se toma", instr_bne(1, 1, 8), 32'd7,     32'd0,        1'b0);

        // ---- Condicion calculada por la ALU en la instruccion anterior -------
        begin_test("beq con condicion calculada justo antes");
        emit(instr_addi(1, 0, 4));
        emit(instr_addi(2, 1, -4));        // x2 = 0
        emit(instr_beq(2, 0, 8));          // x2 == x0: se toma
        emit(instr_addi(3, 0, 1));         // se saltea
        emit(instr_addi(4, 0, 2));
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'd0);
        check_register(4, 32'd2);
        end_test;

        // ---- Hacia atras -----------------------------------------------------
        begin_test("bne hacia atras: lazo de 3 iteraciones");
        emit(instr_addi(1, 0, 3));         // 0: contador
        emit(instr_addi(2, 2, 1));         // 1: inicio del lazo, x2++
        emit(instr_addi(1, 1, -1));        // 2: contador--
        emit(instr_bne(1, 0, -8));         // 3: vuelve a la palabra 1
        emit(HALT_WORD);                   // 4
        run_program;
        check_register(1, 32'd0);
        check_register(2, 32'd3);
        check_pc(32'd16);
        end_test;

        begin_test("beq hacia atras: lazo de 2 iteraciones");
        emit(instr_addi(1, 0, 2));         // 0: contador
        emit(instr_addi(2, 2, 1));         // 1: inicio del lazo, x2++
        emit(instr_addi(1, 1, -1));        // 2: contador--
        emit(instr_beq(1, 0, 8));          // 3: si x1 == 0 sale a la palabra 5
        emit(instr_beq(0, 0, -12));        // 4: salto incondicional a la palabra 1
        emit(HALT_WORD);                   // 5
        run_program;
        check_register(1, 32'd0);
        check_register(2, 32'd2);
        check_pc(32'd20);
        end_test;

        // ---- Offsets largos (usan los bits altos del inmediato B) --------------
        begin_test("beq con offset +2048 (hacia adelante)");
        emit(instr_beq(0, 0, 2048));       // 0: salta a la palabra 512
        emit(instr_addi(3, 0, 1));         // 1: se saltea
        emit(HALT_WORD);                   // 2: no debe alcanzarse
        emit_nops(509);                    // 3-511
        emit(instr_addi(4, 0, 7));         // 512
        emit(HALT_WORD);                   // 513
        run_program;
        check_register(3, 32'd0);
        check_register(4, 32'd7);
        check_pc(32'd2052);
        end_test;

        begin_test("beq con offset -2048 (hacia atras)");
        emit(instr_beq(0, 0, 2048));       // 0: salta a la palabra 512
        emit(instr_addi(5, 0, 9));         // 1: destino del salto hacia atras
        emit(HALT_WORD);                   // 2
        emit_nops(509);                    // 3-511
        emit(instr_addi(4, 0, 7));         // 512
        emit(instr_beq(0, 0, -2048));      // 513: vuelve a la palabra 1
        run_program;
        check_register(4, 32'd7);
        check_register(5, 32'd9);
        check_pc(32'd8);
        end_test;

        finish_suite("tb_branch (beq, bne)");
    end

endmodule
