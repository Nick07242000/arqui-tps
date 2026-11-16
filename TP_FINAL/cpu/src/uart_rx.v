`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Receptor UART 8-N-1 (8 bits de datos, sin paridad, 1 bit de stop)
// Entrega cada byte bien formado como un pulso de un ciclo. No tiene buffer.
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter CLK_HZ    = 27_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       i_clk,
    input  wire       i_reset,            // reset sincrono
    input  wire       i_rx_pin,           // entrada asincrona: se sincroniza adentro

    output reg  [7:0] o_byte_data,        // ultimo byte recibido, estable hasta el proximo
    output reg        o_byte_valid,       // pulso de un ciclo: o_byte_data es un byte nuevo
    output reg        o_framing_error     // pulso de un ciclo: el bit de stop no llego en 1
);

    // -------------------------------------------------------------------------
    // Constantes y estados
    // -------------------------------------------------------------------------
    localparam DATA_BITS           = 8;
    localparam BIT_PERIOD_CYCLES   = (CLK_HZ + BAUD_RATE / 2) / BAUD_RATE;   // redondeado
    localparam HALF_BIT_CYCLES     = BIT_PERIOD_CYCLES / 2;
    localparam CYCLE_COUNTER_WIDTH = $clog2(BIT_PERIOD_CYCLES);

    localparam [2:0] STATE_IDLE           = 3'd0,
                     STATE_START_BIT      = 3'd1,
                     STATE_DATA_BITS      = 3'd2,
                     STATE_STOP_BIT       = 3'd3,
                     STATE_WAIT_LINE_IDLE = 3'd4;   // tras un framing error

    // -------------------------------------------------------------------------
    // Sincronizador de 2 flip-flops para la entrada asincrona
    // -------------------------------------------------------------------------
    reg rx_sync_first;
    reg rx_sync_second;

    // La linea en reposo vale 1; valores iniciales para que la simulacion no propague 'x'
    initial begin
        rx_sync_first  = 1'b1;
        rx_sync_second = 1'b1;
    end

    always @(posedge i_clk) begin
        rx_sync_first  <= i_rx_pin;
        rx_sync_second <= rx_sync_first;
    end

    wire rx_line = rx_sync_second;

    // -------------------------------------------------------------------------
    // Registros de la recepcion
    // -------------------------------------------------------------------------
    reg [2:0]                       state;
    reg [CYCLE_COUNTER_WIDTH-1:0]   cycles_in_bit;       // ciclos transcurridos en el bit actual
    reg [2:0]                       data_bit_index;      // bit de datos que se esta esperando (0 a 7)
    reg [DATA_BITS-1:0]             receive_shift_register;

    initial begin
        state                  = STATE_IDLE;
        cycles_in_bit          = {CYCLE_COUNTER_WIDTH{1'b0}};
        data_bit_index         = 3'd0;
        receive_shift_register = {DATA_BITS{1'b0}};
        o_byte_data            = 8'h00;
        o_byte_valid           = 1'b0;
        o_framing_error        = 1'b0;
    end

    wire half_bit_elapsed   = (cycles_in_bit == HALF_BIT_CYCLES - 1);
    wire bit_period_elapsed = (cycles_in_bit == BIT_PERIOD_CYCLES - 1);
    wire is_last_data_bit   = (data_bit_index == DATA_BITS - 1);

    // -------------------------------------------------------------------------
    // Secuencia de recepcion
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        // Pulsos de un ciclo: vuelven a 0 salvo que se activen mas abajo
        o_byte_valid    <= 1'b0;
        o_framing_error <= 1'b0;

        if (i_reset) begin
            state                  <= STATE_IDLE;
            cycles_in_bit          <= {CYCLE_COUNTER_WIDTH{1'b0}};
            data_bit_index         <= 3'd0;
            receive_shift_register <= {DATA_BITS{1'b0}};

        end else begin
            case (state)
                // Espera el flanco de bajada del bit de start
                STATE_IDLE: if (!rx_line) begin
                    cycles_in_bit <= {CYCLE_COUNTER_WIDTH{1'b0}};
                    state         <= STATE_START_BIT;
                end

                // Se confirma el start en el centro del bit: un pulso mas corto es ruido
                STATE_START_BIT: begin
                    if (half_bit_elapsed) begin
                        cycles_in_bit  <= {CYCLE_COUNTER_WIDTH{1'b0}};
                        data_bit_index <= 3'd0;
                        state          <= rx_line ? STATE_IDLE : STATE_DATA_BITS;
                    end else begin
                        cycles_in_bit <= cycles_in_bit + 1'b1;
                    end
                end

                // Un muestreo por bit, siempre en su centro. Llega primero el bit menos significativo
                STATE_DATA_BITS: begin
                    if (bit_period_elapsed) begin
                        cycles_in_bit          <= {CYCLE_COUNTER_WIDTH{1'b0}};
                        receive_shift_register <= {rx_line, receive_shift_register[DATA_BITS-1:1]};
                        data_bit_index         <= data_bit_index + 1'b1;

                        if (is_last_data_bit)
                            state <= STATE_STOP_BIT;
                    end else begin
                        cycles_in_bit <= cycles_in_bit + 1'b1;
                    end
                end

                // El stop debe valer 1. Se vuelve a IDLE en su centro para no perder un start inmediato
                STATE_STOP_BIT: begin
                    if (bit_period_elapsed) begin
                        if (rx_line) begin
                            o_byte_data  <= receive_shift_register;
                            o_byte_valid <= 1'b1;
                            state        <= STATE_IDLE;
                        end else begin
                            o_framing_error <= 1'b1;
                            state           <= STATE_WAIT_LINE_IDLE;
                        end
                    end else begin
                        cycles_in_bit <= cycles_in_bit + 1'b1;
                    end
                end

                // Con la linea atascada en 0 (break) no se interpreta cada bit como un byte nuevo
                STATE_WAIT_LINE_IDLE: if (rx_line)
                    state <= STATE_IDLE;

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
