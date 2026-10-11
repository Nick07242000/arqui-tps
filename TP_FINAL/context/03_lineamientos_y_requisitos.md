# Lineamientos y requisitos --- Procesador RISC-V segmentado

## 1. Cómo interpretar este documento

- **MUST / DEBE:** requisito explícito de la consigna o condición necesaria para satisfacerlo correctamente.
- **MUST NOT / NO DEBE:** prohibición explícita o regla necesaria para no violar un requisito.
- **SHOULD / SE RECOMIENDA:** práctica derivada de la teoría o de la ingeniería del proyecto; puede cambiarse si se justifica y se prueba.
- **OPEN / DECISIÓN PENDIENTE:** la consigna solicita una decisión o no fija una única solución. El equipo debe resolverla, documentarla y verificarla.

La consigna es normativa respecto de lo que se entrega. 
La teoría explica por qué ciertas reglas importan, pero no convierte automáticamente todos los temas de los apuntes en funcionalidades obligatorias.

## 2. Requisitos funcionales obligatorios (MUST)

### CPU y pipeline

- [ ] **MUST:** implementar un procesador basado en ISA RISC-V con cinco etapas: IF, ID, EX, MEM y WB.
- [ ] **MUST:** transportar datos y señales de control coherentes entre etapas mediante latches de pipeline.
- [ ] **MUST:** implementar correctamente las instrucciones enumeradas en la sección 3.
- [ ] **MUST:** manejar riesgos estructurales, de datos y de control de forma que la ejecución sea correcta.
- [ ] **MUST:** preservar el comportamiento arquitectónico correcto ante dependencias, stalls, forwarding y flushes.
- [ ] **MUST:** incluir una política definida de reset/preparación de ejecución y de estado inicial.

### Debug Unit y observabilidad

- [ ] **MUST:** implementar una Debug Unit que se comunique con el procesador mediante UART y permita enviar/recibir información.
- [ ] **MUST:** permitir consultar los 32 registros arquitectónicos.
- [ ] **MUST:** permitir consultar el contenido de los latches intermedios del pipeline.
- [ ] **MUST:** permitir consultar el contenido de la memoria de datos utilizada.
- [ ] **MUST:** informar el estado suficiente para controlar y entender carga, ejecución, paso a paso y finalización.
- [ ] **MUST:** definir y documentar los comandos, respuestas, errores y límites del protocolo UART.

### Programa y carga dinámica

- [ ] **MUST:** el programa de prueba debe estar escrito en ensamblador.
- [ ] **MUST:** debe existir un mecanismo para traducir el ensamblador a código máquina compatible con la CPU.
- [ ] **MUST:** el programa debe incluir una instrucción de parada `HALT` implementada como instrucción custom de RISC-V, con codificación fija `0x0000000B` (`custom-0`). El decodificador y el mecanismo de traducción del ensamblador deben reconocer y generar la misma codificación.
- [ ] **MUST:** permitir cargar el programa mediante software de PC escribiendo la memoria de programa.
- [ ] **MUST:** permitir reprogramar dinámicamente la memoria de programa por UART.
- [ ] **MUST:** poder reemplazar un programa por otro sin resintetizar la FPGA.
- [ ] **MUST:** validar que la carga se completó antes de permitir la ejecución de una imagen incompleta.
- [ ] **MUST:** definir qué ocurre si no hay una instrucción de parada o si el PC sale de la imagen cargada.

### Modos de operación

- [ ] **MUST:** soportar ejecución continua iniciada mediante comando UART.
- [ ] **MUST:** en modo continuo, ejecutar hasta el fin definido del programa y después mostrar los valores requeridos.
- [ ] **MUST:** soportar modo paso a paso controlado mediante comandos UART.
- [ ] **MUST:** cada comando de paso a paso debe avanzar un ciclo de clock del pipeline según la semántica documentada.
- [ ] **MUST:** mostrar los valores requeridos en cada paso.
- [ ] **MUST:** asegurar que el pipeline esté vacío al declarar finalizada la ejecución.
- [ ] **MUST:** permitir que el estado final sea consultable y consistente con los efectos de todas las instrucciones válidas previas al fin.

### Clock y análisis temporal

- [ ] **MUST:** no intervenir el clock en ninguna parte del proyecto.
- [ ] **MUST:** durante la integración, identificar el camino crítico del sistema.
- [ ] **MUST:** evaluar si existe skew y explicar sus consecuencias según la evidencia de timing.
- [ ] **MUST:** si se detectan problemas temporales/skew, encontrar una frecuencia de funcionamiento adecuada y justificarla.
- [ ] **MUST:** generar y documentar métricas mediante herramientas de Vivado.
- [ ] **MUST:** aplicar la frecuencia de funcionamiento elegida en el sistema integrado.
- [ ] **MUST:** documentar las decisiones de diseño y por qué se tomaron.

### Interfaz de PC

- [ ] **MUST:** implementar una interfaz para visualizar datos e interactuar con la Debug Unit.
- [ ] **MUST:** la interfaz puede ser CLI, TUI y/o GUI; la consigna no obliga a elegir una modalidad específica.
- [ ] **MUST:** la interfaz debe permitir realizar las operaciones requeridas y mostrar los datos recibidos de la FPGA.

## 3. Lista cerrada de instrucciones requeridas

No considerar completa la ISA del proyecto hasta verificar cada instrucción de esta lista.

| Tipo | Instrucciones | Comportamiento que debe probarse |
| --- | --- | --- |
| R | `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu` | Operación entre registros, resultado y escritura en `rd`. |
| I --- loads | `lb`, `lh`, `lw`, `lbu`, `lhu` | Dirección efectiva, lectura y extensión de signo/cero. |
| I --- inmediatos | `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai` | Inmediato correcto, operación y resultado. |
| I --- salto | `jalr` | Destino calculated, regla de alineamiento y dirección de retorno. |
| S | `sb`, `sh`, `sw` | Dirección efectiva y escritura de 8, 16 o 32 bits. |
| B | `beq`, `bne` | Condición, destino relativo y descarte de instrucciones incorrectas. |
| J | `jal` | Salto relativo y escritura de dirección de retorno. |
| U | `lui` | Carga del inmediato superior. |

Reglas semánticas relacionadas: 
- `x0` debe leerse como cero y no aceptar escrituras efectivas. 
- `slt`/`slti` son comparaciones con signo; `sltu`/`sltiu`, sin signo. 
- `sra`/`srai` son desplazamientos aritméticos; `srl`/`srli`, lógicos. 
- Los inmediatos deben decodificarse y extenderse según el formato RISC-V. 
- Los loads signed y unsigned deben distinguirse; los stores deben escribir solo el ancho indicado. 
- No se deben usar reglas de codificación MIPS/DLX para implementar RISC-V.

## 4. MUST NOT --- prohibiciones y condiciones que no deben violarse

- [ ] **MUST NOT:** detener, conmutar manualmente, generar o modificar el clock para implementar `STEP`.
- [ ] **MUST NOT:** requerir síntesis o generación de un nuevo bitstream cada vez que se carga un programa.
- [ ] **MUST NOT:** declarar `done` mientras existan instrucciones válidas en el pipeline o efectos previos pendientes.
- [ ] **MUST NOT:** permitir que una instrucción descartada por un branch/jump o por HALT escriba registros o memoria.
- [ ] **MUST NOT:** permitir que una burbuja o etapa inválida produzca efectos arquitectónicos.
- [ ] **MUST NOT:** permitir escrituras efectivas en `x0`.
- [ ] **MUST NOT:** aceptar como válida una carga incompleta, fuera de rango o de formato incorrecto sin reportar error.
- [ ] **MUST NOT:** dar por correcta la implementación solo porque compila o porque pasa una única prueba.
- [ ] **MUST NOT:** afirmar que se cumple timing basándose únicamente en simulación funcional; deben revisarse los reportes de Vivado.
- [ ] **MUST NOT:** inferir que hay skew solo porque el camino crítico es largo; debe verificarse en los reportes.
- [ ] **MUST NOT:** asumir que todo el contenido de los apuntes es alcance obligatorio. 
Predicción dinámica, superscalaridad, ejecución fuera de orden, ROB o cachés no son requisitos explícitos de esta consigna.

## 5. Reglas de diseño derivadas de la teoría (SHOULD)

- [ ] **SHOULD:** definir interfaces de módulos antes de implementarlos: entradas, salidas, anchos, latencia, reset y comportamiento en errores.
- [ ] **SHOULD:** mantener separados el datapath, la unidad de control, el manejo de riesgos, UART, protocolo y aplicación de PC.
- [ ] **SHOULD:** representar explícitamente la validez de cada etapa, o documentar una convención equivalente, para distinguir instrucciones válidas, burbujas y etapas vacías.
- [ ] **SHOULD:** implementar forwarding desde `EX/MEM` y `MEM/WB` hacia las entradas de EX para resolver dependencias sin stalls innecesarios.
- [ ] **SHOULD:** priorizar el resultado más reciente cuando varias instrucciones anteriores escriben el mismo registro.
- [ ] **SHOULD:** implementar un stall para la dependencia *load-use* cuando el dato leído de memoria no esté disponible a tiempo.
- [ ] **SHOULD:** durante un stall, congelar el PC y `IF/ID`, insertar una burbuja en `ID/EX` y permitir que las instrucciones anteriores válidas continúen avanzando.
- [ ] **SHOULD:** si el tiempo disponible no permite completar y verificar el forwarding, usar stalls como alternativa, documentar la simplificación y demostrar mediante pruebas que no se compromete la corrección funcional.
- [ ] **SHOULD:** en branch/jump tomado, invalidar las instrucciones del camino incorrecto.
- [ ] **SHOULD:** elegir conscientemente entre memoria de instrucciones/datos separadas, memoria compartida o una configuración de puertos que resuelva riesgos estructurales.
- [ ] **SHOULD:** verificar cada instrucción con pruebas dirigidas y después con secuencias de instrucciones.
- [ ] **SHOULD:** usar un programa pequeño de referencia con resultados calculables manualmente.
- [ ] **SHOULD:** probar explícitamente dependencias ALU-ALU, load-use, saltos tomados/no tomados y stores próximos a HALT.
- [ ] **SHOULD:** mantener UART y la lógica de control disponibles cuando el CPU esté pausado en modo paso a paso.
- [ ] **SHOULD:** hacer que la consulta de debug sea de solo lectura y no altere el estado de ejecución.
- [ ] **SHOULD:** usar confirmaciones explícitas y mensajes de error para el protocolo UART.
- [ ] **SHOULD:** registrar resultados esperados y observados, en lugar de limitar la validación a capturas de formas de onda.
- [ ] **SHOULD:** revisar el uso de IP cores de memoria y Clock Wizard de Vivado; documentar si se usan o por qué no son necesarios.
- [ ] **SHOULD:** fijar la frecuencia final con evidencia de timing de la implementación integrada.
- [ ] **SHOULD:** comprobar una dependencia ALU-ALU inmediata que se resuelva mediante forwarding.
- [ ] **SHOULD:** comprobar una dependencia que requiera seleccionar el resultado desde `MEM/WB`.
- [ ] **SHOULD:** comprobar una dependencia *load-use* que introduzca el stall necesario.
- [ ] **SHOULD:** comprobar varias escrituras consecutivas al mismo registro y verificar que se utilice el valor más reciente.
- [ ] **SHOULD:** comprobar que `HALT` se decodifique únicamente con la codificación definida y que no se ejecuten instrucciones posteriores.
- [ ] **SHOULD:** comprobar que un store inmediatamente anterior a `HALT` se complete antes de declarar `done`.
- [ ] **SHOULD:** comprobar la finalización por `N_WORDS` cuando la imagen no contiene `HALT`.

## 6. Decisiones de diseño adoptadas

Las siguientes decisiones establecen la implementación prevista para priorizar la simplicidad sin descartar funcionalidades razonables para el proyecto. Cualquier desviación deberá documentarse, especialmente cuando implique simplificar una funcionalidad prevista.

### Memorias, registros y pipeline

- **Reset:** poner el PC en cero, inicializar `x1`–`x31` en cero e invalidar todos los latches del pipeline. `x0` siempre debe leerse como cero y descartar escrituras.
- **Memoria de datos:** conservar su contenido durante el reset y la carga de un programa. Cada programa de prueba debe inicializar las posiciones que necesite antes de leerlas.
- **Memoria de programa:** al cargar un programa, sobrescribir las primeras `N_WORDS` palabras y guardar esa longitud. No es necesario borrar toda la memoria: las posiciones posteriores a `N_WORDS` no se ejecutarán.
- **Memorias separadas:** utilizar una memoria de instrucciones y otra de datos para evitar conflictos de acceso entre IF y MEM.
- **Latencia:** definir y verificar la latencia real de ambas memorias antes de cerrar el pipeline.

### Pipeline y riesgos

- **Riesgos de datos:** intentar implementar forwarding desde `EX/MEM` y `MEM/WB` hacia las entradas de la etapa EX. Si dos etapas anteriores pueden proporcionar el mismo registro, debe seleccionarse el resultado más reciente.
- **Alternativa por tiempo:** si no resulta posible completar y verificar el forwarding dentro del tiempo disponible, se permitirá utilizar stalls hasta que el dato requerido esté disponible. Esta simplificación deberá documentarse y superar las mismas pruebas funcionales.
- **Load-use:** implementar un stall cuando una instrucción utilice inmediatamente un dato cargado desde memoria que todavía no esté disponible. El forwarding no elimina todos los casos de espera.
- **Control de stalls:** durante una espera, congelar el PC y `IF/ID`, insertar una burbuja en `ID/EX` y permitir que las instrucciones anteriores continúen avanzando.
- **Branches y jumps:** resolverlos en EX. Cuando se toma un salto, invalidar las instrucciones más jóvenes que correspondan al camino incorrecto.
- **Validez:** cada latch debe indicar si contiene una instrucción válida, o utilizar una convención equivalente que permita detectar burbujas y vaciar el pipeline. Las burbujas no deben producir efectos arquitectónicos.

### HALT y fin de ejecución

- **HALT:** implementar `HALT` como una instrucción custom de RISC-V con codificación fija `0x0000000B`, correspondiente al opcode `custom-0`. El decodificador reconocerá la palabra completa y el proceso de preparación del programa deberá generar exactamente esa codificación. No se presentará como una instrucción estándar de RV32I.
- **Detención:** al detectar `HALT`, detener la búsqueda de instrucciones nuevas e impedir que las instrucciones posteriores produzcan efectos arquitectónicos.
- **Vaciado:** permitir que las instrucciones válidas anteriores a `HALT` completen sus operaciones, incluidas las escrituras de registros y los stores. Declarar `done` solamente cuando no queden instrucciones válidas en el pipeline ni efectos pendientes.
- **Fin de imagen:** si el PC alcanza `N_WORDS` sin encontrar `HALT`, detener la búsqueda y terminar la ejecución después de completar las instrucciones válidas que permanezcan en el pipeline. La condición deberá distinguirse de una finalización mediante `HALT`.
- **Carga posterior:** al cargar un programa nuevo, invalidar el estado de ejecución anterior, vaciar el pipeline y actualizar `N_WORDS` para impedir que se ejecuten instrucciones residuales de una imagen previa.

### UART y Debug Unit

- **Formato serie:** 115200 baudios, 8 bits de datos, sin paridad y 1 bit de parada (8-N-1).
- **Protocolo:** usar mensajes binarios con código de comando, longitud y datos. Cada operación debe recibir una respuesta de éxito o error.
- **Comandos mínimos:** `LOAD_PROGRAM`, `RESET`, `RUN`, `STEP`, `GET_STATUS`, `GET_REGS`, `GET_PIPELINE` y `GET_MEMORY`.
- **Consultas:** permitir consultas completas cuando la CPU esté pausada, en paso a paso o finalizada. Durante la ejecución continua, limitar las consultas a un estado básico.
- **Carga:** no permitir `RUN` hasta que la imagen completa haya sido recibida y su longitud validada.
- **Representación:** transmitir palabras de 32 bits en little-endian y documentar las direcciones y los tamaños de memoria.

### Interfaz de PC y traducción

- **Interfaz:** implementar primero una CLI que permita cargar, ejecutar, avanzar un ciclo y consultar los datos requeridos. No se considera necesaria una TUI o GUI.
- **Ensamblador:** utilizar una herramienta RISC-V existente compatible con la ISA implementada. Un script auxiliar preparará la imagen y generará la codificación de `HALT`, por ejemplo mediante `.word 0x0000000B` o una transformación equivalente, antes de transmitir el programa.
- **Formato de imagen:** transmitir palabras máquina de 32 bits y registrar `N_WORDS`. Para la implementación base sin instrucciones comprimidas, el PC avanza en unidades de 4 bytes y el límite de la imagen se calcula a partir de la cantidad de palabras cargadas.

### FPGA, clock y análisis temporal

- **Memorias:** utilizar memoria inferida o BSRAM de Gowin, con memorias de instrucciones y datos separadas.
- **Clock:** usar la entrada de reloj documentada para la Tang Nano 20K. El modo `STEP` se implementará mediante una habilitación síncrona del avance del procesador, sin detener ni conmutar manualmente el clock.
- **PLL:** no incorporar un PLL salvo que sea necesario para obtener una frecuencia requerida.
- **Frecuencia:** elegirla a partir de los resultados del análisis temporal de la implementación integrada.
- **Herramienta:** usar los reportes de timing disponibles en Gowin EDA para la Tang Nano 20K. Si la consigna exige expresamente reportes de Vivado, confirmar con el profesor cómo satisfacer ese punto.
- **Evidencia:** documentar el camino crítico, las métricas de slack y el análisis de skew, sin afirmar que existe una violación si los reportes no lo muestran.

## 7. Criterios de aceptación de la entrega completa

La entrega puede considerarse funcionalmente completa solo cuando se demuestra todo lo siguiente:

1.  Se carga un programa ensamblador traducido a código máquina.
2.  El programa se carga por UART a la memoria de programa del mismo bitstream, sin resíntesis.
3.  El CPU ejecuta correctamente el conjunto de instrucciones requerido, incluyendo secuencias con dependencias y saltos.
4.  Se puede ejecutar en modo continuo y el sistema informa los datos solicitados al terminar.
5.  Se puede ejecutar en modo paso a paso y cada comando avanza un ciclo lógico del pipeline sin intervenir el clock físico.
6.  La Debug Unit informa los 32 registros, latches intermedios y memoria de datos.
7.  HALT/STOP y el caso sin instrucción de parada tienen comportamiento definido y probado.
8.  El pipeline queda vacío cuando se declara finalizada la ejecución.
9.  Se documenta la política de reset y persistencia de memorias/registros.
10. Se presentan reportes de Vivado que identifican el camino crítico, evalúan skew y fundamentan la frecuencia final.
11. La interfaz de PC permite controlar y visualizar el sistema y reporta errores de forma comprensible.
12. Las decisiones de diseño no prescritas por la consigna están documentadas con su justificación.

## 8. Regla de trazabilidad

Cada requisito MUST debe enlazarse a: 
- uno o más módulos responsables; 
- una historia/tarea del roadmap; 
- al menos una prueba que demuestre su cumplimiento; 
- una evidencia de resultado (log, testbench, captura, reporte de Vivado o sesión UART).

Un requisito sin prueba asociada no debe marcarse como cumplido. 
Una prueba que no tiene resultado esperado explícito no constituye, por sí sola, evidencia suficiente.
