CC     = gcc
CFLAGS = -Wall -Wextra -g
LDLIBS = -lm

SRC = $(wildcard *.c)
OBJ = $(SRC:.c=.o)
BIN = {{NAME}}

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $^ -o $@ $(LDLIBS)

run: all
	./$(BIN)

clean:
	rm -f $(BIN) $(OBJ)

.PHONY: all run clean
