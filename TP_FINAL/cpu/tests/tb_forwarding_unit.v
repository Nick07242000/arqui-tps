`timescale 1ns / 1ps
`include "forwarding_defs.vh"

module tb_forwarding_unit;

    reg  [4:0] id_ex_rs1_addr;
    reg  [4:0] id_ex_rs2_addr;
    reg        ex_mem_valid;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read;
    reg  [4:0] ex_mem_rd_addr;
    reg        mem_wb_valid;
    reg        mem_wb_reg_write;
    reg  [4:0] mem_wb_rd_addr;
    wire [1:0] forward_a_select;
    wire [1:0] forward_b_select;

    integer error_count = 0;

    forwarding_unit dut (
        .i_id_ex_rs1_addr   (id_ex_rs1_addr),
        .i_id_ex_rs2_addr   (id_ex_rs2_addr),
        .i_ex_mem_valid     (ex_mem_valid),
        .i_ex_mem_reg_write (ex_mem_reg_write),
        .i_ex_mem_mem_read  (ex_mem_mem_read),
        .i_ex_mem_rd_addr   (ex_mem_rd_addr),
        .i_mem_wb_valid     (mem_wb_valid),
        .i_mem_wb_reg_write (mem_wb_reg_write),
        .i_mem_wb_rd_addr   (mem_wb_rd_addr),
        .o_forward_a_select (forward_a_select),
        .o_forward_b_select (forward_b_select)
    );

    // Estado base: EX lee x1 y x2, ninguna otra etapa produce un dato
    task clear_producers;
    begin
        id_ex_rs1_addr   = 5'd1;
        id_ex_rs2_addr   = 5'd2;
        ex_mem_valid     = 1'b0;
        ex_mem_reg_write = 1'b0;
        ex_mem_mem_read  = 1'b0;
        ex_mem_rd_addr   = 5'd0;
        mem_wb_valid     = 1'b0;
        mem_wb_reg_write = 1'b0;
        mem_wb_rd_addr   = 5'd0;
    end
    endtask

    // Instruccion ALU valida en MEM que escribe rd_addr
    task set_ex_mem_producer(input [4:0] rd_addr);
    begin
        ex_mem_valid     = 1'b1;
        ex_mem_reg_write = 1'b1;
        ex_mem_mem_read  = 1'b0;
        ex_mem_rd_addr   = rd_addr;
    end
    endtask

    // Instruccion valida en WB que escribe rd_addr
    task set_mem_wb_producer(input [4:0] rd_addr);
    begin
        mem_wb_valid     = 1'b1;
        mem_wb_reg_write = 1'b1;
        mem_wb_rd_addr   = rd_addr;
    end
    endtask

    task expect_select(input [8*48-1:0] case_name,
                       input [1:0]      expected_a,
                       input [1:0]      expected_b);
    begin
        #1;
        if (forward_a_select !== expected_a || forward_b_select !== expected_b) begin
            $display("[FAIL] %0s: A=%b (esperado %b), B=%b (esperado %b)",
                     case_name, forward_a_select, expected_a,
                     forward_b_select, expected_b);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] %0s", case_name);
        end
    end
    endtask

    initial begin
        clear_producers;
        expect_select("sin productores", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; set_ex_mem_producer(1);
        expect_select("EX/MEM produce rs1", `FORWARD_FROM_EX_MEM, `FORWARD_NONE);

        clear_producers; set_mem_wb_producer(2);
        expect_select("MEM/WB produce rs2", `FORWARD_NONE, `FORWARD_FROM_MEM_WB);

        clear_producers; set_ex_mem_producer(1); set_mem_wb_producer(2);
        expect_select("EX/MEM produce rs1 y MEM/WB produce rs2",
                      `FORWARD_FROM_EX_MEM, `FORWARD_FROM_MEM_WB);

        clear_producers; set_ex_mem_producer(1); set_mem_wb_producer(1);
        expect_select("mismo destino: gana EX/MEM sobre MEM/WB",
                      `FORWARD_FROM_EX_MEM, `FORWARD_NONE);

        clear_producers; id_ex_rs2_addr = 5'd1; set_ex_mem_producer(1);
        expect_select("rs1 y rs2 son el mismo registro",
                      `FORWARD_FROM_EX_MEM, `FORWARD_FROM_EX_MEM);

        clear_producers; set_ex_mem_producer(1); ex_mem_mem_read = 1'b1;
        expect_select("load en EX/MEM no se adelanta", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; set_ex_mem_producer(1); ex_mem_valid = 1'b0;
        expect_select("burbuja en EX/MEM", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; set_ex_mem_producer(1); ex_mem_reg_write = 1'b0;
        expect_select("EX/MEM no escribe registro", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; set_mem_wb_producer(1); mem_wb_valid = 1'b0;
        expect_select("burbuja en MEM/WB", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; set_mem_wb_producer(1); mem_wb_reg_write = 1'b0;
        expect_select("MEM/WB no escribe registro", `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; id_ex_rs1_addr = 5'd0; set_ex_mem_producer(0);
        expect_select("destino x0 no se adelanta desde EX/MEM",
                      `FORWARD_NONE, `FORWARD_NONE);

        clear_producers; id_ex_rs1_addr = 5'd0; set_mem_wb_producer(0);
        expect_select("destino x0 no se adelanta desde MEM/WB",
                      `FORWARD_NONE, `FORWARD_NONE);

        if (error_count == 0) $display("forwarding_unit_tb: TODOS LOS CASOS PASARON");
        else                  $display("forwarding_unit_tb: %0d CASOS FALLARON", error_count);
        $finish;
    end

endmodule
