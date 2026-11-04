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

## ADR - Módulos de latch del pipeline

### Contexto

El diseño del datapath requiere registros entre las etapas del pipeline para almacenar el estado intermedio de las instrucciones en vuelo. Se debe definir la granularidad estructural de estos registros en el código.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Un único módulo `pipeline_registers` que agrupa las señales de todas las etapas. |
| **A** | **Cuatro módulos de latch independientes (uno por frontera de etapa).** |

### Decisión

**Opción A.**

### Motivos

* Cada latch tiene una interfaz corta y propia, lo que hace al código más fácil de leer y de ampliar en el futuro.

### Consecuencias

* La arquitectura los lista como un solo módulo conceptual, pero en la implementación RTL se materializa en cuatro módulos distintos.

## ADR - Formato de las señales de control en los latches

### Contexto

Las señales de generadas por la unidad de control deben propagarse a través de las etapas del pipeline. Es necesario definir cómo se agrupan o representan estas señales en las interfaces de los latches.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Usar una única palabra consolidada `ctrl` de 16 bits. |
| **A** | **Usar señales de control separadas y con nombre explícito en los latches.** |

### Decisión

**Opción A.**

### Motivos

* Se entiende de inmediato qué hace cada cable a lo largo del datapath sin necesidad de decodificar mentalmente posiciones de bits.

### Consecuencias

* El empaquetado del formato binario requerido por el comando de debug `GET_PIPELINE` se debe hacer al final, en la etapa E5, al armar la señal `dbg_pipe`.

## ADR - Ubicación del bit de acceso fuera de rango

### Contexto

Cuando el procesador detecta un acceso a memoria de datos fuera del rango de direcciones permitido, el sistema debe manejar el error y retornar valores seguros (ej. 0).

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Resolver el error únicamente dentro de la etapa MEM y forzar la salida de la memoria sin propagar banderas de estado. |
| **A** | **Incluir y propagar un bit `access_out_of_range` hacia el latch MEM/WB.** |

### Decisión

**Opción A.**

### Motivos

* El rango de la dirección efectivamente se verifica en la etapa MEM, pero la instrucción de *load* inyecta o devuelve el valor 0 en el banco de registros recién en la etapa WB. WB necesita la señal para saber qué escribir.

### Consecuencias

* Utiliza el bit 6 (actualmente reservado) del campo `ctrl8` definido en el documento de arquitectura `04` §3.1. Se debe actualizar ese documento.

## ADR - Alcance del reset en los latches del pipeline

### Contexto

Al aplicar una señal de reset al procesador, se debe definir qué porción del estado de los registros de segmentación se limpia para garantizar un inicio seguro.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Resetear únicamente el bit `valid` de cada etapa para anular las instrucciones, ahorrando un mínimo de lógica de ruteo. |
| **A** | **Resetear todos los campos de todos los latches del pipeline.** |

### Decisión

**Opción A.**

### Motivos

* Las consultas de depuración realizadas inmediatamente tras un reset muestran un estado completamente en ceros, evitando que el usuario de debug vea basura o restos confusos de la ejecución anterior.

### Consecuencias

* El costo en recursos lógicos es despreciable: el reset síncrono general es una característica inherente al hardware de los flip-flops en la FPGA.

## ADR - Interfaz de depuración del banco de registros

### Contexto

El sistema de depuración requiere leer el contenido de los registros de propósito general sin interferir con la ejecución normal. Se debe definir cómo enrutar esta consulta a nivel jerárquico superior.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Implementar un módulo intermedio o decodificador de debug que intercepte y gestione los accesos hacia el datapath. |
| **A** | **El módulo jerárquico `cpu_core` expone directamente los puertos `i_debug_reg_addr` y `o_debug_reg_data`.** |

### Decisión

**Opción A.**

### Motivos

* Reutiliza directamente el puerto de lectura asíncrona de debug que ya se diseñó en el banco de registros, dejando resuelta y lista la ruta de datos para el comando `GET_REGS`.

### Consecuencias

* Ninguna.

## ADR - Separación de la unidad de riesgos

### Contexto

Para manejar las dependencias de datos y de control en el pipeline, es necesario implementar lógica que detecte riesgos (hazards) y los resuelva mediante adelantamiento de datos (forwarding) o detención del cauce (stall).

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Implementar un único módulo de riesgos que centralice todas las decisiones. |
| **A** | **Implementar el forwarding y la detección de stall en dos módulos separados.** |

### Decisión

**Opción A.**

### Motivos

* Cada módulo tiene una responsabilidad clara, lo que permite que se puedan aislar y probar por separado mediante sus propios testbenches.

### Consecuencias

* El diseño jerárquico es más limpio y facilita la depuración de la lógica de resolución de dependencias.

## ADR - Mecanismo de Stall

### Contexto

Cuando se detecta un riesgo de datos insalvable (por ejemplo, un *Load-Use hazard*), las etapas iniciales del pipeline deben congelar su estado para dar tiempo a que el dato esté disponible.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Detener o filtrar la señal de reloj (clock gating) para las etapas afectadas. |
| **A** | **El stall se logra utilizando señales de *enable* en los registros, sin tocar el reloj.** |

### Decisión

**Opción A.**

### Motivos

* Es un requisito estricto de la consigna: la red de distribución de reloj (clock tree) no se debe intervenir.

### Consecuencias

* Se evitan problemas de sincronismo, *glitches* y violaciones de timing que suelen ocurrir al manipular el reloj en FPGAs.

## ADR - Lógica de comparación en el Forwarding

### Contexto

La unidad de adelantamiento debe comparar las direcciones de los registros destino de las etapas avanzadas con las direcciones de los registros fuente de la etapa de ejecución para inyectar los datos más recientes.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Hacer viajar las banderas `uses_rs1` y `uses_rs2` por los latches para validar que la instrucción destino realmente lee ese registro. |
| **A** | **El forwarding compara solo los números de registro, ignorando la señal `uses_rs`.** |

### Decisión

**Opción A.**

### Motivos

* Si el campo comparado no es realmente una fuente para la instrucción actual, el multiplexor adelantará un valor que simplemente será ignorado por el datapath.
* A diferencia del forwarding, la lógica de stall sí requiere comprobar `uses_rs` para evitar frenar el pipeline innecesariamente.

### Consecuencias

* Se reduce el tamaño de los latches intermedios y se simplifica la lógica combinacional del módulo de forwarding.

## ADR - Limpieza del latch al insertar una burbuja

### Contexto

Cuando es necesario anular una instrucción en el cauce (por ejemplo, al insertar un stall o vaciar el pipeline por un salto), se debe introducir una "burbuja" en el registro intermedio (ej. `ID/EX`).

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Limpiar únicamente el bit `valid` y poner en cero las señales de control de memoria y escritura. |
| **A** | **La burbuja limpia todos los campos del latch `ID/EX` por completo.** |

### Decisión

**Opción A.**

### Motivos

* Coincide con la política definida para el reset de los latches.
* Una burbuja se visualiza en las herramientas de depuración (debug) como una etapa completamente vacía y en ceros, facilitando su interpretación.

### Consecuencias

* Consume levemente más lógica de ruteo para poner a cero los datos de los registros de propósito general y los inmediatos, pero mejora sustancialmente la experiencia de depuración.

## ADR - Ubicación de la sección de riesgos en el Top-Level

### Contexto

La lógica de riesgos interconecta múltiples etapas del procesador, tomando señales de IF, ID, EX, MEM y WB, lo que requiere definir dónde instanciar estos módulos dentro del código del núcleo.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Intercalar la lógica en un bloque dedicado dentro del código de cada etapa. |
| **A** | **Ubicar la sección de riesgos de forma unificada al final del módulo `cpu_core`.** |

### Decisión

**Opción A.**

### Motivos

* Como esta lógica observa varias etapas del datapath a la vez de forma transversal, agruparla al final tiene más sentido conceptual. Sus salidas se declaran al principio del archivo, aplicando la misma convención utilizada para el lazo de realimentación de la etapa WB.

### Consecuencias

* El flujo natural de las etapas IF hasta WB en el código RTL se mantiene lineal e ininterrumpido.

## ADR - Guardas defensivas en la lógica de riesgos

### Contexto

Durante ciclos irregulares (como el arranque) o frente a combinaciones particulares de instrucciones, la lógica de riesgos podría tomar decisiones anómalas a partir de datos inválidos en los latches.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Omitir comprobaciones adicionales, asumiendo que el control de validez estándar filtrará cualquier efecto adverso final. |
| **A** | **Agregar guardas defensivas explícitas (`!mem_read` en forwarding, `if_id_valid` en stall).** |

### Decisión

**Opción A.**

### Motivos

* La condición de evitar el forwarding si la instrucción fuente es una lectura a memoria (`!mem_read`) cumple explícitamente con la tarea T3.2.3 de la especificación.
* La guarda `if_id_valid` evita generar un stall espurio cuando el latch `IF/ID` contiene basura (por ejemplo, ceros o restos de memoria) al estar inactivo.
* Ninguna de estas condiciones altera el comportamiento observable del procesador en su ejecución normal.

### Consecuencias

* Prevención de interbloqueos (deadlocks) en el arranque o comportamientos indefinidos transitorios.

## ADR - Inserción de burbujas en ID/EX

### Contexto

En un stall load-use, el `load` debe avanzar de EX a MEM mientras la instrucción dependiente espera en ID. `ID/EX` no puede retener su contenido (el load se capturaría dos veces en `EX/MEM`) ni capturar de ID (ejecutaría la dependiente con un dato viejo).

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Controlar la burbuja solo con `i_enable`. |
| A | Entrada `i_insert_bubble` que limpia solo `valid` y los controles de efecto. |
| **B** | **Entrada `i_insert_bubble` que limpia el latch completo, como el reset.** |

### Decisión

**Opción B.**

### Motivos

- `i_enable` solo puede retener o capturar; una burbuja requiere capturar "nada".
- Es consistente con el ADR del alcance del reset: una burbuja se ve en debug como una etapa vacía.

### Consecuencias

- La burbuja solo se inserta si el CPU avanza (`i_enable && i_insert_bubble`).
- La US-3.3 reutiliza la misma entrada para el flush.

## ADR - Forwarding sin `uses_rs`

### Contexto

El forwarding compara `rs1`/`rs2` de la instrucción en EX contra el destino de `EX/MEM` y `MEM/WB`, pero algunos formatos usan esos bits como inmediato.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Hacer viajar `uses_rs1/2` por `ID/EX` y condicionar el forwarding. |
| **A** | **Comparar solo números de registro; `uses_rs` se usa únicamente para el stall.** |

### Decisión

**Opción A.**

### Motivos

- Si el campo no es una fuente, el valor adelantado nunca se consume (la ALU usa el inmediato).
- Un stall falso sí cuesta un ciclo, por eso ahí sí se usa `uses_rs`.

### Consecuencias

- `store_data` de instrucciones que no son stores puede mostrar un valor adelantado sin significado, sin efectos.

## ADR - Módulo de resolución de saltos

### Contexto

La etapa EX debe decidir si un `beq`, `bne`, `jal` o `jalr` cambia el flujo y hacia dónde. La decisión depende de la condición, del tipo de salto, de la validez de la instrucción y del destino.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Escribir la lógica directamente en `cpu_core`, junto a la ALU. |
| **A** | **Un módulo `branch_unit` combinacional con su propio testbench.** |

### Decisión

**Opción A.**

### Motivos

- Se prueba por separado con casos límite (igualdad en un solo bit, destinos negativos, bit 0 de `jalr`) sin armar un programa completo.
- `cpu_core` conserva su papel de cableado entre etapas.
- La condición y el destino quedan juntos y fáciles de leer en pocas líneas.

### Consecuencias

- Un módulo y un testbench más.
- La interfaz recibe `i_valid`: una burbuja en EX puede traer controles encendidos y no debe redirigir.

## ADR - Selección del próximo PC sin módulo `pc_control`

### Contexto

El documento de arquitectura (§1.1) lista un módulo `pc_control`. Con la US-3.3 el PC debe elegir entre `PC + 4` y el destino del salto.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Crear `pc_control` con el registro del PC, el mux del próximo PC y la lógica de stall. |
| **A** | **Mantener el PC como instancia de `register` y agregar un `mux` de 2 entradas en `cpu_core`.** |

### Decisión

**Opción A.**

### Motivos

- Reutiliza el `mux` genérico, igual que el resto de `cpu_core`.
- La selección es una sola señal (`ex_redirect`); un módulo nuevo solo envolvería un registro y un mux.
- Los nombres del roadmap son sugeridos, no obligatorios.

### Consecuencias

- `pc_control` no se materializa. Si la US-4.3 necesita más lógica de fetch (`fetch_stop`, límite `N_WORDS`), conviene reevaluar la extracción.
- El documento de arquitectura (§1.1) debe actualizarse.

## ADR - Generación del flush en `hazard_unit`

### Contexto

El flush por salto tomado afecta a `IF/ID` e `ID/EX`, igual que el stall afecta al front-end. Hay que decidir dónde se genera la señal.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | `cpu_core` usa directamente `ex_redirect` como señal de flush. |
| **A** | **`hazard_unit` recibe `i_ex_redirect` y entrega `o_flush_front`.** |

### Decisión

**Opción A.**

### Motivos

- Coincide con el documento de arquitectura: `flush_front` sale de `hazard_unit` (§11.5).
- Deja en un solo módulo las dos señales que controlan el front-end (stall y flush).
- La US-4.3 suma la condición de `HALT` en este mismo punto, sin tocar `cpu_core`.

### Consecuencias

- Hoy `o_flush_front` es una conexión directa de `i_ex_redirect`.
- Los testbenches existentes de `hazard_unit` deben conectar la entrada nueva.
- Stall y flush no coinciden nunca (el stall exige un `load` en EX y el flush un salto). Los testbenches lo vigilan.

## ADR - Flush de `IF/ID` con `i_insert_bubble`

### Contexto

`ID/EX` ya tiene una entrada `i_insert_bubble` que limpia el latch completo si el CPU avanza. `IF/ID` también necesita anularse cuando se toma un salto.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Entrada distinta (`i_flush`) con semántica propia. |
| **A** | **La misma entrada `i_insert_bubble`, con la misma semántica que en `ID/EX`.** |

### Decisión

**Opción A.**

### Motivos

- Un mismo nombre para un mismo comportamiento en ambos latches: se limpia por completo, y solo si el front-end avanza.
- Es consistente con el ADR de inserción de burbujas en `ID/EX`.
- Condicionar a `i_enable` evita alterar el pipeline mientras el CPU está pausado (modo `STEP`).

### Consecuencias

- `register_if_id` tiene una entrada más; su testbench debe conectarla.
- `IF/ID` no guarda la instrucción: sale directo de la memoria de programa y el flush no la limpia. Se resuelve por la regla del ADR siguiente: el cliente decide por `valid`.

## ADR - Destino de `jalr` calculado por la ALU

### Contexto

El destino de `jalr` es `rs1 + imm` con el bit 0 anulado. `branch` y `jal` usan `PC + imm`, que requiere un sumador dedicado.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Un segundo sumador dentro de `branch_unit` para `rs1 + imm`. |
| **A** | **Reutilizar el resultado de la ALU (`rs1 + imm`) y anular el bit 0 en `branch_unit`.** |

### Decisión

**Opción A.**

### Motivos

- La unidad de control ya configura la ALU para `jalr` (suma con el inmediato como segundo operando).
- Evita un sumador de 32 bits.
- La ALU ya recibe `rs1` con forwarding, así que el destino también lo respeta.

### Consecuencias

- `branch_unit` recibe `i_alu_result`, que solo usa `jalr`.
- El camino `forwarding → ALU → redirect → mux del PC` es candidato a camino crítico. Se revisa en la etapa E7.

## ADR - Contenido de una etapa invalidada: decide `valid`

### Contexto

Tras un flush, `IF/ID` queda con `valid = 0` pero con la `instr` anulada (sale de la memoria de programa), y un ciclo después `ID/EX` queda con `valid = 0` arrastrando esa instrucción y sus controles. El ADR de burbujas en `ID/EX` menciona que una burbuja se ve "vacía y en ceros". Hay que decidir si esa visualización debe garantizarse.

### Alternativas

| Opción | Descripción |
| --- | --- |
| **0** | **El cliente de debug decide por `valid`. Una etapa con `valid = 0` está vacía y el resto de sus campos son irrelevantes.** |
| A | Garantizar ceros: insertar burbuja en `ID/EX` también cuando `!if_id_valid` y enmascarar `instr` de `IF/ID` con `valid` al armar `dbg_pipe`. |

### Decisión

**Opción 0.**

### Motivos

- Un flush invalida una instrucción apagando sus permisos de escritura; el resto de las señales pasan a ser irrelevantes. Limpiar los datos no agrega valor funcional.
- La opción A suma lógica combinacional (términos de burbuja y enmascaramiento) solo para una presentación estética, con costo de recursos y posible retardo en el camino crítico.
- Interpretar el estado es responsabilidad del software de depuración, y el documento de arquitectura ya prevé que el cliente use `valid`.

### Consecuencias

- Sin cambios de RTL.
- `GET_PIPELINE` puede traer campos no nulos en etapas con `valid = 0`. La CLI no debe desensamblar ni mostrar esos campos.
- El ADR de burbujas en `ID/EX` sigue vigente para la burbuja insertada por stall o flush, pero no garantiza que la etapa se vea en ceros ciclos después.
- Hay que ajustar la redacción del documento de arquitectura (§3) y fijar la regla en la especificación de la CLI (E6).

## ADR - Exclusión entre Debug Unit y CPU por estado, sin interlock en hardware

### Contexto

La Debug Unit escribe la memoria de programa y lee registros y memoria de datos mientras el CPU puede estar corriendo. Hay que decidir quién evita que esos accesos interfieran: un circuito entre ambos o la máquina de estados de la Debug Unit.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Un interlock en hardware que bloquee la escritura de `program_memory` mientras el CPU avanza. |
| **A** | **Sin interlock: la Debug Unit solo escribe en los estados permitidos y rechaza el resto con `ERR_BUSY`.** |

### Decisión

**Opción A.**

### Motivos

- Las lecturas de debug no necesitan protección: usan puertos de solo lectura con registro de salida propio, y no alteran el CPU aun si coinciden con un acceso del CPU.
- La escritura de la memoria de programa con el CPU pausado tampoco corrompe nada: la lectura de instrucciones queda deshabilitada y la instrucción ya registrada en IF/ID no cambia.
- El único riesgo real es lógico, no físico: escribir el programa mientras el CPU corre lo dejaría ejecutando una mezcla de instrucciones viejas y nuevas. Eso ya lo impide la matriz comando × estado (`LOAD_PROGRAM` devuelve `ERR_BUSY` en `RUNNING`).
- Un interlock agregaría lógica y un camino hacia el habilitador de escritura de la memoria para cubrir algo que el protocolo ya cubre.

### Consecuencias

- El hardware, por sí solo, no impide una escritura de la Debug Unit durante `RUNNING`; depende de que la Debug Unit respete su matriz de estados.
- En E5 hay que probar explícitamente que `LOAD_PROGRAM`, `GET_MEMORY`, `GET_REGS` y `GET_PIPELINE` devuelven `ERR_BUSY` en `RUNNING` (T5.3.7).
- Si por error coinciden en el mismo ciclo y la misma dirección una lectura del CPU y una escritura de la Debug Unit, el resultado sigue siendo determinista: la lectura devuelve el dato anterior (verificado en `tb_memory_port_contention`).

## ADR - Convenciones de los testbenches de riesgos estructurales

### Contexto

Los testbenches de la US-3.4 necesitan un CPU que ejecute programas, pero todavía no existen la Debug Unit (E5), `HALT` ni el límite `N_WORDS` (US-4.3). También hay que comparar el contenido de la memoria de datos, que el reset no borra por decisión de diseño.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Esperar a tener la Debug Unit y `HALT` para escribir estas pruebas. |
| **A** | **Emular la Debug Unit desde el testbench, terminar los programas en `jal x0, 0` y limpiar la memoria de datos por jerarquía antes de las comparaciones.** |

### Decisión

**Opción A.**

### Motivos

- La emulación usa los mismos puertos que usará la Debug Unit (escritura de `program_memory`, puerto B de `data_memory` y puerto de debug de los registros), así que las pruebas siguen siendo válidas cuando exista la real.
- Un salto a sí mismo mantiene al CPU sin ejecutar posiciones sin programa y no modifica registros ni memoria.
- La memoria de datos conserva su contenido entre ejecuciones. Una prueba que compare contenido sin limpiarla puede pasar aunque se hayan perdido stores, porque la ejecución anterior dejó los mismos valores. Esto se detectó al inyectar fallas en el RTL (ver el documento de la US-3.4).

### Consecuencias

- La limpieza por jerarquía (`data_mem.byte_bank[n].bank[...]`) es un atajo solo de simulación y depende del nombre del bloque `generate` de `data_memory`. Si se renombra, hay que actualizar la tarea `clear_data_memory_words`.
- Al implementar la US-4.3, los programas de prueba pueden pasar a terminar en `HALT` y la convención del salto a sí mismo se retira.
- Los programas de prueba se arman con el mini-ensamblador `test_instruction_encoders.vh`, cotejado con un desensamblador externo, y no con hexadecimal escrito a mano.
