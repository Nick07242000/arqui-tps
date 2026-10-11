# TRABAJO FINAL: PIPELINE PROCESADOR (RISC-V)

---

## 1. Consigna General

El objetivo de este proyecto final es diseñar e implementar un procesador RISC-V segmentado (*pipelined*) junto con un entorno de depuración e interacción en FPGA.

Las tareas principales son:

1. **Implementar el pipeline del procesador RISC-V.**
2. **Implementar una Debug Unit** que permita enviar y recibir información hacia y desde el procesador mediante el protocolo UART.
3. **Desarrollar una interfaz de usuario** para visualizar los datos e interactuar con la Debug Unit (a través de una CLI, GUI y/o TUI).

---

## 2. Marco Teórico

### Comparativa de Arquitecturas

* **Monociclo:** Cada instrucción se ejecuta en un único ciclo de reloj extenso (ej. *Load*, *Store*).
* **Multiciclo:** Cada instrucción se divide en varias fases executed en múltiples ciclos de reloj más cortos.
* **Segmentado (Pipeline):** Se solapan las etapas de ejecución de múltiples instrucciones simultáneamente para optimizar el *throughput*.

```
   Monociclo:   |--- Load ---|--- Store ---|
  Multiciclo:   |IF|ID|EX|MEM|WB|IF|ID|EX|MEM|
  Segmentado:   |IF|ID|EX|MEM|WB|
                   |IF|ID|EX|MEM|WB|
                      |IF|ID|EX|MEM|WB|
```

---

## 3. Etapas del Pipeline

El procesador consta de 5 etapas clásicas de ejecución:

1. **IF (Instruction Fetch):** Búsqueda de la instrucción en la memoria de programa a partir del PC (*Program Counter*).
2. **ID (Instruction Decode):** Decodificación de la instrucción y lectura del banco de registros.
3. **EX (Execute):** Ejecución de la operación propiamente dicha en la ALU o cálculo de dirección efectiva.
4. **MEM (Memory Access):** Lectura o escritura desde/hacia la memoria de datos.
5. **WB (Write Back):** Escritura del resultado devuelto en el banco de registros.

---

## 4. Riesgos (Hazards)

Durante la segmentación se presentan distintos tipos de riesgos que deben ser contemplados y resueltos:

* **Estructurales:** Producidos cuando dos o más instrucciones intentan utilizar el mismo recurso de hardware en el mismo ciclo de reloj.
* **De Datos:** Surgen cuando una instrucción depende del resultado de una instrucción previa que aún no ha completado su fase de escritura (*Write Back*). Se debe mantener el orden estricto de lecturas y escrituras.
* **De Control:** Surgen al tomar decisiones sobre una condición de salto o ramificación que todavía no se ha evaluado.

---

## 5. Formatos y Campos de las Instrucciones

Las instrucciones en RISC-V están compuestas por campos específicos distribuidos en los 32 bits de ancho:

### Descripción de Campos Principales

* **`opcode` ($7\text{ bits}$):** Código de operación básica de la instrucción.
* **`rd` ($5\text{ bits}$):** Registro destino que recibe el resultado de la operación.
* **`funct3` ($3\text{ bits}$):** Campo de operación adicional/secundario.
* **`rs1` ($5\text{ bits}$):** Primer registro fuente operando.
* **`rs2` ($5\text{ bits}$):** Segundo registro fuente operando.
* **`funct7` ($7\text{ bits}$):** Campo de operación adicional/secundario.

---

### Detalle por Tipo de Instrucción

#### Tipo R (Operaciones Registro - Registro)
Destinado a operaciones aritméticas y lógicas entre registros.

| Formato | funct7 (7b) | rs2 (5b) | rs1 (5b) | funct3 (3b) | rd (5b) | opcode (7b) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Generico** | `funct7` | `rs2` | `rs1` | `funct3` | `rd` | `opcode` |
| **`add`** | `0000000` | reg | reg | `000` | reg | `0110011` |
| **`sub`** | `0100000` | reg | reg | `000` | reg | `0110011` |

---

#### Tipo I (Operaciones Inmediatas / Load)
Utilizado para operaciones con valores constantes e instrucciones de carga desde memoria.

| Formato | immediate (12b) | rs1 (5b) | funct3 (3b) | rd (5b) | opcode (7b) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Genérico** | `immediate[11:0]` | `rs1` | `funct3` | `rd` | `opcode` |
| **`addi`** | constant | reg | `000` | reg | `0010011` |
| **`ld / lw`**| address | reg | `011 / 010` | reg | `0000011` |

---

#### Tipo S (Operaciones de Almacenamiento / Store)
Utilizado para escribir datos en la memoria.

| Bits | [31:25] | [24:20] | [19:15] | [14:12] | [11:7] | [6:0] |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Campos** | `imm[11:5]` | `rs2` | `rs1` | `funct3` | `imm[4:0]` | `opcode` |
| **Ejemplo (`sb`)** | `imm[11:5]` | `rs2` | `rs1` | `000` | `imm[4:0]` | `0100011` |

---

#### Tipo J (Salto Incondicional)
Utilizado para saltos incondicionales (`jal`). La dirección de retorno se guarda en el registro `rd`.

| Bits | [31] | [30:21] | [20] | [19:12] | [11:7] | [6:0] |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Ejemplo (`jal`)** | `imm[20]` | `imm[10:1]` | `imm[11]` | `imm[19:12]` | `rd` | `1101111` |

---

#### Tipo B (Ramificación Condicional)
Realizan saltos condicionales según una evaluación determinada.

| Bits | [31] | [30:25] | [24:20] | [19:15] | [14:12] | [11:8] | [7] | [6:0] |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Ejemplo (`beq`)** | `imm[12]` | `imm[10:5]` | `rs2` | `rs1` | `000` | `imm[4:1]` | `imm[11]` | `1100011` |

---

#### Tipo U (Carga de Inmediato Superior)
Cargan inmediatos de 20 bits en la parte más significativa (*upper*) de un registro.

| Bits | [31:12] | [11:7] | [6:0] |
| :--- | :---: | :---: | :---: |
| **Ejemplo (`lui`)** | `imm[31:12]` | `rd` | `0110111` |

---

## 6. Listado de Instrucciones a Implementar

Es obligatorio implementar el conjunto de instrucciones indicado en el siguiente desglose:

* **R-Type (Registro a Registro):**
  `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu`
* **I-Type (Inmediato / Carga / Salto):**
  * Operaciones lógicas y aritméticas: `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai`
  * Cargas: `lb`, `lh`, `lw`, `lbu`, `lhu`
  * Salto condicionado a registro: `jalr`
* **S-Type (Almacenamiento):**
  `sb`, `sh`, `sw`
* **B-Type (Ramificación Condicional):**
  `beq`, `bne`
* **U-Type (Inmediato Superior):**
  `lui`
* **J-Type (Salto Incondicional):**
  `jal`

---

## 7. Requerimientos del Sistema

* **Programación dinámica:** El procesador debe ser capaz de programarse y reprogramarse a través de comandos enviados por UART sin necesidad de volver a sintetizar la FPGA.
* **Integridad del Clock:** El *clock* del sistema no debe verse intervenido ni modificado manualmente mediante lógica combinacional en ninguna parte del proyecto.
* **Toma de Decisiones y Criterio de Diseño:** Existen elementos de la arquitectura que quedan abiertos al criterio del grupo. Se exige documentar estas decisiones de diseño y su justificación.
* **Interfaz Visual:** Innovación y creatividad al mostrar los datos e interactuar con el procesador (GUI, TUI o CLI).

---

## 8. Debug Unit y Visualización

La unidad de depuración (*Debug Unit*) debe enviar hacia la PC mediante protocolo UART la siguiente información:

1. El contenido completo de los **32 registros** del banco de registros.
2. El contenido de todos los **latches intermedios del pipeline** (IF/ID, ID/EX, EX/MEM, MEM/WB).
3. El contenido de la **memoria de datos en uso**.

---

## 9. Carga de Programa y Modos de Operación

### Carga de Programa
* El programa a ejecutar debe estar escrito en ensamblador RISC-V.
* Debe existir una herramienta/script capaz de traducir el código ensamblador a lenguaje máquina (código binario/hexadecimal) para ser transmitido al procesador.
* El programa debe incluir una instrucción de parada (`HALT` / instrucción de *stop*).
* El sistema de hardware debe permitir programar la memoria de programa mediante el software y soportar reprogramación dinámica por UART.

### Modos de Operación
1. **Modo Continuo:** Se envía el comando desde la PC por UART; la FPGA ejecuta el programa continuamente hasta alcanzar la instrucción de parada. Al finalizar, se envían y muestran todos los estados del procesador en pantalla.
2. **Modo Paso a Paso (Single-Step):** Por cada comando recibido por UART, se ejecuta exactamente un ciclo de reloj ($1\text{ clk}$). Tras cada paso, se visualiza el estado actual en pantalla.

*Nota:* En ambos modos de operación, el pipeline debe quedar completamente vacío al finalizar la ejecución del programa.

---

## 10. Análisis de Timing y Clock

Al momento de realizar la integración del diseño en la FPGA, es necesario analizar e implementar el camino crítico:

1. **¿Cuál es el camino crítico de mi sistema?**
2. **¿Genera este camino crítico *Clock Skew* en el sistema? ¿Qué consecuencias trae esto consigo?**

### Acciones requeridas en Vivado:
* Encontrar la **frecuencia de funcionamiento óptima** de la arquitectura propuesta.
* Generar las **métricas de funcionamiento y temporización** mediante las herramientas provistas por Vivado (Timing Analysis Report).
* Configurar y aplicar dicha frecuencia óptima en el diseño final.

---

## 11. Preguntas a Responder en el Informe / Documentación

Durante la elaboración del informe final se deben responder y fundamentar los siguientes puntos:

### Carga y Reprogramación:
1. ¿Es necesario vaciar la memoria al reprogramar?
2. ¿Es necesario vaciar/limpiar el banco de registros?
3. ¿Se necesita vaciar el pipeline al reprogramar?
4. ¿Es necesario vaciar la memoria de programa?

### Modos de Operación:
5. ¿Qué sucede si en la memoria no se encuentra una instrucción de parada (`HALT`)?

---

## 12. Consejos y Recomendaciones (Tips)

1. **Inspiración propia:** *"No copien, inspírense."*
2. **Uso de IP Cores:** Investiguen las herramientas que brinda Vivado (IP Cores para memorias BRAM, Clock Wizard, etc.).
3. **Metodología previa a codificar:**
   * Diseñen, dibujen y esquematicen la arquitectura completa antes de escribir código Verilog/VHDL.
   * Imaginen los módulos:
     * Piensen cómo probarlos (testbenches).
     * Definan claramente cómo interactúan entre sí.
     * Identifiquen qué herramientas vistas previamente pueden reutilizar.
   * Definan previamente cómo van a interactuar con el sistema y cómo interpretar el estado de la máquina durante la ejecución.
4. **Originalidad:** Todo lo solicitado en la consigna ya ha sido implementado múltiples veces; asegúrense de que la solución desarrollada sea única.

---

## 13. Bibliografía Recomendada

* **Instrucciones:** *RISC-V Instruction Set Manual (Volume I: Unprivileged ISA)*.
* **Pipeline / Arquitectura:** *Computer Organization and Design RISC-V Edition* (David A. Patterson, John L. Hennessy).