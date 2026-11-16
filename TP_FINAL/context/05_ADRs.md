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

* Utiliza el bit 6 (antes reservado) del campo `ctrl8` de `MEM/WB`, ya reflejado en el documento de arquitectura 04 §3.1.

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

* Las consultas de depuración realizadas inmediatamente tras un reset muestran todos los latches en ceros, sin restos de la ejecución anterior. Excepción: `IF/ID.instr` y `MEM/WB.mem_raw` son salidas de las memorias, no de los latches, y conservan su último valor; el cliente decide por `valid` (ver ADR «Contenido de una etapa invalidada»).

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
* La guarda `if_id_valid` evita que `stall` dependa del contenido residual de `IF/ID` cuando la etapa está vacía. No cambia ciclos ni efectos: con `IF/ID` inválido el frente ya está vacío.
* Ninguna de las dos guardas altera el comportamiento observable. Verificado por inyección de falla: al quitar cualquiera, el estado final y los ciclos no cambian en 600 casos aleatorios. La guarda `!mem_read` es inalcanzable porque el stall load-use ya impide ese caso.

### Consecuencias

* Hacen explícita la regla T3.2.3 y evitan que la lógica de riesgos dependa del contenido de etapas vacías. No previenen interbloqueos: no existe ninguno posible, porque tras un stall `ID/EX` recibe siempre una burbuja.

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
- Es consistente con el ADR del alcance del reset: la burbuja insertada deja la etapa vacía (la visualización posterior la decide `valid`, ver ADR «Contenido de una etapa invalidada»)
- Coincide con la política definida para el reset de los latches.

### Consecuencias

- La burbuja solo se inserta si el CPU avanza (`i_enable && i_insert_bubble`).
- La US-3.3 reutiliza la misma entrada para el flush.
- La señal de limpieza (stall o flush) llega a unos 190 FF de ID/EX. Si en E7 limita el timing, alcanza con limpiar valid y los controles de efecto.

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
- Se reduce el tamaño de los latches intermedios y se simplifica la lógica combinacional del módulo de forwarding.

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

- Se prueba por separado con casos límite (igualdad en un solo bit, destinos negativos, bits bajos del destino de `jalr`) sin armar un programa completo.
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

El destino de `jalr` es `rs1 + imm`; la ISA anula el bit 0 y, sin extensión C, este procesador alinea también el bit 1.

`branch` y `jal` usan `PC + imm`, que requiere un sumador dedicado.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Un segundo sumador dentro de `branch_unit` para `rs1 + imm`. |
| **A** | **Reutilizar el resultado de la ALU (`rs1 + imm`) y alinear a palabra el destino de todos los saltos en `branch_unit`.** |

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

## ADR - Módulo `program_loader` separado de la Debug Unit, con timeout propio

### Contexto

La carga de un programa es el primer comando que la Debug Unit debe ejecutar y la US-4.2 se implementa antes que la UART y la Debug Unit (E5). Hay que decidir dónde vive la lógica que recibe el payload de `LOAD_PROGRAM`, lo valida y escribe `program_memory`.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Implementarla dentro de la Debug Unit, junto con el parser de comandos. |
| **A** | **Un módulo `program_loader` que trabaja sobre una secuencia de bytes, con su propio timeout entre bytes.** |

### Decisión

**Opción A.**

### Motivos

- Se puede probar completo (validaciones, carga truncada, reprogramación) en simulación sin UART ni parser, alineado con el orden del roadmap (E4 antes que E5).
- La Debug Unit queda como frontera con el protocolo: decodifica el encabezado `[CMD][LEN]` y le entrega los bytes del payload al loader, sin conocer el formato interno de la imagen.
- Con el timeout dentro del loader, el criterio "se detectan cargas truncadas" se verifica en esta historia y no queda pendiente de E5.

### Consecuencias

- El timeout de 100 ms existe en dos lugares: el loader para `LOAD_PROGRAM` y el parser de la Debug Unit para el resto de los comandos, que tienen payloads de pocos bytes.
- La Debug Unit debe reenviar exactamente `LEN` bytes y esperar `o_load_finished` antes de leer el comando siguiente.
- Los nombres del roadmap son sugeridos: `program_loader` no figura en la tabla de módulos del documento de arquitectura (§2) y conviene agregarlo.

## ADR - El encabezado se valida antes de invalidar el programa, resetear la CPU o escribir

### Contexto

El mensaje trae `N_WORDS` y `LEN`, que deben ser coherentes. Si no lo son, hay que decidir qué se hace con el programa que ya estaba cargado y con la CPU, y qué se hace con los bytes restantes. La arquitectura (§7.3, §8.4) invalida el programa y aplica `cpu_rst` al recibir el comando, de modo que toda carga con error termina en `EMPTY`; pero la regla 3 del parser (§8.3) y el criterio de la US-5.2 piden que un comando inválido no corrompa CPU ni memorias.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Escribir las palabras a medida que llegan y validar al final. |
| A | Invalidar el programa y resetear la CPU al recibir `i_load_start`; validar el encabezado después. Toda carga con error termina en `EMPTY`. |
| **B** | **Validar el encabezado completo antes de invalidar el programa, resetear la CPU o escribir. Ante un encabezado inválido, consumir los bytes restantes sin tocar nada.** |

### Decisión

**Opción B.**

### Motivos

- Un comando inválido no destruye el programa ya cargado ni el estado de la CPU: un error del cliente (por ejemplo, un `N_WORDS` mal calculado) no obliga a recargar.
- Cumple literalmente la regla 3 del parser y el criterio de la US-5.2, sin excepciones para `LOAD_PROGRAM`.
- Un `N_WORDS` o un `LEN` inválidos nunca llegan a escribir `program_memory`, y la dirección no puede salirse de rango por construcción.
- Consumir el mensaje completo mantiene sincronizado el flujo (regla 1 del parser): los bytes de un comando inválido no se interpretan como comandos nuevos.
- Cuando `N_WORDS` y `LEN` fallan a la vez se informa `ARGUMENT` (el dato declarado es el primer sospechoso).

### Consecuencias

- El encabezado válido es el punto de no retorno: desde ahí el programa anterior se invalida (`o_program_valid = 0`, `o_n_words = 0`) y la CPU entra en reset. Una carga que se interrumpe después de ese punto deja el sistema sin programa.
- Un timeout antes de validar el encabezado también conserva el programa y la CPU.
- La matriz comando × estado (§7.3), el diagrama de estados (§7.2) y los pasos 1 y 5 de §8.4 de la arquitectura deben actualizarse: `LOAD_PROGRAM` OK → `READY`; error con `o_program_valid = 1` → el estado no cambia; error con `o_program_valid = 0` → `EMPTY`.
- La Debug Unit decide el estado a partir de `o_program_valid` después de `o_load_finished`.
- Se necesita un contador de bytes restantes (16 bits) y un estado `DISCARD_BYTES`.
- Tras un timeout con encabezado válido pueden quedar escritas palabras completas; no se ejecutan porque `o_n_words = 0` y `o_program_valid = 0`.

## ADR - CPU en reset mientras se reescribe la imagen

### Contexto

Mientras se escribe `program_memory` la CPU no debe ejecutar. El documento de arquitectura ubica `cpu_rst` al inicio de `LOAD_PROGRAM` (§8.4) y también al fin (§1.3). Con la decisión anterior, el programa y la CPU no se tocan hasta validar el encabezado. Hay que decidir durante qué tramo de la carga la CPU permanece en reset.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Pulso de reset al inicio o al final de la carga; el resto del tiempo depende de que `cpu_en` esté en 0. |
| A | `o_cpu_reset` en 1 durante toda la carga, desde `i_load_start`. |
| **B** | **`o_cpu_reset` en 1 desde que el encabezado es válido hasta el fin de la carga (mientras dura la escritura de la imagen).** |

### Decisión

**Opción B.**

### Motivos

- Es coherente con la decisión anterior: la CPU no se resetea por un comando que luego se rechaza.
- Desde el primer byte escrito hasta el final, la CPU no puede avanzar aunque la Debug Unit tuviera un error: en `cpu_core` el reset tiene prioridad sobre `cpu_en` (también anula los stores). La protección es del hardware y no del protocolo.
- Cumple la política de carga: registros en 0 y pipeline vacío al finalizar, sin lógica adicional.
- Invariante simple de verificar: toda escritura de `program_memory` ocurre con la CPU en reset y con el programa anterior ya invalidado.

### Consecuencias

- Durante el encabezado el loader no protege a la CPU: la Debug Unit debe rechazar `LOAD_PROGRAM` con la CPU en `RUNNING` (`ERR_BUSY`) y no avanzar la CPU mientras la carga está en curso.
- El top debe combinar los resets: `cpu_rst = reset_de_la_DU | o_cpu_reset | sys_rst`.
- `o_cpu_reset` es una decodificación combinacional del estado del loader (`state == RECEIVE_WORDS`) con fanout hacia todos los flip-flops del CPU. Si en E7 resultara crítico, se registra la señal.

## ADR - El PC se retiene con la búsqueda detenida, salvo redirect

### Contexto

Cuando `HALT` se confirma o el PC sale de la imagen, IF deja de producir instrucciones válidas. Hay que decidir qué hace el registro del PC mientras tanto. El fin de imagen no es permanente: un branch o jump en EX puede devolver el PC al interior de la imagen.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | El PC sigue avanzando siempre; solo se invalida lo que se busca. |
| A | El PC se retiene siempre que la búsqueda está detenida. |
| **B** | **El PC se retiene con la búsqueda detenida, salvo que EX lo redirija.** |

### Decisión

**Opción B.**

### Motivos

- La opción 0 deja el PC corriendo después de `done`, por lo que el PC final no sirve para depurar y el CPU deja de ser idempotente con `done` en alto (la Debug Unit tarda un ciclo en registrarlo).
- La opción A pierde el redirect de un branch tomado en la última palabra de la imagen: el lazo se rompería. Lo detectó la prueba del branch en el borde de la imagen al inyectar la falla.
- La opción B mantiene ambas propiedades con un solo término extra: `pc_enable = front_end_enable && (!fetch_stopped || ex_redirect)`.

### Consecuencias

- Con `END_OF_IMAGE`, el PC queda en `4 · N_WORDS`. Con `HALT` queda en el menor entre `H + 12` y `4 · N_WORDS`.
- `ex_redirect` ya alimentaba el selector del mux del próximo PC; ahora también el enable del PC. Se revisa en E7 junto con el camino `forwarding → ALU → redirect`.

## ADR - `halting` solo cambia cuando el CPU avanza

### Contexto

`HALT` se confirma en EX y, en el mismo flanco, se anulan `IF/ID` e `ID/EX`. Esos latches solo capturan o se limpian con `cpu_en = 1`. En modo paso a paso, un `HALT` puede quedar en EX con el CPU pausado.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | `halting` se activa apenas `halt_commit` está en alto, aunque el CPU esté pausado. |
| **A** | **`halting` se activa solo con `cpu_en = 1`, en el mismo flanco que el flush.** |

### Decisión

**Opción A.**

### Motivos

- Con la opción 0, durante la pausa el CPU mostraría la búsqueda detenida pero el pipeline sin anular: un estado que no corresponde a ningún ciclo real.
- La opción A mantiene el estado coherente: lo que se consulta con el CPU pausado es siempre el resultado de un número entero de ciclos.

### Consecuencias

- `halt_controller` recibe `i_enable`.
- La prueba de paso a paso con pausas lo verifica: con `HALT` en EX y `cpu_en = 0`, `halting` permanece en 0.

## ADR - `done` combinacional y motivo enmascarado

### Contexto

La Debug Unit necesita saber cuándo terminó la ejecución y por qué. Hay que decidir si `done` se registra o se deriva de las validez de las etapas, y qué vale el motivo mientras no terminó.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | `done` registrado; `done_reason` sin enmascarar. |
| **A** | **`done` combinacional (`fetch_stopped` y los cuatro `valid` en 0); `done_reason` vale `NONE` mientras `done = 0`.** |

### Decisión

**Opción A.**

### Motivos

- Los `valid` ya son flip-flops: `done` es una compuerta sobre registros, sin camino largo.
- Registrar `done` retrasaría un ciclo la finalización y obligaría a razonar sobre un ciclo de CPU "de más" ejecutándose.
- Con el motivo en `NONE` hasta que `done` se activa, `GET_STATUS` puede copiar el campo sin lógica adicional (`0 = ninguna`).
- Si `HALT` y fin de imagen coinciden, gana `HALT`: es la información más específica y el caso habitual.

### Consecuencias

- Con `N_WORDS = 0`, `done` vale 1 trivialmente; la Debug Unit lo ignora en `EMPTY` y `LOADING`.
- Con `done = 1` el CPU es idempotente, así que un ciclo habilitado de más al registrar `done` no altera el estado.

## ADR - Reevaluación de `pc_control` en la US-4.3

### Contexto

El ADR "Selección del próximo PC sin módulo `pc_control`" dejaba abierto reevaluar la extracción si la US-4.3 sumaba lógica de fetch (`fetch_stop`, límite `N_WORDS`).

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Crear `pc_control` con el PC, el mux del próximo PC, `fetch_stop` y el límite `N_WORDS`. |
| **A** | **Mantener el PC y su mux en `cpu_core` y poner la lógica de fin de ejecución en `halt_controller`.** |

### Decisión

**Opción A.**

### Motivos

- La lógica nueva (`halting`, `fetch_stopped`, `done`) trata del *fin de la ejecución*, no de elegir el próximo PC; el documento de arquitectura ya la ubicaba en `halt_controller`.
- En `cpu_core` solo queda un término en el enable del PC y la validez de IF (`!fetch_is_stopped`).
- Un `pc_control` mezclaría la selección del PC con el vaciado del pipeline, que depende de la validez de las cuatro etapas.

### Consecuencias

- `pc_control` sigue sin materializarse; el ADR anterior queda resuelto.
- `halt_controller` expone `o_halt_commit`, que `cpu_core` entrega a `hazard_unit` para el flush, tal como anticipaba el ADR "Generación del flush en `hazard_unit`".

## ADR - Módulo `execution_controller` separado de la Debug Unit

### Contexto

El documento de arquitectura (§7.1, §7.2) ubica en la Debug Unit la FSM de sistema (`EMPTY`, `READY`, `RUNNING`, `PAUSED`, `DONE`) y la generación de `cpu_en = (state == RUNNING) | step_pulse`. La US-4.4 se implementa antes que la UART y el parser (E5), pero el paso a paso y la ejecución continua ya se pueden verificar con el CPU real. Hay que decidir dónde vive esa lógica.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Implementarla dentro de la Debug Unit, junto con el parser de comandos. |
| **A** | **Un módulo `execution_controller` que recibe las órdenes como pulsos y devuelve el estado y un código de resultado.** |

### Decisión

**Opción A.**

### Motivos

- Se prueba completo con `cpu_core`, memorias y `program_loader` sin UART ni parser, respetando el orden del roadmap (E4 antes que E5).
- Sigue el mismo criterio que `program_loader`: la Debug Unit queda como frontera con el protocolo y no conoce los detalles de la ejecución.
- Los códigos de resultado (`OK`, `BUSY`, `NO_PROGRAM`, `WRONG_STATE`) se traducen a los `STATUS` del protocolo sin que el controlador conozca los bytes de la UART.
- La lógica del estado del sistema y la del permiso de avance comparten el mismo registro de estado: separarlas en dos módulos obligaría a duplicarlo.

### Consecuencias

- La Debug Unit debe esperar `o_command_finished` antes de emitir otra orden; el controlador ignora una orden que llegue con otra en curso.
- La decisión de responder `ERR_BUSY` a `LOAD_PROGRAM` y a las consultas `GET_*` durante `RUNNING` sigue siendo de la Debug Unit, a partir de `o_system_state`.
- El controlador aplica la regla de estado tras una carga: completa → `READY`; rechazada con el programa anterior intacto → el estado no cambia; interrumpida después de un encabezado válido → `EMPTY`.
- `execution_controller` no figura en la tabla de módulos del documento de arquitectura (§1.1) y conviene agregarlo.
- El top debe combinar los resets: `cpu_rst = sys_rst | o_cpu_reset (execution_controller) | o_cpu_reset (program_loader)`.

## ADR - `STEP`: pulso registrado de un ciclo y `done` leído un ciclo después

### Contexto

Un `STEP` debe habilitar al CPU durante exactamente un ciclo y responder con el estado posterior a ese ciclo, sin tocar el clock. Hay que decidir cómo se genera el permiso de avance y cuándo se lee `done`.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | `cpu_enable` combinacional a partir de `i_step_request`. |
| **A** | **Un pulso registrado (`step_pulse`) de un ciclo; el estado final se decide un ciclo después, cuando el CPU ya avanzó.** |
| B | Igual que A, y además condicionar `cpu_enable` con `!done`. |

### Decisión

**Opción A.**

### Motivos

- Con un pulso registrado, el ancho del permiso no depende del ancho de la orden ni de glitches de la entrada: es siempre un ciclo.
- `done` es combinacional sobre registros que cambian en el flanco del ciclo habilitado; leído en el ciclo siguiente describe el estado posterior al paso. Leerlo en el mismo ciclo del pulso devolvería el estado previo (la inyección de esa falla se detecta en el testbench).
- La opción B agrega un camino `done → CE` de alto fanout. No hace falta: con `done = 1` el CPU es idempotente (ya lo establece el documento de arquitectura, §7.1).

### Consecuencias

- Latencia de respuesta medida: `RUN` 1 ciclo, `RESET` 2, `STEP` 3.
- `o_system_state` no cambia hasta que el paso terminó, así que siempre es coherente con lo que el CPU muestra.
- Un `STEP` consume un ciclo de reloj del pipeline aunque haya un stall o un flush: el permiso de avance es ortogonal a los riesgos.
- En `RUNNING` se habilita un ciclo extra al detectar `done`. No tiene efectos por la idempotencia del CPU; el testbench lo verifica comparando el estado antes y después de ese ciclo.

## ADR - `RESET` corta el enable antes de aplicar el reset

### Contexto

`RESET` aborta una ejecución en `RUNNING`. En ese momento `cpu_enable` vale 1 de forma continua, y el reset síncrono debe aplicarse sobre un CPU que no esté avanzando. `cpu_core` ya da prioridad al reset sobre el enable, pero conviene no depender de eso.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Mantener `RUNNING` hasta que termine el pulso de reset; durante un ciclo coinciden `cpu_enable` y `cpu_reset`. |
| **A** | **Cambiar el estado a `READY` al aceptar la orden y aplicar el pulso de reset en el ciclo siguiente.** |

### Decisión

**Opción A.**

### Motivos

- `cpu_enable` y `cpu_reset` nunca coinciden: cada flip-flop y cada memoria tiene un único motivo para cambiar en un ciclo dado.
- Permite una invariante simple y verificable por un monitor: `cpu_enable` solo vale 1 durante un `STEP` en curso o con el estado en `RUNNING`.

### Consecuencias

- Durante un ciclo `o_system_state` ya vale `READY` y el CPU todavía no se reseteó. No es observable: la Debug Unit responde recién con `o_command_finished`, dos ciclos después de aceptar la orden.
- `RESET` en `EMPTY` mantiene `EMPTY`; en cualquier otro estado deja `READY`. El estado alcanza para saberlo: no hace falta consultar `i_program_valid`.

## ADR - Las comparaciones de estado del testbench se hacen por `valid`

### Contexto

La prueba central de la US-4.4 compara, ciclo a ciclo, la ejecución paso a paso contra la continua. La primera versión de la comparación falló en los primeros pasos y en el ciclo extra de `RUN`, aunque el RTL era correcto: la "foto" incluía campos de etapas con `valid = 0`, como `ID/EX.instr`, que captura la salida vieja de la BRAM de `program_memory` y puede variar entre una ejecución y otra.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Comparar todos los campos de todos los latches. |
| **A** | **Enmascarar en la foto los campos de cada etapa con su `valid`.** |
| B | Limpiar esos campos en el RTL (la opción A del ADR «Contenido de una etapa invalidada»). |

### Decisión

**Opción A.**

### Motivos

- Es coherente con el ADR «Contenido de una etapa invalidada: decide `valid`»: una etapa con `valid = 0` está vacía y el resto de sus campos son irrelevantes.
- La opción B sumaría lógica combinacional al RTL solo para que una comparación de simulación resulte más cómoda.

### Consecuencias

- Sin cambios de RTL.
- La foto lee los registros por jerarquía (`cpu.register_file.registers`) y las etapas con `cpu.if_id_valid` y similares. Es un atajo de simulación que depende de esos nombres, igual que la limpieza de `data_memory` en el ADR de convenciones de los testbenches de riesgos estructurales.
- Los programas de prueba se arman con un mini-ensamblador local de seis funciones dentro del testbench. Pueden reemplazarse por `test_instruction_encoders.vh` sin cambiar las pruebas.

## ADR - UART sin buffers: pulso de un ciclo y dato estable

### Contexto

La tarea T5.1.3 pide definir buffers y el comportamiento ante overflow. El receptor entrega bytes a la Debug Unit y el transmisor los recibe de ella. Hay que decidir si cada sentido lleva una FIFO.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | FIFO en recepción y en transmisión, con indicadores de lleno/vacío y manejo de overflow. |
| **A** | **Sin buffers: `uart_rx` entrega cada byte como un pulso de un ciclo (`o_byte_valid`) y `uart_tx` aplica contrapresión con `o_busy`.** |

### Decisión

**Opción A.**

### Motivos

- Entre dos bytes consecutivos pasan unos 2340 ciclos y la Debug Unit consume cada byte en el ciclo del pulso. Un byte no puede pisar a otro sin consumir.
- El protocolo es estrictamente pregunta-respuesta: la PC no envía el comando siguiente hasta recibir la respuesta, y la FPGA no emite mensajes espontáneos.
- Una FIFO agrega memoria, contadores de nivel y un camino de overflow que habría que probar, para cubrir un caso que el protocolo ya impide.
- `o_byte_data` se mantiene estable hasta el byte siguiente, así que la Debug Unit lo puede leer también un ciclo tarde sin riesgo.

### Consecuencias

- La UART no absorbe ráfagas: la Debug Unit debe tomar `o_byte_data` en el ciclo en que `o_byte_valid` vale 1.
- Un byte que la Debug Unit no espera (comando desconocido, bytes sobrantes) se entrega igual; es ella quien decide qué hacer.
- Si una US futura incorporara mensajes asíncronos de la FPGA hacia la PC, habría que reevaluar esta decisión.

## ADR - Tras un framing error el receptor espera la línea en reposo

### Contexto

Cuando el bit de stop llega en 0, la trama es inválida y el byte se descarta. Hay que decidir qué hace el receptor a continuación. Una línea atascada en 0 (break, cable desconectado) tiene el mismo aspecto que una cadena infinita de tramas con stop en 0.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Volver a `IDLE` de inmediato. |
| **A** | **Pasar a un estado `WAIT_LINE_IDLE` y volver a `IDLE` recién cuando la línea valga 1.** |

### Decisión

**Opción A.**

### Motivos

- Con la opción 0, una línea fija en 0 se interpretaría como un nuevo start cada 10 bits: un framing error cada ≈ 87 µs, que la Debug Unit tendría que procesar uno tras otro.
- Con la opción A se informa un solo error por evento y el receptor retoma solo cuando la línea se libera.
- Cuesta un estado y una condición de salida.

### Consecuencias

- Un emisor que envíe un stop en 0 seguido de un start inmediato, sin que la línea toque 1, pierde la trama siguiente. Es aceptable: no es tráfico válido, y el cliente espera ≥ 150 ms y vacía el buffer tras cualquier error (arquitectura §8.3).
- Con la línea fija en 0 el receptor queda esperando sin generar actividad. Es una falla física que ninguna lógica puede resolver.
- El testbench `tb_uart_rx` verifica que un break de más de cinco tramas produce exactamente un framing error.

## ADR - Muestreo único en el centro del bit con confirmación del start

### Contexto

El receptor debe leer cada bit en un instante en que la línea sea estable. Hay que elegir la técnica de muestreo.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Sobremuestreo (por ejemplo x16) con voto por mayoría en cada bit. |
| **A** | **Una muestra por bit en su centro, tras confirmar el start a medio bit.** |

### Decisión

**Opción A.**

### Motivos

- Con 234 ciclos por bit, una única muestra en el centro deja un margen amplio: el receptor tolera aproximadamente de −4,7 % a +5,6 % de diferencia de velocidad (medido en simulación), contra un error real de 0,16 % entre 27 MHz y 115200 baudios.
- La confirmación del start a medio bit descarta pulsos de ruido más cortos que medio bit sin lógica adicional.
- El sobremuestreo agregaría un contador y la lógica de votación para mejorar la inmunidad al ruido en un enlace USB-UART corto, donde no es un problema esperado.

### Consecuencias

- No hay filtrado de ruido dentro de un bit. Un glitch de más de medio bit se toma como start y produce un byte espurio o un framing error.
- Esos casos los cubren los timeouts del protocolo (100 ms en la Debug Unit, ≥ 150 ms de espera en el cliente).
- El margen de tolerancia mínimo se verifica en `tb_uart_rx` con emisores ±2 % y ±4 %.

## ADR - Pedido de transmisión con `o_busy` en 1: se ignora

### Contexto

`uart_tx` envía un byte por vez. La arquitectura (§11.2) indica que `tx_start` es válido solo con `!tx_busy`, pero hay que decidir qué hace el módulo si ese contrato se viola.

### Alternativas

| Opción | Descripción |
| --- | --- |
| 0 | Aceptar el pedido y sobrescribir la trama en curso. |
| A | Registro de retención de un byte: guardar el pedido y enviarlo al terminar la trama actual. |
| **B** | **Ignorar el pedido; la trama en curso no se altera.** |

### Decisión

**Opción B.**

### Motivos

- La opción 0 corrompería el byte que ya está saliendo, y el receptor de la PC vería una trama defectuosa.
- La opción A necesita 8 flip-flops más y un estado de «pendiente», para tolerar un error que la Debug Unit no debería cometer.
- Ignorar el pedido protege la trama en curso con una guarda de una condición.

### Consecuencias

- Si la Debug Unit viola el contrato, el byte se pierde sin aviso. Se evita con la regla de uso: pedir solo con `o_busy` en 0.
- `o_busy` cubre la trama completa, bit de stop incluido (2340 ciclos), de modo que pedir el byte siguiente en cuanto baja no acorta el stop anterior.
- `o_busy` sube un ciclo después de que la Debug Unit pone `i_send_request` en 1. Hay que documentarlo para quien escriba el secuenciador de respuestas (US-5.2): no consultar `o_busy` en ese ciclo intermedio y mantener `i_send_request` como un pulso de un ciclo.
- `tb_uart_tx` verifica el caso con pedidos justo tras aceptar, a mitad de trama y en el último ciclo con `o_busy` en 1.