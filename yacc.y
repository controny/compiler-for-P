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
	char* atrribute;
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
%}

%token SEMICOLON COLON COMMA RPAREN LPAREN LSBRACKET RSBRACKET 
KVAR KBEGIN KDEF KDO KELSE KEND KTO KOF
KFOR KIF KPRINT KREAD KTHEN KRET KWHILE
PLUS MINUS MULTIP DIVIDE MOD ASSIGN LESS LESSEQ NOTEQ GREQ GREATER EQ AND OR NOT
%token <text> IDENT KINTEGER KREAL KSTRING KBOOL KARRAY
%type <text> scalar_type type return_type programname arguments argument function
%token <constant> PINT ZERO REAL STRING KTRUE KFALSE
%type <constant> literal_constant integer_constant

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
			yyerror("The program name must be the same as the file name.");
		} else {
			add_symbol($1);
			add_kind_and_type("program", "void");
		}
	}
	programbody
	KEND IDENT
	{
		if (strcmp($1, $6))
			yyerror("The identifier after the end of a program declaration must be the same identifier as the name given at the beginning of the declaration.");
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
	RPAREN return_type SEMICOLON
	KBEGIN declarations statements KEND
		{ 
			dumpsymbol();
			add_kind_and_type("function", $8);
			add_attribute($<text>6);
		}
	KEND IDENT

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
	ASSIGN integer_constant KTO integer_constant KDO statements KEND KDO { iter_stack_pop(); }

return :
	KRET expression SEMICOLON

procedure_call :
	function_invocation SEMICOLON

function_invocation :
	IDENT LPAREN expressions RPAREN

variable_reference :
	IDENT | array_reference

array_reference : 
	IDENT index_references

index_references :
	/* empty */
	| LSBRACKET expression RSBRACKET index_references

programname	: IDENT

identifier_list :
	IDENT {add_symbol($1);}
	| IDENT {add_symbol($1);} COMMA identifier_list

scalar_type :
	KINTEGER | KREAL | KSTRING | KBOOL

type :
	scalar_type
	| KARRAY integer_constant KTO integer_constant KOF type
		{
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

integer_constant :
	PINT

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
	literal_constant | variable_reference | function_invocation

expression :
	expression_component {if(DEBUG1) printf("----------expression_component\n");}
	| boolean_expression
	| expression PLUS expression {if(DEBUG1) printf("----------expression + expression\n");}
	| expression MINUS expression {if(DEBUG1) printf("----------expression - expression\n");}
	| expression MULTIP expression {if(DEBUG1) printf("----------expression * expression\n");}
	| expression DIVIDE expression {if(DEBUG1) printf("----------expression / expression\n");}
	| expression MOD expression {if(DEBUG1) printf("----------expression mod expression\n");}
	| MINUS expression %prec MULTIP {if(DEBUG1) printf("----------MINUS expression\n");}
	| LPAREN expression RPAREN {if(DEBUG1) printf("----------(expression)\n");}

boolean_expression :
	expression LESS expression {if(DEBUG1) printf("----------expression < expression\n");}
	| expression LESSEQ expression {if(DEBUG1) printf("----------expression <= expression\n");}
	| expression NOTEQ expression {if(DEBUG1) printf("----------expression <> expression\n");}
	| expression GREQ expression {if(DEBUG1) printf("----------expression >= expression\n");}
	| expression GREATER expression {if(DEBUG1) printf("----------expression > expression\n");}
	| expression EQ expression {if(DEBUG1) printf("----------expression = expression\n");}
	| expression OR expression {if(DEBUG1) printf("----------expression or expression\n");}
	| expression AND expression {if(DEBUG1) printf("----------expression and expression\n");}
	| NOT expression {if(DEBUG1) printf("----------not expression\n");}

/*
integer_expression :
	integer_literal
*/

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
				&& !stack[top][i].atrribute ) {
			stack[top][i].atrribute = strdup(attr);
		}
}

void clear_table()
{
	for (int i = 0; i < cur_index[top]; i++)
	{
		stack[top][i].name = NULL;
		stack[top][i].kind = NULL;
		stack[top][i].type = NULL;
		stack[top][i].atrribute = NULL;
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
			printf("%-11s", stack[top][i].atrribute ? stack[top][i].atrribute : "");
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

