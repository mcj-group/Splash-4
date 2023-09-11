
# p: pthread_mutex_t, t: simple_lock ttas
target_p = pmutex_test
target_t = ttas_test
targets = $(target_p) $(target_t)

OBJS_p = test_p.o
OBJS_t = test_t.o

SRC = test.c

EXTRA_FLAGS_p = -D USE_PTHREAD_MUTEX
EXTRA_FLAGS_t = 

CC = gcc-9
CFLAGS += -I ../swarm-runtime
CFLAGS += -pthread
CFLAGS += -O3
LDFLAGS := -lm

all: $(targets)

pmutex: $(target_p)

ttas: $(target_t)

clean:
	rm -rf *.o $(targets)

# $< is the first prerequisite
# $@ is the target

$(target_p): $(OBJS_p)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

$(OBJS_p): $(SRC)
	$(CC) -c $(CFLAGS) $< -o $@ $(EXTRA_FLAGS_p)

$(target_t): $(OBJS_t)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

$(OBJS_t): $(SRC)
	$(CC) -c $(CFLAGS) $< -o $@ $(EXTRA_FLAGS_t)


