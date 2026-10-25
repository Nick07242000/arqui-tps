`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de lui
// -----------------------------------------------------------------------------
module tb_upper_immediate;
`include "tb_common.vh"

    // lui x1, imm20 -> x1 debe valer imm20 << 12
    task lui_case(input [NAME_BITS-1:0] name, input [19:0] imm20, input [31:0] expected);
        begin
            begin_test(name);
            emit(instr_lui(1, imm20));
            emit(HALT_WORD);
            run_program;
            check_register(1, expected);
            end_test;
        end
    endtask

    initial begin
        lui_case("lui 0x12345", 20'h12345, 32'h12345000);
        lui_case("lui 0x00000", 20'h00000, 32'h00000000);
        lui_case("lui 0x00001 (menor valor no nulo)", 20'h00001, 32'h00001000);
        lui_case("lui 0x7FFFF (mayor positivo)", 20'h7FFFF, 32'h7FFFF000);
        lui_case("lui 0x80000 (bit de signo)", 20'h80000, 32'h80000000);
        lui_case("lui 0xFFFFF (todos unos)", 20'hFFFFF, 32'hFFFFF000);

        begin_test("lui sobrescribe el valor previo del registro");
        emit(instr_addi(1, 0, 12'h7FF));
        emit(instr_lui(1, 20'h00ABC));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'h00ABC000);
        end_test;

        begin_test("lui no modifica otros registros");
        emit(instr_addi(2, 0, 5));
        emit(instr_lui(1, 20'h12345));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'h12345000);
        check_register(2, 32'd5);
        end_test;

        begin_test("lui x0 no modifica x0");
        emit(instr_addi(1, 0, 9));
        emit(instr_lui(0, 20'h12345));
        emit(instr_add(1, 0, 0));          // x1 = x0 + x0, debe ser 0
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'd0);
        end_test;

        begin_test("lui + addi forman una constante de 32 bits");
        emit(instr_lui(1, 20'h12345));
        emit(instr_addi(1, 1, 12'h678));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'h12345678);
        end_test;

        finish_suite("tb_upper_immediate (lui)");
    end

endmodule
