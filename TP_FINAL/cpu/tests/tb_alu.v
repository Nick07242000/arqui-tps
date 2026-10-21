`timescale 1ns / 1ps
`include "alu_ops.vh"

module tb_alu;

    reg  [31:0] operand_a;
    reg  [31:0] operand_b;
    reg  [3:0]  alu_op;
    wire [31:0] result;

    integer error_count = 0;
    integer test_count  = 0;

    alu dut (
        .i_operand_a (operand_a),
        .i_operand_b (operand_b),
        .i_alu_op    (alu_op),
        .o_result    (result)
    );

    // Aplica un estimulo y compara contra el resultado esperado
    task check(
        input [255:0] test_name,
        input [3:0]   op,
        input [31:0]  a,
        input [31:0]  b,
        input [31:0]  expected
    );
        begin
            alu_op    = op;
            operand_a = a;
            operand_b = b;
            #1;
            test_count = test_count + 1;
            if (result !== expected) begin
                error_count = error_count + 1;
                $display("FAIL  %0s: a=%h b=%h esperado=%h obtenido=%h",
                         test_name, a, b, expected, result);
            end
        end
    endtask

    initial begin
        // ---- ADD / SUB ------------------------------------------------------
        check("add basico",         `ALU_OP_ADD, 32'd5,         32'd7,         32'd12);
        check("add cero",           `ALU_OP_ADD, 32'd0,         32'd0,         32'd0);
        check("add overflow",       `ALU_OP_ADD, 32'hFFFFFFFF,  32'd1,         32'd0);
        check("add max positivo",   `ALU_OP_ADD, 32'h7FFFFFFF,  32'd1,         32'h80000000);
        check("add negativo",       `ALU_OP_ADD, -32'sd3,       32'd10,        32'd7);

        check("sub basico",         `ALU_OP_SUB, 32'd10,        32'd3,         32'd7);
        check("sub resultado neg",  `ALU_OP_SUB, 32'd3,         32'd10,        -32'sd7);
        check("sub underflow",      `ALU_OP_SUB, 32'd0,         32'd1,         32'hFFFFFFFF);
        check("sub min - 1",        `ALU_OP_SUB, 32'h80000000,  32'd1,         32'h7FFFFFFF);

        // ---- Logicas --------------------------------------------------------
        check("and",                `ALU_OP_AND, 32'hF0F0F0F0,  32'hFF00FF00,  32'hF000F000);
        check("or",                 `ALU_OP_OR,  32'hF0F0F0F0,  32'h0F0F0F0F,  32'hFFFFFFFF);
        check("xor",                `ALU_OP_XOR, 32'hAAAAAAAA,  32'hFFFFFFFF,  32'h55555555);
        check("xor mismo valor",    `ALU_OP_XOR, 32'h12345678,  32'h12345678,  32'd0);

        // ---- Desplazamientos ------------------------------------------------
        check("sll 1",              `ALU_OP_SLL, 32'd1,         32'd4,         32'd16);
        check("sll 31",             `ALU_OP_SLL, 32'd1,         32'd31,        32'h80000000);
        check("sll shift 0",        `ALU_OP_SLL, 32'hDEADBEEF,  32'd0,         32'hDEADBEEF);
        check("sll usa solo 5 bits",`ALU_OP_SLL, 32'd1,         32'h00000025,  32'd32);  // 0x25 -> shamt 5

        check("srl positivo",       `ALU_OP_SRL, 32'h80000000,  32'd4,         32'h08000000);
        check("srl 31",             `ALU_OP_SRL, 32'hFFFFFFFF,  32'd31,        32'd1);
        check("srl shift 0",        `ALU_OP_SRL, 32'hDEADBEEF,  32'd0,         32'hDEADBEEF);

        check("sra negativo",       `ALU_OP_SRA, 32'h80000000,  32'd4,         32'hF8000000);
        check("sra positivo",       `ALU_OP_SRA, 32'h40000000,  32'd4,         32'h04000000);
        check("sra 31 negativo",    `ALU_OP_SRA, 32'h80000000,  32'd31,        32'hFFFFFFFF);
        check("sra 31 positivo",    `ALU_OP_SRA, 32'h7FFFFFFF,  32'd31,        32'd0);
        check("sra shift 0",        `ALU_OP_SRA, 32'hDEADBEEF,  32'd0,         32'hDEADBEEF);

        // ---- Comparaciones --------------------------------------------------
        check("slt menor",          `ALU_OP_SLT,  32'd1,         32'd2,        32'd1);
        check("slt igual",          `ALU_OP_SLT,  32'd2,         32'd2,        32'd0);
        check("slt mayor",          `ALU_OP_SLT,  32'd3,         32'd2,        32'd0);
        check("slt neg < pos",      `ALU_OP_SLT,  32'hFFFFFFFF,  32'd1,        32'd1);  // -1 < 1
        check("slt pos < neg",      `ALU_OP_SLT,  32'd1,         32'hFFFFFFFF, 32'd0);
        check("slt min < max",      `ALU_OP_SLT,  32'h80000000,  32'h7FFFFFFF, 32'd1);

        check("sltu menor",         `ALU_OP_SLTU, 32'd1,         32'd2,        32'd1);
        check("sltu igual",         `ALU_OP_SLTU, 32'd2,         32'd2,        32'd0);
        check("sltu 0xFFFFFFFF > 1",`ALU_OP_SLTU, 32'hFFFFFFFF,  32'd1,        32'd0);  // difiere de slt
        check("sltu 1 < 0xFFFFFFFF",`ALU_OP_SLTU, 32'd1,         32'hFFFFFFFF, 32'd1);
        check("sltu 0x8.. > 0x7..", `ALU_OP_SLTU, 32'h80000000,  32'h7FFFFFFF, 32'd0);  // difiere de slt

        // ---- PASS_B (lui) ---------------------------------------------------
        check("pass_b",             `ALU_OP_PASS_B, 32'hFFFFFFFF, 32'h12345000, 32'h12345000);

        // ---- Codigos no definidos -------------------------------------------
        check("op indefinida 1001", 4'b1001, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0);
        check("op indefinida 1010", 4'b1010, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0);
        check("op indefinida 1110", 4'b1110, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0);

        // ---- Resumen --------------------------------------------------------
        $display("----------------------------------------");
        if (error_count == 0)
            $display("PASS: %0d pruebas, 0 errores", test_count);
        else
            $display("FAIL: %0d pruebas, %0d errores", test_count, error_count);
        $finish;
    end

endmodule
