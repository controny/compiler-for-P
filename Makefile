parser: y.tab.c lex.yy.c
	gcc -g lex.yy.c y.tab.c -ly -lfl -o parser

lex.yy.c: lex.l y.tab.h
	flex lex.l

y.tab.c: yacc.y
	yacc -d -v yacc.y

clean:
	rm parser lex.yy.c y.tab.c y.output y.tab.h