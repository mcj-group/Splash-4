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

#include "../swarm-runtime/include/swarm/impl/simple_lock.h"
#include "../swarm-runtime/include/swarm/worker_hooks.h"

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>



#ifndef NTHREADS
#define NTHREADS 16
#endif
// #define WORK 1000000
#define WORK 1000
// #define WORK 3

// #define ALL_COUNTERS
// #define DETAILED_CYCLE_TIMING
// #define USE_PTHREAD_MUTEX
#define USE_SWARM_ROI

#define USE_ADAPTIVE_MUTEX


#ifndef USE_PTHREAD_MUTEX

#define LOCKDEC Lock
#define LOCKINIT(m) sw_lock_init_p(&m, NULL)
#define LOCK(m) sw_lock_aquire(&m)
#define UNLOCK(m) sw_lock_release(&m)


#else // if USE_PTHREAD_MUTEX

#define LOCKDEC pthread_mutex_t
#ifdef USE_ADAPTIVE_MUTEX
#define LOCKINIT(m) { \
	pthread_mutexattr_t attr; \
	pthread_mutexattr_init(&attr); \
	pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ADAPTIVE_NP); \
	m.__data.__spins = 10000; \
	pthread_mutex_init(&m, &attr); \
	m.__data.__spins = 10000; \
}
#else
#define LOCKINIT(m) pthread_mutex_init(&m, NULL)
#endif
#define LOCK(m) pthread_mutex_lock(&m)
#define UNLOCK(m) pthread_mutex_unlock(&m)

// https://github.com/lattera/glibc/blob/895ef79e04a953cac1493863bcae29ad85657ee1/nptl/pthreadP.h#L113-L114
#define PTHREAD_MUTEX_TYPE(m) \
  ((m)->__data.__kind & 127)

#endif

void whichMutex(LOCKDEC *m) {
#ifndef USE_PTHREAD_MUTEX
	printf("Type: %s\n", "In-House TTAS");
#else // if USE_PTHREAD_MUTEX
	int kind = m->__data.__kind;
	int type = PTHREAD_MUTEX_TYPE(m);
	printf("Mutex kind: 0x%x, type: 0x%x\n", kind, type);

	// ! todo try ADAPTIVE TYPE
	// change spins variable to 100

	// Test old mutex vs adaptive mutex - is there more traffic?

	switch(type) {
		case PTHREAD_MUTEX_TIMED_NP:
			printf("Type: %s\n", "PTHREAD_MUTEX_TIMED_NP");
			break;
		case PTHREAD_MUTEX_RECURSIVE_NP:
			printf("Type: %s\n", "PTHREAD_MUTEX_RECURSIVE_NP");
			break;
		case PTHREAD_MUTEX_ERRORCHECK_NP:
			printf("Type: %s\n", "PTHREAD_MUTEX_ERRORCHECK_NP");
			break;
		case PTHREAD_MUTEX_ADAPTIVE_NP:
			printf("Type: %s\n", "PTHREAD_MUTEX_ADAPTIVE_NP");
			break;
		default:
			printf("Unknown type\n");	
  
	}
#endif // USE_PTHREAD_MUTEX
}

typedef _Atomic(uint32_t) atomic_uint32_t;

LOCKDEC mutex;
volatile char buffer1[60];
atomic_uint32_t acnt;
volatile char buffer2[60];
uint32_t mcnt;
volatile char buffer3[60];
uint32_t cnt;
volatile char buffer4[60];
uint32_t mcnt_arr[16*NTHREADS];

typedef struct Args_t {
	int id;
} Args;

void* worker(void *args_vp) {
#ifdef USE_SWARM_ROI
	zsim_worker_roi_begin();
#endif
#ifdef DETAILED_CYCLE_TIMING
	uint64_t time_size = 0, time[10000];
	time[time_size++] = sim_get_cycle();
#endif
	
	Args* args_p = (Args*) args_vp;
	unsigned id = args_p->id;
	
    for(int n = 0; n < WORK; ++n) {
		LOCK(mutex);
        mcnt_arr[id*16]++;
		// mcnt++;
		UNLOCK(mutex);
#ifdef DETAILED_CYCLE_TIMING
		time[time_size++] = sim_get_cycle();
#endif
    }
#ifdef ALL_COUNTERS
	sim_barrier();
	if(id == 0) info("Done mutex count");
	sim_barrier();
	for(int n = 0; n < WORK; ++n) {
        acnt++;
    }
	sim_barrier();
	if(id == 0) info("Done atomic count");
	sim_barrier();
	for(int n = 0; n < WORK; ++n) {
        cnt++;
    }
	sim_barrier();
	if(id == 0) info("Done unsafe count");
#endif
#ifdef USE_SWARM_ROI
	zsim_worker_roi_end();
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



int main(int argc, char **argv) {
	if(argc != 2) {
		printf("%s <nthreads>\n", argv[0]);
		exit(-1);
	}
	
	int nthreads = atoi(argv[1]);
	printf("nthreads %d\n", nthreads);
	assert(nthreads <= NTHREADS);
	
	LOCKINIT(mutex);

	whichMutex(&mutex);

    pthread_t thr[NTHREADS-1];
	Args args[NTHREADS];
    for(int n = 0; n < nthreads-1; ++n) {
		args[n].id = n;
        pthread_create(&thr[n], NULL, worker, (void*)(&args[n]));
	}
	args[nthreads-1].id = nthreads-1;
	worker((void*)(&args[nthreads-1]));
    for(int n = 0; n < nthreads-1; ++n)
        pthread_join(thr[n], NULL);
 
	// printf("The mutex counter is  %u\n", mcnt);
	printf("The mutex counter array is  [\n\t");
	for(int i = 0; i < NTHREADS; i++) {
		if(i > 0 && ((i&7) == 0)) printf("\n\t");
		printf("%u, ", mcnt_arr[i*16]);
	}
	printf("]\n");
#ifdef ALL_COUNTERS
    printf("The atomic counter is %u\n", acnt);
	printf("The unsafe counter is %u\n", cnt);
#endif
}