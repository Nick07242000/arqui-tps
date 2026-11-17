### U3.2

- Los saltos todavía no se resuelven: el testbench usa programas sin `branch` ni `jump`, y como aún no existe `HALT`, termina por cantidad de ciclos con la memoria de programa en cero.
- `ex_rs1_value` y `ex_rs2_value` son los operandos ya adelantados. El comparador de `beq/bne` y el cálculo de `jalr` deben tomar estos valores.
- La entrada `i_insert_bubble` del latch `ID/EX` se reutiliza para el *flush*. `front_end_enable` deberá combinarse con la lógica de redirección del PC.
- **Camino crítico (a revisar en E7):** el forwarding agrega un multiplexor de tres entradas delante de la ALU. El camino más largo candidato es dato leído de `dmem` → extensión del load → forwarding → ALU.

### U5.2

### Punto de unión con la US-5.3

La US-5.3 debe completar tres cosas. Ninguna requiere modificar los módulos de esta historia.

**1. Cablear el parser** con los módulos existentes:

| Desde | Hacia |
| --- | --- |
| `uart_rx` | entradas `i_rx_*` del parser |
| `o_run_request`, `o_step_request`, `o_reset_request` | `execution_controller` |
| `o_load_*` | `program_loader` |
| `i_load_finished`, `i_load_error_code` (compartidos) | parser y `execution_controller` |
| `o_response_*` | `response_sender` |
| `o_tx_send_request`, `o_tx_byte_data` | `uart_tx` |

**2. Entregar `i_payload_byte`.** Un selector combinacional (o con un ciclo de latencia) que, según `o_command_code` y `o_payload_byte_index`, devuelva el byte pedido:

| Comando | Contenido del payload |
| --- | --- |
| `LOAD_PROGRAM`, `RESET`, `RUN`, `STEP` | `{5'b0, o_system_state}` |
| `GET_STATUS` | los 17 bytes de la arquitectura (§8.2) |
| `GET_REGS` | registro `índice[6:2]`, byte `índice[1:0]` |
| `GET_PIPELINE` | byte `índice` del vector `dbg_pipe` |
| `GET_MEMORY` | palabra `o_memory_start_word + índice[15:2]`, byte `índice[1:0]` |

**3. Combinar los resets** como ya indican los ADR de `program_loader` y `execution_controller`:
`cpu_rst = sys_rst | execution_controller.o_cpu_reset | program_loader.o_cpu_reset`.
