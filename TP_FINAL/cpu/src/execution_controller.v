`timescale 1ns / 1ps
`include "execution_defs.vh"
`include "program_loader_defs.vh"

// -----------------------------------------------------------------------------
// Control de ejecucion: estado del sistema, modo continuo y modo paso a paso.
// -----------------------------------------------------------------------------
module execution_controller (
    input  wire       i_clk,
    input  wire       i_reset,                // reset de sistema

    // ---- Ordenes de la Debug Unit (pulsos de un ciclo) ----------------------
    input  wire       i_run_request,
    input  wire       i_step_request,
    input  wire       i_reset_request,

    // ---- Resultado de la carga (lo entrega program_loader) ------------------
    input  wire       i_load_finished,
    input  wire [1:0] i_load_error_code,
    input  wire       i_program_valid,

    // ---- Estado del CPU -----------------------------------------------------
    input  wire       i_cpu_done,

    // ---- Control del CPU ----------------------------------------------------
    output wire       o_cpu_enable,           // el CPU avanza un ciclo
    output wire       o_cpu_reset,            // reset sincrono del comando RESET

    // ---- Estado del sistema y respuesta a la orden --------------------------
    output reg  [2:0] o_system_state,         // ver execution_defs.vh
    output reg        o_command_finished,     // pulso: RUN, STEP o RESET terminaron
    output reg  [1:0] o_command_result        // valido con o_command_finished
);

    // -------------------------------------------------------------------------
    // Pulsos internos de un ciclo
    // -------------------------------------------------------------------------
    reg step_pulse;       // habilita un unico ciclo del CPU
    reg step_settling;    // el CPU ya avanzo: done se puede leer
    reg reset_pulse;      // reset sincrono del CPU

    // Valores iniciales definidos para que la simulacion no propague 'x'
    initial begin
        o_system_state     = `EXEC_STATE_EMPTY;
        o_command_finished = 1'b0;
        o_command_result   = `EXEC_RESULT_OK;
        step_pulse         = 1'b0;
        step_settling      = 1'b0;
        reset_pulse        = 1'b0;
    end

    // -------------------------------------------------------------------------
    // Habilitacion del CPU: continuo (RUNNING) o un unico ciclo (STEP)
    // -------------------------------------------------------------------------
    wire cpu_is_running = (o_system_state == `EXEC_STATE_RUNNING);

    assign o_cpu_enable = cpu_is_running || step_pulse;
    assign o_cpu_reset  = reset_pulse;

    // -------------------------------------------------------------------------
    // Ordenes recibidas
    // -------------------------------------------------------------------------
    // Una orden nueva solo se atiende si no hay otra en curso
    wire command_in_progress = step_pulse || step_settling || reset_pulse;

    wire reset_requested     = i_reset_request && !command_in_progress;
    wire execution_requested = (i_run_request || i_step_request) && !command_in_progress;

    // RUN y STEP solo se aceptan con un programa listo para avanzar
    wire state_accepts_execution = (o_system_state == `EXEC_STATE_READY)
                                || (o_system_state == `EXEC_STATE_PAUSED);

    reg [1:0] execution_rejection;

    always @(*) begin
        case (o_system_state)
            `EXEC_STATE_EMPTY:   execution_rejection = `EXEC_RESULT_NO_PROGRAM;
            `EXEC_STATE_RUNNING: execution_rejection = `EXEC_RESULT_BUSY;
            default:             execution_rejection = `EXEC_RESULT_WRONG_STATE;   // DONE
        endcase
    end

    // -------------------------------------------------------------------------
    // Secuencia de estados y ordenes
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        // Pulsos de un ciclo: vuelven a 0 salvo que se activen mas abajo
        o_command_finished <= 1'b0;
        step_pulse         <= 1'b0;
        reset_pulse        <= 1'b0;
        step_settling      <= step_pulse;

        if (i_reset) begin
            o_system_state   <= `EXEC_STATE_EMPTY;
            o_command_result <= `EXEC_RESULT_OK;
            step_settling    <= 1'b0;

        end else begin
            // Con done = 1 el CPU esta idempotente: el ciclo extra de RUNNING no cambia nada
            if (cpu_is_running && i_cpu_done)
                o_system_state <= `EXEC_STATE_DONE;

            if (i_load_finished) begin
                if (i_load_error_code == `LOAD_ERROR_NONE)
                    o_system_state <= `EXEC_STATE_READY;
                else if (!i_program_valid)
                    o_system_state <= `EXEC_STATE_EMPTY;     // carga interrumpida tras el encabezado
                // Una carga rechazada con el programa anterior intacto no cambia el estado

            end else if (step_settling) begin
                // El paso ya se ejecuto: done refleja el estado posterior al ciclo
                o_system_state     <= i_cpu_done ? `EXEC_STATE_DONE : `EXEC_STATE_PAUSED;
                o_command_finished <= 1'b1;
                o_command_result   <= `EXEC_RESULT_OK;

            end else if (reset_pulse) begin
                // El CPU ya se reseteo
                o_command_finished <= 1'b1;
                o_command_result   <= `EXEC_RESULT_OK;

            end else if (reset_requested) begin
                // RESET se acepta siempre; en RUNNING aborta la ejecucion
                o_system_state <= (o_system_state == `EXEC_STATE_EMPTY) ? `EXEC_STATE_EMPTY
                                                                        : `EXEC_STATE_READY;
                reset_pulse    <= 1'b1;

            end else if (execution_requested) begin
                if (!state_accepts_execution) begin
                    o_command_finished <= 1'b1;
                    o_command_result   <= execution_rejection;

                end else if (i_run_request) begin
                    o_system_state     <= `EXEC_STATE_RUNNING;
                    o_command_finished <= 1'b1;
                    o_command_result   <= `EXEC_RESULT_OK;

                end else begin
                    step_pulse <= 1'b1;
                end
            end
        end
    end

endmodule
