# Projet {{NAME}} : make | make run [ARGS="…"] | make debug | make clean
CC      = gcc
CFLAGS  = -Wall -Wextra -g -std=c17 -Iinclude -MMD -MP
LDFLAGS =
LDLIBS  = -lm

SRC = $(wildcard src/*.c)
OBJ = $(SRC:src/%.c=build/%.o)
BIN = build/{{NAME}}

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $(LDFLAGS) $^ -o $@ $(LDLIBS)

build/%.o: src/%.c | build
	$(CC) $(CFLAGS) -c $< -o $@

build:
	mkdir -p build

# lancer le programme (arguments : make run ARGS="a b")
run: all
	./$(BIN) $(ARGS)

# déboguer dans gdb
debug: all
	gdb -q --args ./$(BIN) $(ARGS)

clean:
	rm -rf build

-include $(OBJ:.o=.d)

.PHONY: all run debug clean
