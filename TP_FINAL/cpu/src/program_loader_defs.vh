// -----------------------------------------------------------------------------
// Codigos de resultado de una carga de programa (program_loader)
// -----------------------------------------------------------------------------
`ifndef PROGRAM_LOADER_DEFS_VH
`define PROGRAM_LOADER_DEFS_VH

`define LOAD_ERROR_NONE      2'd0   // carga completa y valida
`define LOAD_ERROR_ARGUMENT  2'd1   // N_WORDS fuera de [1, capacidad]      -> ERR_ARG
`define LOAD_ERROR_LENGTH    2'd2   // LEN distinto de 2 + 4 * N_WORDS      -> ERR_LEN
`define LOAD_ERROR_TIMEOUT   2'd3   // el mensaje se interrumpio (truncado) -> ERR_TIMEOUT

`endif
