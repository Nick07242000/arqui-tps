# Desviaciones (So Far)

Las principales desviaciones respecto a la teoría pura son:

## 1. **Uso de Memorias Síncronas (Block RAM) como Latches Implícitos**
* **Teoría (Patterson):** Modela memorias ideales con lectura combinacional (asíncrona) y coloca registros de latch explícitos para guardar la instrucción en `IF/ID` y el dato leído en `MEM/WB`.
* **Implementación:** Las Block RAMs de las FPGAs reales tienen 1 ciclo de latencia síncrona obligatoria. En lugar de agregar un registro de latch redundante (que demoraría la lectura un ciclo adicional), **la propia salida registrada de la memoria cumple la función del latch de pipeline** (`program_memory` para la instrucción e `i_dmem_read_data` para el dato).

## 2. **Bit `valid` Explícito en los Latches de Pipeline**
* **Teoría (Patterson):** Representa las burbujas o NOPs forzando únicamente a cero las señales de control de efecto (`RegWrite = 0`, `MemWrite = 0`).
* **Implementación:** Cada latch incluye un bit **`valid`** explícito. Si `valid = 0`, la etapa no ejecuta ningún efecto de escritura ni chequeos. Esto simplifica la gestión del estado inicial tras un reset (etapas vacías) y la posterior inyección de burbujas.

## 3. **Fusión de la Unidad de Control en un Solo Nivel**
* **Teoría (Patterson):** Propone un control en dos niveles: una *Unidad de Control Principal* (genera `ALUOp` de 2 bits) y un bloque secundario *ALU Control* (decodifica `funct3`/`funct7`).
* **Implementación:** Se **fusionan ambos niveles en un único módulo combinacional** (`control_unit.v`), el cual evalúa directamente `opcode`, `funct3` y `funct7`. En síntesis para FPGA, esto no altera el área ni los tiempos y simplifica la jerarquía en Verilog.

## 4. **Bypass Interno Local en el Banco de Registros**
* **Teoría (Patterson):** Plantea resolver la lectura/escritura simultánea en el ciclo `WB`/`ID` mediante la división del ciclo de reloj en dos medios ciclos (escritura en el flanco descendente y lectura en el ascendente) o mediante *forwarding* externo.
* **Implementación:** Se utiliza un **multiplexor de *bypass* interno en `registers.v`**, de modo que si se lee y escribe el mismo registro en el mismo ciclo, el módulo entrega combinacionalmente el dato nuevo sin alterar las fases del reloj.

## 5. **Evaluación de Saltos fuera de la ALU**
* **Teoría (Patterson):** La ALU genera la bandera `Zero` para determinar si se toma un salto condicional en la etapa `EX`.
* **Implementación:** La ALU no incluye salida `Zero`. La evaluación de igualdad (`BEQ`/`BNE`) y el cálculo de la dirección de destino se realizan mediante un comparador y sumador dedicados en `EX`, dejando la ALU principal libre para operaciones puramente aritmético-lógicas.

## 6. **Modularización de Registros de Pipeline**
* **Teoría (Patterson):** Suele ilustrar los latches de segmentación como un gran bus empaquetado de control.
* **Implementación:** Se dividen en **4 módulos independientes** (`if_id_register`, `id_ex_register`, `ex_mem_register`, `mem_wb_register`) con señales explícitamente nombradas en lugar de buses empaquetados, facilitando la depuración visual.

---

Ninguna de estas desviaciones compromete la especificación de la ISA RV32I ni el funcionamiento del cauce; al contrario, hacen que el procesador sea **100 % sintetizable en hardware real**.