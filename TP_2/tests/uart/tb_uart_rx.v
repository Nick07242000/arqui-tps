`timescale 1ns/1ps

module tb_uart_rx;

    localparam DATA_BITS       = 8;
    localparam OVERSAMPLE_RATE = 16;
    localparam STOP_BIT_TICKS  = 16;

    reg                    i_clk   = 0;
    reg                    i_reset = 1;
    reg                    i_rx    = 1;
    wire                   o_rx_done;
    wire [DATA_BITS-1:0]   o_data_out;

    integer errors = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s (time=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    // One clock cycle = one baud tick. Simplifies timing
    wire i_baud_tick = 1'b1;

    uart_rx #(
        .DATA_BITS(DATA_BITS),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE),
        .STOP_BIT_TICKS(STOP_BIT_TICKS)
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_rx(i_rx),
        .i_baud_tick(i_baud_tick),
        .o_rx_done(o_rx_done),
        .o_data_out(o_data_out)
    );

    always #5 i_clk = ~i_clk;

    // Captures the data present whenever o_rx_done pulses.
    reg [DATA_BITS-1:0] captured_data;
    reg                  done_seen;
    always @(posedge i_clk) begin
        if (o_rx_done) begin
            captured_data <= o_data_out;
            done_seen     <= 1'b1;
        end
    end

    integer i;

    // Drives one standard UART frame.
    task send_byte(input [DATA_BITS-1:0] data);
        begin
            i_rx = 1'b0; // start bit
            repeat (OVERSAMPLE_RATE) @(posedge i_clk);
            for (i = 0; i < DATA_BITS; i = i + 1) begin
                i_rx = data[i];
                repeat (OVERSAMPLE_RATE) @(posedge i_clk);
            end
            i_rx = 1'b1; // stop bit
            repeat (STOP_BIT_TICKS) @(posedge i_clk);
        end
    endtask

    task receive_and_check(input [DATA_BITS-1:0] data);
        begin
            done_seen = 1'b0;
            send_byte(data);
            @(posedge i_clk); // rx_done is registered, give it a cycle to settle
            check(done_seen, "o_rx_done never pulsed");
            check(captured_data == data, "received byte does not match sent byte");
        end
    endtask

    initial begin
        repeat (3) @(posedge i_clk);
        i_reset = 0;
        @(posedge i_clk);

        // Basic bytes, including all-zero and all-one patterns.
        receive_and_check(8'h00);
        receive_and_check(8'hFF);
        receive_and_check(8'hA5);

        // Back-to-back frames with no idle gap between them: the
        // receiver must return to idle and accept a new start bit
        // right away, with no leftover state from the previous byte.
        done_seen = 1'b0;
        send_byte(8'h3C);
        @(posedge i_clk);
        check(done_seen, "o_rx_done never pulsed for first back-to-back byte");
        check(captured_data == 8'h3C, "first back-to-back byte was corrupted");

        done_seen = 1'b0;
        send_byte(8'h81);
        @(posedge i_clk);
        check(done_seen, "o_rx_done never pulsed for second back-to-back byte");
        check(captured_data == 8'h81, "second back-to-back byte was corrupted");

        // Idle line must not produce spurious done pulses.
        done_seen = 1'b0;
        repeat (50) @(posedge i_clk);
        check(!done_seen, "spurious o_rx_done while line idle");

        if (errors == 0)
            $display("PASS: uart_rx");
        else
            $display("DONE: uart_rx with %0d error(s)", errors);

        $finish;
    end

endmodule