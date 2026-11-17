`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Emisor de respuestas: envia [STATUS][LEN:2 LE][PAYLOAD] byte a byte por uart_tx.
// El payload se pide por indice: quien conoce los datos entrega el byte pedido.
// -----------------------------------------------------------------------------
module response_sender (
    input  wire        i_clk,
    input  wire        i_reset,                          // reset de sistema

    // ---- Orden de respuesta (la entrega command_parser) ---------------------
    input  wire        i_response_request,               // pulso, solo con el emisor libre
    input  wire [7:0]  i_response_status,
    input  wire [15:0] i_response_payload_length_bytes,
    output reg         o_response_finished,              // pulso: el ultimo byte termino de salir

    // ---- Payload: el emisor pide un byte por indice -------------------------
    output reg  [15:0] o_payload_byte_index,
    input  wire [7:0]  i_payload_byte,                   // debe ser valido 2 ciclos despues de cambiar el indice

    // ---- Transmisor UART ----------------------------------------------------
    output reg         o_tx_send_request,                // pulso de un ciclo
    output reg  [7:0]  o_tx_byte_data,
    input  wire        i_tx_busy
);

    // -------------------------------------------------------------------------
    // Estados
    // -------------------------------------------------------------------------
    localparam [2:0] STATE_IDLE             = 3'd0,
                     STATE_SEND_STATUS      = 3'd1,
                     STATE_SEND_LENGTH_LOW  = 3'd2,
                     STATE_SEND_LENGTH_HIGH = 3'd3,
                     STATE_SEND_PAYLOAD     = 3'd4,
                     STATE_WAIT_LAST_BYTE   = 3'd5;

    // -------------------------------------------------------------------------
    // Registros internos
    // -------------------------------------------------------------------------
    reg [2:0]  state;
    reg [7:0]  status_to_send;
    reg [15:0] payload_length_bytes;

    // -------------------------------------------------------------------------
    // Condiciones derivadas
    // -------------------------------------------------------------------------
    // o_busy de uart_tx sube un ciclo despues del pedido: mientras el pedido
    // sigue en alto el transmisor todavia figura libre
    wire tx_is_free = !i_tx_busy && !o_tx_send_request;

    wire is_last_payload_byte = (o_payload_byte_index == payload_length_bytes - 16'd1);

    // -------------------------------------------------------------------------
    // Secuencia de envio
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        // Pulsos de un ciclo: vuelven a 0 salvo que se activen mas abajo
        o_response_finished <= 1'b0;
        o_tx_send_request   <= 1'b0;

        if (i_reset) begin
            state                <= STATE_IDLE;
            status_to_send       <= 8'd0;
            payload_length_bytes <= 16'd0;
            o_payload_byte_index <= 16'd0;
            o_tx_byte_data       <= 8'd0;

        end else begin
            case (state)
                STATE_IDLE: if (i_response_request) begin
                    status_to_send       <= i_response_status;
                    payload_length_bytes <= i_response_payload_length_bytes;
                    o_payload_byte_index <= 16'd0;
                    state                <= STATE_SEND_STATUS;
                end

                STATE_SEND_STATUS: if (tx_is_free) begin
                    o_tx_send_request <= 1'b1;
                    o_tx_byte_data    <= status_to_send;
                    state             <= STATE_SEND_LENGTH_LOW;
                end

                STATE_SEND_LENGTH_LOW: if (tx_is_free) begin
                    o_tx_send_request <= 1'b1;
                    o_tx_byte_data    <= payload_length_bytes[7:0];
                    state             <= STATE_SEND_LENGTH_HIGH;
                end

                STATE_SEND_LENGTH_HIGH: if (tx_is_free) begin
                    o_tx_send_request <= 1'b1;
                    o_tx_byte_data    <= payload_length_bytes[15:8];
                    state             <= (payload_length_bytes == 16'd0) ? STATE_WAIT_LAST_BYTE
                                                                         : STATE_SEND_PAYLOAD;
                end

                // El indice avanza al pedir el byte: durante la trama anterior
                // (miles de ciclos) el proveedor ya tuvo tiempo de entregar el siguiente
                STATE_SEND_PAYLOAD: if (tx_is_free) begin
                    o_tx_send_request    <= 1'b1;
                    o_tx_byte_data       <= i_payload_byte;
                    o_payload_byte_index <= o_payload_byte_index + 16'd1;

                    if (is_last_payload_byte)
                        state <= STATE_WAIT_LAST_BYTE;
                end

                STATE_WAIT_LAST_BYTE: if (tx_is_free) begin
                    o_response_finished <= 1'b1;
                    state               <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
