`timescale 1ns/1ps

module tb_uart_interface;

    // Tiny clock/baud ratio: 1 clk cycle per baud tick
    localparam CLK_FREQ        = 32;
    localparam BAUD_RATE       = 2;
    localparam DATA_BITS       = 8;
    localparam OVERSAMPLE_RATE = 16;
    localparam BIT_CYCLES      = OVERSAMPLE_RATE; // = CLK_FREQ/(BAUD_RATE*1)

    reg                   i_clk        = 0;
    reg                   i_reset      = 1;
    reg                   i_rx         = 1;
    reg                   i_rd_uart    = 0;
    reg                   i_wr_uart    = 0;
    reg [DATA_BITS-1:0]   i_write_data = 0;

    wire                  o_tx;
    wire                  o_rx_empty;
    wire                  o_tx_busy;
    wire [DATA_BITS-1:0]  o_read_data;

    integer errors = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s (time=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    uart_interface #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(DATA_BITS),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE)
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_rx(i_rx),
        .i_rd_uart(i_rd_uart),
        .i_wr_uart(i_wr_uart),
        .i_write_data(i_write_data),
        .o_tx(o_tx),
        .o_rx_empty(o_rx_empty),
        .o_tx_busy(o_tx_busy),
        .o_read_data(o_read_data)
    );

    always #5 i_clk = ~i_clk;

    integer i;

    // Serializes one byte onto i_rx at the interface's own baud rate.
    task send_rx_byte(input [DATA_BITS-1:0] data);
        begin
            i_rx = 1'b0;
            repeat (BIT_CYCLES) @(posedge i_clk);
            for (i = 0; i < DATA_BITS; i = i + 1) begin
                i_rx = data[i];
                repeat (BIT_CYCLES) @(posedge i_clk);
            end
            i_rx = 1'b1;
            repeat (BIT_CYCLES) @(posedge i_clk);
        end
    endtask

    // Decodes o_tx while a transmission is in flight and checks it
    task check_tx_frame(input [DATA_BITS-1:0] data);
        integer j;
        begin
            repeat (BIT_CYCLES/2) @(posedge i_clk);
            check(o_tx == 1'b0, "tx start bit not low");
            repeat (BIT_CYCLES/2) @(posedge i_clk);
            for (j = 0; j < DATA_BITS; j = j + 1) begin
                repeat (BIT_CYCLES/2) @(posedge i_clk);
                check(o_tx == data[j], "tx data bit mismatch");
                repeat (BIT_CYCLES/2) @(posedge i_clk);
            end
            repeat (BIT_CYCLES/2) @(posedge i_clk);
            check(o_tx == 1'b1, "tx stop bit not high");
            repeat (BIT_CYCLES/2) @(posedge i_clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge i_clk);
        i_reset = 0;
        @(posedge i_clk);

        check(o_rx_empty == 1'b1, "rx should start empty");
        check(o_tx_busy  == 1'b0, "tx should start idle");

        // --- Receive path ---
        send_rx_byte(8'h3C);
        @(posedge i_clk); // let rx_done register into the buffer
        check(o_rx_empty == 1'b0, "rx_empty should clear once a byte arrives");
        check(o_read_data == 8'h3C, "read_data does not match received byte");

        i_rd_uart = 1'b1;
        @(posedge i_clk);
        i_rd_uart = 1'b0;
        @(posedge i_clk);
        check(o_rx_empty == 1'b1, "rx_empty should be set again after being read");

        // --- Transmit path ---
        i_write_data = 8'h91;
        i_wr_uart    = 1'b1;
        @(posedge i_clk);
        i_wr_uart = 1'b0;
        check(o_tx_busy == 1'b1, "tx_busy should assert right after a write request");
        check_tx_frame(8'h91);
        @(posedge i_clk);
        check(o_tx_busy == 1'b0, "tx_busy should clear once the frame finishes");

        // A write request while busy must be ignored
        i_write_data = 8'hAA;
        i_wr_uart    = 1'b1;
        @(posedge i_clk);
        i_wr_uart = 1'b0;
        fork
            check_tx_frame(8'hAA);
            begin
                repeat (BIT_CYCLES) @(posedge i_clk); // now mid-frame
                i_write_data = 8'h00;
                i_wr_uart    = 1'b1;
                @(posedge i_clk);
                i_wr_uart = 1'b0;
                check(o_tx_busy == 1'b1, "tx_busy should stay high through the ignored request");
            end
        join
        @(posedge i_clk);
        check(o_tx_busy == 1'b0, "tx_busy should clear after the original frame finishes");

        // --- Simultaneous rx and tx: neither should disturb the other ---
        i_write_data = 8'h5A;
        i_wr_uart    = 1'b1;
        @(posedge i_clk);
        i_wr_uart = 1'b0;
        fork
            check_tx_frame(8'h5A);
            send_rx_byte(8'h66);
        join
        @(posedge i_clk);
        check(o_rx_empty == 1'b0, "rx byte lost while tx was active");
        check(o_read_data == 8'h66, "rx byte corrupted while tx was active");
        check(o_tx_busy == 1'b0, "tx did not finish while rx was active");

        if (errors == 0)
            $display("PASS: uart_interface");
        else
            $display("DONE: uart_interface with %0d error(s)", errors);

        $finish;
    end

endmodule