## Programa de referencia

### Qué es y para qué sirve

El programa de referencia es un programa corto en ensamblador RISC-V cuyos resultados se pueden calcular a mano. Se ejecuta sobre el datapath no segmentado y deja valores conocidos en registros y en memoria de datos.

Cumple dos funciones:

1. **Prueba de integración del datapath.** Las pruebas por instrucción verifican cada operación por separado. Este programa verifica que **trabajen juntas** en secuencias reales: lazos, llamadas a función, accesos a memoria que dependen de resultados anteriores.
2. **Referencia para el pipeline.** El estado final que produce este modelo es el que debe reproducir el pipeline de cinco etapas. Cualquier diferencia indica un error en el manejo de riesgos.

---

### Archivos

| Archivo | Descripción |
| --- | --- |
| `programs/reference_program.s` | Programa en ensamblador, comentado |
| `programs/build_program.sh` | Ensambla un `.s` y genera el `.hex` y el listado |
| `programs/reference_program.hex` | Imagen lista para cargar: 54 palabras de 32 bits, una por línea |
| `programs/reference_program.lst` | Desensamblado de la imagen, para revisar la codificación |
| `tb/tb_reference_program.v` | Testbench que ejecuta el programa y compara el resultado |

**Generar la imagen** (requiere las binutils de RISC-V):

```bash
./programs/build_program.sh programs/reference_program.s
```

**Ejecutar la prueba**, desde la carpeta raíz del proyecto:

```bash
./run_tests.sh tb_reference_program
```

La instrucción `HALT` se escribe como la macro `halt`, que emite la palabra `0x0000000B`. El ensamblador estándar no la conoce, así que el programa define la macro al comienzo.

---

### Qué calcula el programa

El programa se divide en seis secciones independientes. Cada una trabaja con registros propios para que los resultados finales no se pisen entre sí.

| Sección | Qué hace | Resultado |
| --- | --- | --- |
| **A. Aritmética y lógica** | Opera con 10 y 3 usando `add`, `sub`, `and`, `or`, `xor`, `sll`, `srl` | Valores en `x4` a `x10` |
| **B. Suma con lazo** | Calcula 1 + 2 + … + 10 con un lazo armado con `beq` y `jal` | 55 en `x12` y en memoria |
| **C. Fibonacci** | Escribe los 10 primeros números de Fibonacci en memoria con un lazo `bne` | 0, 1, 1, 2, 3, 5, 8, 13, 21, 34 |
| **D. Llamada a función** | `jal` a una función que suma los 10 elementos del arreglo con `lw`, y vuelve con `jalr` | 88 en `x20` y en memoria |
| **E. Bytes y medias palabras** | Guarda `0x80FF7F01` con `lui` + `addi` y lo lee con `lb`, `lbu`, `lh`, `lhu`; después modifica un byte con `sb` | Ver tabla de resultados |
| **F. Con signo y sin signo** | Compara y desplaza el valor −16 con `sra`, `sltu` y `slt` | Ver tabla de resultados |

La función `sum_array` está al final del programa, después de `HALT`. Solo se llega a ella mediante la llamada de la sección D, y esa llamada se resuelve con un `jal` hacia adelante y un `jalr` de retorno.

El programa usa 23 mnemónicos distintos, todos de la lista obligatoria, más la palabra de `halt`. Las instrucciones que no aparecen (`andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli` y `srai`) están cubiertas por las pruebas por instrucción.

---

### Resultados esperados

Todos los valores se calcularon a mano, sin ejecutar el programa.

#### Registros

| Registro | Valor | Origen |
| --- | --- | --- |
| `x0` | `0x00000000` | Siempre cero |
| `x1` | `0x00000078` | Dirección de retorno de la llamada (instrucción siguiente al `jal` en `0x74`) |
| `x2` | `10` | Operando de la sección A |
| `x3` | `3` | Operando de la sección A |
| `x4` | `13` | 10 + 3 |
| `x5` | `7` | 10 − 3 |
| `x6` | `2` | `1010 & 0011` |
| `x7` | `11` | `1010 \| 0011` |
| `x8` | `9` | `1010 ^ 0011` |
| `x9` | `80` | 10 << 3 |
| `x10` | `1` | 10 >> 3 |
| `x11` | `0` | Contador del lazo de suma, agotado |
| `x12` | `55` | Suma 1 + … + 10 |
| `x13` | `55` | fib(10), siguiente valor tras el último guardado |
| `x14` | `89` | fib(11) |
| `x15` | `40` | Puntero final: 10 elementos × 4 bytes |
| `x16` | `0` | Elementos restantes |
| `x17` | `89` | Último valor calculado en el lazo |
| `x18` | `40` | Puntero final de `sum_array` |
| `x19` | `0` | Contador de `sum_array`, agotado |
| `x20` | `88` | Suma de los 10 números de Fibonacci |
| `x21` | `34` | Último elemento leído (fib(9)) |
| `x22` | `0x80FF7F01` | `lui 0x80FF8` + `addi −255` |
| `x23` | `0xFFFFFFFE` | −16 >> 3 aritmético = −2 |
| `x24` | `1` | `sltu`: 10 < 0xFFFFFFF0 sin signo |
| `x25` | `0xFFFFFF80` | `lb` del byte `0x80` (con signo) |
| `x26` | `0x00000080` | `lbu` del mismo byte (sin signo) |
| `x27` | `0xFFFF80FF` | `lh` de la mitad alta (con signo) |
| `x28` | `0x000080FF` | `lhu` de la mitad alta (sin signo) |
| `x29` | `0xFFFFFFF0` | −16 |
| `x30` | `0x80FF5501` | Palabra leída después de `sb` |
| `x31` | `0` | `slt`: 10 < −16 con signo es falso |

`x31` pasa por `0x55` (valor guardado con `sb`) antes de recibir el resultado de `slt`, de modo que el `0` final prueba que la instrucción escribió el registro y no que quedó el valor inicial.

#### Memoria de datos

| Palabra | Dirección (bytes) | Valor | Contenido |
| --- | --- | --- | --- |
| 0 – 9 | `0x00` – `0x24` | 0, 1, 1, 2, 3, 5, 8, 13, 21, 34 | Fibonacci |
| 10 – 15 | `0x28` – `0x3C` | 0 | No deben haberse escrito |
| 16 | `0x40` | 55 | Suma 1 + … + 10 |
| 17 | `0x44` | 88 | Suma de los elementos de Fibonacci |
| 18 | `0x48` | `0x80FF5501` | Palabra de prueba con el byte 1 reemplazado (`0x7F` → `0x55`) |
| 19 | `0x4C` | 0 | No debe haberse escrito |

El testbench también verifica las palabras que **no** deben cambiar, para detectar escrituras de más.

#### Resumen de la ejecución

| Dato | Valor esperado | Cálculo |
| --- | --- | --- |
| PC al detenerse | `0x000000B8` | `HALT` está en la palabra 46 |
| Instrucciones completadas | 198 | A: 9 · B: 44 · C: 74 · D: 56 · E: 11 · F: 4 |
| Ciclos hasta `HALT` | 213 | 198 instrucciones + 15 ciclos de espera (cada load usa 2 ciclos: 5 en la sección E y 10 en `sum_array`) |
| Indicadores de error | Ninguno | Sin instrucciones ilegales, accesos fuera de rango ni desalineados |

---

### Resultado de la verificación

El programa se ejecutó sobre el datapath no segmentado y **todos los valores coinciden con los calculados a mano**, incluidos el PC final, la cantidad de instrucciones y la cantidad de ciclos.

También se comprobó que la prueba es sensible a defectos del diseño. Por ejemplo, inyectando un `sltu` implementado como `slt`, o un load que tarda un ciclo en lugar de dos, el testbench del programa de referencia falla.

---

### Uso en las etapas siguientes

- **Pipeline (E3).** Debe terminar con los mismos registros y la misma memoria. Cambian los ciclos, porque aparecen los stalls de load-use y las penalizaciones de los saltos tomados; este programa los ejercita: `sum_array` tiene un `lw` seguido de un `add` que lo usa, y los lazos tienen saltos tomados en cada iteración.
- **Debug Unit y PC (E5 y E6).** Sirve como programa de demostración repetible: se carga por UART, se ejecuta en modo continuo o paso a paso y se comparan los registros y la memoria que informa la FPGA con las tablas de este documento.
- **Herramienta de traducción (E6).** El archivo `.hex` sirve de referencia para comparar la salida del script que prepara la imagen.