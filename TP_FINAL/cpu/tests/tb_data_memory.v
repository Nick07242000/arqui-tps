`timescale 1ns / 1ps

module tb_data_memory;

    reg         clk = 0;
    reg         mem_write = 0;
    reg         read_enable = 0;
    reg  [2:0]  funct3 = 0;
    reg  [9:0]  word_addr = 0;
    reg  [1:0]  byte_offset = 0;
    reg  [31:0] store_data = 0;
    reg  [9:0]  debug_addr = 0;

    wire [3:0]  write_byte_enable;
    wire [31:0] formatted_write_data;
    wire [31:0] raw_word;
    wire [31:0] load_data;
    wire [31:0] debug_data;

    integer error_count = 0;

    store_data_formatter formatter (
        .i_mem_write(mem_write),
        .i_funct3(funct3),
        .i_byte_offset(byte_offset),
        .i_store_data(store_data),
        .o_write_byte_enable(write_byte_enable),
        .o_write_data(formatted_write_data)
    );

    data_memory dut (
        .i_clk(clk),
        .i_read_enable(read_enable),
        .i_word_addr(word_addr),
        .i_write_byte_enable(write_byte_enable),
        .i_write_data(formatted_write_data),
        .o_read_data(raw_word),
        .i_debug_word_addr(debug_addr),
        .o_debug_read_data(debug_data)
    );

    load_data_extender extender (
        .i_funct3(funct3),
        .i_byte_offset(byte_offset),
        .i_raw_word(raw_word),
        .o_load_data(load_data)
    );

    always #5 clk = ~clk;

    localparam SB = 3'b000, SH = 3'b001, SW = 3'b010;
    localparam LB = 3'b000, LH = 3'b001, LW = 3'b010, LBU = 3'b100, LHU = 3'b101;

    task check(input [511:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL %0s: obtenido=%h esperado=%h", name, actual, expected);
            end else
                $display("ok   %0s", name);
        end
    endtask

    task store(input [2:0] op, input [9:0] addr, input [1:0] offset, input [31:0] data);
        begin
            mem_write = 1; funct3 = op; word_addr = addr;
            byte_offset = offset; store_data = data;
            @(posedge clk); #1 mem_write = 0;
        end
    endtask

    task load(input [2:0] op, input [9:0] addr, input [1:0] offset);
        begin
            read_enable = 1; funct3 = op; word_addr = addr; byte_offset = offset;
            @(posedge clk); #1 read_enable = 0;
        end
    endtask

    initial begin
        // sw / lw
        store(SW, 10'd0, 2'd0, 32'hDEADBEEF);
        load(LW, 10'd0, 2'd0);
        check("sw/lw", load_data, 32'hDEADBEEF);

        // sb en los 4 carriles
        store(SW, 10'd1, 2'd0, 32'h0);
        store(SB, 10'd1, 2'd0, 32'hAABBCC11);
        store(SB, 10'd1, 2'd1, 32'hAABBCC22);
        store(SB, 10'd1, 2'd2, 32'hAABBCC33);
        store(SB, 10'd1, 2'd3, 32'hAABBCC80);
        load(LW, 10'd1, 2'd0);
        check("sb x4 -> lw", load_data, 32'h80332211);
        load(LBU, 10'd1, 2'd0); check("lbu offset 0", load_data, 32'h00000011);
        load(LBU, 10'd1, 2'd1); check("lbu offset 1", load_data, 32'h00000022);
        load(LBU, 10'd1, 2'd2); check("lbu offset 2", load_data, 32'h00000033);
        load(LBU, 10'd1, 2'd3); check("lbu offset 3", load_data, 32'h00000080);
        load(LB,  10'd1, 2'd3); check("lb signo",      load_data, 32'hFFFFFF80);
        load(LB,  10'd1, 2'd2); check("lb positivo",   load_data, 32'h00000033);

        // sh en ambas mitades
        store(SW, 10'd2, 2'd0, 32'h0);
        store(SH, 10'd2, 2'd0, 32'h0000BEEF);
        store(SH, 10'd2, 2'd2, 32'h00001234);
        load(LW,  10'd2, 2'd0); check("sh x2 -> lw", load_data, 32'h1234BEEF);
        load(LH,  10'd2, 2'd0); check("lh signo",    load_data, 32'hFFFFBEEF);
        load(LHU, 10'd2, 2'd0); check("lhu inferior", load_data, 32'h0000BEEF);
        load(LH,  10'd2, 2'd2); check("lh positivo", load_data, 32'h00001234);
        load(LHU, 10'd2, 2'd2); check("lhu superior", load_data, 32'h00001234);

        // Los stores parciales no tocan los otros bytes
        store(SW, 10'd3, 2'd0, 32'hFFFFFFFF);
        store(SB, 10'd3, 2'd2, 32'h0);
        load(LW,  10'd3, 2'd0); check("sb preserva vecinos", load_data, 32'hFF00FFFF);
        store(SW, 10'd4, 2'd0, 32'hFFFFFFFF);
        store(SH, 10'd4, 2'd2, 32'h0);
        load(LW,  10'd4, 2'd0); check("sh preserva mitad baja", load_data, 32'h0000FFFF);

        // Desalineado fuera de contrato: se alinea hacia abajo
        store(SW, 10'd5, 2'd0, 32'h0);
        store(SH, 10'd5, 2'd1, 32'h0000ABCD);
        load(LW,  10'd5, 2'd0); check("sh desalineado alinea abajo", load_data, 32'h0000ABCD);

        // Limites de direccion
        store(SW, 10'd1023, 2'd0, 32'hCAFEF00D);
        load(LW,  10'd1023, 2'd0); check("palabra 1023", load_data, 32'hCAFEF00D);
        load(LW,  10'd0, 2'd0);    check("palabra 0 intacta", load_data, 32'hDEADBEEF);

        // Sin mem_write no escribe
        mem_write = 0; funct3 = SW; word_addr = 10'd0; store_data = 32'h0;
        @(posedge clk); #1;
        load(LW, 10'd0, 2'd0); check("sin mem_write no escribe", load_data, 32'hDEADBEEF);

        // funct3 invalido en store: no escribe
        store(3'b111, 10'd0, 2'd0, 32'h0);
        load(LW, 10'd0, 2'd0); check("funct3 invalido no escribe", load_data, 32'hDEADBEEF);

        // Sin read_enable la salida se conserva
        word_addr = 10'd1; funct3 = LW;
        @(posedge clk); #1;
        check("sin read_enable conserva", raw_word, 32'hDEADBEEF);

        // Puerto B: lectura de debug y aislamiento del puerto A
        debug_addr = 10'd2;
        @(posedge clk); #1;
        check("puerto B lee palabra 2", debug_data, 32'h1234BEEF);
        check("puerto B no altera puerto A", raw_word, 32'hDEADBEEF);
        debug_addr = 10'd1023;
        @(posedge clk); #1;
        check("puerto B lee palabra 1023", debug_data, 32'hCAFEF00D);

        // Escritura de A visible en B
        store(SW, 10'd10, 2'd0, 32'h0A0B0C0D);
        debug_addr = 10'd10;
        @(posedge clk); #1;
        check("escritura A visible en B", debug_data, 32'h0A0B0C0D);

        if (error_count == 0) $display("TB data_memory: TODAS LAS PRUEBAS PASARON");
        else                  $display("TB data_memory: %0d FALLAS", error_count);
        $finish;
    end

endmodule
