#ifndef CONSTANT
#define CONSTANT 1

struct Constant {
	char *type;
	union {
		char* text;
		int integer;
		double real;
	} data;
};

#endif