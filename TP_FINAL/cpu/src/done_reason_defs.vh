// -----------------------------------------------------------------------------
// Motivo de fin de ejecucion (halt_controller)
// Los valores coinciden con el campo done_reason de GET_STATUS
// -----------------------------------------------------------------------------
`ifndef DONE_REASON_DEFS_VH
`define DONE_REASON_DEFS_VH

`define DONE_REASON_NONE          2'd0   // la ejecucion todavia no termino
`define DONE_REASON_HALT          2'd1   // termino por la instruccion HALT
`define DONE_REASON_END_OF_IMAGE  2'd2   // el PC llego al final de la imagen sin HALT

`endif
