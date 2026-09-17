`timescale 1ns / 1ps

module tb_top;
    parameter DATA_WIDTH = 8;
    parameter OP_WIDTH   = 6;

    reg        clk;
    reg  [7:0] sw;
    reg  [3:0] btn;
    wire [7:0] led;
    wire [3:0] led_aux;
    reg        uart_rx;
    wire       uart_tx;

    // Configuración de Baudrate acelerado para simulaciones rápidas
    localparam BAUD_RATE  = 1_000_000;
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; // ns

    top #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH(OP_WIDTH)
    ) uut (
        .clk(clk),
        .sw(sw),
        .btn(btn),
        .led(led),
        .led_aux(led_aux),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // Sobrescribir baud rate internamente para acelerar la simulación
    defparam uut.uart_interface_inst.BAUD_RATE = BAUD_RATE;

    // Reloj de 27 MHz (~37 ns por periodo)
    always #18.5 clk = ~clk;

    // Tarea auxiliar para enviar tramas UART serie
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            uart_rx = 1'b0;
            #(BIT_PERIOD);
            // Data bits (LSB primero)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end
            // Stop bit
            uart_rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    initial begin
        // Inicialización
        clk     = 0;
        sw      = 8'h00;
        btn     = 4'b1111; // Inactivo (Lógica activa en bajo)
        uart_rx = 1'b1;    // UART en reposo (High)

        // Reset inicial (btn[3] activo en bajo)
        #100;
        btn[3] = 1'b0;
        #200;
        btn[3] = 1'b1;
        #100;

        // ----------------------------------------------------
        // PRUEBA 1: Control Manual (Switches + Botones)
        // ----------------------------------------------------
        $display("=== [TOP] Prueba de Control Manual ===");
        
        // Cargar Reg A = 0x0A (Switches invertidos por lógica ~sw)
        sw = ~8'h0A; btn[0] = 1'b0; #100; btn[0] = 1'b1;

        // Cargar Reg B = 0x05
        sw = ~8'h05; btn[1] = 1 me0; #100; btn[1] = 1'b1;

        // Cargar Reg OP = ADD (0x20)
        sw = ~8'h20; btn[2] = 1'b0; #100; btn[2] = 1'b1;
        #100;

        // Validar si el resultado de la ALU (0x0A + 0x05 = 0x0F) sale por los LEDs
        if (led === 8'h0F)
            $display("[PASS] Salida manual en LEDs correcta: 0x%h", led);
        else
            $error("[FAIL] Error en LEDs. Esperado: 0x0F, Obtenido: 0x%h", led);

        // ----------------------------------------------------
        // PRUEBA 2: Flujo UART + Controller FSM
        // ----------------------------------------------------
        $display("=== [TOP] Prueba de Comando UART ===");

        // Enviar Comando 0 (Set A) -> Valor 0x04
        send_uart_byte(8'd0);
        send_uart_byte(8'h04);

        // Enviar Comando 1 (Set B) -> Valor 0x02
        send_uart_byte(8'd1);
        send_uart_byte(8'h02);

        // Enviar Comando 2 (Set OP) -> Valor 0x20 (ADD)
        send_uart_byte(8'd2);
        send_uart_byte(8'h20);

        // Esperar que la FSM procese y transmita las 5 respuestas UART
        #(BIT_PERIOD * 10 * 6);

        $display("=== [TOP] Pruebas Finalizadas ===");
        $finish;
    end
endmodule