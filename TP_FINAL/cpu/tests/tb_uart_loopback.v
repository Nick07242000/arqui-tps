`timescale 1ns / 1ps

module tb_uart_loopback;

    parameter CLK_HZ    = 27_000_000;
    parameter BAUD_RATE = 115_200;

    localparam BYTES_TO_SEND     = 512;
    localparam CLK_PERIOD_NS     = 10;
    localparam BIT_PERIOD_CYCLES = (CLK_HZ + BAUD_RATE / 2) / BAUD_RATE;
    localparam FRAME_CYCLES      = BIT_PERIOD_CYCLES * 10;

    reg        clk          = 1'b0;
    reg        reset        = 1'b1;
    reg        send_request = 1'b0;
    reg  [7:0] byte_to_send = 8'h00;
    wire       line;
    wire       busy;
    wire [7:0] received_byte;
    wire       received_valid;
    wire       framing_error;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) transmitter (
        .i_clk          (clk),
        .i_reset        (reset),
        .i_send_request (send_request),
        .i_byte_data    (byte_to_send),
        .o_tx_pin       (line),
        .o_busy         (busy)
    );

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) receiver (
        .i_clk           (clk),
        .i_reset         (reset),
        .i_rx_pin        (line),
        .o_byte_data     (received_byte),
        .o_byte_valid    (received_valid),
        .o_framing_error (framing_error)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // Primera pasada ascendente (0 a 255) y segunda descendente (255 a 0)
    function [7:0] pattern(input integer index);
        begin
            pattern = (index < 256) ? index : (511 - index);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Emisor: pide el byte siguiente en cuanto el transmisor queda libre
    // -------------------------------------------------------------------------
    integer sent_count = 0;

    always @(posedge clk) begin
        send_request <= 1'b0;

        if (!reset && !busy && !send_request && sent_count < BYTES_TO_SEND) begin
            byte_to_send <= pattern(sent_count);
            send_request <= 1'b1;
            sent_count   <= sent_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Receptor: compara cada byte con el esperado
    // -------------------------------------------------------------------------
    integer received_count      = 0;
    integer mismatch_count      = 0;
    integer framing_error_count = 0;

    always @(posedge clk) begin
        if (received_valid) begin
            if (received_byte !== pattern(received_count)) begin
                mismatch_count = mismatch_count + 1;
                $display("[%0t] ERROR: byte %0d: esperado %h, recibido %h",
                         $time, received_count, pattern(received_count), received_byte);
            end
            received_count = received_count + 1;
        end

        if (framing_error)
            framing_error_count = framing_error_count + 1;
    end

    // -------------------------------------------------------------------------
    // Secuencia
    // -------------------------------------------------------------------------
    integer start_cycle;
    integer elapsed_cycles;
    integer cycle_counter = 0;

    always @(posedge clk) cycle_counter <= cycle_counter + 1;

    initial begin
        $display("tb_uart_loopback: inicio (CLK_HZ = %0d, %0d ciclos por bit)", CLK_HZ, BIT_PERIOD_CYCLES);

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        start_cycle = cycle_counter;

        wait (received_count == BYTES_TO_SEND);
        elapsed_cycles = cycle_counter - start_cycle;
        repeat (4 * BIT_PERIOD_CYCLES) @(posedge clk);              // margen para detectar bytes de mas

        $display("  %0d bytes recibidos en %0d ciclos (una trama dura %0d ciclos)",
                 received_count, elapsed_cycles, FRAME_CYCLES);

        if (mismatch_count == 0 && framing_error_count == 0 && received_count == BYTES_TO_SEND)
            $display("tb_uart_loopback: PASS");
        else
            $display("tb_uart_loopback: FAIL (%0d distintos, %0d framing errors, %0d bytes recibidos)",
                     mismatch_count, framing_error_count, received_count);

        $finish;
    end

    // Evita que una falla deje la simulacion colgada
    initial begin
        #(CLK_PERIOD_NS * 4 * BYTES_TO_SEND * FRAME_CYCLES);
        $display("tb_uart_loopback: TIMEOUT");
        $finish;
    end

endmodule
