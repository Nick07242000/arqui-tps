`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.2 - Verificacion aislada de loads y stores
// lb, lh, lw, lbu, lhu, sb, sh, sw (y casos fuera de contrato)
// -----------------------------------------------------------------------------
module tb_load_store;
`include "tb_common.vh"

    localparam [31:0] LOAD_BASE_ADDRESS  = 32'h0000_0100;   // palabra 64
    localparam [31:0] STORE_BASE_ADDRESS = 32'h0000_0200;   // palabra 128
    localparam [31:0] OUT_OF_RANGE_ADDRESS = 32'h0000_1000; // primera direccion fuera de dmem

    // Palabra de prueba: bytes (de menor a mayor) 0x01, 0x7F, 0xFF, 0x80
    localparam [31:0] SAMPLE_WORD = 32'h80FF7F01;

    // Guarda SAMPLE_WORD en LOAD_BASE_ADDRESS (x1 = base) y ejecuta el load
    // x3 = <load>(x1, desplazamiento)
    task load_case(input [NAME_BITS-1:0] name, input [31:0] load_instruction, input [31:0] expected);
        begin
            begin_test(name);
            emit_load_immediate(1, LOAD_BASE_ADDRESS);
            emit_load_immediate(2, SAMPLE_WORD);
            emit(instr_sw(2, 1, 0));
            emit(load_instruction);
            emit(HALT_WORD);
            run_program;
            check_register(3, expected);
            check_register(1, LOAD_BASE_ADDRESS);
            check_flags(1'b0, 1'b0, 1'b0);
            end_test;
        end
    endtask

    // Prellena la palabra con 0x11223344, ejecuta el store de x4 = 0xAABBCCDD
    // y compara la palabra resultante
    task store_case(input [NAME_BITS-1:0] name, input [31:0] store_instruction, input [31:0] expected_word);
        begin
            begin_test(name);
            emit_load_immediate(1, STORE_BASE_ADDRESS);
            emit_load_immediate(2, 32'h11223344);
            emit(instr_sw(2, 1, 0));
            emit_load_immediate(4, 32'hAABBCCDD);
            emit(store_instruction);
            emit(HALT_WORD);
            run_program;
            check_memory_word(STORE_BASE_ADDRESS >> 2, expected_word);
            check_register(4, 32'hAABBCCDD);
            check_flags(1'b0, 1'b0, 1'b0);
            end_test;
        end
    endtask

    initial begin
        // ---- Loads -----------------------------------------------------------
        load_case("lb  byte 0 (0x01)",               instr_lb (3, 1, 0), 32'h00000001);
        load_case("lb  byte 1 (0x7F)",               instr_lb (3, 1, 1), 32'h0000007F);
        load_case("lb  byte 2 (0xFF, signo)",        instr_lb (3, 1, 2), 32'hFFFFFFFF);
        load_case("lb  byte 3 (0x80, signo)",        instr_lb (3, 1, 3), 32'hFFFFFF80);
        load_case("lbu byte 0 (0x01)",               instr_lbu(3, 1, 0), 32'h00000001);
        load_case("lbu byte 1 (0x7F)",               instr_lbu(3, 1, 1), 32'h0000007F);
        load_case("lbu byte 2 (0xFF, sin signo)",    instr_lbu(3, 1, 2), 32'h000000FF);
        load_case("lbu byte 3 (0x80, sin signo)",    instr_lbu(3, 1, 3), 32'h00000080);
        load_case("lh  mitad baja (0x7F01)",         instr_lh (3, 1, 0), 32'h00007F01);
        load_case("lh  mitad alta (0x80FF, signo)",  instr_lh (3, 1, 2), 32'hFFFF80FF);
        load_case("lhu mitad baja (0x7F01)",         instr_lhu(3, 1, 0), 32'h00007F01);
        load_case("lhu mitad alta (0x80FF, sin signo)", instr_lhu(3, 1, 2), 32'h000080FF);
        load_case("lw  palabra completa",            instr_lw (3, 1, 0), 32'h80FF7F01);

        begin_test("lw: latencia de 2 ciclos (6 instrucciones, 7 ciclos)");
        emit_load_immediate(1, LOAD_BASE_ADDRESS);
        emit_load_immediate(2, SAMPLE_WORD);
        emit(instr_sw(2, 1, 0));
        emit(instr_lw(3, 1, 0));
        emit(HALT_WORD);
        run_program;
        check_run_stats(6, 7);
        end_test;

        begin_test("lw con desplazamiento negativo");
        emit_load_immediate(1, LOAD_BASE_ADDRESS + 16);
        emit_load_immediate(2, 32'hCAFEBABE);
        emit(instr_sw(2, 1, -16));
        emit(instr_lw(3, 1, -16));
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'hCAFEBABE);
        check_memory_word(LOAD_BASE_ADDRESS >> 2, 32'hCAFEBABE);
        end_test;

        begin_test("dos loads consecutivos");
        emit_load_immediate(1, LOAD_BASE_ADDRESS);
        emit_load_immediate(2, 32'h11111111);
        emit_load_immediate(5, 32'h22222222);
        emit(instr_sw(2, 1, 0));
        emit(instr_sw(5, 1, 4));
        emit(instr_lw(3, 1, 0));
        emit(instr_lw(4, 1, 4));
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'h11111111);
        check_register(4, 32'h22222222);
        end_test;

        begin_test("load seguido de uso inmediato: lw + add");
        emit_load_immediate(1, LOAD_BASE_ADDRESS);
        emit_load_immediate(2, 32'd21);
        emit(instr_sw(2, 1, 0));
        emit(instr_lw(3, 1, 0));
        emit(instr_add(4, 3, 3));
        emit(HALT_WORD);
        run_program;
        check_register(4, 32'd42);
        end_test;

        begin_test("load con destino igual a la base: lw x1,0(x1)");
        emit_load_immediate(1, LOAD_BASE_ADDRESS);
        emit_load_immediate(2, 32'h00001234);
        emit(instr_sw(2, 1, 0));
        emit(instr_lw(1, 1, 0));
        emit(HALT_WORD);
        run_program;
        check_register(1, 32'h00001234);
        end_test;

        begin_test("lw x0 no modifica x0");
        emit_load_immediate(1, LOAD_BASE_ADDRESS);
        emit_load_immediate(2, 32'h00000055);
        emit(instr_sw(2, 1, 0));
        emit(instr_addi(3, 0, 9));
        emit(instr_lw(0, 1, 0));
        emit(instr_add(3, 0, 0));          // x3 = x0 + x0, debe ser 0
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'd0);
        end_test;

        // ---- Stores ----------------------------------------------------------
        store_case("sb byte 0",                      instr_sb(4, 1, 0), 32'h112233DD);
        store_case("sb byte 1",                      instr_sb(4, 1, 1), 32'h1122DD44);
        store_case("sb byte 2",                      instr_sb(4, 1, 2), 32'h11DD3344);
        store_case("sb byte 3",                      instr_sb(4, 1, 3), 32'hDD223344);
        store_case("sh mitad baja",                  instr_sh(4, 1, 0), 32'h1122CCDD);
        store_case("sh mitad alta",                  instr_sh(4, 1, 2), 32'hCCDD3344);
        store_case("sw palabra completa",            instr_sw(4, 1, 0), 32'hAABBCCDD);

        begin_test("sb no afecta palabras vecinas (offset negativo y positivo)");
        emit_load_immediate(1, STORE_BASE_ADDRESS);
        emit_load_immediate(2, 32'h11111111);
        emit_load_immediate(5, 32'h22222222);
        emit_load_immediate(6, 32'h33333333);
        emit(instr_sw(2, 1, 0));
        emit(instr_sw(5, 1, 4));
        emit(instr_sw(6, 1, -4));
        emit_load_immediate(4, 32'hFFFFFFFF);
        emit(instr_sb(4, 1, 0));
        emit(HALT_WORD);
        run_program;
        check_memory_word((STORE_BASE_ADDRESS >> 2) - 1, 32'h33333333);
        check_memory_word(STORE_BASE_ADDRESS >> 2,       32'h111111FF);
        check_memory_word((STORE_BASE_ADDRESS >> 2) + 1, 32'h22222222);
        end_test;

        // ---- Casos fuera de contrato (ver ADR-09 y ADR-10) -------------------
        begin_test("store fuera de rango: se suprime y levanta el flag");
        emit_load_immediate(6, 32'hDEADBEEF);
        emit(instr_sw(6, 0, 0));                         // dmem[0] = 0xDEADBEEF
        emit_load_immediate(1, OUT_OF_RANGE_ADDRESS);
        emit_load_immediate(2, 32'h12345678);
        emit(instr_sw(2, 1, 0));                         // alias de dmem[0] si no se suprimiera
        emit(HALT_WORD);
        run_program;
        check_memory_word(10'd0, 32'hDEADBEEF);
        check_flags(1'b0, 1'b1, 1'b0);
        end_test;

        begin_test("load fuera de rango: devuelve 0 y levanta el flag");
        emit_load_immediate(1, OUT_OF_RANGE_ADDRESS);
        emit(instr_addi(4, 0, 9));
        emit(instr_lw(4, 1, 0));
        emit(HALT_WORD);
        run_program;
        check_register(4, 32'd0);
        check_flags(1'b0, 1'b1, 1'b0);
        end_test;

        begin_test("lw desalineado: se alinea hacia abajo y levanta el flag");
        emit_load_immediate(1, STORE_BASE_ADDRESS);
        emit_load_immediate(2, 32'hA1B2C3D4);
        emit(instr_sw(2, 1, 0));
        emit(instr_lw(3, 1, 1));
        emit(HALT_WORD);
        run_program;
        check_register(3, 32'hA1B2C3D4);
        check_flags(1'b0, 1'b0, 1'b1);
        end_test;

        begin_test("sw desalineado: se alinea hacia abajo y levanta el flag");
        emit_load_immediate(1, STORE_BASE_ADDRESS);
        emit_load_immediate(4, 32'h0BADF00D);
        emit(instr_sw(4, 1, 3));
        emit(HALT_WORD);
        run_program;
        check_memory_word(STORE_BASE_ADDRESS >> 2, 32'h0BADF00D);
        check_flags(1'b0, 1'b0, 1'b1);
        end_test;

        finish_suite("tb_load_store (loads y stores)");
    end

endmodule
