# ADRs

## ADR - ubicación del cableado de campos de la instrucción

### Contexto

En la etapa ID, la instrucción tiene campos (`rs1`, `rs2`, `rd`, `funct3`) que son simples cortes de bits. La primera versión de `control_unit` los entregaba como salidas, junto con las señales de control.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | `control_unit` extrae y reenvía los campos. |
| **A** | **La etapa ID corta los campos del latch `IF/ID`; `control_unit` solo decide.** |
| B | Un módulo `instruction_fields` dedicado extrae todos los campos. |

### Decisión

**Opción A.**

### Motivos

- Coincide con los diagramas de datapath de la bibliografía de la cátedra: `rs1` y `rs2` salen directo del latch `IF/ID`, no de la unidad de control.
- La unidad de detección de riesgos compara `rs1`/`rs2` tomados del latch, así que no necesita pasar por el decodificador.
- `control_unit` queda con una sola responsabilidad: decidir. Su interfaz pasa de 17 a 13 salidas.
- La Opción B agregaría un módulo y un testbench para seis cables sin lógica.
- No hay diferencia de performance, recursos ni camino crítico: son cables y la síntesis aplana la jerarquía.

### Consecuencias

- `funct3` se corta en dos lugares (dentro de `control_unit` para decidir y en la etapa ID para enviarlo al latch). Es inocuo.
- `control_unit` fusiona la unidad de control principal con el `ALU Control` y la detección de ilegales. Se aparta del modelo teórico, que los separa.
- Pendiente de verificar: las figuras citadas en la respuesta del notebook deben contrastarse con los libros antes de incluirse en el informe.