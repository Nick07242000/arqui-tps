`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de las operaciones con inmediato
// addi, andi, ori, xori, slti, sltiu, slli, srli, srai
// -----------------------------------------------------------------------------
module tb_immediate_ops;
`include "tb_common.vh"

    // x1 = source_value; x3 = <instruccion>(x1, inmediato); se espera x3 = expected
    task immediate_case(input [NAME_BITS-1:0] name, input [31:0] instruction_word,
                        input [31:0] source_value, input [31:0] expected);
        begin
            begin_test(name);
            emit_load_immediate(1, source_value);
            emit(instruction_word);
            emit(HALT_WORD);
            run_program;
            check_register(3, expected);
            check_register(1, source_value);     // la fuente no se modifica
            end_test;
        end
    endtask

    initial begin
        // ---- addi ----------------------------------------------------------
        immediate_case("addi 5 + 7",                 instr_addi(3, 1, 7),     32'd5,        32'd12);
        immediate_case("addi 5 + (-7)",              instr_addi(3, 1, -7),    32'd5,        32'hFFFFFFFE);
        immediate_case("addi desborda 0x7FFFFFFF + 1", instr_addi(3, 1, 1),   32'h7FFFFFFF, 32'h80000000);
        immediate_case("addi inmediato maximo +2047", instr_addi(3, 1, 2047), 32'd0,        32'h000007FF);
        immediate_case("addi inmediato minimo -2048", instr_addi(3, 1, -2048), 32'd0,       32'hFFFFF800);
        immediate_case("addi +1024 (bit 30 en 1, no es sub)", instr_addi(3, 1, 1024), 32'd10, 32'd1034);
        immediate_case("addi -1024",                 instr_addi(3, 1, -1024), 32'd10,       32'hFFFFFC0A);

        // ---- andi ----------------------------------------------------------
        immediate_case("andi 0xF0F0F0F0 & 0x0FF",    instr_andi(3, 1, 12'h0FF), 32'hF0F0F0F0, 32'h000000F0);
        immediate_case("andi con -1 conserva todo",  instr_andi(3, 1, -1),      32'h12345678, 32'h12345678);
        immediate_case("andi con 0x7FF",             instr_andi(3, 1, 12'h7FF), 32'h12345678, 32'h00000678);
        immediate_case("andi con -2048 (extension de signo)", instr_andi(3, 1, -2048), 32'hFFFFFFFF, 32'hFFFFF800);

        // ---- ori -----------------------------------------------------------
        immediate_case("ori 0x0F0 | 0x00F",          instr_ori(3, 1, 12'h00F),  32'h000000F0, 32'h000000FF);
        immediate_case("ori con -1 da todos unos",   instr_ori(3, 1, -1),       32'd0,        32'hFFFFFFFF);
        immediate_case("ori con 0x7FF",              instr_ori(3, 1, 12'h7FF),  32'h12340000, 32'h123407FF);

        // ---- xori ----------------------------------------------------------
        immediate_case("xori 0xFF ^ 0x0F",           instr_xori(3, 1, 12'h00F), 32'h000000FF, 32'h000000F0);
        immediate_case("xori con -1 es NOT",         instr_xori(3, 1, -1),      32'hAAAAAAAA, 32'h55555555);
        immediate_case("xori con 0 no cambia",       instr_xori(3, 1, 0),       32'd5,        32'd5);

        // ---- slti (con signo) ----------------------------------------------
        immediate_case("slti -5 < 3",                instr_slti(3, 1, 3),       32'hFFFFFFFB, 32'd1);
        immediate_case("slti 3 < -5",                instr_slti(3, 1, -5),      32'd3,        32'd0);
        immediate_case("slti 5 < 5",                 instr_slti(3, 1, 5),       32'd5,        32'd0);
        immediate_case("slti -5 < -4",               instr_slti(3, 1, -4),      32'hFFFFFFFB, 32'd1);
        immediate_case("slti 0x80000000 < 0 (signo)", instr_slti(3, 1, 0),      32'h80000000, 32'd1);

        // ---- sltiu (sin signo, inmediato extendido con signo) ----------------
        immediate_case("sltiu 3 < 5",                instr_sltiu(3, 1, 5),      32'd3,        32'd1);
        immediate_case("sltiu 5 < 3",                instr_sltiu(3, 1, 3),      32'd5,        32'd0);
        immediate_case("sltiu 0 < -1 (0xFFFFFFFF)",  instr_sltiu(3, 1, -1),     32'd0,        32'd1);
        immediate_case("sltiu 0xFFFFFFFF < -1 (iguales)", instr_sltiu(3, 1, -1), 32'hFFFFFFFF, 32'd0);
        immediate_case("sltiu 0x80000000 < 0 (sin signo)", instr_sltiu(3, 1, 0), 32'h80000000, 32'd0);
        immediate_case("sltiu 0 < 1 (seqz)",         instr_sltiu(3, 1, 1),      32'd0,        32'd1);

        // ---- slli ----------------------------------------------------------
        immediate_case("slli 1 << 0",                instr_slli(3, 1, 0),       32'd1,        32'd1);
        immediate_case("slli 1 << 4",                instr_slli(3, 1, 4),       32'd1,        32'd16);
        immediate_case("slli 1 << 31",               instr_slli(3, 1, 31),      32'd1,        32'h80000000);
        immediate_case("slli descarta bits altos",   instr_slli(3, 1, 1),       32'h80000001, 32'h00000002);
        immediate_case("slli 0xFFFFFFFF << 31",      instr_slli(3, 1, 31),      32'hFFFFFFFF, 32'h80000000);

        // ---- srli (logico) ---------------------------------------------------
        immediate_case("srli 0x80000000 >> 31",      instr_srli(3, 1, 31),      32'h80000000, 32'd1);
        immediate_case("srli 0xF0 >> 4",             instr_srli(3, 1, 4),       32'h000000F0, 32'h0000000F);
        immediate_case("srli 0xFFFFFFFF >> 1",       instr_srli(3, 1, 1),       32'hFFFFFFFF, 32'h7FFFFFFF);
        immediate_case("srli >> 0 no cambia",        instr_srli(3, 1, 0),       32'h12345678, 32'h12345678);

        // ---- srai (aritmetico) -----------------------------------------------
        immediate_case("srai 0x80000000 >> 31",      instr_srai(3, 1, 31),      32'h80000000, 32'hFFFFFFFF);
        immediate_case("srai 0xF0000000 >> 4",       instr_srai(3, 1, 4),       32'hF0000000, 32'hFF000000);
        immediate_case("srai positivo >> 31",        instr_srai(3, 1, 31),      32'h7FFFFFFF, 32'd0);
        immediate_case("srai -16 >> 2",              instr_srai(3, 1, 2),       32'hFFFFFFF0, 32'hFFFFFFFC);
        immediate_case("srai >> 0 no cambia",        instr_srai(3, 1, 0),       32'hFFFFFFF0, 32'hFFFFFFF0);
        immediate_case("srli 0x80000000 >> 4 (contraste con srai)", instr_srli(3, 1, 4), 32'h80000000, 32'h08000000);
        immediate_case("srai 0x80000000 >> 4 (contraste con srli)", instr_srai(3, 1, 4), 32'h80000000, 32'hF8000000);

        // ---- Casos de registros destino -------------------------------------
        begin_test("destino igual a fuente: addi x1,x1,1 tres veces");
        emit(instr_addi(1, 1, 1));
        emit(instr_addi(1, 1, 1));
        emit(instr_addi(1, 1, 1));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'd3);
        end_test;

        begin_test("addi x0 no modifica x0");
        emit(instr_addi(1, 0, 9));
        emit(instr_addi(0, 0, 5));
        emit(instr_addi(1, 0, 0));         // x1 = x0 + 0, debe ser 0
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'd0);
        end_test;

        finish_suite("tb_immediate_ops (inmediatos)");
    end

endmodule
