# override version in invocation of make
# ex. make VERSION=2
VERSION = 2

ARR_LEN_MULT = 1
ARR_LEN_DIV = 1

target = instrPerInvx

OBJS = instrPerInvx.o

SRC = instrPerInvx.c

CC = gcc-9
CFLAGS += -I ../swarm-runtime
CFLAGS += -pthread
CFLAGS += -O3
CFLAGS += -DVERSION=$(VERSION)
CFLAGS += -DARR_LEN_MULT=$(ARR_LEN_MULT)
CFLAGS += -DARR_LEN_DIV=$(ARR_LEN_DIV)
LDFLAGS := -lm

all: $(target)

clean:
	rm -rf *.o $(target)

debug: CFLAGS += -g -Og
debug: $(target)

.PHONY: all clean debug

# $< is the first prerequisite
# $@ is the target

$(target): $(OBJS)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

$(OBJS): $(SRC)
	$(CC) -c $(CFLAGS) $< -o $@ $(EXTRA_FLAGS)


