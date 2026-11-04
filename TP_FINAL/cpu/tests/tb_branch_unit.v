`timescale 1ns / 1ps
`include "riscv_defs.vh"

module tb_branch_unit;

    reg         valid;
    reg         is_branch;
    reg         is_jal;
    reg         is_jalr;
    reg  [2:0]  funct3;
    reg  [31:0] pc;
    reg  [31:0] immediate;
    reg  [31:0] rs1_value;
    reg  [31:0] rs2_value;
    reg  [31:0] alu_result;

    wire        redirect;
    wire [31:0] redirect_pc;

    branch_unit dut (
        .i_valid       (valid),
        .i_is_branch   (is_branch),
        .i_is_jal      (is_jal),
        .i_is_jalr     (is_jalr),
        .i_funct3      (funct3),
        .i_pc          (pc),
        .i_immediate   (immediate),
        .i_rs1_value   (rs1_value),
        .i_rs2_value   (rs2_value),
        .i_alu_result  (alu_result),
        .o_redirect    (redirect),
        .o_redirect_pc (redirect_pc)
    );

    integer error_count = 0;
    integer test_count  = 0;

    // -------------------------------------------------------------------------
    // Estimulos: cada tarea deja todas las entradas en un estado conocido
    // -------------------------------------------------------------------------
    task drive_idle;
        begin
            valid      = 1'b1;
            is_branch  = 1'b0;
            is_jal     = 1'b0;
            is_jalr    = 1'b0;
            funct3     = 3'b000;
            pc         = 32'h0000_0040;
            immediate  = 32'h0000_0010;
            rs1_value  = 32'd0;
            rs2_value  = 32'd0;
            alu_result = 32'd0;
        end
    endtask

    task drive_branch(input [2:0] branch_funct3, input [31:0] a, input [31:0] b);
        begin
            drive_idle;
            is_branch = 1'b1;
            funct3    = branch_funct3;
            rs1_value = a;
            rs2_value = b;
        end
    endtask

    task drive_jal;
        begin
            drive_idle;
            is_jal    = 1'b1;
            rs1_value = 32'hDEAD_BEEF;      // un jal no mira los operandos
            rs2_value = 32'h1234_5678;
        end
    endtask

    task drive_jalr(input [31:0] base_plus_offset);
        begin
            drive_idle;
            is_jalr    = 1'b1;
            alu_result = base_plus_offset;
        end
    endtask

    // -------------------------------------------------------------------------
    // Verificacion
    // -------------------------------------------------------------------------
    task check(input [8*44-1:0] test_name, input expected_redirect, input [31:0] expected_pc);
        begin
            #1;
            test_count = test_count + 1;
            if (redirect !== expected_redirect) begin
                $display("FAIL %0s: redirect=%b esperado=%b", test_name, redirect, expected_redirect);
                error_count = error_count + 1;
            end else if (expected_redirect && redirect_pc !== expected_pc) begin
                $display("FAIL %0s: redirect_pc=%h esperado=%h", test_name, redirect_pc, expected_pc);
                error_count = error_count + 1;
            end else begin
                $display("ok   %0s", test_name);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Casos
    // -------------------------------------------------------------------------
    initial begin
        // ---- beq / bne --------------------------------------------------------
        drive_branch(`FUNCT3_BEQ, 32'd7, 32'd7);
        check("beq con operandos iguales", 1'b1, 32'h0000_0050);

        drive_branch(`FUNCT3_BEQ, 32'd7, 32'd8);
        check("beq con operandos distintos", 1'b0, 32'bx);

        drive_branch(`FUNCT3_BNE, 32'd7, 32'd8);
        check("bne con operandos distintos", 1'b1, 32'h0000_0050);

        drive_branch(`FUNCT3_BNE, 32'd7, 32'd7);
        check("bne con operandos iguales", 1'b0, 32'bx);

        // La igualdad mira los 32 bits
        drive_branch(`FUNCT3_BEQ, 32'h8000_0000, 32'h0000_0000);
        check("beq: difieren solo en el bit 31", 1'b0, 32'bx);

        drive_branch(`FUNCT3_BEQ, 32'h0000_0001, 32'h0000_0000);
        check("beq: difieren solo en el bit 0", 1'b0, 32'bx);

        drive_branch(`FUNCT3_BEQ, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check("beq con todos los bits en uno", 1'b1, 32'h0000_0050);

        // ---- Destino relativo -------------------------------------------------
        drive_branch(`FUNCT3_BEQ, 32'd1, 32'd1);
        immediate = -32'sd16;
        check("branch hacia atras (inmediato negativo)", 1'b1, 32'h0000_0030);

        drive_branch(`FUNCT3_BEQ, 32'd1, 32'd1);
        pc        = 32'h0000_0100;
        immediate = 32'h0000_0FFC;
        check("branch hacia adelante lejano", 1'b1, 32'h0000_10FC);

        // ---- Una igualdad sin branch no cambia el flujo -----------------------
        drive_idle;
        rs1_value = 32'd5;
        rs2_value = 32'd5;
        check("operandos iguales sin ser branch", 1'b0, 32'bx);

        // ---- jal --------------------------------------------------------------
        drive_jal;
        check("jal salta siempre", 1'b1, 32'h0000_0050);

        drive_jal;
        immediate = -32'sd8;
        check("jal hacia atras", 1'b1, 32'h0000_0038);

        // ---- jalr -------------------------------------------------------------
        drive_jalr(32'h0000_0200);
        check("jalr usa el resultado de la ALU", 1'b1, 32'h0000_0200);

        drive_jalr(32'h0000_0201);
        check("jalr anula el bit 0 del destino", 1'b1, 32'h0000_0200);

        drive_jalr(32'hFFFF_FFFF);
        check("jalr anula el bit 0 con todos en uno", 1'b1, 32'hFFFF_FFFE);

        // ---- Una instruccion invalida no cambia el flujo ----------------------
        drive_branch(`FUNCT3_BEQ, 32'd3, 32'd3);
        valid = 1'b0;
        check("branch invalido (burbuja)", 1'b0, 32'bx);

        drive_jal;
        valid = 1'b0;
        check("jal invalido (burbuja)", 1'b0, 32'bx);

        drive_jalr(32'h0000_0200);
        valid = 1'b0;
        check("jalr invalido (burbuja)", 1'b0, 32'bx);

        // ---- Resumen ----------------------------------------------------------
        if (error_count == 0)
            $display("\nbranch_unit_tb: PASS (%0d casos)", test_count);
        else
            $display("\nbranch_unit_tb: FAIL (%0d de %0d casos)", error_count, test_count);
        $finish;
    end

endmodule
