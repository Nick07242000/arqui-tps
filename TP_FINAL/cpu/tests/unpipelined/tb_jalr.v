`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de jalr
// -----------------------------------------------------------------------------
module tb_jalr;
`include "tb_common.vh"

    // Programa base de cada caso (una palabra = 4 bytes):
    //   0    x7 = 9 (testigo para detectar escrituras en x0)
    //   1-2  x1 = rs1_value
    //   3    jalr rd, imm(x1)        -> enlace = 16
    //   4-5  x3 = 1, x3 = 2          (se saltean)
    //   6    x4 = 5                  (destino: byte 24)
    //   7    x7 = x0 + x0            (debe quedar en 0)
    //   8    HALT
    localparam [31:0] LINK_VALUE = 32'd16;
    localparam [31:0] FINAL_PC   = 32'd32;

    task jalr_case(input [NAME_BITS-1:0] name, input [4:0] rd,
                   input [31:0] rs1_value, input [11:0] immediate);
        begin
            begin_test(name);
            emit(instr_addi(7, 0, 9));
            emit_load_immediate(1, rs1_value);
            emit(instr_jalr(rd, 1, immediate));
            emit(instr_addi(3, 0, 1));
            emit(instr_addi(3, 0, 2));
            emit(instr_addi(4, 0, 5));
            emit(instr_add(7, 0, 0));
            emit(HALT_WORD);
            run_program;
            if (rd != 0) check_register(rd, LINK_VALUE);
            check_register(3, 32'd0);
            check_register(4, 32'd5);
            check_register(7, 32'd0);
            check_pc(FINAL_PC);
            end_test;
        end
    endtask

    initial begin
        jalr_case("jalr destino = rs1 + 0",               2, 32'd24,   0);
        jalr_case("jalr destino = rs1 + inmediato (+4)",  2, 32'd20,   4);
        jalr_case("jalr destino = rs1 + inmediato (-4)",  2, 32'd28,  -4);
        jalr_case("jalr con rs1 impar: se limpia el bit 0", 2, 32'd25,  0);
        jalr_case("jalr con suma impar (20 + 5): se limpia el bit 0", 2, 32'd20, 5);
        jalr_case("jalr con inmediato minimo -2048",      2, 32'd2072, -2048);
        jalr_case("jalr con inmediato maximo +2047",      2, 32'hFFFFF819, 2047);
        jalr_case("jalr x0 salta pero no escribe x0",     0, 32'd24,   0);
        jalr_case("jalr con rd = rs1 (usa el rs1 viejo)", 1, 32'd24,   0);

        begin_test("llamada y retorno: jal + jalr");
        emit(instr_jal(1, 12));            // 0: llama a la funcion (palabra 3), x1 = 4
        emit(instr_addi(5, 0, 1));         // 1: punto de retorno
        emit(HALT_WORD);                   // 2
        emit(instr_addi(4, 0, 7));         // 3: cuerpo de la funcion
        emit(instr_jalr(0, 1, 0));         // 4: retorno (ret)
        run_program;
        check_register(1, 32'd4);
        check_register(4, 32'd7);
        check_register(5, 32'd1);
        check_pc(32'd8);
        end_test;

        finish_suite("tb_jalr (jalr)");
    end

endmodule
