#ifndef CONSTANT
#define CONSTANT 1

struct Constant {
	int global;
	char *symbol;
	char *kind;
	char *type;
	union {
		char* text;
		int integer;
		float real;
	} data;
};

#endif