/** $lic$
 * Copyright (C) 2014-2020 by Massachusetts Institute of Technology
 *
 * This file is distributed under the University of Illinois Open Source
 * License. See LICENSE.TXT for details.
 *
 * If you use this software in your research, we request that you send us a
 * citation of your work, and reference the Swarm MICRO 2015 paper ("A Scalable
 * Architecture for Ordered Parallelism", Jeffrey et al., MICRO-48, December
 * 2015) as the source of the simulator, or reference the T4 ISCA 2020 paper
 * ("T4: Compiling Sequential Code for Effective Speculative Parallelization in
 * Hardware", Ying et al., ISCA-47, June 2020) as the source of the compiler.
 *
 * This file is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.
 */

// This microbenchmark tests the simple_lock implemented by swarm-runtime
// Adapted from https://en.cppreference.com/w/c/language/atomic

// #include "../swarm-runtime/include/swarm/impl/simple_lock.h"
#include "../swarm-runtime/include/swarm/worker_hooks.h"

#include <assert.h>
#include <emmintrin.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#define MAX_NTHREADS 576

#ifndef DEFAULT_NTHREADS
#define DEFAULT_NTHREADS 16
#endif
#ifndef DELAY
#define DELAY 5
#endif
#ifndef WORK
// #define WORK 1000000
#define WORK 1000
// #define WORK 3
#endif


#ifndef VERSION
#define VERSION 2
#endif // VERSION

// #define DETAILED_CYCLE_TIMING
#define USE_SWARM_ROI

#define ALIGN_CACHE_LINE 64
#define I32_PER_CACHE_LINE (ALIGN_CACHE_LINE >> 2)

#define MAX_ARRAY_LEN (ALIGN_CACHE_LINE*MAX_NTHREADS)

typedef _Atomic(uint32_t) atomic_uint32_t;

_Alignas(ALIGN_CACHE_LINE) volatile uint32_t global_delay_iters;

_Alignas(ALIGN_CACHE_LINE) uint32_t global_array_len = MAX_ARRAY_LEN;

// volatile char buffer1[60];
_Alignas(ALIGN_CACHE_LINE) atomic_uint32_t acnt;
// igi: WHY IS THIS VOLATILE?
_Alignas(ALIGN_CACHE_LINE) volatile uint32_t mcnt;
_Alignas(ALIGN_CACHE_LINE) uint32_t cnt;
_Alignas(ALIGN_CACHE_LINE) uint32_t mcnt_arr[I32_PER_CACHE_LINE*MAX_ARRAY_LEN];

typedef struct Args_t {
	int id;
	int work;
	int delay_iters;
} Args;

__attribute__((always_inline))
static inline void delay() {
	for(int i = 1; i < global_delay_iters; i++)
		// _mm_pause();
		;
}

// static inline void delay(uint32_t delay_iters) {
// 	for(int i = 0; i < delay_iters; i++)
// 		_mm_pause();
// }

void* worker(void *args_vp) {
#ifdef DETAILED_CYCLE_TIMING
	uint64_t time_size = 0, time[10000];
	time[time_size++] = sim_get_cycle();
#endif
	
	Args* args_p = (Args*) args_vp;
	const uint32_t id = args_p->id;
	const uint32_t work = args_p->work;
	const uint32_t delay_iters = args_p->delay_iters;
	uint64_t rand;

#if (VERSION == 3)
	uint32_t *index = malloc(sizeof(uint32_t) * work);
	for(int n = 0; n < work; ++n) {
		sim_rdrand(&rand);
		index[n] = (rand % global_array_len) * I32_PER_CACHE_LINE;
	}
#endif

#ifdef USE_SWARM_ROI
	zsim_worker_roi_begin();
#endif

    for(int n = 0; n < work; ++n) {
		// version 1
#if (VERSION == 1)
		if(mcnt < MAX_NTHREADS)
			mcnt = id;
		// version 2
#elif (VERSION == 2)
		sim_rdrand(&rand);
		rand = (rand % global_array_len) * I32_PER_CACHE_LINE;

		// char buf[1024];
		// snprintf(buf, 1024, "\nThread %d, RNG: %ld", id, rand / I32_PER_CACHE_LINE);
		// info(buf);
		
		if(mcnt_arr[rand] < MAX_NTHREADS)
			mcnt_arr[rand] = id;

#elif (VERSION == 3)
		if(mcnt_arr[index[n]] < MAX_NTHREADS)
			mcnt_arr[index[n]] = id;

// #elif (VERSION == 3)
		// version 3
		// __atomic_exchange_n(&mcnt, id, __ATOMIC_ACQ_REL);
		
		// acnt += id;
		// printf("[%lu] W [%u] %u\n", sim_get_cycle(), id, n);
		// delay(delay_iters);
#else
		#error "Version VERSION is invalid"
#endif // VERSION == ?
		delay();
		
#ifdef DETAILED_CYCLE_TIMING
		time[time_size++] = sim_get_cycle();
#endif
    }
#ifdef USE_SWARM_ROI
	zsim_worker_roi_end();
#endif
#if (VERSION == 3)
	free(index);
#endif
#ifdef DETAILED_CYCLE_TIMING
	LOCK(mutex);
	char buf[1024];
	snprintf(buf, 1024, "\nStart: Thread %d", id);
	info(buf);
	for(int i = 0; i < time_size; i++) {
		snprintf(buf, 1024, "Thread %2d, time[%5d]: %8ld, since i-1: %8ld, since time[0]: %8ld",
				id, i, time[i], (i==0)?0:(time[i]-time[i-1]), time[i]-time[0]);
		info(buf);
	}
	UNLOCK(mutex);
#endif
    return 0;
}

void usage(int argc, char **argv) {
	printf("%s <nthreads> <work> <delay_iters>\n", argv[0]);
	printf("Use -1 for default value");
	exit(-1);
}

#ifndef ARR_LEN_MULT
#define ARR_LEN_MULT 1
#endif
#ifndef ARR_LEN_DIV
#define ARR_LEN_DIV 32
#endif

int main(int argc, char **argv) {
	if(argc < 2 || argc > 4)
		usage(argc, argv);
	for(int i = 0; i < argc; i++)
		if(strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)
			usage(argc, argv);

	int nthreads = -1, work = -1, delay_iters = -1;
	if(argc >= 2)
		nthreads = atoi(argv[1]);
	if(argc >= 3)
		work = atoi(argv[2]);
	if(argc >= 4)
		delay_iters = atoi(argv[3]);
	if(nthreads < 0) nthreads = DEFAULT_NTHREADS;
	if(work < 0) work = WORK;
	if(delay_iters < 0) delay_iters = DELAY;

	global_array_len = ARR_LEN_MULT * nthreads / ARR_LEN_DIV;
	if(global_array_len <= 0) global_array_len = 1;
	
	printf("Version = %d\n", VERSION);
	printf("nthreads = %d\n", nthreads);
	assert(nthreads <= MAX_NTHREADS);
	printf("work = %d\n", work);
	printf("delay_iters = %d\n", delay_iters);
	global_delay_iters = delay_iters;
#if (VERSION == 2 || VERSION == 3)
	printf("array_len = %d\n", global_array_len);
	assert(global_array_len < MAX_ARRAY_LEN);
#endif // VERSION == ?
	fflush(NULL);

	acnt = 0; mcnt = 0; cnt = 0;
	for(int i = 0; i < I32_PER_CACHE_LINE*global_array_len; i++)
		mcnt_arr[i] = 0;
	
    pthread_t thr[MAX_NTHREADS-1];
	Args args[MAX_NTHREADS];
	int n = 0;
    for(n = 0; n < nthreads-1; ++n) {
		args[n].id = n;
		args[n].work = work;
		args[n].delay_iters = delay_iters;
        pthread_create(&thr[n], NULL, worker, (void*)(&args[n]));
	}
	n = nthreads - 1;
	args[n].id = n;
	args[n].work = work;
	args[n].delay_iters = delay_iters;
	worker((void*)(&args[n]));

    for(n = 0; n < nthreads-1; ++n)
        pthread_join(thr[n], NULL);
 
	// // printf("The mutex counter is  %u\n", mcnt);
	// printf("The mutex counter array is  [\n\t");
	// for(int i = 0; i < nthreads; i++) {
	// 	if(i > 0 && ((i&7) == 0)) printf("\n\t");
	// 	printf("%u, ", mcnt_arr[i*16]);
	// }
	// printf("]\n");
}
