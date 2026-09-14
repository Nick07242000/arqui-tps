module uart_top (
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output wire       tx,
    
    // interface to ALU / top module
    input  wire       rd_uart,  // read trigger
    input  wire       wr_uart,  // write trigger
    input  wire [7:0] w_data,   // data to transmit
    output wire [7:0] r_data,   // data received
    output wire       rx_empty,
    output wire       tx_full
);

    wire tick;
    wire rx_done_tick;
    wire tx_done_tick;
    wire [7:0] rx_data_out;

    // interface registers
    reg [7:0] r_data_reg;
    reg       rx_empty_reg;
    reg       tx_full_reg;

    // initial values for registers
    initial begin
        r_data_reg   = 8'b0;
        rx_empty_reg = 1'b1;
        tx_full_reg  = 1'b0;
    end

    // baud rate generator instantiation
    baud_rate_generator baud_gen_unit (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    // receiver instantiation
    uart_rx rx_unit (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .s_tick(tick),
        .rx_done_tick(rx_done_tick),
        .dout(rx_data_out)
    );

    // transmitter instantiation
    uart_tx tx_unit (
        .clk(clk),
        .reset(reset),
        .tx_start(wr_uart && ~tx_full_reg),
        .s_tick(tick),
        .din(w_data),
        .tx_done_tick(tx_done_tick),
        .tx(tx)
    );

    // simple interface circuit logic (buffer management)
    always @(posedge clk) begin
        if (reset) begin
            rx_empty_reg <= 1'b1;
            tx_full_reg  <= 1'b0;
            r_data_reg   <= 8'b0;
        end else begin
            // RX Logic
            if (rx_done_tick) begin
                r_data_reg   <= rx_data_out;
                rx_empty_reg <= 1'b0; // data is ready
            end else if (rd_uart) begin
                rx_empty_reg <= 1'b1; // data read, mark empty
            end

            // TX Logic
            if (wr_uart && ~tx_full_reg) begin
                tx_full_reg <= 1'b1; // transmission started
            end else if (tx_done_tick) begin
                tx_full_reg <= 1'b0; // transmission finished
            end
        end
    end

    assign r_data   = r_data_reg;
    assign rx_empty = rx_empty_reg;
    assign tx_full  = tx_full_reg;

endmodule
