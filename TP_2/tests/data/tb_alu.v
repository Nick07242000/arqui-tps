`timescale 1ns / 1ps

module tb_alu;
    parameter DATA_WIDTH = 8;

    reg  [DATA_WIDTH-1:0] i_a, i_b;
    reg  [5:0]            i_alu_op;
    wire [DATA_WIDTH-1:0] o_result;
    wire                  o_zero, o_carry, o_overflow;

    // Instancia del módulo
    alu #(.DATA_WIDTH(DATA_WIDTH)) uut (
        .i_a(i_a),
        .i_b(i_b),
        .i_alu_op(i_alu_op),
        .o_result(o_result),
        .o_zero(o_zero),
        .o_carry(o_carry),
        .o_overflow(o_overflow)
    );

    // Opcodes
    localparam OP_ADD = 6'b100000;
    localparam OP_SUB = 6'b100010;
    localparam OP_SRL = 6'b000010;
    localparam OP_SRA = 6'b000011;

    integer i;

    initial begin
        // ----------------------------------------------------
        // 1. PRUEBAS MANUALES Y EDGE CASES
        // ----------------------------------------------------
        $display("=== [ALU] Pruebas Manuales y Casos Borde ===");

        // Flag Zero (SUB con mismos operandos)
        i_a = 8'h05; i_b = 8'h05; i_alu_op = OP_SUB; #10;
        if (!o_zero || o_result !== 8'h00) 
            $error("[FAIL] Error en flag Zero/SUB");

        // Flags Carry y Overflow (ADD con desbordamiento signado y no signado)
        i_a = 8'h80; i_b = 8'h80; i_alu_op = OP_ADD; #10;
        if (!o_overflow || !o_carry) 
            $error("[FAIL] Error en flags Carry/Overflow");

        // Desplazamiento Lógico vs Aritmético (SRL vs SRA)
        i_a = 8'h80; i_b = 8'h02; i_alu_op = OP_SRL; #10; // Esperado: 0x20
        if (o_result !== 8'h20) $error("[FAIL] Error en SRL");

        i_a = 8'h80; i_b = 8'h02; i_alu_op = OP_SRA; #10; // Esperado: 0xE0
        if (o_result !== 8'hE0) $error("[FAIL] Error en SRA");

        // ----------------------------------------------------
        // 2. GENERACIÓN ALEATORIA
        // ----------------------------------------------------
        $display("=== [ALU] Generacion Aleatoria ===");
        for (i = 0; i < 10; i = i + 1) begin
            i_a      = $random;
            i_b      = $random;
            i_alu_op = OP_ADD;
            #10;
            $display("RAND ADD | A: 0x%h | B: 0x%h | Res: 0x%h | C: %b | V: %b | Z: %b", 
                     i_a, i_b, o_result, o_carry, o_overflow, o_zero);
        end

        $display("=== [ALU] Pruebas Finalizadas ===");
        $finish;
    end
endmodule