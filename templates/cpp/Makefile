# Projet {{NAME}} : make | make run [ARGS="…"] | make debug | make clean
CXX      = g++
CXXFLAGS = -Wall -Wextra -g -std=c++17 -Iinclude -MMD -MP
LDFLAGS  =
LDLIBS   =

SRC = $(wildcard src/*.cpp)
OBJ = $(SRC:src/%.cpp=build/%.o)
BIN = build/{{NAME}}

all: $(BIN)

$(BIN): $(OBJ)
	$(CXX) $(LDFLAGS) $^ -o $@ $(LDLIBS)

build/%.o: src/%.cpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

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
