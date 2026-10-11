# Teoría pertinente para el proyecto final: procesador RISC-V segmentado

> **Propósito.** Este documento concentra los conceptos teóricos que
> sirven para diseñar, implementar, probar e integrar el procesador
> RISC-V segmentado, su Debug Unit por UART y la interfaz de PC. No
> pretende resumir toda la asignatura. La consigna del trabajo final es
> la fuente normativa para los requisitos del proyecto; los apuntes
> aportan el marco conceptual. Cuando se propone una decisión de
> implementación que la consigna no fija, se identifica como **decisión
> de diseño**.

## 1. Arquitectura, ISA y microarquitectura

La **arquitectura de conjunto de instrucciones (ISA)** define el
contrato visible para el software: codificación de instrucciones,
registros arquitectónicos, operaciones, formatos, reglas de
direccionamiento y resultados esperados. En este proyecto la ISA
objetivo es **RISC-V**, y el conjunto de instrucciones obligatorio es el
enumerado en la consigna.

La **microarquitectura** describe cómo se implementa ese contrato en
hardware. Aquí se requiere un procesador con cinco etapas de pipeline.
Dos implementaciones pueden ejecutar la misma ISA y producir los mismos
resultados arquitectónicos, pero diferir en su organización interna,
tratamiento de riesgos y rendimiento.

**Consecuencia práctica:** la unidad de control y el datapath deben
interpretar correctamente las instrucciones RISC-V requeridas. No debe
trasladarse automáticamente la codificación o semántica de ejemplos
MIPS/DLX de los apuntes a RISC-V. Los apuntes se utilizan para
comprender conceptos de segmentación y riesgos; la especificación RISC-V
gobierna las instrucciones concretas.

## 2. Datapath y estado del procesador

El **datapath** es el conjunto de componentes que transporta y
transforma datos. Como mínimo, la implementación necesita cubrir las
funciones siguientes:

-   **PC (Program Counter):** dirección de la instrucción que se busca o
    referencia para el próximo acceso a memoria de programa.
-   **Memoria de programa:** contiene las instrucciones máquina que se
    ejecutarán.
-   **Banco de registros:** almacena los registros arquitectónicos
    enteros de 32 bits de RISC-V, incluyendo `x0`, cuyo valor debe
    leerse como cero y no puede modificarse.
-   **Unidad de control/decodificador:** interpreta opcode, `funct3`,
    `funct7` y otros campos relevantes; produce señales de control para
    el datapath.
-   **Generador de inmediatos:** reconstruye y extiende el inmediato de
    acuerdo con el formato RISC-V correspondiente.
-   **ALU:** realiza operaciones aritméticas, lógicas, desplazamientos,
    comparaciones y cálculos de direcciones según las instrucciones
    soportadas.
-   **Memoria de datos:** permite las cargas (`load`) y los
    almacenamientos (`store`).
-   **Multiplexores:** seleccionan operandos de ALU, destino de
    escritura, dato de escritura y próximo PC.
-   **Registros de segmentación (pipeline latches):** conservan datos,
    direcciones y señales de control entre etapas.

El estado arquitectónico ---por ejemplo, PC, registros y memoria de
datos--- no es lo mismo que el estado microarquitectónico ---por
ejemplo, contenido de `IF/ID`, `ID/EX`, `EX/MEM` y `MEM/WB`, señales de
control o burbujas---. La consigna exige que la Debug Unit permita
consultar ambos tipos de información: registros, latches intermedios y
memoria de datos.

## 3. Pipeline de cinco etapas

La segmentación divide el recorrido de una instrucción en etapas
separadas por registros de pipeline. Varias instrucciones pueden estar
activas en etapas distintas durante un mismo ciclo. En condiciones
ideales, después de llenar el pipeline puede completarse una instrucción
por ciclo; esto no significa que cada instrucción individual tarde un
ciclo, ni que siempre se alcance ese rendimiento. Los riesgos, las
dependencias y los saltos pueden introducir esperas o vaciados.

| Etapa | Función principal | Información que debe avanzar |
| --- | --- | --- |
| **IF --- Instruction Fetch** | Busca la instrucción indicada por el PC y determina la dirección secuencial siguiente. | PC/instrucción y, según el diseño, PC+4. |
| **ID --- Instruction Decode** | Decodifica, lee registros, genera el inmediato y produce/controla señales. También es un lugar habitual para detectar ciertos riesgos. | Operandos, registros fuente/destino, inmediato y controles. |
| **EX --- Execute** | Ejecuta la operación ALU, calcula direcciones efectivas y/o evalúa condiciones y destinos de salto. | Resultado ALU, dirección/datos necesarios y controles. |
| **MEM --- Memory Access** | Realiza lectura o escritura de memoria de datos para loads/stores; para otras instrucciones puede simplemente propagar el resultado. | Dato leído o resultado que seguirá a WB. |
| **WB --- Write Back** | Selecciona el resultado correspondiente y escribe el registro destino cuando la instrucción lo requiere. | Escritura arquitectónica completada. |

Los registros de segmentación deben transportar todos los datos y
controles que una instrucción necesita en las etapas posteriores. Un
error frecuente es propagar los operandos correctos pero no las señales
de control asociadas, o alinear una señal con una instrucción distinta.

### 3.1 Registros de pipeline y validez

Los latches usuales son `IF/ID`, `ID/EX`, `EX/MEM` y `MEM/WB`. Cada uno
conserva la información necesaria para continuar una instrucción en el
siguiente ciclo. Conviene representar explícitamente si el contenido
corresponde a una instrucción válida, una burbuja o un estado vacío.

**Decisión de diseño recomendada:** incorporar un bit `valid` en cada
latch o establecer una convención equivalente, documentada y
verificable. Así, detener la búsqueda, vaciar instrucciones
especulativas y comprobar que el pipeline terminó no depende de adivinar
si una palabra de instrucción equivale a un NOP.

## 4. Riesgos de la segmentación

Un riesgo aparece cuando la ejecución solapada puede producir un
resultado incorrecto o requiere que una instrucción espere.

### 4.1 Riesgos estructurales

Dos operaciones necesitan el mismo recurso físico en el mismo ciclo. Un
caso posible es usar una única memoria para instrucciones y datos
mientras IF intenta buscar una instrucción y MEM accede a datos.

Formas de resolverlo incluyen separar la memoria de instrucciones y
datos, usar recursos con puertos suficientes o introducir
arbitraje/esperas. La elección debe documentarse y probarse.

**Criterio de aceptación:** no puede perderse ni corromperse una
búsqueda o un acceso a datos por compartir recursos. Si se usa memoria
de programa y memoria de datos separadas, debe verificarse que esa
organización coincide con la implementación real de los IP cores o
bloques inferidos.

### 4.2 Riesgos de datos

Una instrucción consume un registro cuyo valor aún no está disponible
porque una instrucción anterior todavía no lo escribió.

-   **Forwarding (anticipación/cortocircuito):** entrega un resultado
    desde una etapa posterior directamente a una entrada que lo
    necesita, evitando esperar a la escritura y relectura del banco de
    registros.
-   **Stall (bloqueo):** evita que una instrucción avance durante uno o
    más ciclos cuando el dato todavía no puede entregarse.
-   **Burbuja:** ciclo en el que una etapa no realiza una operación
    arquitectónica útil. No es exactamente lo mismo que ejecutar una
    instrucción NOP: una burbuja es una condición de control del
    pipeline.

Una dependencia típica es `add x5, ...` seguida de una instrucción que
usa `x5`. El forwarding puede resolver muchas dependencias ALU-ALU. En
una dependencia **load-use**, por ejemplo `lw x5, 0(x1)` seguido
inmediatamente de `add x6, x5, x2`, el dato cargado puede llegar
demasiado tarde para la EX de la instrucción siguiente; suele requerirse
al menos un ciclo de stall incluso si hay forwarding.

El detector debe comparar el registro destino de instrucciones
anteriores que efectivamente escriben un registro con los registros
fuente que la instrucción actual realmente utiliza. No debe tratar como
dependencia una coincidencia de bits que corresponda a un campo que no
es fuente en ese formato.

**Criterio de aceptación:** las dependencias consecutivas, las
dependencias separadas por una instrucción y los casos load-use producen
resultados correctos. Cada stall debe congelar las etapas necesarias e
insertar una burbuja sin duplicar escrituras ni perder instrucciones.

### 4.3 Riesgos de control

Los saltos y ramificaciones pueden cambiar el PC. Mientras no se conozca
el resultado de una condición o el destino, IF puede haber introducido
instrucciones del camino secuencial que ya no corresponden al programa.

El diseño debe definir dónde se resuelven los saltos, cómo se elige el
próximo PC y qué sucede con las instrucciones más jóvenes cuando el
salto se toma. Una solución sencilla es vaciar/inutilizar las
instrucciones incorrectas del pipeline al confirmar el cambio de flujo.
El número exacto de ciclos de penalización depende de dónde se resuelve
el salto y de la política implementada.

**Criterio de aceptación:** `beq`, `bne`, `jal` y `jalr` llevan al PC
correcto; ninguna instrucción del camino incorrecto puede modificar
registros o memoria.

### 4.4 Orden y efectos arquitectónicos

La consigna exige mantener el comportamiento correcto del programa y que
el pipeline quede vacío al terminar. Los mecanismos de forwarding,
stalls y flushes deben preservar el orden lógico de los efectos
observables: escrituras de registros, stores y cambios de flujo deben
corresponder al programa ejecutado.

La consigna no impone una implementación concreta de forwarding ni una política única de detección de riesgos. Para este proyecto se recomienda implementar forwarding desde los registros de pipeline `EX/MEM` y `MEM/WB` hacia las entradas de la etapa EX, ya que permite resolver la mayoría de las dependencias entre instrucciones sin introducir esperas innecesarias.

Las dependencias *load-use* requieren un tratamiento adicional cuando el dato leído de memoria todavía no está disponible para la instrucción siguiente. En ese caso, se debe insertar un stall, conservar las instrucciones que aún no pueden avanzar e introducir una burbuja en el lugar correspondiente. Si el tiempo de implementación resulta insuficiente, puede adoptarse como alternativa una estrategia basada exclusivamente en stalls, siempre que detecte correctamente las dependencias, preserve las instrucciones y sus efectos, y supere las mismas pruebas funcionales.

La estrategia seleccionada debe documentarse y verificarse mediante pruebas de dependencias consecutivas, cadenas de dependencias, instrucciones de carga y uso inmediato del dato.

## 5. Formatos y semántica de las instrucciones RISC-V requeridas

La instrucción máquina tiene 32 bits en la base RISC-V usada normalmente
en este proyecto. Los formatos distribuyen esos bits entre opcode,
registros, funciones e inmediatos. No se debe asumir que todos los
formatos colocan los campos de la misma manera.

| Formato | Uso general | Instrucciones exigidas |
| --- | --- | --- |
| **R** | Operación entre registros. | `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu` |
| **I --- load** | Dirección efectiva base + inmediato; lectura de memoria. | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| **I --- inmediato** | Operación con un registro y un inmediato. | `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai` |
| **I --- salto indirecto** | Salto a dirección calculada desde un registro más inmediato. | `jalr` |
| **S** | Escritura de memoria con dirección base + inmediato. | `sb`, `sh`, `sw` |
| **B** | Salto condicional relativo. | `beq`, `bne` |
| **J** | Salto incondicional relativo con dirección de retorno en `rd`. | `jal` |
| **U** | Carga de inmediato superior. | `lui` |

Aspectos semánticos que deben quedar explícitos en la implementación:

-   `x0` siempre se lee como cero y descarta escrituras.
-   `lb` y `lh` extienden el signo del dato leído; `lbu` y `lhu`
    extienden con ceros. `lw` lee 32 bits.
-   `sb` y `sh` almacenan únicamente los 8 o 16 bits inferiores; `sw`
    almacena 32 bits. Deben definirse y probarse alineamiento y
    selección de bytes de acuerdo con la memoria implementada.
-   `sra`/`srai` desplazan aritméticamente preservando el signo;
    `srl`/`srli` desplazan lógicamente rellenando con ceros.
-   `slt`/`slti` comparan como valores con signo; `sltu`/`sltiu`, como
    valores sin signo.
-   Los inmediatos se deben reconstruir según el formato y extender
    correctamente. Los inmediatos de B y J tienen bits reordenados en la
    codificación.
-   `jal` y `jalr` escriben la dirección de retorno en `rd` y actualizan
    el PC según la semántica RISC-V; `jalr` calcula el destino a partir
    de `rs1 + inmediato` y aplica la regla de alineamiento de destino de
    la ISA.
-   `lui` coloca el inmediato en la parte alta del registro destino, con
    los bits bajos en cero según la codificación RISC-V.

La lista anterior delimita la ISA obligatoria. Extensiones no enumeradas
no deben considerarse requisitos salvo que se acuerden explícitamente.

## 6. Memorias y programación dinámica

La memoria de programa contiene instrucciones máquina; la memoria de
datos contiene valores que el programa lee o modifica. Aunque ambas
pueden usar bloques RAM de FPGA, son funciones lógicas diferentes y
deben tener contratos claros: profundidad, ancho, latencia, puertos,
comportamiento de lectura/escritura y direcciones válidas.

La consigna exige cargar y reemplazar programas mediante UART mientras
el procesador ya está implementado en FPGA, sin resintetizarlo. Por lo
tanto, la memoria de programa debe poder escribirse desde la Debug Unit
en tiempo de ejecución. Esto requiere un protocolo de carga, control de
límites y una forma de evitar que el CPU ejecute un programa
parcialmente cargado.

### 6.1 Estado al cargar/reiniciar

La política adoptada distingue el reset del procesador de la carga de un nuevo programa. Al resetear, el PC vuelve a cero, los registros `x1`–`x31` se inicializan en cero y todos los latches del pipeline se invalidan. `x0` permanece siempre en cero.

La memoria de datos no se borra automáticamente. Esto evita implementar un recorrido adicional para limpiar toda la memoria; los programas de prueba deben inicializar explícitamente las posiciones que utilicen.

Al cargar un programa nuevo, la CPU permanece detenida. La Debug Unit escribe las primeras `N_WORDS` palabras de la memoria de programa y registra la longitud de la imagen. No es necesario borrar las posiciones restantes porque el control de fin de imagen impide ejecutarlas. La CPU solo puede comenzar cuando la carga se completó y la longitud se validó.

## 7. HALT, fin de programa y vaciado del pipeline

La consigna requiere una instrucción de parada y que el pipeline quede vacío al finalizar la ejecución. En este proyecto se implementará `HALT` como una instrucción custom de RISC-V, en lugar de depender exclusivamente de una convención externa o de interpretar cualquier instrucción desconocida como una orden de parada.

Se utilizará la codificación fija `0x0000000B`, correspondiente al opcode `custom-0` de RISC-V con el resto de los campos en cero. El decodificador reconocerá la palabra completa como `HALT`. Esta instrucción no forma parte de la ISA base RV32I, por lo que el ensamblador utilizado deberá permitir incorporarla, por ejemplo, mediante una directiva `.word 0x0000000B` o mediante una pequeña transformación del programa que convierta la instrucción simbólica `halt` en esa palabra máquina.

Al detectar `HALT`, el procesador debe dejar de buscar instrucciones nuevas y evitar que cualquier instrucción posterior a ella produzca efectos arquitectónicos. Sin embargo, las instrucciones válidas anteriores a `HALT` deben completar sus operaciones pendientes, incluyendo escrituras de registros y accesos de escritura a memoria. Por lo tanto, la detección de `HALT` inicia el proceso de finalización, pero no debe declarar inmediatamente que el programa terminó.

Se recomienda representar la validez de las instrucciones en las etapas del pipeline. La señal `done` se activa solamente cuando no quedan instrucciones válidas en las etapas y no hay efectos previos pendientes. De esta forma, el estado final que consulta la Debug Unit refleja todos los efectos de las instrucciones anteriores a `HALT`, sin ejecutar instrucciones posteriores.

La longitud de la imagen cargada, expresada en cantidad de palabras de 32 bits (`N_WORDS`), se conservará como protección adicional. Si el PC alcanza el final de la imagen sin encontrar `HALT`, el procesador deberá detener la búsqueda y finalizar mediante la misma lógica de vaciado, informando que se alcanzó el final de la imagen sin una instrucción explícita de parada. Si el PC intenta acceder fuera de la región cargada, no debe ejecutar contenido residual de la memoria de programa.

La memoria de programa puede contener palabras antiguas después del último elemento de una imagen más corta. Esto no constituye un problema si el límite `N_WORDS` se actualiza en cada carga y se comprueba antes de aceptar una nueva instrucción. La carga de un programa nuevo también debe invalidar el estado de ejecución anterior y vaciar el pipeline antes de comenzar una nueva ejecución.

## 8. UART, Debug Unit e interfaz de PC

UART es un enlace serie asíncrono que permite enviar y recibir bytes
entre la FPGA y el software de PC. El proyecto debe definir un protocolo
de aplicación por encima de UART: comandos, parámetros, respuestas,
delimitación de mensajes, confirmaciones, errores y límites de tamaño.
UART por sí sola no define qué significa `LOAD`, `RUN`, `STEP` o
`READ_REGS`.

La **Debug Unit** es la frontera entre el protocolo UART y los recursos
internos del procesador. Debe permitir, como mínimo, cargar/reprogramar
el programa, iniciar ejecución continua, avanzar un ciclo en modo paso a
paso y leer los datos requeridos por la consigna: 32 registros, latches
intermedios y memoria de datos utilizada.

La interfaz CLI/TUI/GUI envía comandos, presenta resultados y explica
errores. La interfaz no debe necesitar conocer detalles eléctricos de la
UART; debe operar sobre el protocolo de comandos definido por el
proyecto.

**Decisión de diseño adoptada:** utilizar UART a 115200 baudios, 8-N-1, con mensajes binarios que incluyan comando, longitud y datos. Cada comando devuelve una respuesta de éxito o error. Las consultas completas de registros, pipeline y memoria se realizan con la CPU pausada o finalizada. La UART debe permanecer operativa mientras el procesador está pausado, sin intervenir el clock físico.

## 9. Modos de ejecución y clock

La consigna define dos modos:

-   **Continuo:** un comando inicia la ejecución y el sistema continúa
    hasta alcanzar el fin del programa; luego muestra la información
    solicitada.
-   **Paso a paso:** cada comando hace avanzar **un ciclo de clock**, y
    después se muestran los valores solicitados.

Un ciclo no equivale a una instrucción. En un mismo ciclo, hasta cinco
instrucciones pueden ocupar etapas diferentes; una instrucción también
puede tardar más ciclos por stalls.

El requisito "el clock no debe verse intervenido en ninguna parte del
proyecto" implica que el control de ejecución no debe detener, manipular
o generar artificialmente el clock. Para implementar paso a paso se
puede usar una señal de **enable** sincronizada que habilite el avance
del estado del pipeline en un flanco normal del clock; el clock físico
continúa corriendo. El diseño debe asegurar que memorias, UART y lógica
de control no dependan de apagar o conmutar manualmente el clock para
simular un paso.

La consigna pide evaluar el camino crítico, el posible skew y las
métricas de Vivado. El **camino crítico** es el camino de propagación
más lento relevante para el período de reloj; limita la frecuencia
máxima estimada. El **skew** es la diferencia en el tiempo de llegada
del clock a distintos elementos secuenciales; puede reducir el margen
temporal disponible y provocar violaciones de setup/hold. Debe
distinguirse de los retardos de datos y no inferirse únicamente porque
un camino sea largo.

La frecuencia final se justificará mediante los reportes de timing de la herramienta correspondiente a la FPGA utilizada. Para la Tang Nano 20K, se utilizará Gowin EDA. Se documentarán el camino crítico, las métricas de slack y la evidencia disponible sobre skew. Si se detectan violaciones, se corregirá su causa o se seleccionará una frecuencia compatible. La consigna menciona Vivado, por lo que se deberá confirmar con el profesor si acepta los reportes equivalentes de Gowin EDA para esta placa.

## 10. Verificación: cómo convertir teoría en pruebas

Cada bloque debe tener pruebas propias antes de integrarse:

-   **ISA/ALU:** pruebas dirigidas por operación, operandos límite,
    signo, desplazamientos y comparaciones signed/unsigned.
-   **Banco de registros:** lectura, escritura, dos fuentes, registro
    destino y comportamiento inmutable de `x0`.
-   **Memorias:** latencia, direcciones, byte/halfword/word, máscaras de
    escritura y límites.
-   **Pipeline sin riesgos:** secuencia de instrucciones independientes
    y seguimiento por ciclo.
-   **Riesgos:** dependencias ALU-ALU, load-use, saltos tomados/no
    tomados, flushes y ausencia de efectos de instrucciones anuladas.
-   **HALT y fin:** detener búsqueda, drenar el pipeline y verificar que
    no quedan instrucciones válidas.
-   **UART/Debug Unit:** comandos válidos, inválidos, carga
    completa/incompleta, lecturas y errores de protocolo.
-   **Integración:** los resultados leídos por UART deben coincidir con
    los estados internos esperados.
-   **Vivado:** reportes de timing y frecuencia final documentados.

Una prueba útil no se limita a observar una forma de onda: define
estímulo, resultado esperado y criterio de aprobación. Para
instrucciones, comparar los resultados arquitectónicos con una
referencia de software o un cálculo manual ayuda a detectar errores de
codificación y de control.

## 11. Alcance teórico que no debe convertirse en requisito implícito

Los apuntes incluyen modelos y temas adicionales (por ejemplo, MIPS/DLX,
segmentaciones distintas, predicción dinámica, ejecución superescalar y
fuera de orden). No se desprende de la consigna que haya que implementar
esas técnicas. El proyecto requiere un pipeline RISC-V de cinco etapas y
ejecución correcta del conjunto indicado. Predicción dinámica, cachés,
superscalaridad, ejecución fuera de orden y ROB son **fuera de alcance
salvo que el equipo decida ampliarlo** y pueda demostrar que no
compromete los requisitos obligatorios.

## 12. Referencias de trabajo

-   **Fuente normativa del proyecto:** `TRABAJO FINAL 2026.pdf`,
    especialmente los apartados de etapas, riesgos, instrucciones, carga
    de programa, modos de operación y clock.
-   **Fuente teórica:** `Apuntes de Arquitectura de Computadoras.pdf`,
    especialmente la introducción a arquitectura/ISA y datapath, la
    segmentación de cinco etapas y el capítulo de riesgos de
    segmentación (estructurales, de datos y de control).
-   **Especificación ISA:** documentación oficial de RISC-V para
    confirmar codificación y semántica exactas de cada instrucción. Los
    apuntes de modelos MIPS/DLX no sustituyen esta especificación.
