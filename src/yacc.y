%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include "constant.h"

#define DEBUG1 0
#define DEBUG2 0
#define MAX_TABLE_NUMBER 512
#define MAX_TABLE_SIZE 512
#define MAX_NUM_LOCALS 128

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

/* A stack made up of frames, which contain local variables */
char** local_vars_stack[50];
int cur_frame_num;
int next_var_num;

/* Data structure for recording file position to insert back when parsing `if` */
long int if_fp_offsets[10];
int cur_if_fp_offsets_index;

/* To differentiate labels */
int label_postfix;

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
void add_label_postfix();
void add_relop_code();
void add_ariop_code();
void set_locals_limit();
void add_local_var_to_stack();
void load_variable();
int safe_strcmp();
%}

%token SEMICOLON COLON COMMA RPAREN LPAREN LSBRACKET RSBRACKET 
KVAR KBEGIN KDEF KDO KELSE KEND KTO KOF
KFOR KIF KPRINT KREAD KTHEN KRET KWHILE
PLUS MINUS MULTIP DIVIDE MOD ASSIGN LESS LESSEQ NOTEQ GREQ GREATER EQ AND OR NOT
%token <text> IDENT KINTEGER KREAL KSTRING KBOOL KARRAY
%type <text> scalar_type type return_type programname arguments argument function
%token <constant> PINT ZERO REAL STRING KTRUE KFALSE
%type <constant> literal_constant integer_literal expression expression_component boolean_expression
variable_reference function_invocation array_reference print_kind expressions
%type <count> index_references

%right ASSIGN
%left AND OR %right NOT
%nonassoc LESS LESSEQ NOTEQ GREQ GREATER EQ
%left PLUS MINUS
%left MULTIP DIVIDE MOD

%union {
	struct Constant constant;
	struct Constant list[50];  // to denote the type of `expressions`
	char* text;
	int count;
}
%%

program	:
	programname SEMICOLON
		{
			if (safe_strcmp($1, file_name))
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
			if (safe_strcmp($1, $6))
				yyerror("program end ID inconsist with the beginning ID");
			if (safe_strcmp($1, file_name))
				yyerror("program end ID inconsist with file name");
			dumpsymbol();
		}

programbody :
	declarations functions compound

function :
	IDENT LPAREN arguments RPAREN return_type
		{
			$<text>$ = "";
			if (safe_strcmp($5, "integer")
				&& safe_strcmp($5, "real")
				&& safe_strcmp($5, "string")
				&& safe_strcmp($5, "boolean")
				&& safe_strcmp($5, "void")) {
				yyerror("a function cannot return an array type");
				$<text>$ = "error";
			} else {
				for (int i = 0; i < cur_var_index; i++)
					if (!safe_strcmp(var_types[i], "error")) {
						$<text>$ = "error";
						break;
					}
			}
			// Add the function to global level table
			if (safe_strcmp($<text>$, "error"))
				add_symbol($1);
			// Create local table
			add_table();
			char assembly[200];
			sprintf(assembly, ".method public static %s(", $1);
			for (int i = 0; i < cur_var_index; i++) {
				if (safe_strcmp(var_types[i], "error")) {
					add_symbol(var_symbols[i]);
					add_kind_and_type("parameter", var_types[i]);
				}
			}
			if (safe_strcmp($<text>$, "error")) {
				/* Calculate attributes of the funciton */
				char attributes[100] = "";
				for (int i = 0; i < cur_index[top]; i++)
				{
					if (!safe_strcmp(stack[top][i].kind, "parameter"))
					{
						if (!safe_strcmp(attributes, ""))
							strcpy(attributes, stack[top][i].type);
						else
							strcat( strcat(attributes, ", "),  stack[top][i].type);
						strcat(assembly, get_jvm_type_descriptor(stack[top][i].type));
					}
				}
				$<text>$ = strdup(attributes);
			}
			// Add the type and attributes of the function in global table
			if (safe_strcmp($<text>$, "error")) {
				add_kind_and_type("function", $5);
				add_attribute("function", $<text>$);
			}

			// Manage jvm local variables
			cur_var_index = last_var_index = 0;
			cur_func_type = strdup($5);
			strcat( strcat(assembly, ")"), get_jvm_type_descriptor($5) );
			write_assembly_code(assembly);
			write_assembly_code(".limit stack 100");
			set_locals_limit();
			for (int i = 0; i < cur_index[top]; i++) {
				if (!safe_strcmp(stack[top][i].kind, "parameter")) {
					// Add parameters to locals stack
					add_local_var_to_stack(stack[top][i].name);
				}
			}
		}
	SEMICOLON KBEGIN declarations statements KEND KEND IDENT
		{ 
			dumpsymbol();
			if (safe_strcmp($1, $13)) {
				yyerror("function end ID inconsist with the beginning ID");
			}
			cur_func_type = NULL;
			if (!safe_strcmp($5, "void"))
				write_assembly_code("return");
			write_assembly_code(".end method");
			cur_frame_num++;
			next_var_num = 0;
		}

declaration :
	KVAR identifier_list COLON type SEMICOLON
		{
			for (int i = 0; i < cur_var_index; i++) {
				if (safe_strcmp($4, "error")) {
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
					add_local_var_to_stack(var_symbols[i]);
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
					add_local_var_to_stack(var_symbols[i]);
					char* store = "istore";
					if (!safe_strcmp($4.type, "real")) {
						store = "fstore";
					}
					sprintf(assembly, "%s %d", store, get_local_var_num(var_symbols[i]));
					write_assembly_code(assembly);
				}
			}
			cur_var_index = 0;
			char attr[100];
			if (!safe_strcmp($4.type, "integer"))
				sprintf(attr, "%d", $4.data.integer);
			else if (!safe_strcmp($4.type, "real"))
				sprintf(attr, "%f", $4.data.real);
			else
				sprintf(attr, "%s", $4.data.text);
			if (DEBUG2)
				printf("------------Add attribute: %s\n", attr);
			add_attribute("constant", attr);
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
			// In addition to function, only global compound is a method
			if (!top) {
				write_assembly_code(".method public static main([Ljava/lang/String;)V\n\t.limit stack 100");
				// In the beginning of main block, create an instance of java.util.Scanner
				write_assembly_code("new java/util/Scanner\ndup\ngetstatic java/lang/System/in Ljava/io/InputStream;\ninvokespecial java/util/Scanner/<init>(Ljava/io/InputStream;)V");
				char assembly[100];
				sprintf(assembly, "putstatic %s/_sc Ljava/util/Scanner;", file_name);
				write_assembly_code(assembly);
				set_locals_limit();
				add_local_var_to_stack("");
			}
			add_table();
		}
	declarations statements KEND
		{
			dumpsymbol();
			if (!top) {
				write_assembly_code("return\n.end method");
				cur_frame_num++;
				next_var_num = 0;
			}
		}

simple :
	variable_reference ASSIGN expression SEMICOLON
		{
			if ($1.kind && !safe_strcmp($1.kind, "constant")) {
				char message[100] = "constant \'";
				strcat( strcat(message, $1.symbol), "\' cannot be assigned");
				yyerror(message);
			} else if ( safe_strcmp($1.type, $3.type) && (safe_strcmp($1.type, "real") || safe_strcmp($3.type, "integer")) ) {
				char message[100] = "type mismatch, LHS= ";
				strcat( strcat( strcat(message, $1.type), ", RHS= "), $3.type);
				yyerror(message);
			} else if (is_array_type($1.type) || is_array_type($3.type)) {
				yyerror("array arithmetic is not allowed");
			} else if (!safe_strcmp($1.kind, "iterative"))
				yyerror("the value of the loop variable cannot be changed inside the loop");
			char assembly[50];
			if ($1.global) {
				sprintf(assembly, "putstatic %s/%s %s", file_name, $1.symbol, get_jvm_type_descriptor($1.type));
			} else {
				char* store = "istore";
				if (!safe_strcmp($1.type, "real")) {
					if (!safe_strcmp($3.type, "integer")){
						// Deal with type coercion
						write_assembly_code("i2f");
					}
					store = "fstore";
				}
				sprintf(assembly, "%s %d", store, get_local_var_num($1.symbol));
			}
			write_assembly_code(assembly);
		}
	| KREAD variable_reference SEMICOLON
		{
			char* method_name;
			char* store = "istore";
			if (!safe_strcmp($2.type, "integer"))
				method_name = "Int";
			else if (!safe_strcmp($2.type, "boolean"))
				method_name = "Boolean";
			else {
				method_name = "Float";
				store = "fstore";
			}
			char assembly[100];
			sprintf(assembly,
				"getstatic %s/_sc Ljava/util/Scanner;\ninvokevirtual java/util/Scanner/next%s()%s",
				file_name, method_name, get_jvm_type_descriptor($2.type));
			write_assembly_code(assembly);
			if ($2.global) {
				sprintf(assembly, "putstatic %s/%s %s", file_name, $2.symbol, get_jvm_type_descriptor($2.type));
			} else {
				sprintf(assembly, "%s %d", store, get_local_var_num($2.symbol));
			}
			write_assembly_code(assembly);
		}
	| KPRINT
		{ write_assembly_code("getstatic java/lang/System/out Ljava/io/PrintStream;"); }
	print_kind
	SEMICOLON
		{ write_print_code($3.type); }

print_kind :
	variable_reference 
		{ load_variable($1); }
	| expression

conditional : 
	KIF expression KTHEN
		{
			if_fp_offsets[ ++cur_if_fp_offsets_index ] = ftell(code_fp);
			// Leave an empty buffer for inserting later
			char buffer[50];
			memset(buffer, ' ', 50);
			fwrite(buffer, sizeof(char), sizeof(buffer), code_fp);
			fprintf(code_fp, "\n");
			check_conditional_expression($2);
		}
	else_block

else_block :
	statements KEND KIF
		{
			int cur_label_postfix = label_postfix++;
			// Add code back
			fseek(code_fp, if_fp_offsets[ cur_if_fp_offsets_index-- ], SEEK_SET);
			add_label_postfix("ifeq Lexit_%d", cur_label_postfix);
			fseek(code_fp, 0, SEEK_END);
			add_label_postfix("Lexit_%d:", cur_label_postfix);
		}
	| statements KELSE
		{
			$<count>$ = label_postfix++;
			// Add code back
			fseek(code_fp, if_fp_offsets[ cur_if_fp_offsets_index-- ], SEEK_SET);
			add_label_postfix("ifeq Lelse_%d", $<count>$);
			fseek(code_fp, 0, SEEK_END);
			add_label_postfix("goto Lexit_%d", $<count>$);
			add_label_postfix("Lelse_%d:", $<count>$);
		}
	statements KEND KIF
		{
			add_label_postfix("Lexit_%d:", $<count>3);
		}

while :
	KWHILE
		{
			$<count>$ = label_postfix++;
			add_label_postfix("Lbegin_%d:", $<count>$);
		}
	expression KDO
		{
			add_label_postfix("ifeq Lexit_%d", $<count>2);
			check_conditional_expression($3);
		}
	statements KEND KDO
		{
			add_label_postfix("goto Lbegin_%d", $<count>2);
			add_label_postfix("Lexit_%d:", $<count>2);
		}

for :
	KFOR IDENT { add_iter_variable($2); }
	ASSIGN integer_literal
		{
			$<count>$ = label_postfix++;
			add_local_var_to_stack($2);
			char assembly[200];
			sprintf(assembly, "sipush %d\nistore %d\nLbegin_%d:", $5.data.integer, next_var_num-1, $<count>$);
			write_assembly_code(assembly);
		}
	KTO integer_literal
		{
			if ($5.data.integer > $8.data.integer)
				yyerror("the loop parameter must be in the incremental order");
			char assembly[200];
			sprintf(assembly,
				"iload %d\nsipush %d\nisub\niflt Ltrue_%d\niconst_0\ngoto Lfalse_%d\nLtrue_%d:\niconst_1\nLfalse_%d:\nifeq Lexit_%d",
				get_local_var_num($2), $8.data.integer+1, 
				$<count>6, $<count>6, $<count>6, $<count>6, $<count>6);
			write_assembly_code(assembly);
		}
	KDO statements KEND KDO
		{
			char assembly[100];
			int local_var_num = get_local_var_num($2);
			sprintf(assembly,
				"iload %d\nbipush 1\niadd\nistore %d\ngoto Lbegin_%d\nLexit_%d:",
				local_var_num, local_var_num, $<count>6, $<count>6);
			write_assembly_code(assembly);
			iter_stack_pop();
		}

return :
	KRET expression SEMICOLON
	{
		if (!cur_func_type)
			yyerror("program cannot be returned");
		else if (safe_strcmp($2.type, cur_func_type))
			yyerror("return type mismatch");
		write_assembly_code("ireturn");
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
					if (!safe_strcmp($1, stack[scope][i].name)) {
						param_types = strdup(stack[scope][i].attribute);
						return_type = strdup(stack[scope][i].type);
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

			char params_str[20] = "";
			char* params_array[20];
			int num_params = get_splited_parameters(strdup(param_types), ", ", params_array);
			for (int i = 0; i < num_params; i++) {
				strcat(params_str, get_jvm_type_descriptor(params_array[i]));
			}
			char assembly[50];
			sprintf(assembly,
				"invokestatic %s/%s(%s)%s",
				file_name, $1, params_str, get_jvm_type_descriptor(return_type));
			write_assembly_code(assembly);
		}

variable_reference :
	IDENT
		{
			$$ = get_value_of_identifier($1);
		}
	| array_reference

array_reference : 
	IDENT index_references
		{
			char* original_type = get_value_of_identifier($1).type;
			if (safe_strcmp(original_type, "error")) {
				int index_reference_count = $2;
				// -1 indicates an error
				if (index_reference_count != -1) {
					// use `start` and `end` to tailor `original_type`
					int end;
					int start = -1;
					for (end = 0; end < strlen(original_type); end++) {
						if (original_type[end] == '[') {
							index_reference_count--;
							if (start == -1)
								start = end;
						}
						if (index_reference_count == -1)
							break;
					}
					$$.type = malloc(100);
					strncpy($$.type, original_type, start);
					strcat($$.type, original_type + end);
					// Remove the final space if the result is scalar type
					if ($$.type[strlen($$.type)-1] == ' ')
						$$.type[strlen($$.type)-1] = '\0';
				}
			}
		}

index_references :
	/* empty */ { $$ = 0; }
	| LSBRACKET expression RSBRACKET index_references
		{
			if (safe_strcmp($2.type, "integer")) {
				yyerror("each index of array references must be an integer");
				$$ = -1;
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
			sprintf(assembly, "sipush %d", $1.data.integer);
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
		{
			load_variable($1);
		}
	| function_invocation

expression :
	expression_component
	| boolean_expression
	| expression PLUS expression
		{
			/* Allow string concatenation */
			if (!safe_strcmp($1.type, "string") && !safe_strcmp($3.type, "string")) {
				$$.type = "string";
			} else {
				$$.type = get_type_of_arithmetic_operator($1, $3);
			}
			add_ariop_code("iadd", "fadd", $$.type);
		}
	| expression MINUS expression
		{
			$$.type = get_type_of_arithmetic_operator($1, $3);
			add_ariop_code("isub", "fsub", $$.type);
		}
	| expression MULTIP expression
		{
			$$.type = get_type_of_arithmetic_operator($1, $3);
			add_ariop_code("imul", "fmul", $$.type);
		}
	| expression DIVIDE expression
		{
			$$.type = get_type_of_arithmetic_operator($1, $3);
			add_ariop_code("idiv", "fdiv", $$.type);
		}
	| expression MOD expression
		{
			if (safe_strcmp($1.type, "integer") || safe_strcmp($3.type, "integer"))
				yyerror("the operands must be integer types");
			else
				$$.type = "integer";
			add_ariop_code("irem", "", $$.type);
		}
	| MINUS expression %prec MULTIP
		{
			$$ = $2;
			add_ariop_code("ineg", "fneg", $2.type);
		}
	| LPAREN expression RPAREN
		{
			$$ = $2;
		}

boolean_expression :
	expression LESS expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("iflt", $1.type);
		}
	| expression LESSEQ expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("ifle", $1.type);
		}
	| expression NOTEQ expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("ifne", $1.type);
		}
	| expression GREQ expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("ifge", $1.type);
		}
	| expression GREATER expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("ifgt", $1.type);
		}
	| expression EQ expression
		{
			$$.type = get_type_of_relational_operator($1, $3);
			add_relop_code("ifeq", $1.type);
		}
	| expression OR expression
		{
			$$.type = get_type_of_boolean_operator($1, $3);
			write_assembly_code("ior");
		}
	| expression AND expression
		{
			$$.type = get_type_of_boolean_operator($1, $3);
			write_assembly_code("iand");
		}
	| NOT expression
		{
			if (safe_strcmp($2.type, "boolean"))
				yyerror("the operand must be boolean type");
			else
				$$.type = "boolean";
			write_assembly_code("ixor");
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
	int level = top;
	if (!safe_strcmp(kind, "function")) {
		level = 0;
	}
	for (int i = 0; i < cur_index[level]; i++)
		if (!stack[level][i].kind){
			stack[level][i].kind = strdup(kind);
			stack[level][i].type = strdup(type);
		}
}

void add_attribute(char* kind, char *attr) 
{
	int level = top;
	if (!safe_strcmp(kind, "function")) {
		level = 0;
	}
	for (int i = 0; i < cur_index[level]; i++)
		if (!safe_strcmp(stack[level][i].kind, kind)
				&& !stack[level][i].attribute ) {
			stack[level][i].attribute = strdup(attr);
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
		if (!safe_strcmp(name, stack[top][i].name))
			is_ok = 0;
	if (is_ok)
		for (int i = 0; i < iter_top; i++)
			if (!safe_strcmp(name, iter_stack[i]))
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
			if (!safe_strcmp(name, iter_stack[i]))
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
	ret.global = 0;
	for (int scope = top; scope >= 0; scope--) {
		for (int i = 0; i < cur_index[scope]; i++) {
			if (!safe_strcmp(identifier, stack[scope][i].name)) {
				if (!scope) {
					ret.global = 1;
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
		if (!safe_strcmp(identifier, iter_stack[i]))
			is_loop_variable = 1;
	if (is_loop_variable) {
		ret.type = "integer";
		ret.kind = "iterative";
		ret.symbol = identifier;
	} else {
		char message[100] = "symbol '";
		strcat( strcat(message, identifier), "' is not declared");
		yyerror(message);
		ret.type = "error";
		ret.kind = "error";
	}
	return ret;
}

int check_operands_be_integer_or_real(struct Constant a, struct Constant b)
{
	if ( (safe_strcmp(a.type, "integer") && safe_strcmp(a.type, "real"))
		|| (safe_strcmp(b.type, "integer") && safe_strcmp(b.type, "real")) ) {
		yyerror("the operands must be integer or real types");
		return 0;
	} else {
		return 1;
	}
}

char* get_type_of_arithmetic_operator(struct Constant a, struct Constant b)
{
	if (check_operands_be_integer_or_real(a, b)) {
		if (!safe_strcmp(a.type, "real") || !safe_strcmp(b.type, "real")) {
			// Deal with type coercion
			if (!safe_strcmp(a.type, "integer")) {
				// Pop `b` and convert `a` to float
				write_assembly_code("pop\ni2f");
				// Then load b again
				char assembly[50];
				sprintf(assembly, "fload %d", get_local_var_num(b.symbol));
			} else if (!safe_strcmp(b.type, "integer")) {
				// Just convert the top(`b`) to float
				write_assembly_code("i2f");
			}
			return "real";
		} else {
			return "integer";
		}
	} else {
		return "";
	}
}

char* get_type_of_boolean_operator(struct Constant a, struct Constant b)
{
	if (safe_strcmp(a.type, "boolean") || safe_strcmp(b.type, "boolean")) {
		yyerror("the operands must be boolean types");
		return "";
	} else {
		return "boolean";
	}
}

char* get_type_of_relational_operator(struct Constant a, struct Constant b)
{
	if (check_operands_be_integer_or_real(a, b)) {
		if (safe_strcmp(a.type, b.type)) {
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
	if (safe_strcmp(x.type, "boolean"))
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
		if ( (!safe_strcmp(formal_params[i], "real") || !safe_strcmp(formal_params[i], " real") )
			&& (!safe_strcmp(actual_params[i], "integer") || !safe_strcmp(actual_params[i], " integer")) ) {

			continue;
		}
		if (safe_strcmp(formal_params[i], actual_params[i]))
			return 0;
	}
	return 1;
}

char* get_jvm_type_descriptor(char* type)
{
	char* type_descriptor = "";
	if (!safe_strcmp(type, "integer"))
		type_descriptor = "I";
	else if (!safe_strcmp(type, "boolean"))
		type_descriptor = "Z";
	else if (!safe_strcmp(type, "real"))
		type_descriptor = "F";
	else if (!safe_strcmp(type, "void"))
		type_descriptor = "V";
	return type_descriptor;
}

int get_local_var_num(char* name)
{
	// Traverse in a reverse order
	// to avoid getting outter variable with the same name
	for (int i = next_var_num-1; i >= 0; i--) {
		if (!safe_strcmp(local_vars_stack[cur_frame_num][i], name)) {
			return i;
		}
	}
}

void write_print_code(char* type)
{
	char* java_type;
	if (!safe_strcmp(type, "string"))
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
	char comment[500];
	sprintf(comment, "\n; Line #%d:\t%s\n", linenum, buf);
	fprintf(code_fp, comment);
}

void add_label_postfix(char* label, int postfix)
{
	char assembly[50];
	sprintf(assembly, label, postfix);
	write_assembly_code(assembly);
}

void add_relop_code(char* op, char* type)
{
	char assembly[200];
	char* cmp;
	if (!safe_strcmp(type, "integer"))
		cmp = "isub";
	else
		cmp = "fcmpl";
	sprintf(assembly,
		"%s\n%s Ltrue_%d\niconst_0\ngoto Lfalse_%d\nLtrue_%d:\niconst_1\nLfalse_%d:",
		cmp, op, label_postfix, label_postfix, label_postfix, label_postfix);
	label_postfix++;
	write_assembly_code(assembly);
}

void add_ariop_code(char* int_op, char* real_op, char* type)
{
	if (!safe_strcmp(type, "integer"))
		write_assembly_code(int_op);
	else
		write_assembly_code(real_op);
}

void set_locals_limit()
{
	char assembly[50];
	sprintf(assembly, ".limit locals %d", MAX_NUM_LOCALS);
	write_assembly_code(assembly);
	local_vars_stack[cur_frame_num] = malloc( MAX_NUM_LOCALS * sizeof(char*) );
}

void add_local_var_to_stack(char* symbol)
{
	local_vars_stack[cur_frame_num][next_var_num++] = strdup(symbol);
}

void load_variable(struct Constant var)
{
	char assembly[50];
	if (var.global) {
		char* type_descriptor = get_jvm_type_descriptor(var.type);
		sprintf(assembly, "getstatic %s/%s %s", file_name, var.symbol, type_descriptor);
	} else {
		int var_num = get_local_var_num(var.symbol);
		if (!safe_strcmp(var.type, "real"))
			sprintf(assembly, "fload %d", var_num);
		else
			sprintf(assembly, "iload %d", var_num);
	}
	write_assembly_code(assembly);
}

int safe_strcmp(char* a, char* b)
{
	if (a && b)
		return strcmp(a, b);
	return 1;
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

	/*
	fprintf( stdout, "\n" );
	fprintf( stdout, "|---------------------------------------------|\n" );
	fprintf( stdout, "|  There is no syntactic and semantic error!  |\n" );
	fprintf( stdout, "|---------------------------------------------|\n" );
	*/
	
	exit(0);
}

