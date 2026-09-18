`timescale 1ns/1ps

module tb_top;

    // Opcodes de la ALU usados en las pruebas
    localparam OP_ADD = 6'b100000;
    localparam OP_AND = 6'b100100;

    // Ciclos de clock por bit UART
    localparam integer CLKS_PER_BIT = 2800;
    localparam integer OVERSAMPLE_RATE = 16;

    reg clk;
    reg [7:0] sw;
    reg [3:0] btn;
    reg       uart_rx;

    wire [7:0] led;
    wire [3:0] led_aux;
    wire       uart_tx;

    reg [7:0] resp_a, resp_b, resp_op, resp_result, resp_status;
    integer errors = 0;

    top dut (
        .clk      (clk),
        .sw       (sw),
        .btn      (btn),
        .led      (led),
        .led_aux  (led_aux),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx)
    );

    always #5 clk = ~clk;

    // Compara un valor obtenido contra el esperado e informa el resultado.
    task check(input [8*48:1] name, input integer got, input integer expected);
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FALLO: %0s (obtenido=%0d esperado=%0d)", name, got, expected);
            end else begin
                $display("OK:    %0s", name);
            end
        end
    endtask

    // Carga un registro en modo manual usando llaves + boton
    task load_manual_reg(input integer which, input [7:0] value);
        begin
            sw = ~value;
            btn[which] = 0;
            @(posedge clk);
            #1;
            btn[which] = 1;
            @(posedge clk);
        end
    endtask

    // Envia un byte por uart_rx
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 0; // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i]; // LSB primero
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx = 1; // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Espera n pulsos de la señal interna de tick de baudios
    task wait_baud_ticks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge dut.uart_interface_inst.baud_tick);
        end
    endtask

    // Recibe un byte desde uart_tx
    task recv_uart_byte(output [7:0] data);
        integer i;
        begin
            @(negedge uart_tx); // arranca el bit de start
            wait_baud_ticks(OVERSAMPLE_RATE + OVERSAMPLE_RATE/2); // centro del bit 0
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_tx;
                wait_baud_ticks(OVERSAMPLE_RATE);
            end
        end
    endtask

    // Manda un comando+valor y junta los 5 bytes de respuesta
    // Escuchamos el primer byte de respuesta EN PARALELO con el 
    // envio para no perdernos su bit de start.
    task run_command(input [7:0] cmd, input [7:0] value);
        begin
            fork
                begin
                    send_uart_byte(cmd);
                    send_uart_byte(value);
                end
                recv_uart_byte(resp_a);
            join
            recv_uart_byte(resp_b);
            recv_uart_byte(resp_op);
            recv_uart_byte(resp_result);
            recv_uart_byte(resp_status);
        end
    endtask

    // Reloj de guarda
    initial begin
        #15_000_000;
        $display("FALLO: TIMEOUT, la simulacion no termino a tiempo");
        $finish;
    end

    initial begin
        clk = 0;
        btn = 4'b1111;  // ningun boton presionado (activos en bajo)
        sw  = 8'hFF;    // llaves en 0 logico (activas en bajo)
        uart_rx = 1'b1; // linea UART en reposo

        // --- Power-on-reset ---
        repeat (20) @(posedge clk);
        #1;
        // Tras el reset todo 0
        check("post power-on-reset: led en 0",              led,        0);
        check("post power-on-reset: led_aux (solo zero=1)", led_aux, 4'b0010);

        // --- Reset manual por boton ---
        btn[3] = 0;
        repeat (2) @(posedge clk);
        btn[3] = 1;
        @(posedge clk); #1;
        check("reset manual: led sigue en 0", led, 0);

        // --- Modo manual: A=5, B=3, OP=ADD ---
        load_manual_reg(0, 8'd5);
        load_manual_reg(1, 8'd3);
        load_manual_reg(2, {2'b00, OP_ADD});
        #1;
        check("modo manual: resultado 5+3 en led", led, 8);
        check("modo manual: flag zero (bit1 de led_aux) en 0", led_aux[1], 0);

        // --- Modo manual: verificar flag zero con A-A
        load_manual_reg(1, 8'd5); // B = 5, igual que A
        load_manual_reg(2, {2'b00, 6'b100010}); // OP_SUB
        #1;
        check("modo manual: resultado 5-5 en led", led, 0);
        check("modo manual: flag zero (bit1 de led_aux) en 1", led_aux[1], 1);

        // Reset antes de la seccion UART .
        btn[3] = 0;
        repeat (2) @(posedge clk);
        btn[3] = 1;
        @(posedge clk); #1;

        // --- Protocolo UART completo ---

        // Paso 1: cargar A = 77. B y OP todavia estan en 0.
        run_command(8'd0, 8'd77);
        check("paso1: respuesta A",              resp_a,      77);
        check("paso1: respuesta B",              resp_b,      0);
        check("paso1: respuesta OP",             resp_op,     0);
        check("paso1: respuesta result",         resp_result, 0);
        check("paso1: respuesta status (zero=1)", resp_status, 4'b0010);

        // Paso 2: cargar B = 20.
        run_command(8'd1, 8'd20);
        check("paso2: respuesta A",              resp_a,      77);
        check("paso2: respuesta B",              resp_b,      20);
        check("paso2: respuesta OP",             resp_op,     0);
        check("paso2: respuesta result",         resp_result, 0);
        check("paso2: respuesta status (zero=1)", resp_status, 4'b0010);

        // Paso 3: cargar OP = ADD -> ahora la ALU calcula 77 + 20.
        run_command(8'd2, {2'b00, OP_ADD});
        check("paso3: respuesta A",        resp_a,      77);
        check("paso3: respuesta B",        resp_b,      20);
        check("paso3: respuesta OP",       resp_op,     OP_ADD);
        check("paso3: resultado (77+20)",  resp_result, 97);
        check("paso3: status (sin flags)", resp_status, 0);
        #1;
        check("led refleja el resultado cargado por UART", led, 97);

        // --- El controlador debe volver a IDLE y aceptar un nuevo comando ---
        run_command(8'd2, {2'b00, OP_AND});
        check("2da vuelta: respuesta A",       resp_a,      77);
        check("2da vuelta: respuesta B",       resp_b,      20);
        check("2da vuelta: respuesta OP",      resp_op,     OP_AND);
        check("2da vuelta: resultado (77&20)", resp_result, (77 & 20));
        check("2da vuelta: status (sin flags)", resp_status, 0);

        // --- Un comando invalido no debe romper ni corromper nada ---
        run_command(8'd5, 8'hFF); // comando 5 no existe, no deberia tener efecto
        check("comando invalido: A sin cambios",        resp_a,      77);
        check("comando invalido: B sin cambios",        resp_b,      20);
        check("comando invalido: OP sin cambios",       resp_op,     OP_AND);
        check("comando invalido: resultado sin cambios", resp_result, (77 & 20));
        check("comando invalido: status sin cambios",   resp_status, 0);

        if (errors == 0)
            $display("\nTOP: TODOS LOS TESTS PASARON");
        else
            $display("\nTOP: %0d TEST(S) FALLARON", errors);

        $finish;
    end

endmodule