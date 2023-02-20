LEAF(q1_code)

_start_pos:
    # 赋值 YLD[7:0], GLD[7:0] 为 VAL
    ins     YLD, VAL, 8, 8
    ins     GLD, VAL, 0, 8

    # 判断 SW[23:21]
    ins     t3, SW, 23, 1
    ins     t2, SW, 22, 1
    ins     t1, SW, 21, 1
    # 如果 SW[22] = SW[21] = 0
    or      t0, t2, t1
    beqz    t0, _sw_22_0_21_0
    # 如果 0 0 1
    or      t0, t3, t2
    not     t0, t0
    and     t0, t0, t1
    bnez    t0, _sw_23_0_22_0_21_1

    # 其他情况：接下来我们先耗费掉 1s
    # 假设 CPU 1s 执行 20M 条指令
    li      t8, 0x7 0000 0000 # 7M
_repeat_to_add:
    addi	t8, t8, -0x1
    beq     t8, zero, _lets_go_on
    j       _repeat_to_add

_lets_go_on:
    # 现在来判断 SW[23:21]
    beqz    t3, _sw_23_0
    j       _sw_23_1
_sw_23_0:
    beqz    t1, _sw_23_0_22_1_21_1
    bnez    t1, _sw_23_0_22_1_21_0
    j       _end_pos
_sw_23_1:
    and     t0, t2, t1 # 22 21 都为 1 时，t0 = 1
    bnez    t0, _sw_23_1_22_1_21_1
    beqz    t1, _sw_23_1_22_0_21_1
    beqz    t2, _sw_23_1_22_1_21_0
    j       _end_pos
    

_sw_22_0_21_0: # 无动作
    j       _end_pos

_sw_23_0_22_0_21_1: # 赋值 VAL <- SW[15:0]
    ins     VAL, SW, 0, 16
    j       _end_pos

_sw_23_0_22_1_21_0: # VAL += 1，1s 一次
    addi    VAL, VAL, 0x1
    j       _end_pos

_sw_23_0_22_1_21_1: # VAL -= 1，1s 一次
    addi    VAL, VAL, -0x1
    j       _end_pos

_sw_23_1_22_0_21_1: # VAL <<= 1，1s 一次
    sll    VAL, VAL, 0x1
    j       _end_pos

_sw_23_1_22_1_21_0: # VAL >>= 1 逻辑右移，1s 一次
    srl    VAL, VAL, 0x1
    j       _end_pos

_sw_23_1_22_1_21_1: # VAL >>= 1 算术右移，1s 一次
    srv    VAL, VAL, 0x1
    j       _end_pos


_end_pos:
    j       _start_pos

END(q1_code)