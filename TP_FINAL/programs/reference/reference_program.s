# -----------------------------------------------------------------------------
# Programa de referencia 
# Calcula valores conocidos y los deja en registros y en memoria de datos.
# -----------------------------------------------------------------------------

        .macro  halt
        .word   0x0000000B
        .endm

        .text
        .globl  _start
_start:

# ---- A. Aritmetica y logica con 10 y 3 ---------------------------------------
        addi    x2, x0, 10
        addi    x3, x0, 3
        add     x4, x2, x3              # 13
        sub     x5, x2, x3              # 7
        and     x6, x2, x3              # 2    (1010 & 0011)
        or      x7, x2, x3              # 11   (1010 | 0011)
        xor     x8, x2, x3              # 9    (1010 ^ 0011)
        sll     x9, x2, x3              # 80   (10 << 3)
        srl     x10, x2, x3             # 1    (10 >> 3)

# ---- B. Suma 1 + 2 + ... + 10 con un lazo ------------------------------------
        addi    x11, x0, 10             # contador
        addi    x12, x0, 0              # acumulador
loop_sum:
        beq     x11, x0, end_sum
        add     x12, x12, x11
        addi    x11, x11, -1
        jal     x0, loop_sum
end_sum:
        sw      x12, 64(x0)             # mem[0x40] = 55

# ---- C. Los primeros 10 numeros de fibonacci en memoria ------------------------
        addi    x13, x0, 0              # fib(i)
        addi    x14, x0, 1              # fib(i+1)
        addi    x15, x0, 0              # puntero (bytes)
        addi    x16, x0, 10             # elementos restantes
loop_fib:
        sw      x13, 0(x15)
        add     x17, x13, x14
        addi    x13, x14, 0
        addi    x14, x17, 0
        addi    x15, x15, 4
        addi    x16, x16, -1
        bne     x16, x0, loop_fib

# ---- D. Llamada a una funcion que suma un arreglo de memoria -------------------
        addi    x18, x0, 0              # direccion del arreglo
        addi    x19, x0, 10             # cantidad de elementos
        jal     x1, sum_array           # resultado en x20
        sw      x20, 68(x0)             # mem[0x44] = 88

# ---- E. Accesos de byte y media palabra sobre 0x80FF7F01 -----------------------
        lui     x22, 0x80FF8
        addi    x22, x22, -255          # x22 = 0x80FF7F01
        addi    x24, x0, 72             # base 0x48
        sw      x22, 0(x24)
        lb      x25, 3(x24)             # 0x80 con signo
        lbu     x26, 3(x24)             # 0x80 sin signo
        lh      x27, 2(x24)             # 0x80FF con signo
        lhu     x28, 2(x24)             # 0x80FF sin signo
        addi    x31, x0, 0x55
        sb      x31, 1(x24)             # byte 1: 0x7F -> 0x55
        lw      x30, 0(x24)             # 0x80FF5501

# ---- F. Operaciones con signo y sin signo ------------------------------------
        addi    x29, x0, -16            # 0xFFFFFFF0
        sra     x23, x29, x3            # -16 >> 3 = -2
        sltu    x24, x2, x29            # 10 < 0xFFFFFFF0 sin signo -> 1
        slt     x31, x2, x29            # 10 < -16 con signo -> 0

        halt

# ---- Funcion sum_array(x18 = direccion, x19 = cantidad) -> x20 ------------------
sum_array:
        addi    x20, x0, 0
sum_loop:
        lw      x21, 0(x18)
        add     x20, x20, x21
        addi    x18, x18, 4
        addi    x19, x19, -1
        bne     x19, x0, sum_loop
        jalr    x0, 0(x1)               # retorno