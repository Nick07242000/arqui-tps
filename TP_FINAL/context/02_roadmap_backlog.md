# Roadmap de implementación --- Procesador RISC-V segmentado con Debug Unit UART

## 1. Propósito y reglas de uso

Este documento convierte la consigna del trabajo final en un backlog ordenado por épicas, historias de usuario y tareas verificables. El
orden prioriza una versión mínima que funcione y se pueda probar antes de sumar complejidad.

**Regla de avance:** no comenzar la siguiente tarea hasta cumplir sus criterios de aceptación, registrar las pruebas y dejar una interfaz
estable para el bloque siguiente. Si una decisión queda abierta, registrarla como ADR (Architecture Decision Record) con alternativas,
elección, motivo y consecuencias.

**Convenciones** 
- **Épica:** capacidad grande del sistema. 
- **Historia (US):** resultado útil que debe lograr el sistema. 
- **Tarea (T):** trabajo concreto de diseño, implementación o verificación. 
- **Gate:** condición que debe cumplirse para avanzar. 
- **P0:** imprescindible para cumplir la consigna; 
- **P1:** trabajo necesario para integración/calidad;
- **P2:** mejora opcional.

## 2. Arquitectura objetivo y límites entre módulos

| Módulo | Responsabilidad | No debe hacer |
| --- | --- | --- |
| `program_memory` | Entregar instrucciones al CPU y aceptar escritura de instrucciones desde la Debug Unit durante la carga. | Decidir cuándo ejecutar el programa o interpretar comandos UART. |
| `data_memory` | Ejecutar lecturas/escrituras de datos solicitadas por el CPU y exponer contenido consultable por debug. | Decodificar instrucciones. |
| `pc_control` | Mantener el PC y seleccionar PC secuencial, destino de branch/jump, reset y condiciones de stall/flush. | Controlar el reloj físico. |
| `register_file` | Leer dos operandos, escribir un destino y garantizar `x0 = 0`. | Resolver riesgos por sí solo. |
| `immediate_generator` | Extraer/reconstruir y extender inmediatos de los formatos requeridos. | Decodificar la operación completa. |
| `control_unit` | Decodificar instrucciones y generar señales de control. | Transportar señales a una etapa incorrecta; los controles deben viajar con la instrucción. |
| `alu` | Ejecutar operaciones ALU y comparaciones requeridas. | Seleccionar por sí sola el flujo completo del programa. |
| `hazard_unit` | Detectar dependencias que el forwarding no resuelve (load-use) y solicitar stall o flush. | Alterar los resultados arquitectónicos para "arreglar" una prueba. |
| `forwarding_unit` | Seleccionar operandos recientes disponibles desde etapas posteriores cuando sea posible. | Enmascarar una dependencia cuyo dato aún no existe; load-use puede requerir stall. |
| `pipeline_registers` | Conservar datos, controles y validez entre etapas. | Tener decisiones de protocolo UART o interfaz de PC. |
| `halt_controller` | Reconocer la instrucción custom HALT, controlar el fin de la búsqueda, impedir efectos de instrucciones posteriores y esperar a que el pipeline se vacíe antes de activar done. | Debe operar mediante señales síncronas de control y nunca detener ni modificar el clock físico. |
| `uart_rx` / `uart_tx` | Recibir/transmitir bytes de forma fiable. | Interpretar por sí solos el significado de comandos de alto nivel. |
| `debug_unit` | Decodificar comandos, secuenciar carga/ejecución/lecturas y entregar respuestas. | Ejecutar lógica de ALU o duplicar el datapath del CPU. |
| Aplicación de PC | Permitir cargar programas, ejecutar, avanzar ciclos y visualizar estado. | Suponer que una respuesta llegó sin verificar el protocolo. |

Los nombres son sugeridos, no obligatorios. Se puede combinar módulos si las interfaces siguen claras y verificables.

## 3. Épica E0 --- Diseño y contratos de interfaz

### Objetivo

Evitar comenzar a codificar con interfaces ambiguas o dependencias no resueltas.

### US-0.1 --- Definir la arquitectura del sistema (P0)

**Tareas** 
- **T0.1.1:** dibujar el datapath IF--ID--EX--MEM--WB, sus latches, PC, memorias, banco de registros, ALU y unidad de control. 
- **T0.1.2:** dibujar la conexión PC ↔ UART ↔ Debug Unit ↔ memoria de programa/CPU y el camino de lectura de estado. 
- **T0.1.3:** definir anchos de señales, direcciones, latencia de memoria y qué flanco/etapa consume cada dato. 
- **T0.1.4:** definir convenciones de reset, `valid`, stall, flush, `HALT`, fin de imagen y estado `busy/done/error`. 
- **T0.1.5:** definir el protocolo de comandos y respuestas UART, incluyendo longitud, errores y límites. 
- **T0.1.6:** registrar las decisiones adoptadas: memorias de instrucciones y datos separadas, forwarding desde `EX/MEM` y `MEM/WB` con stall de un ciclo en load-use (alternativa por tiempo: solo stalls), resolución de branches y jumps en EX, reset de registros y pipeline, persistencia de la memoria de datos, convención HALT, longitud `N_WORDS`, protocolo UART y frecuencia inicial según la plataforma.

**Criterios de aceptación / Gate E0** 
- Existe un diagrama actualizado de arquitectura y un mapa de interfaces. 
- Cada señal entre módulos tiene productor, consumidor, ancho y significado definidos. 
- Están definidos el comportamiento de reset, carga, `run`, `step`, `halt`, consulta de estado y errores. 
- No quedan decisiones críticas escondidas en el código.

## 4. Épica E1 --- Componentes base verificables

### US-1.1 --- ALU RISC-V (P0)

**Tareas** 
- **T1.1.1:** implementar operaciones internas necesarias: suma, resta, AND, OR, XOR, shifts lógico/arimético y comparaciones signed/unsigned. 
- **T1.1.2:** mapear códigos de control a cada operación, evitando colisiones entre instrucciones. 
- **T1.1.3:** crear testbench con operandos normales y límites: cero, uno, máximos, negativos representados en complemento a dos y cantidades de shift límite.

**Criterios** 
- Todas las operaciones ALU que requiere la ISA producen el resultado esperado. 
- `sra` y `srl`, y `slt` y `sltu`, se diferencian correctamente. 
- La selección de operación no depende de valores no inicializados.

### US-1.2 --- Banco de registros (P0)

**Tareas** 
- **T1.2.1:** implementar 32 registros de 32 bits, dos puertos de lectura y un puerto de escritura. 
- **T1.2.2:** asegurar que leer `x0` siempre devuelve cero y escribir `x0` no modifica su valor. 
- **T1.2.3:** probar lectura simultánea de dos registros, escritura, colisiones lectura/escritura y reset según la política acordada.

**Criterios** 
- Los 31 registros modificables se leen/escriben correctamente. 
- `x0` permanece cero bajo cualquier secuencia de escritura. 
- La latencia de lectura/escritura queda documentada y es compatible con el pipeline.

### US-1.3 --- Generador de inmediatos y decodificador (P0)

**Tareas** 
- **T1.3.1:** implementar extracción de campos R, I, S, B, U y J. 
- **T1.3.2:** reconstruir inmediatos B/J con los bits en el orden RISC-V correcto. 
- **T1.3.3:** implementar extensión de signo y los casos especiales de shifts. 
- **T1.3.4:** decodificar opcode/funct3/funct7 y generar controles para cada instrucción obligatoria. 
- **T1.3.5:** probar palabras máquina conocidas y casos con inmediatos positivos/negativos.

**Criterios** 
- Cada instrucción obligatoria se clasifica en el tipo correcto y produce sus controles correctos. 
- Los inmediatos reconstruidos coinciden con una referencia de codificación RISC-V. 
- Las instrucciones no soportadas se identifican como ilegales/errores o se neutralizan de forma documentada; nunca generan escrituras accidentales.

### US-1.4 --- Memorias (P0)

**Tareas** 
- **T1.4.1:** definir tamaño, profundidad, dirección base, latencia, ancho y comportamiento de lectura para memoria de programa y de datos. 
- **T1.4.2:** implementar acceso a palabras para una primera versión. 
- **T1.4.3:** ampliar memoria de datos a byte/halfword/word con selección de bytes y extensión correcta. 
- **T1.4.4:** añadir acceso de escritura desde Debug Unit a memoria de programa, independiente del flujo de ejecución del CPU. 
- **T1.4.5:** probar límites de dirección, lectura, escritura y acceso concurrente según la política elegida.

**Criterios** 
- Se puede escribir y leer una instrucción máquina por dirección de programa desde una interfaz de prueba. 
- `lb/lh/lw/lbu/lhu` y `sb/sh/sw` tienen el comportamiento requerido. 
- No hay escrituras fuera de rango ni colisiones no documentadas. 
- La latencia real de memoria está reflejada en el diseño del pipeline.

**Gate E1** 
- ALU, banco de registros, decodificador/generador de inmediatos y memorias tienen pruebas unitarias aprobadas. 
- Cada módulo tiene una interfaz documentada y no depende de un top-level todavía inestable.

## 5. Épica E2 --- Datapath no segmentado funcional como base de referencia

> Esta etapa es un método de desarrollo recomendado, no un requisito
> explícito de la consigna. Si el equipo construye directamente el
> pipeline, debe conservar pruebas equivalentes por bloque y por
> instrucción.

### US-2.1 --- Ejecutar instrucciones aisladas y validar el datapath (P0)

**Tareas** 
- **T2.1.1:** conectar PC, memoria de programa, decodificador, banco de registros, generador de inmediatos, ALU y selección de writeback en un modelo mínimo. 
- **T2.1.2:** verificar por separado operaciones R, inmediatos, loads/stores, branches, `jal`, `jalr` y `lui`. 
- **T2.1.3:** construir un programa pequeño que calcule valores conocidos y escriba resultados en registros/memoria. 
- **T2.1.4:** comparar resultados con cálculo manual o un ensamblador/simulador RISC-V de referencia.

**Criterios** 
- Cada instrucción se ejecuta correctamente en el caso aislado y en secuencias cortas. 
- Se validan PC secuencial y cambios de flujo. 
- Esta base no se considera lista para el entregable final hasta estar integrada con el pipeline de cinco etapas.

## 6. Épica E3 --- Pipeline de cinco etapas

### US-3.1 --- Segmentar el datapath (P0)

**Tareas** 
- **T3.1.1:** definir campos de `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`, incluidos datos y controles. 
- **T3.1.2:** insertar latches y separar las funciones IF, ID, EX, MEM y WB. 
- **T3.1.3:** propagar `valid` o equivalente por cada etapa. 
- **T3.1.4:** verificar una secuencia de instrucciones independientes y registrar por ciclo la instrucción de cada etapa. 
- **T3.1.5:** comprobar que las escrituras arquitectónicas ocurren en la etapa prevista y una sola vez.

**Criterios** 
- Se observan cinco etapas distintas con avance sincronizado por clock. 
- Varias instrucciones ocupan etapas distintas simultáneamente. 
- Datos y señales de control pertenecen a la misma instrucción a lo largo del pipeline. 
- Sin riesgos, los resultados coinciden con la versión de referencia.

### US-3.2 --- Riesgos de datos y forwarding (P0)

**Objetivo:** resolver correctamente las dependencias entre instrucciones y reducir stalls mediante forwarding cuando sea posible.

**Tareas**
- **T3.2.1:** identificar los registros fuente realmente utilizados por cada instrucción y los registros destino de las instrucciones que escriben resultados.
- **T3.2.2:** implementar forwarding desde `EX/MEM` y `MEM/WB` hacia las entradas de la ALU en EX, priorizando el resultado más reciente cuando más de una instrucción anterior pueda suministrar el mismo registro.
- **T3.2.3:** evitar forwarding desde `EX/MEM` cuando la instrucción allí ubicada sea un `load` cuyo dato leído de memoria todavía no esté disponible.
- **T3.2.4:** implementar la detección de dependencias *load-use* que no puedan resolverse a tiempo e insertar el stall requerido.
- **T3.2.5:** durante un stall, congelar el PC y `IF/ID`, y colocar una burbuja en `ID/EX`, permitiendo que las instrucciones anteriores continúen avanzando.
- **T3.2.6:** probar dependencias inmediatas ALU-ALU, dependencias con instrucciones intermedias, cadenas de dependencias, dependencias sobre el mismo destino y *load-use*.
- **T3.2.7:** verificar que stalls y forwarding no dupliquen stores ni escrituras de registros, no pierdan instrucciones y respeten `x0`.
- **T3.2.8:** si el forwarding no puede completarse dentro del tiempo disponible, implementar una alternativa basada exclusivamente en stalls, actualizar la documentación y ejecutar nuevamente las pruebas de dependencias.

**Criterios**
- Las instrucciones consumen el valor más reciente disponible de cada operando.
- El forwarding selecciona correctamente entre resultados de `EX/MEM` y `MEM/WB`.
- Las dependencias *load-use* esperan los ciclos necesarios cuando el dato aún no está disponible.
- PC e instrucciones en `IF/ID` no se pierden durante un stall.
- Las burbujas no producen efectos arquitectónicos.
- La alternativa basada exclusivamente en stalls se considera aceptable únicamente si mantiene resultados correctos y supera las mismas pruebas funcionales.

### US-3.3 --- Riesgos de control (P0)

**Tareas** 
- **T3.3.1:** definir en qué etapa se resuelven branch y jump. 
- **T3.3.2:** implementar selección del próximo PC para secuencial, branch tomado/no tomado, `jal` y `jalr`. 
- **T3.3.3:** implementar flush/invalidez de instrucciones que pertenezcan al camino incorrecto. 
- **T3.3.4:** probar branch tomado y no tomado, loops, salto hacia adelante/atrás y dependencias entre resultado ALU y condición. 
- **T3.3.5:** confirmar que instrucciones anuladas no escriben registros ni memoria.

**Criterios** 
- El flujo de control es correcto para todas las instrucciones de salto requeridas. 
- No se observan efectos de instrucciones del camino descartado. 
- La penalización de salto está documentada y coincide con la implementación.

### US-3.4 --- Riesgos estructurales (P0)

**Tareas** 
- **T3.4.1:** identificar todos los recursos compartidos por etapas. 
- **T3.4.2:** resolver conflictos por diseño de memoria/puertos o mediante stalls/arbitraje. 
- **T3.4.3:** probar fetch simultáneo con acceso de datos y accesos concurrentes de Debug Unit según los estados permitidos.

**Criterios** 
- Ningún acceso válido se pierde o corrompe por contención. 
- Si la arquitectura impide ciertas operaciones simultáneas, el protocolo informa/gestiona el conflicto de forma determinista.

**Gate E3** 
- Testbench de regresión con instrucciones independientes, dependencias, load-use, branches, jumps y memoria. 
- Resultados arquitectónicos correctos y trazas por ciclo comprensibles. 
- No se avanza a UART hasta tener una CPU reproducible en simulación.

## 7. Épica E4 --- Reset, carga, HALT y control de ejecución

### US-4.1 --- Política de reset y estado inicial (P0)

**Tareas**
- **T4.1.1:** implementar reset del PC e invalidar todos los latches del pipeline.
- **T4.1.2:** inicializar `x1`–`x31` en cero y garantizar que `x0` siempre lea cero.
- **T4.1.3:** conservar la memoria de datos durante reset y carga; los programas de prueba deben inicializar las posiciones que utilizan.
- **T4.1.4:** distinguir reset del CPU, carga de programa y comienzo de ejecución.
- **T4.1.5:** probar ejecuciones sucesivas con programas diferentes.

**Criterios**
- Cada nueva ejecución comienza con PC, registros y pipeline en el estado definido.
- La memoria de datos conserva su contenido según la política documentada.
- No quedan instrucciones de una ejecución anterior en el pipeline.

### US-4.2 --- Carga de programa y reprogramación (P0)

**Tareas** 
- **T4.2.1:** definir la imagen como una secuencia de palabras de 32 bits y registrar la cantidad `N_WORDS`.
- **T4.2.2:** implementar un comando de carga que reciba la cantidad de palabras y el contenido del programa.
- **T4.2.3:** validar que se recibieron todas las palabras y que la longitud no supera la capacidad de la memoria.
- **T4.2.4:** mantener el CPU detenido y rechazar `RUN` mientras la carga esté incompleta.
- **T4.2.5:** probar la carga y ejecución del programa A, seguida por la carga y ejecución del programa B en el mismo bitstream.

**Criterios** 
- Las palabras cargadas se leen idénticas a las enviadas. 
- El sistema detecta cargas truncadas, tamaños excesivos y direcciones inválidas. 
- La reprogramación se realiza por UART en tiempo de ejecución y no requiere nueva síntesis.
- 
### US-4.3 --- HALT custom y vaciado final (P0)

**Objetivo:** permitir que un programa finalice mediante una instrucción custom y garantizar que el estado final se muestre solo después de completar todas las instrucciones válidas anteriores.

**Tareas**
- **T4.3.1:** definir `HALT` como la palabra máquina `0x0000000B`, utilizando el opcode `custom-0` de RISC-V y reconociendo la palabra completa en el decodificador.
- **T4.3.2:** incorporar `HALT` al flujo de traducción del programa, mediante `.word 0x0000000B` o un mecanismo equivalente que genere exactamente esa codificación.
- **T4.3.3:** al detectar `HALT`, detener la búsqueda de instrucciones nuevas e impedir que las instrucciones posteriores produzcan efectos arquitectónicos.
- **T4.3.4:** permitir que las instrucciones válidas anteriores a `HALT` completen sus operaciones, incluyendo escrituras de registros y stores.
- **T4.3.5:** activar `done` solamente cuando no queden instrucciones válidas en el pipeline ni efectos pendientes.
- **T4.3.6:** mantener `N_WORDS` como límite de seguridad para la imagen cargada. Si se alcanza el límite sin `HALT`, finalizar mediante el mismo mecanismo de vaciado e informar que se llegó al final de la imagen sin una parada explícita.
- **T4.3.7:** probar `HALT` después de escrituras de registros y stores, instrucciones posteriores a `HALT`, imágenes sin `HALT` y programas de distinta longitud cargados consecutivamente.

**Criterios**
- El decodificador reconoce la codificación reservada para `HALT`.
- Las instrucciones anteriores a `HALT` completan sus efectos antes de `done`.
- Ninguna instrucción posterior a `HALT` modifica registros o memoria.
- El pipeline está vacío cuando se declara la finalización.
- Una imagen sin `HALT` termina de forma determinista al alcanzar `N_WORDS`.
- Cargar una imagen nueva no permite ejecutar instrucciones residuales de la imagen anterior.

### US-4.4 --- Paso a paso sin intervenir el clock (P0)

**Tareas** 
- **T4.4.1:** diseñar un enable síncrono de avance del CPU. 
- **T4.4.2:** asegurar que el clock de FPGA sigue activo y no se crea un clock derivado/gated para el modo step. 
- **T4.4.3:** definir cómo se relacionan stall/flush con el enable de paso a paso. 
- **T4.4.4:** probar que un comando `STEP` permite exactamente un avance lógico de ciclo del pipeline, salvo que la especificación del protocolo diferencie aceptación del comando y ejecución. 
- **T4.4.5:** comprobar que UART RX/TX puede seguir recibiendo y respondiendo mientras el CPU está pausado.

**Criterios** 
- No se interviene el clock físico. 
- Cada comando de paso a paso produce el comportamiento de un ciclo documentado y se devuelve una instantánea posterior consistente. 
- El UART no queda inutilizado por pausar la CPU.

**Gate E4** 
- Reset, carga, reprogramación, HALT, finalización y step funcionan en simulación. 
- El estado final es determinista y el pipeline queda vacío.

## 8. Épica E5 --- UART y Debug Unit

### US-5.1 --- UART RX/TX fiable (P0)

**Tareas** 
- **T5.1.1:** implementar UART a 115200 baudios, 8-N-1, utilizando el reloj de la placa y un divisor calculado para esa frecuencia.
- **T5.1.2:** verificar recepción y transmisión de bytes, errores de framing y secuencias largas. 
- **T5.1.3:** definir buffers y comportamiento ante overflow/bytes inesperados.

**Criterios** 
- Los bytes recibidos y transmitidos coinciden con la prueba de referencia. 
- Los errores no dejan el protocolo bloqueado indefinidamente.

### US-5.2 --- Protocolo de comandos (P0)

Definí un protocolo binario con comando, longitud, datos y respuesta de éxito/error. No hace falta incorporar un mecanismo de versionado o checksum para la primera versión.

**Tareas** 
- **T5.2.1:** implementar parser de mensajes y estados de protocolo. 
- **T5.2.2:** implementar respuesta explícita para comando correcto, inválido, ocupado, datos insuficientes y error interno. 
- **T5.2.3:** limitar tamaño de mensajes y validar argumentos/direcciones antes de modificar estado. 
- **T5.2.4:** documentar el protocolo de bytes para que la aplicación de PC pueda implementarlo independientemente.

**Criterios** 
- Cada comando válido tiene una respuesta inequívoca. 
- Un comando inválido no corrompe CPU ni memorias. 
- Se manejan correctamente mensajes fragmentados o recibidos de forma parcial si el protocolo de transporte lo permite.

### US-5.3 --- Acciones de Debug Unit (P0)

**Tareas** 
- **T5.3.1:** conectar comandos de carga con la escritura de memoria de programa. 
- **T5.3.2:** conectar `RUN`, `STEP`, `RESET`/preparación y consulta de estado. 
- **T5.3.3:** exponer los 32 registros arquitectónicos. 
- **T5.3.4:** exponer los campos/controles de todos los latches intermedios. 
- **T5.3.5:** exponer la memoria de datos utilizada, con límites de consulta y formato definido. 
- **T5.3.6:** garantizar que la lectura de estado no provoca escrituras ni cambia el estado del CPU. 
- **T5.3.7:** probar las consultas completas cuando el CPU está pausado, en modo paso a paso o finalizado. Durante `RUN`, permitir únicamente la consulta de estado básico.

**Criterios** 
- La Debug Unit puede cargar/reprogramar y controlar la ejecución por UART. 
- Los datos que informa coinciden con el estado interno de simulación. 
- Se pueden consultar registros, latches y memoria de datos. 
- El protocolo informa cuándo el estado está en ejecución, detenido, cargando o finalizado.

**Gate E5** 
- Pruebas de integración UART ↔ Debug Unit ↔ CPU aprobadas en simulación. 
- Especificación de protocolo actualizada y probada con un cliente de prueba.

## 9. Épica E6 --- Herramienta de traducción y aplicación de PC

### US-6.1 --- Ensamblador/traductor de programa (P0)

**Tareas** 
- **T6.1.1:** seleccionar una herramienta de ensamblado RISC-V existente compatible con la ISA implementada.
- **T6.1.2:** definir la palabra reservada HALT y agregarla al final del programa mediante el proceso de preparación de la imagen.
- **T6.1.3:** generar la imagen de palabras máquina y registrar `N_WORDS`.
- **T6.1.4:** cotejar las palabras generadas con una herramienta de referencia antes de transmitirlas.

**Criterios** 
- El flujo acepta un programa ensamblador, lo traduce y genera datos cargables. 
- La codificación coincide con la ISA implementada, no con MIPS/DLX. 
- Los errores de ensamblado/codificación se informan antes de enviar la imagen.

### US-6.2 --- Cliente de PC mínimo (P0)

**Tareas** 
- **T6.2.1:** implementar conexión a puerto serie y configuración UART. 
- **T6.2.2:** implementar `load`, `run`, `step`, `status`, `regs`, `pipeline` y consulta de memoria. 
- **T6.2.3:** mostrar respuestas y errores sin ocultar timeouts o desconexiones. 
- **T6.2.4:** separar el transporte serie, el protocolo y la presentación para facilitar pruebas.
- **T6.2.5:** crear una sesión de demostración repetible con programa conocido.

**Criterios** 
- Se puede cargar un programa, ejecutarlo de forma continua y en paso a paso. 
- Se muestran registros, latches y memoria de datos. 
- La aplicación detecta errores y no informa éxito sin una confirmación de FPGA.

### US-6.3 --- Experiencia de visualización (P1)

**Tareas**
- **T6.3.1:** implementar una CLI con comandos y salidas legibles.
- **T6.3.2:** mostrar las cinco etapas del pipeline y distinguir instrucciones válidas, burbujas y etapas vacías.
- **T6.3.3:** mostrar registros y memoria con sus direcciones o índices en hexadecimal.
- **T6.3.4:** mostrar el estado de conexión y ejecución y los errores del protocolo.

No se requiere una TUI o GUI para cumplir el proyecto.

**Criterios** 
- El usuario puede interpretar el estado del procesador sin inspeccionar señales internas de Vivado. 
- La visualización distingue una instrucción válida de una burbuja y de una etapa vacía.

**Gate E6** 
- Cliente de PC y FPGA completan la demo integral con un programa conocido. 
- El flujo de carga y ejecución no requiere intervención manual de herramientas de síntesis.

## 10. Épica E7 --- Integración FPGA y análisis temporal

### US-7.1 --- Integración en Vivado (P0/P1)

**Tareas** 
- **T7.1.1:** integrar top-level, pines, UART, memorias/IP cores y clock según la plataforma. 
- **T7.1.2:** verificar constraints de reloj y de pines. 
- **T7.1.3:** revisar informes de síntesis/implementación, uso de recursos y advertencias. 
- **T7.1.4:** ejecutar pruebas en hardware para carga, ejecución, step y lectura de estado.

**Criterios** 
- El bitstream puede cargar y ejecutar programas sin resíntesis entre programas. 
- Las interfaces físicas y constraints están documentadas. 
- Las advertencias críticas se investigan y no se ignoran sin justificación.

### US-7.2 --- Camino crítico, skew y frecuencia (P0)

**Tareas** 
- **T7.2.1:** identificar el camino crítico en los reportes de timing de la implementación integrada. 
- **T7.2.2:** revisar slack de setup/hold, retardo de datos y skew del clock; distinguir sus causas. 
- **T7.2.3:** determinar si hay violaciones y qué lógica/recursos las originan. 
- **T7.2.4:** optimizar el diseño o seleccionar una frecuencia compatible con los reportes. 
- **T7.2.5:** registrar métricas de Gowin EDA antes/después y la frecuencia final elegida. 
- **T7.2.6:** evaluar PLL de Gowin e IP cores de memoria si aportan una solución adecuada, documentando la decisión.

**Criterios** 
- El informe identifica el camino crítico y presenta métricas concretas de Vivado. 
- La frecuencia elegida está respaldada por los reportes de timing. 
- No se afirma que hay skew solo por existir un camino crítico; se presenta evidencia del reporte. 
- El clock no es intervenido para implementar el modo de paso a paso.

**Gate E7** 
- La implementación integrada funciona en FPGA. 
- El reporte de timing y la frecuencia final están documentados. 
- Se completa la regresión final en hardware.

## 11. Épica E8 --- Regresión, documentación y entrega

### US-8.1 --- Pruebas end-to-end (P0)

**Tareas** 
- **T8.1.1:** definir programas de prueba: ALU, inmediatos, loads/stores, dependencias, load-use, branches, jumps, HALT y memoria. 
- **T8.1.2:** para cada programa registrar imagen, estado inicial, resultado esperado y resultado observado. 
- **T8.1.3:** repetir carga/ejecución con más de un programa para demostrar reprogramación dinámica. 
- **T8.1.4:** probar comando inválido, carga incompleta, memoria fuera de rango, desconexión UART y programa sin HALT. 
- **T8.1.5:** verificar en modo step la traza por ciclo y el vaciado final.

**Criterios** 
- Las pruebas críticas pasan de manera reproducible. 
- Cada fallo tiene una evidencia y un estado de resolución. 
- No hay diferencias inexplicadas entre simulación y FPGA.

### US-8.2 --- Documentación técnica (P0)

**Tareas** 
- **T8.2.1:** documentar arquitectura, módulos, interfaces y decisiones. 
- **T8.2.2:** documentar protocolo UART y uso de la aplicación de PC. 
- **T8.2.3:** documentar instrucciones soportadas, limitaciones y convención HALT. 
- **T8.2.4:** documentar estrategia de riesgos, pruebas y resultados. 
- **T8.2.5:** incluir reportes de Vivado, camino crítico, skew, frecuencia y recursos relevantes.

**Criterios** 
- Un tercero puede comprender el sistema, cargar un programa y repetir las pruebas usando solo la documentación. 
- Las decisiones que la consigna deja abiertas están justificadas.

## 12. Orden de trabajo resumido

1.  **E0:** arquitectura, interfaces y decisiones.
2.  **E1:** ALU, banco de registros, inmediatos/decodificador y memorias.
3.  **E2:** referencia funcional mínima del datapath (si se adopta esta estrategia).
4.  **E3:** pipeline y riesgos, con regresión de CPU.
5.  **E4:** reset, carga, HALT, fin y step sin intervenir clock.
6.  **E5:** UART y Debug Unit.
7.  **E6:** traductor y aplicación de PC.
8.  **E7:** integración FPGA y timing.
9.  **E8:** regresión y documentación.

No conviene comenzar por una GUI ni integrar UART antes de tener un contrato de estado y ejecución estable. 
Tampoco conviene dejar el manejo de HALT, el vaciado del pipeline o la política de reset para el final: condicionan el comportamiento de `run`, `step`, `done` y las consultas de debug.

## 13. Matriz mínima de trazabilidad

| Requisito de consigna | Épica/US principal | Evidencia mínima |
| --- | --- | --- |
| Pipeline de cinco etapas | E3 / US-3.1 | Traza por ciclo con IF, ID, EX, MEM, WB. |
| ISA enumerada | E1 + E2 + E3 | Prueba por instrucción y pruebas de secuencia. |
| Riesgos estructurales, de datos y control | E3 / US-3.2--3.4 | Testbenches de contención, dependencias y saltos. |
| Debug Unit por UART | E5 | Prueba de comandos y respuestas desde cliente. |
| Mostrar 32 registros | E5 / US-5.3 | Respuesta UART comparada con banco de registros. |
| Mostrar latches intermedios | E5 / US-5.3 | Respuesta con los campos de cada latch. |
| Mostrar memoria de datos usada | E5 / US-5.3 | Lectura de rango documentado. |
| Programa en ensamblador y traducción a máquina | E6 / US-6.1 | Fuente ensamblador, imagen generada y cotejo. |
| HALT/STOP y respuesta ante su ausencia | E4 / US-4.3 | Pruebas con y sin HALT. |
| Carga/reprogramación por UART sin resíntesis | E4 + E5 + E6 | Cargar programa A y luego B en el mismo bitstream. |
| Modo continuo | E4 + E5 + E6 | `run` termina y muestra estado solicitado. |
| Paso a paso, un ciclo por comando | E4 + E5 + E6 | Traza y snapshot después de cada ciclo lógico. |
| Pipeline vacío al finalizar | E4 / US-4.3 | Todos los `valid` inactivos y sin efectos pendientes. |
| Clock no intervenido | E4 + E7 | Diseño con enable síncrono y revisión del clocking. |
| Camino crítico, skew y frecuencia de Vivado | E7 / US-7.2 | Reportes y justificación de frecuencia. |
| Documentar decisiones | E0 + E8 | ADRs y documentación técnica. |
