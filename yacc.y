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

void add_table();
void add_symbol();
void add_kind_and_type();
void add_attribute();
void add_iter_variable();
void iter_stack_pop();
int check_normal_redeclaration();
int check_for_loop_redeclaration();
void dumpsymbol();
struct Constant get_value_of_identifier();
int check_operands_be_integer_or_real();
char* get_type_of_relational_operator();
char* get_type_of_boolean_operator();
%}

%token SEMICOLON COLON COMMA RPAREN LPAREN LSBRACKET RSBRACKET 
KVAR KBEGIN KDEF KDO KELSE KEND KTO KOF
KFOR KIF KPRINT KREAD KTHEN KRET KWHILE
PLUS MINUS MULTIP DIVIDE MOD ASSIGN LESS LESSEQ NOTEQ GREQ GREATER EQ AND OR NOT
%token <text> IDENT KINTEGER KREAL KSTRING KBOOL KARRAY
%type <text> scalar_type type return_type programname arguments argument function
%token <constant> PINT ZERO REAL STRING KTRUE KFALSE
%type <constant> literal_constant integer_literal expression expression_component boolean_expression variable_reference

%right ASSIGN
%left AND OR %right NOT
%nonassoc LESS LESSEQ NOTEQ GREQ GREATER EQ
%left PLUS MINUS
%left MULTIP DIVIDE MOD

%union {
	struct Constant constant;
	char* text;
}
%%

program	:
	programname SEMICOLON
		{
			if (strcmp($1, file_name)) {
				yyerror("The program name must be the same as the file name");
			} else {
				add_symbol($1);
				add_kind_and_type("program", "void");
			}
		}
	programbody
	KEND IDENT
		{
			if (strcmp($1, $6))
				yyerror("The identifier after the end of a program declaration must be the same identifier as the name given at the beginning of the declaration");
			else
				dumpsymbol();
		}

programbody :
	declarations functions compound

function :
	IDENT {add_symbol($1);} LPAREN { add_table(); }
	arguments
		{
			/* Calculate attributes of the funciton */
			char result[100] = "";
			for (int i = 0; i < cur_index[top]; i++)
			{
				if (!strcmp(stack[top][i].kind, "parameter"))
				{
					if (!strcmp(result, ""))
						strcpy(result, stack[top][i].type);
					else
						strcat( strcat(result, ", "),  stack[top][i].type);
				}
			}
			$<text>$ = strdup(result);
		}
	RPAREN return_type
		{
			if (strcmp($8, "integer")
				&& strcmp($8, "real")
				&& strcmp($8, "string")
				&& strcmp($8, "bool"))
			yyerror("The return value must be a scalar type");
		}
	SEMICOLON
	KBEGIN declarations statements KEND
	KEND IDENT
		{ 
			if (strcmp($1, $16)) {
				yyerror("The identifier after the end of a function declaration must be the same identifier as the name given at the beginning of the declaration");
			} else {
				dumpsymbol();
				add_kind_and_type("function", $8);
				add_attribute($<text>6);
			}
		}

declaration :
	KVAR identifier_list COLON type SEMICOLON { add_kind_and_type("variable", $4); }
	| KVAR identifier_list COLON literal_constant SEMICOLON
		{
			add_kind_and_type("constant", $4.type);
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
	KBEGIN {add_table();}
	declarations statements KEND {dumpsymbol();}

simple :
	variable_reference ASSIGN expression SEMICOLON
		{
			/* array arithmetic is not allowed */
		}
	| KPRINT variable_reference SEMICOLON
	| KPRINT expression SEMICOLON
	| KREAD variable_reference SEMICOLON

/* Don't care about the difference between 'expression' and 'boolean expression' */
conditional : 
	KIF expression KTHEN statements KELSE statements KEND KIF
	| KIF expression KTHEN statements KEND KIF

while :
	KWHILE expression KDO statements KEND KDO

for :
	KFOR IDENT { add_iter_variable($2); }
	ASSIGN integer_literal KTO integer_literal KDO statements KEND KDO { iter_stack_pop(); }

return :
	KRET expression SEMICOLON

procedure_call :
	function_invocation SEMICOLON

function_invocation :
	IDENT LPAREN expressions RPAREN

variable_reference :
	IDENT { $$ = get_value_of_identifier($1); }
	| array_reference

array_reference : 
	IDENT index_references

index_references :
	/* empty */
	| LSBRACKET integer_literal RSBRACKET index_references

programname	: IDENT

identifier_list :
	IDENT {add_symbol($1);}
	| IDENT {add_symbol($1);} COMMA identifier_list

scalar_type :
	KINTEGER | KREAL | KSTRING | KBOOL

type :
	scalar_type
	| KARRAY integer_literal KTO integer_literal KOF type
		{
			if ($2.data.integer > $4.data.integer) {
				yyerror("The index of the lower bound must be smaller than that of the upper bound");
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
	integer_literal | REAL | STRING {$$.data.text = strdup($1.data.text);} | KTRUE | KFALSE

expressions :
	/* empty */
	| expression
	| expression COMMA expressions

arguments :
	/* empty */ /*{ $$ = ""; }*/
	| argument
	| argument SEMICOLON arguments
		/*{
			char *tmp = malloc(50);
			strcpy(tmp, $1);
			strcat( strcat(tmp, ", "), $3);
			$$ = strdup(tmp);
		}*/

argument :
	identifier_list COLON type { $$ = $3; add_kind_and_type("parameter", $3); }

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
	| expression PLUS expression { check_operands_be_integer_or_real($1, $3); }
	| expression MINUS expression { check_operands_be_integer_or_real($1, $3); }
	| expression MULTIP expression { check_operands_be_integer_or_real($1, $3); }
	| expression DIVIDE expression { check_operands_be_integer_or_real($1, $3); }
	| expression MOD expression
		{
			if (strcmp($1.type, "integer") || strcmp($3.type, "integer"))
				yyerror("The operands must be integer types");
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
				yyerror("The operand must be boolean type");
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
		iter_stack[iter_top++] = strdup(name);
		if (DEBUG2)
			printf("------------Add iterative variable: %s\n", name);
	}
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
	for (int scope = top; scope >= 0; scope--)
		for (int i = 0; i < cur_index[top]; i++)
			if (!strcmp(identifier, stack[scope][i].name)) {
				ret.type = stack[scope][i].type;
				return ret;
			}
	char message[100] = "symbol ";
	strcat( strcat(message, identifier), " is not declared");
	yyerror(message);
}

int check_operands_be_integer_or_real(struct Constant a, struct Constant b)
{
	if ( (strcmp(a.type, "integer") && strcmp(a.type, "real"))
		|| (strcmp(b.type, "integer") && strcmp(b.type, "real")) ) {
		yyerror("The operands must be integer or real types");
		return 0;
	} else {
		return 1;
	}
}

char* get_type_of_boolean_operator(struct Constant a, struct Constant b)
{
	if (strcmp(a.type, "boolean") || strcmp(b.type, "boolean")) {
		yyerror("The operands must be boolean types");
		return NULL;
	} else {
		return "boolean";
	}
}

char* get_type_of_relational_operator(struct Constant a, struct Constant b)
{
	if (check_operands_be_integer_or_real(a, b)) {
		if (strcmp(a.type, b.type)) {
			yyerror("The operands must be of the same type");
			return NULL;
		}
		return "boolean";
	} else {
		return NULL;
	}
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

