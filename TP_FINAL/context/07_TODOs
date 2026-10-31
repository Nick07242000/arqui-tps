### U3.2

- Los saltos todavía no se resuelven: el testbench usa programas sin `branch` ni `jump`, y como aún no existe `HALT`, termina por cantidad de ciclos con la memoria de programa en cero.
- `ex_rs1_value` y `ex_rs2_value` son los operandos ya adelantados. El comparador de `beq/bne` y el cálculo de `jalr` deben tomar estos valores.
- La entrada `i_insert_bubble` del latch `ID/EX` se reutiliza para el *flush*. `front_end_enable` deberá combinarse con la lógica de redirección del PC.
- **Camino crítico (a revisar en E7):** el forwarding agrega un multiplexor de tres entradas delante de la ALU. El camino más largo candidato es dato leído de `dmem` → extensión del load → forwarding → ALU.