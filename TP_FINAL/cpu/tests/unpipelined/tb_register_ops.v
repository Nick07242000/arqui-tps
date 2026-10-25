`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de las operaciones registro-registro
// add, sub, sll, srl, sra, and, or, xor, slt, sltu
// -----------------------------------------------------------------------------
module tb_register_ops;
`include "tb_common.vh"

    // x1 = operand_a; x2 = operand_b; x3 = <instruccion>(x1, x2)
    task register_case(input [NAME_BITS-1:0] name, input [31:0] instruction_word,
                       input [31:0] operand_a, input [31:0] operand_b, input [31:0] expected);
        begin
            begin_test(name);
            emit_load_immediate(1, operand_a);
            emit_load_immediate(2, operand_b);
            emit(instruction_word);
            emit(HALT_WORD);
            run_program;
            check_register(3, expected);
            check_register(1, operand_a);        // las fuentes no se modifican
            check_register(2, operand_b);
            end_test;
        end
    endtask

    initial begin
        // ---- add -----------------------------------------------------------
        register_case("add 5 + 7",                   instr_add(3, 1, 2), 32'd5,        32'd7,        32'd12);
        register_case("add 0 + 0",                   instr_add(3, 1, 2), 32'd0,        32'd0,        32'd0);
        register_case("add -5 + 3",                  instr_add(3, 1, 2), 32'hFFFFFFFB, 32'd3,        32'hFFFFFFFE);
        register_case("add desborda 0xFFFFFFFF + 1", instr_add(3, 1, 2), 32'hFFFFFFFF, 32'd1,        32'd0);
        register_case("add desborda 0x7FFFFFFF + 1", instr_add(3, 1, 2), 32'h7FFFFFFF, 32'd1,        32'h80000000);

        // ---- sub -----------------------------------------------------------
        register_case("sub 7 - 5",                   instr_sub(3, 1, 2), 32'd7,        32'd5,        32'd2);
        register_case("sub 5 - 7",                   instr_sub(3, 1, 2), 32'd5,        32'd7,        32'hFFFFFFFE);
        register_case("sub 0 - 1",                   instr_sub(3, 1, 2), 32'd0,        32'd1,        32'hFFFFFFFF);
        register_case("sub 0x80000000 - 1",          instr_sub(3, 1, 2), 32'h80000000, 32'd1,        32'h7FFFFFFF);
        register_case("sub x - x",                   instr_sub(3, 1, 2), 32'h12345678, 32'h12345678, 32'd0);

        // ---- sll (usa solo los 5 bits bajos de rs2) --------------------------
        register_case("sll 1 << 4",                  instr_sll(3, 1, 2), 32'd1,        32'd4,        32'h00000010);
        register_case("sll 1 << 31",                 instr_sll(3, 1, 2), 32'd1,        32'd31,       32'h80000000);
        register_case("sll 1 << 32 (cantidad = 0)",  instr_sll(3, 1, 2), 32'd1,        32'd32,       32'd1);
        register_case("sll 1 << 33 (cantidad = 1)",  instr_sll(3, 1, 2), 32'd1,        32'd33,       32'd2);
        register_case("sll << 0 no cambia",          instr_sll(3, 1, 2), 32'hFFFFFFFF, 32'd0,        32'hFFFFFFFF);

        // ---- srl (logico) ----------------------------------------------------
        register_case("srl 0x80000000 >> 31",        instr_srl(3, 1, 2), 32'h80000000, 32'd31,       32'd1);
        register_case("srl 0xFFFFFFFF >> 4",         instr_srl(3, 1, 2), 32'hFFFFFFFF, 32'd4,        32'h0FFFFFFF);
        register_case("srl 0x80000000 >> 32 (cantidad = 0)", instr_srl(3, 1, 2), 32'h80000000, 32'd32, 32'h80000000);
        register_case("srl 0xF0 >> 36 (cantidad = 4)", instr_srl(3, 1, 2), 32'h000000F0, 32'd36,     32'h0000000F);

        // ---- sra (aritmetico) --------------------------------------------------
        register_case("sra 0x80000000 >> 31",        instr_sra(3, 1, 2), 32'h80000000, 32'd31,       32'hFFFFFFFF);
        register_case("sra 0xF0000000 >> 4",         instr_sra(3, 1, 2), 32'hF0000000, 32'd4,        32'hFF000000);
        register_case("sra positivo 0x7FFFFFF0 >> 4", instr_sra(3, 1, 2), 32'h7FFFFFF0, 32'd4,       32'h07FFFFFF);
        register_case("sra 0x80000000 >> 33 (cantidad = 1)", instr_sra(3, 1, 2), 32'h80000000, 32'd33, 32'hC0000000);
        register_case("srl 0x80000000 >> 4 (contraste con sra)", instr_srl(3, 1, 2), 32'h80000000, 32'd4, 32'h08000000);
        register_case("sra 0x80000000 >> 4 (contraste con srl)", instr_sra(3, 1, 2), 32'h80000000, 32'd4, 32'hF8000000);

        // ---- and / or / xor ------------------------------------------------
        register_case("and mascara alterna",         instr_and(3, 1, 2), 32'hF0F0F0F0, 32'hFF00FF00, 32'hF000F000);
        register_case("and con 0",                   instr_and(3, 1, 2), 32'h12345678, 32'd0,        32'd0);
        register_case("and con 0xFFFFFFFF",          instr_and(3, 1, 2), 32'h12345678, 32'hFFFFFFFF, 32'h12345678);
        register_case("or complementarios",          instr_or (3, 1, 2), 32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF);
        register_case("or con 0",                    instr_or (3, 1, 2), 32'h12345678, 32'd0,        32'h12345678);
        register_case("or extremos",                 instr_or (3, 1, 2), 32'hF0000000, 32'h0000000F, 32'hF000000F);
        register_case("xor mascara",                 instr_xor(3, 1, 2), 32'hFFFF0000, 32'hFF00FF00, 32'h00FFFF00);
        register_case("xor x ^ x",                   instr_xor(3, 1, 2), 32'h12345678, 32'h12345678, 32'd0);
        register_case("xor con 0xFFFFFFFF es NOT",   instr_xor(3, 1, 2), 32'hAAAAAAAA, 32'hFFFFFFFF, 32'h55555555);

        // ---- slt (con signo) / sltu (sin signo) ------------------------------
        register_case("slt -1 < 1",                  instr_slt (3, 1, 2), 32'hFFFFFFFF, 32'd1,        32'd1);
        register_case("slt 1 < -1",                  instr_slt (3, 1, 2), 32'd1,        32'hFFFFFFFF, 32'd0);
        register_case("slt 5 < 5",                   instr_slt (3, 1, 2), 32'd5,        32'd5,        32'd0);
        register_case("slt 0x80000000 < 0x7FFFFFFF", instr_slt (3, 1, 2), 32'h80000000, 32'h7FFFFFFF, 32'd1);
        register_case("slt 3 < 4",                   instr_slt (3, 1, 2), 32'd3,        32'd4,        32'd1);
        register_case("sltu 0xFFFFFFFF < 1",         instr_sltu(3, 1, 2), 32'hFFFFFFFF, 32'd1,        32'd0);
        register_case("sltu 1 < 0xFFFFFFFF",         instr_sltu(3, 1, 2), 32'd1,        32'hFFFFFFFF, 32'd1);
        register_case("sltu 5 < 5",                  instr_sltu(3, 1, 2), 32'd5,        32'd5,        32'd0);
        register_case("sltu 0x80000000 < 0x7FFFFFFF", instr_sltu(3, 1, 2), 32'h80000000, 32'h7FFFFFFF, 32'd0);
        register_case("sltu 0 < 1",                  instr_sltu(3, 1, 2), 32'd0,        32'd1,        32'd1);

        // ---- Casos de registros destino -------------------------------------
        begin_test("destino igual a fuente: add x1,x1,x2");
        emit(instr_addi(1, 0, 5));
        emit(instr_addi(2, 0, 7));
        emit(instr_add(1, 1, 2));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'd12);
        check_register(2, 32'd7);
        end_test;

        begin_test("las dos fuentes son el mismo registro: add x1,x1,x1");
        emit(instr_addi(1, 0, 5));
        emit(instr_add(1, 1, 1));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'd10);
        end_test;

        begin_test("add x0 no modifica x0");
        emit(instr_addi(1, 0, 5));
        emit(instr_addi(2, 0, 7));
        emit(instr_addi(3, 0, 9));
        emit(instr_add(0, 1, 2));          // intenta escribir x0
        emit(instr_add(3, 0, 0));          // x3 = x0 + x0, debe ser 0
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'd0);
        end_test;

        finish_suite("tb_register_ops (R-type)");
    end

endmodule
