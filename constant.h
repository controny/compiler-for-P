#ifndef CONSTANT
#define CONSTANT 1

struct Constant {
	char *symbol;
	char *kind;
	char *type;
	union {
		char* text;
		int integer;
		double real;
	} data;
};

#endif