SRC = ./src
BUILD = ./build
BIN = ./bin
TARGET = parser
OBJECT = lex.yy.c y.tab.c y.output y.tab.h
CC = gcc
CCFLAGS = -g
LEX = flex
YACC = yacc
YACCFLAG = -d -v
LIBS = -lfl -ly

$(BIN)/$(TARGET): $(BUILD)/y.tab.c $(BUILD)/lex.yy.c
	$(CC) $^ $(CCFLAGS) $(LIBS) -I $(SRC) -o $@

$(BUILD)/y.tab.c: $(SRC)/yacc.y
	$(YACC) $(YACCFLAG) $< -o $@

$(BUILD)/lex.yy.c: $(SRC)/lex.l
	$(LEX) -o $@ $<

clean:
	rm $(BIN)/* $(BUILD)/*

# parser: y.tab.c lex.yy.c
# 	gcc -g lex.yy.c y.tab.c -ly -lfl -o parser

# lex.yy.c: lex.l y.tab.h
# 	flex lex.l

# y.tab.c: yacc.y
# 	yacc -d -v yacc.y

# clean:
# 	rm parser lex.yy.c y.tab.c y.output y.tab.h
