`timescale 1ns / 1ps

module tb_program_memory;

    reg         clk = 0;
    reg         read_enable = 0;
    reg  [9:0]  read_word_addr = 0;
    wire [31:0] read_data;
    reg         write_enable = 0;
    reg  [9:0]  write_word_addr = 0;
    reg  [31:0] write_data = 0;

    integer error_count = 0;
    integer word_index;

    program_memory dut (
        .i_clk(clk),
        .i_read_enable(read_enable),
        .i_read_word_addr(read_word_addr),
        .o_read_data(read_data),
        .i_write_enable(write_enable),
        .i_write_word_addr(write_word_addr),
        .i_write_data(write_data)
    );

    always #5 clk = ~clk;

    task check(input [511:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL %0s: obtenido=%h esperado=%h", name, actual, expected);
            end else
                $display("ok   %0s", name);
        end
    endtask

    task write_word(input [9:0] addr, input [31:0] data);
        begin
            write_enable = 1; write_word_addr = addr; write_data = data;
            @(posedge clk); #1 write_enable = 0;
        end
    endtask

    task read_word(input [9:0] addr);
        begin
            read_enable = 1; read_word_addr = addr;
            @(posedge clk); #1 read_enable = 0;
        end
    endtask

    initial begin
        // Escritura y lectura de una palabra
        write_word(10'd0, 32'h00500093);
        read_word(10'd0);
        check("lectura direccion 0", read_data, 32'h00500093);

        // Limites del espacio de direcciones
        write_word(10'd1023, 32'hCAFEBABE);
        read_word(10'd1023);
        check("lectura direccion 1023", read_data, 32'hCAFEBABE);

        // Secuencia de palabras
        for (word_index = 0; word_index < 16; word_index = word_index + 1)
            write_word(word_index, 32'h1000_0000 + word_index);
        for (word_index = 0; word_index < 16; word_index = word_index + 1) begin
            read_word(word_index);
            check("secuencia", read_data, 32'h1000_0000 + word_index);
        end

        // Sin enable la salida se conserva
        read_word_addr = 10'd3;
        @(posedge clk); #1;
        check("sin enable conserva salida", read_data, 32'h1000_000F);

        // Sobrescritura
        write_word(10'd5, 32'hAAAA5555);
        read_word(10'd5);
        check("sobrescritura", read_data, 32'hAAAA5555);

        // Lectura y escritura simultanea en la misma direccion: dato viejo
        read_enable = 1; read_word_addr = 10'd5;
        write_enable = 1; write_word_addr = 10'd5; write_data = 32'h12345678;
        @(posedge clk); #1 read_enable = 0; write_enable = 0;
        check("lectura simultanea devuelve dato viejo", read_data, 32'hAAAA5555);
        read_word(10'd5);
        check("dato nuevo en lectura posterior", read_data, 32'h12345678);

        // Escritura sin write_enable no modifica
        write_enable = 0; write_word_addr = 10'd6; write_data = 32'hFFFFFFFF;
        @(posedge clk); #1;
        read_word(10'd6);
        check("sin write_enable no escribe", read_data, 32'h1000_0006);

        // La escritura funciona con la lectura deshabilitada (CPU detenida)
        write_word(10'd7, 32'h0BADF00D);
        read_word(10'd7);
        check("escritura con CPU detenida", read_data, 32'h0BADF00D);

        if (error_count == 0) $display("TB program_memory: TODAS LAS PRUEBAS PASARON");
        else                  $display("TB program_memory: %0d FALLAS", error_count);
        $finish;
    end

endmodule
