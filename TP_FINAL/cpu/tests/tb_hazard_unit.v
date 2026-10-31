`timescale 1ns / 1ps

module tb_hazard_unit;

    reg        if_id_valid;
    reg  [4:0] id_rs1_addr;
    reg  [4:0] id_rs2_addr;
    reg        id_uses_rs1;
    reg        id_uses_rs2;
    reg        id_ex_valid;
    reg        id_ex_mem_read;
    reg  [4:0] id_ex_rd_addr;
    wire       stall;

    integer error_count = 0;

    hazard_unit dut (
        .i_if_id_valid    (if_id_valid),
        .i_id_rs1_addr    (id_rs1_addr),
        .i_id_rs2_addr    (id_rs2_addr),
        .i_id_uses_rs1    (id_uses_rs1),
        .i_id_uses_rs2    (id_uses_rs2),
        .i_id_ex_valid    (id_ex_valid),
        .i_id_ex_mem_read (id_ex_mem_read),
        .i_id_ex_rd_addr  (id_ex_rd_addr),
        .o_stall          (stall)
    );

    // Estado base: ID lee x5 y x6; EX tiene un load valido a x5 (hay dependencia)
    task set_load_use_on_rs1;
    begin
        if_id_valid    = 1'b1;
        id_rs1_addr    = 5'd5;
        id_rs2_addr    = 5'd6;
        id_uses_rs1    = 1'b1;
        id_uses_rs2    = 1'b1;
        id_ex_valid    = 1'b1;
        id_ex_mem_read = 1'b1;
        id_ex_rd_addr  = 5'd5;
    end
    endtask

    task expect_stall(input [8*48-1:0] case_name, input expected_stall);
    begin
        #1;
        if (stall !== expected_stall) begin
            $display("[FAIL] %0s: stall=%b (esperado %b)", case_name, stall, expected_stall);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] %0s", case_name);
        end
    end
    endtask

    initial begin
        set_load_use_on_rs1;
        expect_stall("load en EX, coincide rs1", 1'b1);

        set_load_use_on_rs1; id_ex_rd_addr = 5'd6;
        expect_stall("load en EX, coincide rs2", 1'b1);

        set_load_use_on_rs1; id_rs2_addr = 5'd5;
        expect_stall("load en EX, coinciden rs1 y rs2", 1'b1);

        set_load_use_on_rs1; id_ex_mem_read = 1'b0;
        expect_stall("la instruccion en EX no es un load", 1'b0);

        set_load_use_on_rs1; id_ex_rd_addr = 5'd7;
        expect_stall("load a un registro que ID no lee", 1'b0);

        set_load_use_on_rs1; id_rs1_addr = 5'd0; id_ex_rd_addr = 5'd0;
        expect_stall("load a x0 no genera dependencia", 1'b0);

        set_load_use_on_rs1; id_uses_rs1 = 1'b0;
        expect_stall("rs1 coincide pero no es fuente", 1'b0);

        set_load_use_on_rs1; id_ex_rd_addr = 5'd6; id_uses_rs2 = 1'b0;
        expect_stall("rs2 coincide pero no es fuente", 1'b0);

        set_load_use_on_rs1; if_id_valid = 1'b0;
        expect_stall("IF/ID invalido (residuo de memoria)", 1'b0);

        set_load_use_on_rs1; id_ex_valid = 1'b0;
        expect_stall("burbuja en ID/EX", 1'b0);

        if (error_count == 0) $display("hazard_unit_tb: TODOS LOS CASOS PASARON");
        else                  $display("hazard_unit_tb: %0d CASOS FALLARON", error_count);
        $finish;
    end

endmodule
