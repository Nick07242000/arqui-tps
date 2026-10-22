`timescale 1ns / 1ps
`include "riscv_defs.vh"

module tb_immediate_generator;

    reg  [31:0] i_instruction;
    reg  [2:0]  i_imm_type;
    wire [31:0] o_immediate;

    integer error_count = 0;

    immediate_generator dut (
        .i_instruction (i_instruction),
        .i_imm_type    (i_imm_type),
        .o_immediate   (o_immediate)
    );

    task check(
        input [8*24-1:0] test_name,
        input [2:0]      imm_type,
        input [31:0]     instruction,
        input [31:0]     expected_immediate
    );
    begin
        i_imm_type    = imm_type;
        i_instruction = instruction;
        #1;
        if (o_immediate !== expected_immediate) begin
            error_count = error_count + 1;
            $display("FALLO %0s: instr=%h esperado=%h obtenido=%h",
                     test_name, instruction, expected_immediate, o_immediate);
        end
    end
    endtask

    initial begin
        // ---- Tipo I ---------------------------------------------------------
        check("addi x1,x0,5",      `IMM_TYPE_I, 32'h00500093, 32'h00000005);
        check("addi x1,x0,-1",     `IMM_TYPE_I, 32'hFFF00093, 32'hFFFFFFFF);
        check("addi imm=2047",     `IMM_TYPE_I, 32'h7FF00093, 32'h000007FF);
        check("addi imm=-2048",    `IMM_TYPE_I, 32'h80000093, 32'hFFFFF800);
        check("lw x2,8(x1)",       `IMM_TYPE_I, 32'h0080A103, 32'h00000008);

        // ---- Tipo S ---------------------------------------------------------
        check("sw x2,8(x1)",       `IMM_TYPE_S, 32'h0020A423, 32'h00000008);
        check("sw x2,-4(x1)",      `IMM_TYPE_S, 32'hFE20AE23, 32'hFFFFFFFC);

        // ---- Tipo B (bits reordenados) --------------------------------------
        check("beq x1,x2,+8",      `IMM_TYPE_B, 32'h00208463, 32'h00000008);
        check("beq x0,x0,-4",      `IMM_TYPE_B, 32'hFE000EE3, 32'hFFFFFFFC);
        check("beq solo imm[11]",  `IMM_TYPE_B, 32'h000000E3, 32'h00000800);
        check("beq solo imm[12]",  `IMM_TYPE_B, 32'h80000063, 32'hFFFFF000);

        // ---- Tipo U ---------------------------------------------------------
        check("lui x1,0x12345",    `IMM_TYPE_U, 32'h123450B7, 32'h12345000);
        check("lui x1,0xFFFFF",    `IMM_TYPE_U, 32'hFFFFF0B7, 32'hFFFFF000);

        // ---- Tipo J (bits reordenados) --------------------------------------
        check("jal x1,+8",         `IMM_TYPE_J, 32'h008000EF, 32'h00000008);
        check("jal x0,-4",         `IMM_TYPE_J, 32'hFFDFF06F, 32'hFFFFFFFC);
        check("jal solo imm[11]",  `IMM_TYPE_J, 32'h0010006F, 32'h00000800);
        check("jal solo imm[12]",  `IMM_TYPE_J, 32'h0000106F, 32'h00001000);
        check("jal solo imm[20]",  `IMM_TYPE_J, 32'h8000006F, 32'hFFF00000);

        // ---- Sin inmediato --------------------------------------------------
        check("tipo NONE",         `IMM_TYPE_NONE, 32'hFFFFFFFF, 32'h00000000);

        if (error_count == 0) $display("tb_immediate_generator: TODAS LAS PRUEBAS PASARON");
        else                  $display("tb_immediate_generator: %0d FALLOS", error_count);
        $finish;
    end

endmodule
