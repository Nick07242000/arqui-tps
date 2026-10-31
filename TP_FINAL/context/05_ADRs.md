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