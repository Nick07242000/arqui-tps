// -----------------------------------------------------------------------------
// Estados del sistema y resultados de las ordenes de ejecucion
// Los estados coinciden con el campo state de GET_STATUS
// -----------------------------------------------------------------------------
`ifndef EXECUTION_DEFS_VH
`define EXECUTION_DEFS_VH

`define EXEC_STATE_EMPTY    3'd0   // sin programa valido
`define EXEC_STATE_READY    3'd1   // programa valido, CPU en reset, sin ejecutar
`define EXEC_STATE_RUNNING  3'd2   // ejecucion continua en curso
`define EXEC_STATE_PAUSED   3'd3   // se ejecuto al menos un paso, no termino
`define EXEC_STATE_DONE     3'd4   // la ejecucion termino
// 5 = LOADING: estado interno de la Debug Unit, este modulo no lo maneja

`define EXEC_RESULT_OK           2'd0   // orden aceptada                  -> OK
`define EXEC_RESULT_BUSY         2'd1   // el CPU esta en RUNNING          -> ERR_BUSY
`define EXEC_RESULT_NO_PROGRAM   2'd2   // no hay programa valido          -> ERR_NO_PROGRAM
`define EXEC_RESULT_WRONG_STATE  2'd3   // orden no valida en este estado  -> ERR_STATE

`endif
