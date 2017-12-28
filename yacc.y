%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "constant.h"

#define DEBUG1 0
#define DEBUG2 0
#define MAX_TABLE_NUMBER 512
#define MAX_TABLE_SIZE 512

extern int linenum;             /* declared in lex.l */
extern FILE *yyin;              /* declared by lex */
extern char *yytext;            /* declared by lex */
extern char buf[256];           /* declared in lex.l */
extern int Opt_D;

struct Attrs {
	char* name;
	char* kind;
	int level;
	char* type;
	char* attribute;
};

char* file_name;
/* Initialize a stack whose elements is symbol tables */
struct Attrs stack[MAX_TABLE_NUMBER][MAX_TABLE_SIZE];
int top;		/* The top of the stack */
int cur_index[MAX_TABLE_NUMBER];	/* The current index of a table */
char* iter_stack[MAX_TABLE_SIZE];	/* A stack to record iterative variables in for loop */
int iter_top;
int has_error;
/* To handle adding function parameters and variable declaration */
char* var_symbols[50];
char* var_types[50];
int cur_var_index, last_var_index;
/* Indicate the current function type to check return type 
and empty string means not in a function scope */
char* cur_func_type;

/* File pointer to java assembly code file */
FILE* code_fp;

char* jvm_var_stack[200];
int next_var_num = 1;

void add_table();
void add_symbol();
void add_kind_and_type();
void add_var_type();
void add_attribute();
void add_iter_variable();
void iter_stack_pop();
int check_normal_redeclaration();
int check_for_loop_redeclaration();
void dumpsymbol();
struct Constant get_value_of_identifier();
int check_operands_be_integer_or_real();
char* get_type_of_arithmetic_operator();
char* get_type_of_relational_operator();
char* get_type_of_boolean_operator();
void check_conditional_expression();
int is_array_type();
int get_splited_parameters();
int parameters_match();
int get_local_var_num();
char* get_jvm_type_descriptor();
void write_print_code();
void write_assembly_code();
%}

%token SEMICOLON COLON COMMA RPAREN LPAREN LSBRACKET RSBRACKET 
KVAR KBEGIN KDEF KDO KELSE KEND KTO KOF
KFOR KIF KPRINT KREAD KTHEN KRET KWHILE
PLUS MINUS MULTIP DIVIDE MOD ASSIGN LESS LESSEQ NOTEQ GREQ GREATER EQ AND OR NOT
%token <text> IDENT KINTEGER KREAL KSTRING KBOOL KARRAY
%type <text> scalar_type type return_type programname arguments argument function
%token <constant> PINT ZERO REAL STRING KTRUE KFALSE
%type <constant> literal_constant integer_literal expressions expression expression_component boolean_expression
variable_reference function_invocation array_reference
%type <count> index_references

%right ASSIGN
%left AND OR %right NOT
%nonassoc LESS LESSEQ NOTEQ GREQ GREATER EQ
%left PLUS MINUS
%left MULTIP DIVIDE MOD

%union {
	struct Constant constant;
	char* text;
	int count;
}
%%

program	:
	programname SEMICOLON
		{
			if (strcmp($1, file_name))
				yyerror("program beginning ID inconsist with file name");
			add_symbol($1);
			add_kind_and_type("program", "void");
			char assembly[100] = "; ";
			strcat( strcat(assembly, file_name), ".j\n.class public " );
			strcat( strcat(assembly, file_name), "\n.super java/lang/Object\n.field public static _sc Ljava/util/Scanner;\n" );
			write_assembly_code(assembly);
		}
	programbody
	KEND IDENT
		{
			if (strcmp($1, $6))
				yyerror("program end ID inconsist with the beginning ID");
			if (strcmp($1, file_name))
				yyerror("program end ID inconsist with file name");
			dumpsymbol();
		}

programbody :
	declarations functions compound

function :
	IDENT LPAREN arguments RPAREN return_type
		{
			if (strcmp($5, "integer")
				&& strcmp($5, "real")
				&& strcmp($5, "string")
				&& strcmp($5, "bool")
				&& strcmp($5, "void")) {
				yyerror("a function cannot return an array type");
				$<text>$ = "error";
			} else {
				for (int i = 0; i < cur_var_index; i++)
					if (!strcmp(var_types[i], "error")) {
						$<text>$ = "error";
						break;
					}
			}
			if (strcmp($<text>$, "error"))
				add_symbol($1);
			add_table();
			for (int i = 0; i < cur_var_index; i++) {
				if (strcmp(var_types[i], "error")) {
					add_symbol(var_symbols[i]);
					add_kind_and_type("parameter", var_types[i]);
				}
			}
			if (strcmp($<text>$, "error")) {
				/* Calculate attributes of the funciton */
				char attributes[100] = "";
				for (int i = 0; i < cur_index[top]; i++)
				{
					if (!strcmp(stack[top][i].kind, "parameter"))
					{
						if (!strcmp(attributes, ""))
							strcpy(attributes, stack[top][i].type);
						else
							strcat( strcat(attributes, ", "),  stack[top][i].type);
					}
				}
				$<text>$ = strdup(attributes);
			}
			cur_var_index = last_var_index = 0;
			cur_func_type = strdup($5);
		}
	SEMICOLON KBEGIN declarations statements KEND KEND IDENT
		{ 
			dumpsymbol();
			if (strcmp($1, $13)) {
				yyerror("function end ID inconsist with the beginning ID");
			}
			if (strcmp($<text>6, "error")) {
				add_kind_and_type("function", $5);
				add_attribute($<text>6);
			}
			cur_func_type = NULL;
		}

declaration :
	KVAR identifier_list COLON type SEMICOLON
		{
			for (int i = 0; i < cur_var_index; i++) {
				if (strcmp($4, "error")) {
					add_symbol(var_symbols[i]);
					add_kind_and_type("variable", $4);
				}
				if (!top) {
					// Add global variables in assembly code
					char assembly[50];
					char* type_descriptor = get_jvm_type_descriptor($4);
					sprintf(assembly, ".field public static %s %s", var_symbols[i], type_descriptor);
					write_assembly_code(assembly);
				} else {
					jvm_var_stack[next_var_num++] = strdup(var_symbols[i]);
				}
			}
			cur_var_index = 0;
		}
	| KVAR identifier_list COLON literal_constant SEMICOLON
		{
			for (int i = 0; i < cur_var_index; i++) {
				add_symbol(var_symbols[i]);
				add_kind_and_type("constant", $4.type);
				char assembly[50];
				if (!top) {
					// Add global variables in assembly code
					char* type_descriptor = get_jvm_type_descriptor($4.type);
					sprintf(assembly, ".field public static %s %s", var_symbols[i], type_descriptor);
					write_assembly_code(assembly);
					sprintf(assembly, "putstatic %s/%s %s", file_name, var_symbols[i], type_descriptor);
					write_assembly_code(assembly);
				} else {
					jvm_var_stack[next_var_num++] = strdup(var_symbols[i]);
					sprintf(assembly, "istore %d", get_local_var_num(var_symbols[i]));
					write_assembly_code(assembly);
				}
			}
			cur_var_index = 0;
			char attr[100];
			if (!strcmp($4.type, "integer"))
				sprintf(attr, "%d", $4.data.integer);
			else if (!strcmp($4.type, "real"))
				sprintf(attr, "%f", $4.data.real);
			else
				sprintf(attr, "%s", $4.data.text);
			if (DEBUG2)
				printf("------------Add attribute: %s\n", attr);
			add_attribute(attr);
		}

statement :
	compound | simple | conditional | while | for | return | procedure_call

functions :
	/* empty */
	| function functions

declarations :
	/* empty */
	| declaration declarations

statements :
	/* empty */
	| statement statements

compound :
	KBEGIN
		{
			if (!top) {
				write_assembly_code(".method public static main([Ljava/lang/String;)V\n\t.limit stack 15");
				// In the beginning of main block, create an instance of java.util.Scanner
				write_assembly_code("new java/util/Scanner\ndup\ngetstatic java/lang/System/in Ljava/io/InputStream;\ninvokespecial java/util/Scanner/<init>(Ljava/io/InputStream;)V");
				char assembly[100];
				sprintf(assembly, "putstatic %s/_sc Ljava/util/Scanner;", file_name);
				write_assembly_code(assembly);
			}
			add_table();
		}
	declarations statements KEND
		{
			dumpsymbol();
			if (!top)
				write_assembly_code("\treturn\n.end method");
		}

simple :
	variable_reference ASSIGN expression SEMICOLON
		{
			if ($1.kind && !strcmp($1.kind, "constant")) {
				char message[100] = "constant \'";
				strcat( strcat(message, $1.symbol), "\' cannot be assigned");
				yyerror(message);
			} else if ( strcmp($1.type, $3.type) && (strcmp($1.type, "real") || strcmp($3.type, "integer")) ) {
				char message[100] = "type mismatch, LHS= ";
				strcat( strcat( strcat(message, $1.type), ", RHS= "), $3.type);
				yyerror(message);
			} else if (is_array_type($1.type) || is_array_type($3.type)) {
				yyerror("array arithmetic is not allowed");
			}
			char assembly[50];
			if ($1.global) {
				sprintf(assembly, "putstatic %s/%s %s", file_name, $1.symbol, get_jvm_type_descriptor($1.type));
			} else {
				sprintf(assembly, "istore %d", get_local_var_num($1.symbol));
			}
			write_assembly_code(assembly);
		}
	| KPRINT
		{ write_assembly_code("getstatic java/lang/System/out Ljava/io/PrintStream;"); }
	variable_reference SEMICOLON
		{ write_print_code($3.type); }
	| KPRINT
		{ write_assembly_code("getstatic java/lang/System/out Ljava/io/PrintStream;"); }
	expression SEMICOLON
		{ write_print_code($3.type); }
	| KREAD variable_reference SEMICOLON
		{
			char* method_name;
			char* store = "istore";
			if (!strcmp($2.type, "integer"))
				method_name = "Int";
			else if (!strcmp($2.type, "boolean"))
				method_name = "Boolean";
			else {
				method_name = "Float";
				store = "fstore";
			}
			char assembly[100];
			sprintf(assembly,
				"getstatic %s/_sc Ljava/util/Scanner;\ninvokevirtual java/util/Scanner/next%s()%s\n%s %d",
				file_name, method_name, get_jvm_type_descriptor($2.type), store, get_local_var_num($2.symbol));
			write_assembly_code(assembly);
		}

conditional : 
	KIF expression KTHEN statements KELSE statements KEND KIF { check_conditional_expression($2); }
	| KIF expression KTHEN statements KEND KIF { check_conditional_expression($2); }

while :
	KWHILE expression KDO statements KEND KDO { check_conditional_expression($2); }

for :
	KFOR IDENT { add_iter_variable($2); }
	ASSIGN integer_literal KTO integer_literal
		{
			if ($5.data.integer > $7.data.integer)
				yyerror("the loop parameter must be in the incremental order");
		}
	KDO statements KEND KDO { iter_stack_pop(); }

return :
	KRET expression SEMICOLON
	{
		if (!cur_func_type)
			yyerror("program cannot be returned");
		else if (strcmp($2.type, cur_func_type))
			yyerror("return type mismatch");
	}

procedure_call :
	function_invocation SEMICOLON

function_invocation :
	IDENT LPAREN expressions RPAREN
		{
			$$.type = "";
			char* param_types = NULL;
			char* return_type;
			for (int scope = top; scope >= 0; scope--) {
				for (int i = 0; i < cur_index[scope]; i++) {
					if (!strcmp($1, stack[scope][i].name)) {
						param_types = stack[scope][i].attribute;
						return_type = stack[scope][i].type;
					}
				}
			}
			if (!param_types) {
				char message[100] = "symbol '";
				strcat( strcat(message, $1), "' not found");
				yyerror(message);
			} else if (!parameters_match(strdup(param_types), strdup($3.type))) {
				yyerror("parameter type mismatch");
			} else {
				$$.type = return_type;
			}
		}

variable_reference :
	IDENT
		{
			$$ = get_value_of_identifier($1);
			int var_num = get_local_var_num($1);
			char assembly[50];
			/*
			if (!strcmp($$.type, "integer"))
				sprintf(assembly, "iload %d", var_num);
			else
				sprintf(assembly, "fload %d", var_num);
			write_assembly_code(assembly);
			*/
		}
	| array_reference

array_reference : 
	IDENT index_references
		{
			char* original_type = get_value_of_identifier($1).type;
			if (strcmp(original_type, "error")) {
				int index_reference_count = $2;
				int pos;
				for (pos = strlen(original_type)-1; pos >= 0; pos--) {
					if (original_type[pos] == '[')
						index_reference_count--;
					if (!index_reference_count)
						break;
				}
				/* Remove the gap space */
				if (original_type[pos-1] == ' ')
					pos--;
				$$.type = malloc(100);
				strncpy($$.type, original_type, pos);
			}
		}

index_references :
	/* empty */ { $$ = 0; }
	| LSBRACKET expression RSBRACKET index_references
		{
			if (strcmp($2.type, "integer")) {
				yyerror("each index of array references must be an integer");
			} else {
				$$ = $4 + 1;
			}
		}

programname	: IDENT

identifier_list :
	IDENT { var_symbols[cur_var_index++] = strdup($1); }
	| IDENT { var_symbols[cur_var_index++] = strdup($1); } COMMA identifier_list

scalar_type :
	KINTEGER | KREAL | KSTRING | KBOOL

type :
	scalar_type
	| KARRAY integer_literal KTO integer_literal KOF type
		{
			if ($2.data.integer >= $4.data.integer) {
				yyerror("lower bound must be smaller than upper bound");
				$$ = "error";
			} else {
				char int_str[10];
				sprintf(int_str, "%d", $4.data.integer-$2.data.integer+1);
				char result[50];
				/* Insert "[int_str]" before the first '[' */
				int i;
				for (i = 0; i < strlen($6); i++)
					if ($6[i] == '[') {
						break;
					}
				strncpy(result, $6, i);
				result[i] = '\0';
				/* If there's no "[]", we have to add another space */
				if (i == strlen($6))
					strcat(result, " ");
				strcat( strcat(strcat(result, "["), int_str), "]" );
				strcat(result, $6 + i);
				$$ = strdup(result);
			}
		}

integer_literal :
	PINT | ZERO

literal_constant :
	integer_literal
		{
			char assembly[50];
			sprintf(assembly, "bipush %d", $1.data.integer);
			write_assembly_code(assembly);
		}
	| REAL
		{
			char assembly[50];
			sprintf(assembly, "ldc %lf", $1.data.real);
			write_assembly_code(assembly);
		}
	| STRING
		{
			$$.data.text = strdup($1.data.text);
			char assembly[50];
			sprintf(assembly, "ldc %s", $1.data.text);
			write_assembly_code(assembly);
		}
	| KTRUE { write_assembly_code("iconst_1"); }
	| KFALSE { write_assembly_code("iconst_0"); }

expressions :
	/* empty */ { $$.type = ""; }
	| expression
	| expression COMMA expressions
		{
			$$.type = malloc(100);
			strcpy($$.type, $1.type);
			strcat( strcat($$.type, ", "), $3.type );
		}

arguments :
	/* empty */
	| argument
	| argument SEMICOLON arguments

argument :
	identifier_list COLON type { add_var_type($3); }

return_type :
	/* empty */ { $$ = "void"; }
	| COLON type { $$ = $2; }

expression_component :
	literal_constant
	| variable_reference
	| function_invocation

expression :
	expression_component
	| boolean_expression
	| expression PLUS expression
		{
			/* Allow string concatenation */
			if (!strcmp($1.type, "string") && !strcmp($3.type, "string")) {
				$$.type = "string";
			} else {
				$$.type = get_type_of_arithmetic_operator($1, $3);
			}
		}
	| expression MINUS expression { $$.type = get_type_of_arithmetic_operator($1, $3); }
	| expression MULTIP expression { $$.type = get_type_of_arithmetic_operator($1, $3); }
	| expression DIVIDE expression { $$.type = get_type_of_arithmetic_operator($1, $3); }
	| expression MOD expression
		{
			if (strcmp($1.type, "integer") || strcmp($3.type, "integer"))
				yyerror("the operands must be integer types");
			else
				$$.type = "integer";
		}
	| MINUS expression %prec MULTIP
	| LPAREN expression RPAREN

boolean_expression :
	expression LESS expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression LESSEQ expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression NOTEQ expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression GREQ expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression GREATER expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression EQ expression { $$.type = get_type_of_relational_operator($1, $3); }
	| expression OR expression { $$.type = get_type_of_boolean_operator($1, $3); }
	| expression AND expression { $$.type = get_type_of_boolean_operator($1, $3); }
	| NOT expression
		{
			if (strcmp($2.type, "boolean"))
				yyerror("the operand must be boolean type");
			else
				$$.type = "boolean";
		}

%%

int yyerror( char *msg )
{
	if (msg) {
		printf("<Error> found in Line %d: %s\n", linenum, msg);
		has_error = 1;
		return;
	}
        fprintf( stderr, "\n|--------------------------------------------------------------------------\n" );
	fprintf( stderr, "| Error found in Line #%d: %s\n", linenum, buf );
	fprintf( stderr, "|\n" );
	fprintf( stderr, "| Unmatched token: %s\n", yytext );
        fprintf( stderr, "|--------------------------------------------------------------------------\n" );
        exit(-1);
}

void add_table()
{
	top++;
	cur_index[top] = 0;
	if (DEBUG2)
		printf("-----------Add a new symbol table\n");
}

void add_symbol(char* name)
{
	if (check_normal_redeclaration(name)) {
		stack[top][cur_index[top]++].name = strdup(name);
		if (DEBUG2)
			printf("------------Add symbol: %s\n", name);
	}
}

void add_var_type(char* type)
{
	for (int i = last_var_index; i < cur_var_index; i++){
		var_types[i] = strdup(type);
	}
	last_var_index = cur_var_index;
}

void add_kind_and_type(char* kind, char* type)
{
	if (DEBUG2)
		printf("------------Add kind: %s, type: %s\n", kind, type);
	for (int i = 0; i < cur_index[top]; i++)
		if (!stack[top][i].kind){
			stack[top][i].kind = strdup(kind);
			stack[top][i].type = strdup(type);
		}
}

void add_attribute(char *attr) 
{
	for (int i = 0; i < cur_index[top]; i++)
		if ( (!strcmp(stack[top][i].kind, "constant") || !strcmp(stack[top][i].kind, "function") )
				&& !stack[top][i].attribute ) {
			stack[top][i].attribute = strdup(attr);
		}
}

void clear_table()
{
	for (int i = 0; i < cur_index[top]; i++)
	{
		stack[top][i].name = NULL;
		stack[top][i].kind = NULL;
		stack[top][i].type = NULL;
		stack[top][i].attribute = NULL;
	}
}

void add_iter_variable(char *name)
{
	if (check_for_loop_redeclaration(name)) {
		iter_stack[iter_top] = strdup(name);
		if (DEBUG2)
			printf("------------Add iterative variable: %s\n", name);
	} else {
		iter_stack[iter_top] = "";
	}
	iter_top++;
}

void iter_stack_pop()
{
	iter_stack[iter_top--] = NULL;
}

int check_normal_redeclaration(char *name)
{
	int is_ok = 1;
	for (int i = 0; i < cur_index[top]; i++)
		if (!strcmp(name, stack[top][i].name))
			is_ok = 0;
	if (is_ok)
		for (int i = 0; i < iter_top; i++)
			if (!strcmp(name, iter_stack[i]))
				is_ok = 0;
	if (!is_ok) {
		char message[100] = "symbol ";
		strcat( strcat(message, name), " is redeclared");
		yyerror(message);
	}
	return is_ok;
}

int check_for_loop_redeclaration(char *name)
{
	int is_ok = 1;
	if (is_ok)
		for (int i = 0; i < iter_top; i++)
			if (!strcmp(name, iter_stack[i]))
				is_ok = 0;
	if (!is_ok) {
		char message[100] = "symbol ";
		strcat( strcat(message, name), " is redeclared");
		yyerror(message);
	}
	return is_ok;
}

void dumpsymbol()
{
	if (Opt_D)
	{
		int i;
		for (i = 0; i < 110; i++)
			printf("=");
		printf("\n");
		printf("%-33s%-11s%-11s%-17s%-11s\n","Name","Kind","Level","Type","Attribute");
		for(i=0;i< 110;i++)
			printf("-");
		printf("\n");
		for (i = 0; i < cur_index[top]; i++)
		{
			printf("%-33s", stack[top][i].name);
			printf("%-11s", stack[top][i].kind);
			printf("%d%-10s", top, top ? "(local)" : "(global)");
			printf("%-17s", stack[top][i].type);
			printf("%-11s", stack[top][i].attribute ? stack[top][i].attribute : "");
			printf("\n");
		}
		for (i = 0; i < 110; i++)
			printf("-");
		printf("\n");
	}

	/* Pop the table and remember to clear it*/
	clear_table();
	top--;
}

struct Constant get_value_of_identifier(char *identifier)
{
	struct Constant ret;
	/* Scan every scope from top to bottom */
	for (int scope = top; scope >= 0; scope--) {
		for (int i = 0; i < cur_index[scope]; i++) {
			if (!strcmp(identifier, stack[scope][i].name)) {
				if (!scope) {
					ret.global = 1;
					char assembly[50];
					char* type_descriptor = get_jvm_type_descriptor(stack[scope][i].type);
					sprintf(assembly, "getstatic %s/%s %s", file_name, identifier, type_descriptor);
					write_assembly_code(assembly);
				}
				ret.type = stack[scope][i].type;
				ret.kind = stack[scope][i].kind;
				ret.symbol = stack[scope][i].name;
				return ret;
			}
		}
	}
	int is_loop_variable = 0;
	for (int i = 0; i < iter_top; i++)
		if (!strcmp(identifier, iter_stack[i]))
			is_loop_variable = 1;
	if (is_loop_variable) {
		yyerror("the value of the loop variable cannot be changed inside the loop");
	} else {
		char message[100] = "symbol '";
		strcat( strcat(message, identifier), "' is not declared");
		yyerror(message);
	}
	ret.type = "error";
	ret.kind = "error";
	return ret;
}

int check_operands_be_integer_or_real(struct Constant a, struct Constant b)
{
	if ( (strcmp(a.type, "integer") && strcmp(a.type, "real"))
		|| (strcmp(b.type, "integer") && strcmp(b.type, "real")) ) {
		yyerror("the operands must be integer or real types");
		return 0;
	} else {
		return 1;
	}
}

char* get_type_of_arithmetic_operator(struct Constant a, struct Constant b)
{
	if (check_operands_be_integer_or_real(a, b)) {
		if (!strcmp(a.type, "real") || !strcmp(b.type, "real"))
			return "real";
		else
			return "integer";
	} else {
		return "";
	}
}

char* get_type_of_boolean_operator(struct Constant a, struct Constant b)
{
	if (strcmp(a.type, "boolean") || strcmp(b.type, "boolean")) {
		yyerror("the operands must be boolean types");
		return "";
	} else {
		return "boolean";
	}
}

char* get_type_of_relational_operator(struct Constant a, struct Constant b)
{
	if (check_operands_be_integer_or_real(a, b)) {
		if (strcmp(a.type, b.type)) {
			yyerror("the operands must be of the same type");
			return "";
		}
		return "boolean";
	} else {
		return "";
	}
}

void check_conditional_expression(struct Constant x)
{
	if (strcmp(x.type, "boolean"))
		yyerror("the conditional expression part must be Boolean type");
}

int is_array_type(char* t)
{
	for (int i = 0; i < strlen(t); i++)
		if (t[i] == '[')
			return 1;
	return 0;
}

int get_splited_parameters(char* str, char* delim, char** result)
{
	char* token = strtok(str, delim);
	int i = 0;
	while (token) {
		result[i++] = strdup(token);
		token = strtok(NULL, delim);
	}
	/* Return the number of tokens */
	return i;
}

int parameters_match(char* formal_params_str, char* actual_params_str)
{
	char* delim = ",";
	char* formal_params[20];
	char* actual_params[20];
	int num_fparams = get_splited_parameters(formal_params_str, delim, formal_params);
	int num_aparams = get_splited_parameters(actual_params_str, delim, actual_params);
	/* Compare the number of parameters */
	if (num_fparams != num_aparams)
		return 0;
	for (int i = 0; i < num_fparams; i++) {
		/* Consider coercion */
		if ( (!strcmp(formal_params[i], "real") || !strcmp(formal_params[i], " real") )
			&& (!strcmp(actual_params[i], "integer") || !strcmp(actual_params[i], " integer")) )
			continue;
		if (strcmp(formal_params[i], actual_params[i]))
			return 0;
	}
	return 1;
}

char* get_jvm_type_descriptor(char* type)
{
	char* type_descriptor;
	if (!strcmp(type, "integer"))
		type_descriptor = "I";
	else if (!strcmp(type, "boolean"))
		type_descriptor = "Z";
	else if (!strcmp(type, "real"))
		type_descriptor = "F";
	return type_descriptor;
}

int get_local_var_num(char* name)
{
	for (int i = next_var_num-1; i > 0; i--)
		if (!strcmp(jvm_var_stack[i], name))
			return i;
}

void write_print_code(char* type)
{
	char* java_type;
	if (!strcmp(type, "string"))
		java_type = "Ljava/lang/String;";
	else
		java_type = get_jvm_type_descriptor(type);
	char assembly[100];
	sprintf(assembly, "invokevirtual java/io/PrintStream/print(%s)V", java_type);
	write_assembly_code(assembly);
}

void write_assembly_code(char* assembly)
{
	fprintf(code_fp, assembly);
	char comment[100];
	sprintf(comment, "\t\t\t\t\t; Line #%d:\t%s\n", linenum, buf);
	fprintf(code_fp, comment);
}

int  main( int argc, char **argv )
{
	if( argc != 2 ) {
		fprintf(  stdout,  "Usage:  ./parser  [filename]\n"  );
		exit(0);
	}

	FILE *fp = fopen( argv[1], "r" );

	/* Extract file name discarding the extension */
	char *base_name = basename(strdup(argv[1]));
	int length = strlen(base_name)-2;
	file_name = malloc(length+1);
	strncpy(file_name, base_name, length);
	
	if( fp == NULL )  {
		fprintf( stdout, "Open  file  error\n" );
		exit(-1);
	}
	
	code_fp = fopen( strcat(strdup(file_name), ".j"), "w");
	if (code_fp == NULL) {
		printf("Open code file error\n");
		exit(-1);
	}

	yyin = fp;
	yyparse();

	if (has_error)
		exit(-1);

	fprintf( stdout, "\n" );
	fprintf( stdout, "|---------------------------------------------|\n" );
	fprintf( stdout, "|  There is no syntactic and semantic error!  |\n" );
	fprintf( stdout, "|---------------------------------------------|\n" );
	
	exit(0);
}

