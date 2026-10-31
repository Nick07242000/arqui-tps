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