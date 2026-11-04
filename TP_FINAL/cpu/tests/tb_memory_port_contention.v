`timescale 1ns / 1ps

module tb_memory_port_contention;

    localparam ADDR_WIDTH = 10;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    `include "test_check_helpers.vh"

    // ---- program_memory: lectura (CPU) y escritura (Debug Unit) ---------------
    reg                  program_read_enable  = 1'b0;
    reg  [ADDR_WIDTH-1:0] program_read_addr   = 0;
    wire [31:0]          program_read_data;
    reg                  program_write_enable = 1'b0;
    reg  [ADDR_WIDTH-1:0] program_write_addr  = 0;
    reg  [31:0]          program_write_data   = 0;

    program_memory #(.ADDR_WIDTH(ADDR_WIDTH)) program_mem (
        .i_clk             (clk),
        .i_read_enable     (program_read_enable),
        .i_read_word_addr  (program_read_addr),
        .o_read_data       (program_read_data),
        .i_write_enable    (program_write_enable),
        .i_write_word_addr (program_write_addr),
        .i_write_data      (program_write_data)
    );

    // ---- data_memory: puerto A (CPU) y puerto B (Debug Unit) ------------------
    reg                  data_read_enable     = 1'b0;
    reg  [ADDR_WIDTH-1:0] data_word_addr      = 0;
    reg  [3:0]           data_write_byte_enable = 4'b0000;
    reg  [31:0]          data_write_data      = 0;
    wire [31:0]          data_read_data;
    reg  [ADDR_WIDTH-1:0] debug_word_addr     = 0;
    wire [31:0]          debug_read_data;

    data_memory #(.ADDR_WIDTH(ADDR_WIDTH)) data_mem (
        .i_clk               (clk),
        .i_read_enable       (data_read_enable),
        .i_word_addr         (data_word_addr),
        .i_write_byte_enable (data_write_byte_enable),
        .i_write_data        (data_write_data),
        .o_read_data         (data_read_data),
        .i_debug_word_addr   (debug_word_addr),
        .o_debug_read_data   (debug_read_data)
    );

    // -------------------------------------------------------------------------
    // Acciones de un ciclo: se aplican en un flanco de bajada y se observan en el
    // siguiente, con exactamente un flanco de subida en el medio
    // -------------------------------------------------------------------------
    task write_program_word(input [ADDR_WIDTH-1:0] i_addr, input [31:0] i_data);
        begin
            program_write_enable = 1'b1;
            program_write_addr   = i_addr;
            program_write_data   = i_data;
            @(negedge clk);
            program_write_enable = 1'b0;
        end
    endtask

    task write_data_word(input [ADDR_WIDTH-1:0] i_addr, input [31:0] i_data);
        begin
            data_word_addr         = i_addr;
            data_write_data        = i_data;
            data_write_byte_enable = 4'b1111;
            @(negedge clk);
            data_write_byte_enable = 4'b0000;
        end
    endtask

    // -------------------------------------------------------------------------
    // program_memory
    // -------------------------------------------------------------------------
    task test_program_memory_same_address_read_and_write;
        begin
            $display("\n[M1] program_memory: lectura y escritura de la misma direccion en un ciclo");
            write_program_word(10'd5, 32'hAAAA0005);

            // Mismo ciclo: la CPU lee la direccion 5 mientras la DU la reescribe
            program_read_enable  = 1'b1;
            program_read_addr    = 10'd5;
            program_write_enable = 1'b1;
            program_write_addr   = 10'd5;
            program_write_data   = 32'hBBBB0005;
            @(negedge clk);
            program_write_enable = 1'b0;
            check_equal("lectura del mismo ciclo devuelve el dato viejo", program_read_data, 32'hAAAA0005);

            @(negedge clk);
            check_equal("la lectura siguiente devuelve el dato nuevo", program_read_data, 32'hBBBB0005);
            program_read_enable = 1'b0;
        end
    endtask

    task test_program_memory_write_does_not_touch_output_register;
        begin
            $display("\n[M2] program_memory: escribir con la lectura deshabilitada no altera la salida");
            write_program_word(10'd6, 32'hAAAA0006);

            program_read_enable = 1'b1;
            program_read_addr   = 10'd6;
            @(negedge clk);
            program_read_enable = 1'b0;
            check_equal("instruccion registrada tras leer la direccion 6", program_read_data, 32'hAAAA0006);

            // CPU pausada: la DU reescribe justo la direccion que se acaba de leer
            write_program_word(10'd6, 32'hBBBB0006);
            check_equal("la salida registrada no cambia por la escritura", program_read_data, 32'hAAAA0006);
        end
    endtask

    task test_program_memory_different_addresses_are_independent;
        begin
            $display("\n[M3] program_memory: escritura y lectura de direcciones distintas en un ciclo");
            write_program_word(10'd8, 32'hAAAA0008);

            program_read_enable  = 1'b1;
            program_read_addr    = 10'd8;
            program_write_enable = 1'b1;
            program_write_addr   = 10'd7;
            program_write_data   = 32'hBBBB0007;
            @(negedge clk);
            program_write_enable = 1'b0;
            check_equal("la lectura de la direccion 8 no se ve afectada", program_read_data, 32'hAAAA0008);

            program_read_addr = 10'd7;
            @(negedge clk);
            program_read_enable = 1'b0;
            check_equal("la direccion 7 quedo escrita", program_read_data, 32'hBBBB0007);
        end
    endtask

    // -------------------------------------------------------------------------
    // data_memory
    // -------------------------------------------------------------------------
    task test_data_memory_port_a_read_and_write_same_word;
        begin
            $display("\n[M4] data_memory: el puerto A lee y escribe la misma palabra en un ciclo");
            write_data_word(10'd3, 32'hAAAAAAAA);

            data_read_enable       = 1'b1;
            data_word_addr         = 10'd3;
            data_write_data        = 32'h11223344;
            data_write_byte_enable = 4'b1111;
            @(negedge clk);
            data_write_byte_enable = 4'b0000;
            check_equal("lectura del mismo ciclo devuelve el dato viejo", data_read_data, 32'hAAAAAAAA);

            @(negedge clk);
            data_read_enable = 1'b0;
            check_equal("la lectura siguiente devuelve el dato nuevo", data_read_data, 32'h11223344);
        end
    endtask

    task test_data_memory_port_b_read_while_port_a_writes_same_word;
        begin
            $display("\n[M5] data_memory: el puerto B lee la palabra que el puerto A escribe");
            write_data_word(10'd4, 32'hAAAAAAAA);

            data_word_addr         = 10'd4;
            data_write_data        = 32'h55667788;
            data_write_byte_enable = 4'b1111;
            debug_word_addr        = 10'd4;
            @(negedge clk);
            data_write_byte_enable = 4'b0000;
            check_equal("puerto B del mismo ciclo devuelve el dato viejo", debug_read_data, 32'hAAAAAAAA);

            @(negedge clk);
            check_equal("puerto B del ciclo siguiente devuelve el dato nuevo", debug_read_data, 32'h55667788);
        end
    endtask

    task test_data_memory_port_b_does_not_disturb_port_a_output;
        integer sweep_index;
        begin
            $display("\n[M6] data_memory: las lecturas del puerto B no alteran la salida del puerto A");
            write_data_word(10'd12, 32'h12121212);
            write_data_word(10'd15, 32'h15151515);

            data_read_enable = 1'b1;
            data_word_addr   = 10'd12;
            @(negedge clk);
            data_read_enable = 1'b0;
            check_equal("dato leido por el puerto A", data_read_data, 32'h12121212);

            // La DU recorre posiciones mientras el puerto A queda sin leer
            for (sweep_index = 10; sweep_index < 16; sweep_index = sweep_index + 1) begin
                debug_word_addr = sweep_index;
                @(negedge clk);
            end
            check_equal("salida del puerto A tras el barrido del puerto B", data_read_data, 32'h12121212);
            check_equal("puerto B sigue leyendo bien la ultima posicion (15)", debug_read_data, 32'h15151515);
        end
    endtask

    task test_data_memory_byte_enable_with_concurrent_port_b_read;
        begin
            $display("\n[M7] data_memory: store de un byte mientras el puerto B lee la misma palabra");
            write_data_word(10'd14, 32'hFFFFFFFF);

            data_word_addr         = 10'd14;
            data_write_data        = 32'h00AA0000;
            data_write_byte_enable = 4'b0100;
            debug_word_addr        = 10'd14;
            @(negedge clk);
            data_write_byte_enable = 4'b0000;
            check_equal("puerto B del mismo ciclo devuelve la palabra vieja", debug_read_data, 32'hFFFFFFFF);

            @(negedge clk);
            check_equal("solo cambio el byte 2 de la palabra", debug_read_data, 32'hFFAAFFFF);
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia de pruebas
    // -------------------------------------------------------------------------
    initial begin
        @(negedge clk);

        test_program_memory_same_address_read_and_write;
        test_program_memory_write_does_not_touch_output_register;
        test_program_memory_different_addresses_are_independent;
        test_data_memory_port_a_read_and_write_same_word;
        test_data_memory_port_b_read_while_port_a_writes_same_word;
        test_data_memory_port_b_does_not_disturb_port_a_output;
        test_data_memory_byte_enable_with_concurrent_port_b_read;

        print_summary;
        $finish;
    end

    // Evita que una prueba colgada deje la simulacion corriendo para siempre
    initial begin
        #100000;
        $display("TIMEOUT: la simulacion no termino");
        $finish;
    end

endmodule
