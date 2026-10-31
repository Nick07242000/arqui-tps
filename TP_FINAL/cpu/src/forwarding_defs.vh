// -----------------------------------------------------------------------------
// Codigos de seleccion del forwarding hacia la etapa EX
// -----------------------------------------------------------------------------
`ifndef FORWARDING_DEFS_VH
`define FORWARDING_DEFS_VH

`define FORWARD_NONE        2'b00   // usa el valor leido en ID (latch ID/EX)
`define FORWARD_FROM_EX_MEM 2'b01   // resultado de la instruccion en MEM
`define FORWARD_FROM_MEM_WB 2'b10   // dato final de la instruccion en WB

`endif
