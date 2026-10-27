`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// T2.1.4 - Volcado del estado final del datapath
//
// Carga una imagen, la ejecuta hasta HALT e imprime el estado final con el
// mismo formato que tools/rv32i_ref.py, para compararlos linea a linea.
//
// Uso: vvp dump_state.vvp +hex=programa.hex +words=<cantidad de palabras>
// No es un test: no informa PASS/FAIL, lo usa tools/compare_with_reference.py
// -----------------------------------------------------------------------------
module tb_dump_state;
`include "tb_common.vh"

    reg [8*256-1:0] program_hex_file;
    integer         program_word_count;
    integer         index;

    initial begin
        if (!$value$plusargs("hex=%s", program_hex_file) ||
            !$value$plusargs("words=%d", program_word_count)) begin
            $display("ERROR: faltan los argumentos +hex=<archivo> +words=<cantidad>");
            $finish;
        end

        begin_test("dump");
        $readmemh(program_hex_file, program_words, 0, program_word_count - 1);
        program_length = program_word_count;
        run_program;

        if (case_errors == 0) $display("STATUS HALT");
        else                  $display("STATUS TIMEOUT");
        $display("PC %08x", pc);
        $display("RETIRED %0d", last_retired_count);
        $display("CYCLES %0d", last_run_cycles);
        $display("FLAGS illegal=%0d out_of_range=%0d misaligned=%0d",
                 seen_illegal, seen_out_of_range, seen_misaligned);

        for (index = 0; index < 32; index = index + 1) begin
            debug_register_addr = index;
            #1 $display("REG %0d %08x", index, debug_register_data);
        end

        for (index = 0; index < 1024; index = index + 1) begin
            debug_data_word_addr = index;
            @(posedge clk);
            #1 $display("MEM %0d %08x", index, debug_data_word);
        end
        $finish;
    end

endmodule
