m4_dnl Found on the web.  Written by Bastiaan Stougie, October 2003
m4_dnl Modified by Alberto Ros and Christos Sakalis, 2015

m4_divert(-1)
m4_define(NEWPROC,) m4_dnl

m4_dnl Empty ROI markers
m4_define(SPLASH3_ROI_BEGIN, `')
m4_define(SPLASH3_ROI_END, `')

m4_define(SWARM_WORKER_ROI_BEGIN, `zsim_worker_roi_begin()')
m4_define(SWARM_WORKER_ROI_END, `zsim_worker_roi_end()')

m4_dnl Region markers
m4_define(_NOTE_START_LOCK, `')
m4_define(_NOTE_END_LOCK, `')
m4_define(_NOTE_START_UNLOCK, `')
m4_define(_NOTE_END_UNLOCK, `')
m4_define(_NOTE_START_BARRIER, `')
m4_define(_NOTE_END_BARRIER, `')
m4_define(_NOTE_START_ATOMIC, `')
m4_define(_NOTE_END_ATOMIC, `')
m4_define(_NOTE_START_CMPXCHG, `')
m4_define(_NOTE_END_CMPXCHG, `')
m4_define(_NOTE_START_SEM_WAIT, `')
m4_define(_NOTE_END_SEM_WAIT, `')
m4_define(_NOTE_START_SEM_POST, `')
m4_define(_NOTE_END_SEM_POST, `')
m4_define(_NOTE_START_WAIT, `')
m4_define(_NOTE_END_WAIT, `')
m4_define(_NOTE_START_SIGNAL, `')
m4_define(_NOTE_END_SIGNAL, `')
m4_define(_NOTE_START_BDCAST, `')
m4_define(_NOTE_END_BDCAST, `')

m4_define(FETCH_ADD, `({_NOTE_START_ATOMIC(); uint64_t ___x =atomic_fetch_add(&($1), $2); _NOTE_END_ATOMIC(); ___x;});')
m4_define(FETCH_SUB, `({_NOTE_START_ATOMIC(); uint64_t ___x =atomic_fetch_sub(&($1), $2); _NOTE_END_ATOMIC(); ___x;});')
m4_define(STORE,`atomic_store(&($1), $2)')
m4_define(LOAD,`atomic_load(&($1))')
m4_define(CAS, `({_NOTE_START_CMPXCHG(); _Bool ___b = atomic_compare_exchange_weak(&($1), &($2), $3); _NOTE_END_CMPXCHG(); ___b;})')

m4_define(_CAS, `({_Bool ___b = atomic_compare_exchange_weak(($1), &($2), $3); ___b;})') m4_dnl Only intended for internal use
m4_define(FETCH_ADD_DOUBLE, `({
  _NOTE_START_CMPXCHG(); 
  double ___oldValue;
  double ___newValue;
  do {
    ___oldValue = *($1);
    ___newValue = ___oldValue + $2;
  } while (!_CAS($1, ___oldValue, ___newValue));
  _NOTE_END_CMPXCHG(); 
  ___oldValue;});')

m4_define(ABARDEF, `unsigned __count__; volatile int __sense__=1; __thread int __local_sense__=1;')

m4_define(ABAREXTERN,`
	extern unsigned __count__;
	extern volatile int __sense__;
	extern __thread int __local_sense__;
')

m4_define(BARRIER,
  m4_ifdef(`ATOMIC_BARRIERS',
`{
_NOTE_START_BARRIER();
__local_sense__ = !__local_sense__;
if (atomic_fetch_sub(&(__count__), 1) == 1) {
	__count__ = $2;
	__sense__ = __local_sense__;
} else {
	do {} while (__sense__ != __local_sense__);
}
_NOTE_END_BARRIER();
}'
,
`{
_NOTE_START_BARRIER();
pthread_mutex_lock(&(($1).bar_mutex));
($1).bar_teller++;
if (($1).bar_teller == ($2)) {
	($1).bar_teller = 0;
	pthread_cond_broadcast(&(($1).bar_cond));
} else {
	pthread_cond_wait(&(($1).bar_cond), &(($1).bar_mutex));
}
pthread_mutex_unlock(&(($1).bar_mutex));
_NOTE_END_BARRIER();}
'))

m4_define(BARDEC,
	m4_ifdef(`ATOMIC_BARRIERS',
	`',	
	`struct { pthread_mutex_t bar_mutex; pthread_cond_t bar_cond; unsigned bar_teller; } $1;')
)

m4_define(BARINIT,
  m4_ifdef(`ATOMIC_BARRIERS',
`__count__=$2;'
,
`{
	pthread_mutex_init(&(($1).bar_mutex), NULL);
	pthread_cond_init(&(($1).bar_cond), NULL);
	($1).bar_teller=0;
}'))

m4_define(BAREXTERN,
  m4_ifdef(`ATOMIC_BARRIERS',
`
	extern unsigned __count__;
	extern volatile int __sense__;
	extern __thread int __local_sense__;
'
, `'))

m4_define(LOCKDEC, m4_ifdef(`SIMPLE_TTAS',
	`Lock $1;',
	`pthread_mutex_t $1;'))
m4_define(LOCKINIT, m4_ifdef(`SIMPLE_TTAS',
	`{sw_lock_init_p(&($1),NULL); printf("Using TTAS for lock $1\n");}',
	`{pthread_mutexattr_t attr;
		pthread_mutexattr_init(&attr);
		pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ADAPTIVE_NP);
		($1).__data.__spins = 10000;
		pthread_mutex_init(&($1), &attr);
		($1).__data.__spins = 10000;
		printf("Using pmutex (adaptive) for lock $1\n"); }'))
m4_dnl `{pthread_mutex_init(&($1),NULL); printf("Using pmutex (normal) for lock $1\n");}'))
m4_define(LOCK, m4_ifdef(`SIMPLE_TTAS',
	`{_NOTE_START_LOCK(); sw_lock_aquire(&($1)); _NOTE_END_LOCK();}',
	`{_NOTE_START_LOCK(); pthread_mutex_lock(&($1)); _NOTE_END_LOCK();}'))
m4_define(UNLOCK, m4_ifdef(`SIMPLE_TTAS',
	`{_NOTE_START_UNLOCK(); sw_lock_release(&($1)); _NOTE_END_UNLOCK();}',
	`{_NOTE_START_UNLOCK(); pthread_mutex_unlock(&($1)); _NOTE_END_UNLOCK();}'))

m4_define(ALOCKDEC, m4_ifdef(`SIMPLE_TTAS',
	`Lock ($1)[$2];',
	`pthread_mutex_t ($1)[$2];'))
m4_define(ALOCKINIT, m4_ifdef(`SIMPLE_TTAS',
	`{ printf("Using TTAS for lock $1[]\n");
		int i; 
		for(i = 0; i < ($2); i++)
			sw_lock_init_p(&(($1)[i]), NULL); }',
	`{ int i; for(i = 0; i < ($2); i++) {
			pthread_mutexattr_t attr;
			pthread_mutexattr_init(&attr);
			pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ADAPTIVE_NP);
			(($1)[i]).__data.__spins = 10000;
			pthread_mutex_init(&(($1)[i]), &attr);
			(($1)[i]).__data.__spins = 10000;
		}
		printf("Using pmutex (adaptive) for lock $1[]\n"); }'))
	`{ int i; for(i = 0; i < ($2); i++)
			pthread_mutex_init(&(($1)[i]), NULL);
		printf("Using pmutex (normal) for lock $1[]\n"); }'))
m4_define(ALOCK, m4_ifdef(`SIMPLE_TTAS',
	`{_NOTE_START_LOCK(); sw_lock_aquire(&(($1)[($2)])); _NOTE_END_LOCK();}',
	`{_NOTE_START_LOCK(); pthread_mutex_lock(&(($1)[($2)])); _NOTE_END_LOCK();}'))
m4_define(AGETL, m4_ifdef(`SIMPLE_TTAS',
	`(($1)[$2])',
	`(($1)[$2])'))
m4_define(AULOCK, m4_ifdef(`SIMPLE_TTAS',
	`{_NOTE_START_UNLOCK(); sw_lock_release(&(($1)[($2)])); _NOTE_END_UNLOCK();}',
	`{_NOTE_START_UNLOCK(); pthread_mutex_unlock(&(($1)[($2)])); _NOTE_END_UNLOCK();}'))

m4_define(PAUSEDEC, `sem_t $1;')
m4_define(PAUSEINIT, `{sem_init(&($1),0,0);}')
m4_define(CLEARPAUSE, `{;}')
m4_define(SETPAUSE, `{_NOTE_START_SEM_POST(); sem_post(&($1)); _NOTE_END_SEM_POST();}')
m4_define(WAITPAUSE, `{_NOTE_START_SEM_WAIT(); sem_wait(&($1)); _NOTE_END_SEM_WAIT();}')

m4_define(CONDVARDEC, `pthread_cond_t $1;')
m4_define(CONDVARINIT, `pthread_cond_init(&($1), NULL);')
m4_define(CONDVARWAIT,`{ _NOTE_START_WAIT(); pthread_cond_wait(&($1), &($2)); _NOTE_END_WAIT(); }')
m4_define(CONDVARSIGNAL,`{ _NOTE_START_SIGNAL(); pthread_cond_signal(&($1)); _NOTE_END_SIGNAL(); }')
m4_define(CONDVARBCAST,`{ _NOTE_START_BDCAST(); pthread_cond_broadcast(&($1)); _NOTE_END_BDCAST(); }')

m4_define(RELEASE_FENCE, `{ atomic_thread_fence(memory_order_release);}')
m4_define(ACQUIRE_FENCE, `{ atomic_thread_fence(memory_order_acquire);}')
m4_define(FULL_FENCE,    `{ atomic_thread_fence(memory_order_seq_cst);}')

m4_define(BIND,
  m4_ifdef(`BIND_CORES', `{
    cpu_set_t cpuset;
    const pthread_t pid = $2;
    cpu_set_t _____cpuset;
    CPU_ZERO(&_____cpuset);
    CPU_SET($1, &_____cpuset);
    const int set_result = pthread_setaffinity_np(pid, sizeof(cpu_set_t), &_____cpuset);
    assert(set_result == 0);
    }',
  m4_ifdef(`BIND_THREADS', `{
    cpu_set_t cpuset;
    const pthread_t pid = $2;
    cpu_set_t _____cpuset;
    CPU_ZERO(&_____cpuset);
    CPU_SET($1/2+($1%2)*sysconf(_SC_NPROCESSORS_CONF)/2, &_____cpuset);
    const int set_result = pthread_setaffinity_np(pid, sizeof(cpu_set_t), &_____cpuset);
    assert(set_result == 0);
    }')
  )
)

m4_define(CREATE,
`{
	long	i, Error;

	assert(__threads__<__MAX_THREADS__);
	pthread_mutex_lock(&__intern__);
	for (i = 0; i < ($2) - 1; i++) {
		BIND(i, __tid__[__threads__-1])
		Error = pthread_create(&__tid__[__threads__++], NULL, (void * (*)(void *))($1), NULL);
		if (Error != 0) {
			printf("Error in pthread_create().\n");
			exit(-1);
		}
	}
	pthread_mutex_unlock(&__intern__);
	BIND(i, __tid__[__threads__-1])

	$1();
}')
m4_define(WAIT_FOR_END, `{int aantal=$1; while (aantal--) pthread_join(__tid__[aantal], NULL);}')

m4_define(MAIN_INITENV, `{__tid__[__threads__++]=pthread_self();}')
m4_define(MAIN_END, `{exit(0);}')

m4_define(INCLUDES,`
#include <stdlib.h>
#include <semaphore.h>
#include <assert.h>
#if __STDC_VERSION__ >= 201112L
#include <stdatomic.h>
#endif
#include <stdint.h>

#include <pthread.h>
#include <sched.h>
#include <unistd.h>

#include <stdio.h>
#include "/mnt/ceph/users/igi/splash4/swarm-runtime/include/swarm/worker_hooks.h"
#include "/mnt/ceph/users/igi/splash4/swarm-runtime/include/swarm/impl/simple_lock.h"

#define PAGE_SIZE 4096
#define __MAX_THREADS__ 256
')

m4_define(MAIN_ENV,`
INCLUDES
pthread_t __tid__[__MAX_THREADS__];
unsigned __threads__=0;
pthread_mutex_t __intern__;
ABARDEF
')

m4_define(EXTERN_ENV, `
INCLUDES
extern pthread_t __tid__[__MAX_THREADS__];
extern unsigned __threads__;
extern pthread_mutex_t __intern__;
BAREXTERN
')

m4_define(G_MALLOC, `({ void* mem = malloc($1); assert(mem); mem; });')
m4_define(NU_MALLOC, `({ void* mem = malloc($1); assert(mem); mem; });')
m4_define(CLOCK, `{long time(); ($1) = time(0);}')
m4_divert(0)
