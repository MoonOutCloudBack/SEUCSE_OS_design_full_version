#define _BOOTCODE 1

#include "boot.h"
#include <mips/regdef.h>
#include <mips/asm.h>
#include <mips/m32c0.h>

	.set	noreorder           # Don't allow the assembler to reorder instructions.
	.set	noat                # Don't allow the assembler to use r1(at) for synthetic instr.

# #################
# 
# 首先，MIPS 的 cache 分为 instruction cache 与 data cache
# init 时，要把所有 cache tag 置为 invalid（通过修改 tag 为全零）
# 达成“所有”的方法，是 1. 得到一共有多少个 cache，2. 计数 一个一个初始化
# 
# #################


# 想跑特权指令，应该要先切到 kernel mode

# 对给出的内存地址 a0，hit writeback + hit invalid
LEAF(_mm_clflush)
    # cache 里的地址应该是 VA 吧，a0 给 VA 应该没问题

    cache   0x19, 0(a0)     # op: 110 01, hit writeback, dcache
    nop
    nop
    nop
    nop
    cache   0x11, 0(a0)     # op: 100 01, hit invalid, dcache
    nop
    nop
    nop
    nop
    jr      ra              # 重申：ra（通用寄存器 31）代表当前 subroutine 的 return addr，相当于 C++ return
    nop
    nop
    nop
    nop
END(_mm_clflush)



# 在 manual 324 / 365 页
# cache 指令：cache op, offset(base)
	# 指令格式：(31)101111(26) (25)base-5(21) (20)op-5(16) (15)offset-16(0)
	# offset(base_reg)：
		# 将 16 位 offset 符号扩展，并与 base_reg 的值相加，得到参数
	# op 的 [17:16] 位指定了要操作的 cache：
		# 00 I 第一级 icache
		# 01 D 第一级 dcache 或整个的第一级 cache（如果没分 icache dcache）
		# 10 T 第三级。 11 S 第二级。（不过咱应该只有一级 cache 吧）
	# op 的 [20:18] 位为操作类型：
		# 后面 offset(base) 参数为 cache index：
			# 000：设为 invalid
			# 001：load tag，把 tag 读到 CP0_TAGLO 里
			# 010：store tag，从 CP0_TAGLO 写入 tag
			# 011：store data，从 CP0_DATALO 里写入 cache 的 data 段
		# 后面 offset(base) 参数为内存 addr：
			# 100：hit invalid，如果 cache 里有给出的 addr，那么设它为 invalid
			# 101：对 icache 来说，用该 addr 的内容 fill 它；对 dcache 来说，好像还是 hit invalid？
			# 110：Hit Writeback，如果这个 line 是 dirty 的，强制写回（并且仍保持在 valid)
			# 111: fetch and lock，用该 addr 的内容 fill 它，并且把 cache 锁住（即，我们认为这个数据很重要，就不要把它换出来了）



/**************************************************************************************
**************************************************************************************/

LEAF(_flush_icache)

	# Determine how big the I$ is
	mfc0	t0, C0_CONFIG1		# read C0_Config1. 我们把 C0_Config1 存到 t0 了
	# C0_CONFIG1 寄存器的 IL（21:19）表示 icache 的 line size：0x0 为没有 icache，0x3 表示 16B
	ext		t1, t0, 19, 3	    # extract IL

	# Skip ahead if No I$. 如果没有 icache，则直接 done
	beq		t1, zero, _done_flush_icache
	nop

	li		t1, 0x10		# 下次用到 t1 是初始化所有 icache 行的时候，t1 存储的是相邻 icache行映射的虚拟地址的递增量

	# 首先得到 icache 的真正 line size

	# C0_CONFIG1 寄存器的 IS（24:22）表示 icache 每一 way 的 line 数量
	# 0x0: 64; 0x1: 128; 0x2: 256; 0x3: 512; 0x4: 1024。 也就是 64 左移的位数
	ext	    t2, t0, 22, 3		# extract IS
	li		t3, 64
	sllv	t2, t3, t2  		# I$ Sets per way, icache 每一 way 的 line 数量，存到 t2
	# sllv 指令：sll rD,rS,rT： rD = rS << (rT 末五位)

	# C0_CONFIG1 寄存器的 IA（18:16）表示 icache 的相联度, 即 有多少 way
	# 0x0: Direct mapped; 0x1: 2-way; 0x2: 3-way; 0x3: 4-way。 加一得到真正相联度
	ext		t3, t0, 16, 3		# extract IA
	addi	t3, t3, 1			# 加一，然后 把相联度存到 t3

	# 得到 icache 总 line 数 = way 数 * 每一 way 的 line 数量
	# 我们要把每个 cache 都置为 invalid，因此需要计数 处理了多少个，所以需要知道总 line 数
	mul		t4, t3, t2			# Total number of sets，将其存到 t4

	# 为接下来的 cache 操作，得到 KSeg0 地址
    lui		t5, 0x8000    		# Get a KSeg0 address for cacheops，存在 t5
	# rD <- (imme<<16)，0x8000 左移 16 位成为虚拟地址 0x8000 0000，是 KSeg0 起始地址，对应物理地址 0x0000 0000

	# Clear TagLo/TagHi registers
	# TagLo 是 CP0 的第 28 号（从 0 开始计数）寄存器，作为 cache tag 的接口（个人理解为缓冲，参见下面 cache 指令）
	# Manual 说 microAptiv UP 没有实现 CP0 的第 29 号寄存器 TagHi，可能因为这个软核比较简单
	mtc0	zero, C0_TAGLO		# write C0_ITagLo
	mtc0	zero, C0_TAGHI		# write C0_ITagHi
	# 重申：mtc0 中，被赋值的 CP0 寄存器，是汇编语句的第二个 arg

	
# 遍历所有的 icache 行，并 clean（若 dirty 则写回）+ tag 置 invalid
_flush_next_icache:
	# 先执行若 dirty 则写回，然后执行 tag 置零 invalid
	cache	0x8, 0(t5) 			    # 8 是 010 00，从 CP0_TAGLO 写入 tag
	addi	t4, t4, -1				# Decrement set counter
	bnez	t4, _flush_next_icache
	add		t5, t5, t1				# Get next line address，从 KSeg0 开始向高地址处增长

_done_flush_icache:
    jr      ra		# 重申：ra（通用寄存器 31）代表当前 subroutine 的 return addr，相当于 C++ return
    nop
END(_flush_icache)


/**************************************************************************************
**************************************************************************************/


LEAF(_flush_dcache) # 基本跟 icache 一致

	mfc0	t0, C0_CONFIG1		# read C0_Config1

	# Isolate D$ Line Size
	ext		t1, t0, 10, 3		# extract DL [12:10]
	
	# Skip ahead if No D$
	beq		t1, zero, _done_flush_dcache
	nop

	li		t1, 0x10			# Now have true D$ line size in bytes

	ext	    t2, t0, 13, 3		# extract DS [15:13]
	li		t3, 64
	sllv	t2, t3, t2 	        # D$ Sets per way

	# Config1DA == D$ Assoc - 1
	ext		t3, t0, 7, 3		# extract DA [9:7]
	addi	t3, t3, 1
	mul		t4, t3, t2		# Get total number of sets

	lui	    t5, 0x8000        # Get a KSeg0 address for cacheops

	# Clear TagLo/TagHi registers
	mtc0	zero, C0_TAGLO       # write C0_TagLo
	mtc0	zero, C0_TAGHI	   # write C0_TagHi
	# write C0_DTagHi C0_DTagLo, 这两个寄存器 microAptiv UP 大概也没实现吧

	move	a3, a0

_flush_next_dcache:
	# Index Store Tag Cache Op
	# Will invalidate the tag entry, clear the lock bit, and clear the LRF bit
    cache	0x9, 0(t5)			    # DCIndexStTag, 9 是 01001
	addi	t4, t4, -1				# Decrement set counter
	bne		t4, zero, _flush_next_dcache
	add		t5, t5, t1				# Get next line address

_done_flush_dcache:
    jr      ra
    nop
END(_flush_dcache)



LEAF(change_k0_cca)
	# 这个函数用于：
	# 当处在 kernel mode 时，改变 kseg0 的 cache coherency attribute (CCA) 一致性，置 kseg0 为 cacheable

	# 这段代码抄的另一个 pdf 文件，大意是把 CP0_CONFIG 的末 3 位置为 011
	# 表示 cacheable, noncoherent, write-back, write allocate

	# NOTE! This code must be executed in KSEG1 (not KSGE0 uncached)
    # Set CCA for kseg0 to cacheable
	mfc0	v0, C0_CONFIG     	# read C0_Config
    li		v1, 3             	# insert K0
	ins		v0, v1, 0, 3		# insert K0 field
	mtc0	v0, C0_CONFIG       # write C0_Config
	jr.hb   ra
	nop

END(change_k0_cca)