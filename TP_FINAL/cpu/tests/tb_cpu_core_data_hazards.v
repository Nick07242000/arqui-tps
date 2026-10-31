`timescale 1ns / 1ps
`include "riscv_defs.vh"

module tb_cpu_core_data_hazards;

    localparam CLK_PERIOD_NS = 10;
    localparam RUN_CYCLES    = 20;     // sobra para programas de hasta 8 instrucciones
    localparam CLEARED_WORDS = 32;     // imem a cero tras el programa: no hay HALT todavia

    // -------------------------------------------------------------------------
    // Clock, estimulos y conexiones
    // -------------------------------------------------------------------------
    reg         clk                  = 1'b0;
    reg         cpu_reset            = 1'b0;
    reg         cpu_en               = 1'b0;
    reg  [4:0]  debug_reg_addr       = 5'b0;
    reg         imem_write_enable    = 1'b0;
    reg  [9:0]  imem_write_word_addr = 10'b0;
    reg  [31:0] imem_write_data      = 32'b0;
    reg  [9:0]  debug_dmem_word_addr = 10'b0;

    wire        imem_read_enable;
    wire [9:0]  imem_word_addr;
    wire [31:0] imem_read_data;
    wire        dmem_read_enable;
    wire [9:0]  dmem_word_addr;
    wire [3:0]  dmem_write_byte_enable;
    wire [31:0] dmem_write_data;
    wire [31:0] dmem_read_data;
    wire [31:0] debug_reg_data;
    wire [31:0] debug_dmem_read_data;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    cpu_core dut (
        .i_clk                    (clk),
        .i_cpu_reset              (cpu_reset),
        .i_cpu_en                 (cpu_en),
        .o_imem_read_enable       (imem_read_enable),
        .o_imem_word_addr         (imem_word_addr),
        .i_imem_read_data         (imem_read_data),
        .o_dmem_read_enable       (dmem_read_enable),
        .o_dmem_word_addr         (dmem_word_addr),
        .o_dmem_write_byte_enable (dmem_write_byte_enable),
        .o_dmem_write_data        (dmem_write_data),
        .i_dmem_read_data         (dmem_read_data),
        .i_debug_reg_addr         (debug_reg_addr),
        .o_debug_reg_data         (debug_reg_data)
    );

    program_memory imem (
        .i_clk             (clk),
        .i_read_enable     (imem_read_enable),
        .i_read_word_addr  (imem_word_addr),
        .o_read_data       (imem_read_data),
        .i_write_enable    (imem_write_enable),
        .i_write_word_addr (imem_write_word_addr),
        .i_write_data      (imem_write_data)
    );

    data_memory dmem (
        .i_clk                (clk),
        .i_read_enable        (dmem_read_enable),
        .i_word_addr          (dmem_word_addr),
        .i_write_byte_enable  (dmem_write_byte_enable),
        .i_write_data         (dmem_write_data),
        .o_read_data          (dmem_read_data),
        .i_debug_word_addr    (debug_dmem_word_addr),
        .o_debug_read_data    (debug_dmem_read_data)
    );

    // -------------------------------------------------------------------------
    // Contadores de eventos (se reinician con cada reset del CPU)
    // -------------------------------------------------------------------------
    integer stall_count;
    integer register_write_count;
    integer store_count;

    always @(posedge clk) begin
        if (cpu_reset) begin
            stall_count          <= 0;
            register_write_count <= 0;
            store_count          <= 0;
        end else if (cpu_en) begin
            if (dut.load_use_stall)
                stall_count <= stall_count + 1;
            if (dut.wb_register_write_enable && dut.wb_register_write_addr != 5'b0)
                register_write_count <= register_write_count + 1;
            if (dmem_write_byte_enable != 4'b0)
                store_count <= store_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Mini ensamblador: una funcion por instruccion, en el orden del assembler
    // -------------------------------------------------------------------------
    function [31:0] asm_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        asm_add = {`FUNCT7_BASE, rs2, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_R_TYPE};
    endfunction

    function [31:0] asm_sub(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        asm_sub = {`FUNCT7_ALT, rs2, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_R_TYPE};
    endfunction

    function [31:0] asm_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        asm_addi = {imm, rs1, `FUNCT3_ADD_SUB, rd, `OPCODE_OP_IMM};
    endfunction

    function [31:0] asm_load(input [2:0] funct3, input [4:0] rd,
                             input [11:0] imm, input [4:0] rs1);
        asm_load = {imm, rs1, funct3, rd, `OPCODE_LOAD};
    endfunction

    function [31:0] asm_lw(input [4:0] rd, input [11:0] imm, input [4:0] rs1);
        asm_lw = asm_load(`FUNCT3_WORD, rd, imm, rs1);
    endfunction

    function [31:0] asm_lb(input [4:0] rd, input [11:0] imm, input [4:0] rs1);
        asm_lb = asm_load(`FUNCT3_BYTE, rd, imm, rs1);
    endfunction

    function [31:0] asm_lbu(input [4:0] rd, input [11:0] imm, input [4:0] rs1);
        asm_lbu = asm_load(`FUNCT3_BYTE_U, rd, imm, rs1);
    endfunction

    function [31:0] asm_sw(input [4:0] rs2, input [11:0] imm, input [4:0] rs1);
        asm_sw = {imm[11:5], rs2, rs1, `FUNCT3_WORD, imm[4:0], `OPCODE_STORE};
    endfunction

    // -------------------------------------------------------------------------
    // Carga y ejecucion de un programa
    // -------------------------------------------------------------------------
    integer program_length;
    integer error_count = 0;
    integer test_first_error_count;
    reg [8*64-1:0] test_name;

    // Escribe una instruccion en la siguiente direccion de la memoria de programa
    task emit(input [31:0] instruction);
    begin
        imem_write_enable    = 1'b1;
        imem_write_word_addr = program_length;
        imem_write_data      = instruction;
        @(negedge clk);
        imem_write_enable    = 1'b0;
        program_length       = program_length + 1;
    end
    endtask

    task start_test(input [8*64-1:0] name);
        integer word_index;
    begin
        test_name              = name;
        test_first_error_count = error_count;
        program_length         = 0;
        for (word_index = 0; word_index < CLEARED_WORDS; word_index = word_index + 1)
            emit(32'h0000_0000);
        program_length = 0;
    end
    endtask

    task run_program;
    begin
        cpu_reset = 1'b1;
        @(negedge clk);
        cpu_reset = 1'b0;
        cpu_en    = 1'b1;
        repeat (RUN_CYCLES) @(negedge clk);
        cpu_en    = 1'b0;
    end
    endtask

    task finish_test;
    begin
        if (error_count == test_first_error_count) $display("[PASS] %0s", test_name);
        else                                       $display("[FAIL] %0s", test_name);
    end
    endtask

    // -------------------------------------------------------------------------
    // Verificaciones
    // -------------------------------------------------------------------------
    task expect_register(input [4:0] register_index, input [31:0] expected_value);
    begin
        debug_reg_addr = register_index;
        #1;
        if (debug_reg_data !== expected_value) begin
            $display("       x%0d = 0x%08h, esperado 0x%08h",
                     register_index, debug_reg_data, expected_value);
            error_count = error_count + 1;
        end
    end
    endtask

    task expect_memory_word(input [9:0] word_addr, input [31:0] expected_value);
    begin
        debug_dmem_word_addr = word_addr;
        @(negedge clk);
        if (debug_dmem_read_data !== expected_value) begin
            $display("       dmem[%0d] = 0x%08h, esperado 0x%08h",
                     word_addr, debug_dmem_read_data, expected_value);
            error_count = error_count + 1;
        end
    end
    endtask

    task expect_stalls(input integer expected_count);
    begin
        if (stall_count !== expected_count) begin
            $display("       stalls = %0d, esperado %0d", stall_count, expected_count);
            error_count = error_count + 1;
        end
    end
    endtask

    task expect_register_writes(input integer expected_count);
    begin
        if (register_write_count !== expected_count) begin
            $display("       escrituras de registro = %0d, esperado %0d",
                     register_write_count, expected_count);
            error_count = error_count + 1;
        end
    end
    endtask

    task expect_stores(input integer expected_count);
    begin
        if (store_count !== expected_count) begin
            $display("       stores = %0d, esperado %0d", store_count, expected_count);
            error_count = error_count + 1;
        end
    end
    endtask

    // =========================================================================
    // Tests de forwarding
    // =========================================================================
    task test_forward_ex_mem_and_mem_wb;
    begin
        start_test("forwarding EX/MEM y MEM/WB en una misma instruccion");
        emit(asm_addi(1, 0, 5));
        emit(asm_addi(2, 1, 3));          // x1 desde EX/MEM
        emit(asm_add (3, 2, 1));          // x2 desde EX/MEM, x1 desde MEM/WB
        run_program;
        expect_register(1, 32'd5);
        expect_register(2, 32'd8);
        expect_register(3, 32'd13);
        expect_stalls(0);
        expect_register_writes(3);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_forward_mem_wb;
    begin
        start_test("forwarding MEM/WB (productor a distancia 2)");
        emit(asm_addi(1, 0, 7));
        emit(asm_addi(9, 0, 1));
        emit(asm_addi(2, 1, 1));
        run_program;
        expect_register(2, 32'd8);
        expect_stalls(0);
        expect_register_writes(3);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_register_file_bypass;
    begin
        start_test("bypass WB a ID del banco (productor a distancia 3)");
        emit(asm_addi(1,  0, 7));
        emit(asm_addi(9,  0, 1));
        emit(asm_addi(10, 0, 2));
        emit(asm_addi(2,  1, 1));
        run_program;
        expect_register(2, 32'd8);
        expect_stalls(0);
        expect_register_writes(4);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_dependency_chain;
    begin
        start_test("cadena de dependencias sobre el mismo registro");
        emit(asm_addi(1, 0, 1));
        emit(asm_add (1, 1, 1));          // 2
        emit(asm_add (1, 1, 1));          // 4
        emit(asm_add (1, 1, 1));          // 8
        emit(asm_add (1, 1, 1));          // 16
        run_program;
        expect_register(1, 32'd16);
        expect_stalls(0);
        expect_register_writes(5);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_most_recent_result_wins;
    begin
        start_test("varias escrituras al mismo registro: gana la mas reciente");
        emit(asm_addi(1, 0, 1));
        emit(asm_addi(1, 0, 2));
        emit(asm_addi(1, 0, 3));
        emit(asm_add (2, 1, 0));          // EX/MEM y MEM/WB escriben x1: debe usar 3
        run_program;
        expect_register(1, 32'd3);
        expect_register(2, 32'd3);
        expect_stalls(0);
        expect_register_writes(4);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_x0_is_never_forwarded;
    begin
        start_test("x0 no se adelanta ni recibe escrituras");
        emit(asm_addi(0, 0, 5));
        emit(asm_addi(1, 0, 1));          // debe leer x0 = 0, no 5
        emit(asm_add (2, 0, 1));
        run_program;
        expect_register(0, 32'd0);
        expect_register(1, 32'd1);
        expect_register(2, 32'd1);
        expect_stalls(0);
        expect_register_writes(2);
        expect_stores(0);
        finish_test;
    end
    endtask

    task test_store_address_and_data_forwarding;
    begin
        start_test("forwarding de direccion base y dato de un store");
        emit(asm_addi(1, 0, 16));
        emit(asm_addi(2, 0, 12'h02A));
        emit(asm_sw  (2, 0, 1));          // rs1 desde MEM/WB, rs2 desde EX/MEM
        run_program;
        expect_memory_word(4, 32'h0000_002A);
        expect_stalls(0);
        expect_register_writes(2);
        expect_stores(1);
        finish_test;
    end
    endtask

    // =========================================================================
    // Tests de load-use
    // =========================================================================
    task test_load_use_on_rs1;
    begin
        start_test("load-use sobre rs1: un stall y dato del load");
        emit(asm_addi(5, 0, 12'h010));
        emit(asm_addi(1, 0, 12'h040));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_sub (3, 2, 5));          // rs1 viene del load
        run_program;
        expect_register(2, 32'h40);
        expect_register(3, 32'h30);
        expect_stalls(1);
        expect_register_writes(4);
        expect_stores(1);
        finish_test;
    end
    endtask

    task test_load_use_on_rs2;
    begin
        start_test("load-use sobre rs2: un stall y orden de operandos");
        emit(asm_addi(5, 0, 12'h010));
        emit(asm_addi(1, 0, 12'h040));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_sub (3, 5, 2));          // rs2 viene del load
        run_program;
        expect_register(2, 32'h40);
        expect_register(3, 32'hFFFF_FFD0);
        expect_stalls(1);
        expect_register_writes(4);
        expect_stores(1);
        finish_test;
    end
    endtask

    task test_store_data_from_load;
    begin
        start_test("store cuyo dato viene de un load");
        emit(asm_addi(1, 0, 12'h033));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_sw  (2, 8, 0));          // rs2 viene del load
        run_program;
        expect_memory_word(0, 32'h33);
        expect_memory_word(2, 32'h33);
        expect_stalls(1);
        expect_register_writes(2);
        expect_stores(2);                 // un stall no duplica el store
        finish_test;
    end
    endtask

    task test_load_with_distance_two_has_no_stall;
    begin
        start_test("load con consumidor a distancia 2: forwarding sin stall");
        emit(asm_addi(1, 0, 12'h044));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_addi(5, 0, 1));
        emit(asm_add (3, 2, 5));          // x2 desde MEM/WB, x5 desde EX/MEM
        run_program;
        expect_register(3, 32'h45);
        expect_stalls(0);
        expect_register_writes(4);
        expect_stores(1);
        finish_test;
    end
    endtask

    task test_non_source_field_does_not_stall;
    begin
        start_test("campo que no es fuente no genera stall");
        emit(asm_addi(1, 0, 12'h044));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_addi(3, 0, 2));          // bits [24:20] = 2 = x2, pero es inmediato
        run_program;
        expect_register(2, 32'h44);
        expect_register(3, 32'd2);
        expect_stalls(0);
        expect_register_writes(3);
        expect_stores(1);
        finish_test;
    end
    endtask

    task test_load_address_from_load;
    begin
        start_test("load cuya direccion viene de otro load (stall)");
        emit(asm_addi(1, 0, 4));
        emit(asm_sw  (1, 0, 0));          // dmem[0] = 4
        emit(asm_addi(2, 0, 12'h077));
        emit(asm_sw  (2, 4, 0));          // dmem[1] = 0x77
        emit(asm_lw  (3, 0, 0));          // x3 = 4
        emit(asm_lw  (4, 0, 3));          // direccion base viene del load
        run_program;
        expect_register(3, 32'd4);
        expect_register(4, 32'h77);
        expect_stalls(1);
        expect_register_writes(4);
        expect_stores(2);
        finish_test;
    end
    endtask

    task test_stall_followed_by_forwarding;
    begin
        start_test("stall seguido de forwarding y bypass del banco");
        emit(asm_addi(1, 0, 12'h010));
        emit(asm_sw  (1, 0, 0));
        emit(asm_lw  (2, 0, 0));
        emit(asm_add (3, 2, 2));          // stall; x2 desde MEM/WB
        emit(asm_add (4, 3, 2));          // x3 desde EX/MEM, x2 por bypass WB a ID
        run_program;
        expect_register(2, 32'h10);
        expect_register(3, 32'h20);
        expect_register(4, 32'h30);
        expect_stalls(1);
        expect_register_writes(4);
        expect_stores(1);
        finish_test;
    end
    endtask

    task test_load_extension_is_forwarded;
    begin
        start_test("load-use con extension de signo y de ceros");
        emit(asm_addi(1, 0, 12'hFFF));    // x1 = -1
        emit(asm_sw  (1, 0, 0));
        emit(asm_lb  (2, 0, 0));
        emit(asm_add (3, 2, 0));          // stall; x3 = 0xFFFFFFFF
        emit(asm_lbu (4, 0, 0));
        emit(asm_add (5, 4, 0));          // stall; x5 = 0x000000FF
        run_program;
        expect_register(3, 32'hFFFF_FFFF);
        expect_register(5, 32'h0000_00FF);
        expect_stalls(2);
        expect_register_writes(5);
        expect_stores(1);
        finish_test;
    end
    endtask

    // =========================================================================
    // Secuencia principal
    // =========================================================================
    initial begin
        @(negedge clk);

        test_forward_ex_mem_and_mem_wb;
        test_forward_mem_wb;
        test_register_file_bypass;
        test_dependency_chain;
        test_most_recent_result_wins;
        test_x0_is_never_forwarded;
        test_store_address_and_data_forwarding;

        test_load_use_on_rs1;
        test_load_use_on_rs2;
        test_store_data_from_load;
        test_load_with_distance_two_has_no_stall;
        test_non_source_field_does_not_stall;
        test_load_address_from_load;
        test_stall_followed_by_forwarding;
        test_load_extension_is_forwarded;

        if (error_count == 0) $display("cpu_core_data_hazards_tb: TODOS LOS TESTS PASARON");
        else                  $display("cpu_core_data_hazards_tb: %0d ERRORES", error_count);
        $finish;
    end

endmodule
