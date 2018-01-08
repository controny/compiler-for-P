%{

#include <string.h>
#include "constant.h"
#include "y.tab.h"
#define LIST strcat( buf, yytext )
#define token(t) { LIST; if (Opt_T) printf("<%s>\n", #t );}
#define tokenChar(t) { LIST; if (Opt_T) printf("<%c>\n", t );}
#define tokenInteger(t, i) { LIST; if (Opt_T) printf("<%s: %d>\n", t, i); yylval.constant.type = "integer"; yylval.constant.data.integer = i; if (i > 0) return PINT; else return ZERO; }
#define tokenOctInteger(t, i) { LIST; if (Opt_T) printf("<%s: %s>\n", t, i); yylval.constant.type = "integer"; yylval.constant.data.integer = strtol(i, NULL, 8); if (i > 0) return PINT; else return ZERO; }
#define tokenFloat(t, i) { LIST; if (Opt_T) printf("<%s: %s>\n", t, i ); yylval.constant.type = "real"; yylval.constant.data.real = atof(i); return REAL; }
#define tokenScientific(t, s) { LIST; if ( Opt_T ) printf("<%s: %s>\n", t, s); yylval.constant.type = "real"; yylval.constant.data.real = atof(s); return REAL; }
#define tokenString(t, s) { LIST; if (Opt_T) printf("<%s: %s>\n", t, s); yylval.text = strndup(s, 32) ; return IDENT;}


#define  MAX_LINE_LENG  256

int Opt_S = 0;				/* list source code option */
int Opt_T = 0;				/* list token option */
int Opt_D = 0;				/* dump symbols */
int linenum = 1;			/* line number */
char buf[MAX_LINE_LENG];		/* source code line buffer */
char strContent[MAX_LINE_LENG];		/* string buffer */

void setPseudoComment( const char * );	/* pseudo comment option switch */
%}

whitespace [ \t]+
letter [A-Za-z]
digit [0-9]
integer 0|[1-9][0-9]*
octal 0[0-7]+
fraction 0|[0-9]*
float {integer}"."{fraction}
scientific ({integer}|{float}|{octal})[Ee][+-]?({integer}|{octal})
identifier ({letter})({letter}|{digit})*

 /* exclusive start conditions */
%x COMMENT
%x COMMENT_CPP

%%

","				{ tokenChar(','); return COMMA; }
";"				{ tokenChar(';'); return SEMICOLON;}
":"				{ tokenChar(':'); return COLON; }
")"				{ tokenChar(')'); return RPAREN; }
"("				{ tokenChar('('); return LPAREN; }
"["				{ tokenChar('['); return LSBRACKET; }
"]"				{ tokenChar(']'); return RSBRACKET; }

"+"				{ tokenChar('+'); return PLUS; }
"-"				{ tokenChar('-'); return MINUS; }
"*"				{ tokenChar('*'); return MULTIP; }
"/"				{ tokenChar('/'); return DIVIDE; }
"mod"				{ token(mod); return MOD; }
":="				{ token(:=); return ASSIGN; }
"<"				{ tokenChar('<'); return LESS; }
"<="				{ token(<=); return LESSEQ; }
"<>"				{ token(<>); return NOTEQ; }
">="				{ token(>=); return GREQ; }
">"				{ tokenChar('>'); return GREATER; }
"="				{ tokenChar('='); return EQ; }
"and"				{ token(and); return AND; }
"or"				{ token(or); return OR; }
"not"				{ token(not); return NOT; }

"array"				{ token(KWarray); return KARRAY; }
"begin"				{ token(KWbegin); return KBEGIN; }
"boolean"			{ token(KWboolean); yylval.text = "boolean"; return KBOOL; }
"def"				{ token(KWdef); return KDEF; }
"do"				{ token(KWdo); return KDO; }
"else"				{ token(KWelse); return KELSE; }
"end"				{ token(KWend); return KEND; }
"false"				{ token(KWfalse); yylval.constant.type = "boolean"; yylval.constant.data.text = "false"; return KFALSE; }
"for"				{ token(KWfor); return KFOR; }
"integer"			{ token(KWinteger); yylval.text = "integer"; return KINTEGER; }
"if"				{ token(KWif); return KIF; }
"of"				{ token(KWof); return KOF; }
"print"				{ token(KWprint); return KPRINT; }
"read"				{ token(KWread); return KREAD; }
"real"				{ token(KWreal); yylval.text = "real"; return KREAL; }
"string"			{ token(KWstring); yylval.text = "string"; return KSTRING; }
"then"				{ token(KWthen); return KTHEN; }
"to"				{ token(KWto); return KTO; }
"true"				{ token(KWtrue); yylval.constant.type = "boolean"; yylval.constant.data.text = "true"; return KTRUE; }
"return"			{ token(KWreturn); return KRET; }
"var"				{ token(KWvar); return KVAR; }
"while"				{ token(KWwhile); return KWHILE; }

{octal} { tokenOctInteger("oct_integer",yytext);}
{identifier}			{ tokenString("id",yytext); }
{integer}			{ tokenInteger("integer",atoi(yytext)); }
{float}				{ tokenFloat("float",yytext); }
{scientific}			{ tokenScientific("scientific", yytext); }

\"((\"\")|[^\"\n])*\"	{
				LIST;
				size_t wrt_idx = 0;
				size_t rd_idx = 1;
				int quote = 0;
				while( yytext[rd_idx] ){
					if( yytext[rd_idx] == '\"' ){
						if( quote )
							strContent[wrt_idx++] = '\"';
						quote = ~quote;
					}
					else
						strContent[wrt_idx++] = yytext[rd_idx];
					rd_idx++;
				}
				strContent[wrt_idx] = '\0';
				yylval.constant.type = "string";
				yylval.constant.data.text = yytext;
				if (Opt_T){
					printf("<%s: %s>\n", "string", strContent);
				}
				return STRING;
			}

"//&"[A-Z][+-][^\n]*		{ /* pseudo comment */
				  LIST;
				  setPseudoComment( yytext );
				}
"//"				{ /* C++ stype comment */
				  LIST;
				  BEGIN COMMENT_CPP;
				}

<COMMENT_CPP>[^\n]+		{
				  LIST;
				}

<COMMENT_CPP>"\n"		{
				  LIST;
				  if( Opt_S )
				  	printf("%d: %s",  linenum,  buf);
				  linenum++;
				  buf[0] = '\0';
				  BEGIN INITIAL;
				}

"/*"				{ /* C-style comment */
				  LIST;
				  BEGIN COMMENT;
				}
<COMMENT>"*/"			{
				  LIST;
				  BEGIN INITIAL;
				}
<COMMENT>"\n"			{
				  LIST;
				  if  (Opt_S)
				  	printf("%d: %s",  linenum,  buf);
				  linenum++;
				  buf[0] = '\0';
				}
<COMMENT>.			{
				  LIST;
				}

{whitespace}			{ 
				  LIST; 
				}

\n 				{
				  LIST;
				  if  (Opt_S)
				  	printf("%d: %s",  linenum,  buf);
				  linenum++;
				  buf[0] = '\0';
		   		}

.				{
				  /* error */
				  printf("error at line %d: bad character \"%s\"\n", linenum, yytext );
				  exit(-1);
				}

%%
/*int  main( int argc, char **argv )
{
	if( argc != 2 ) {
		fprintf(  stdout,  "Usage:  ./scanner  [filename]\n"  );
		exit(0);
	}

	FILE *fp = fopen( argv[1], "r" );
	
	if( fp == NULL )  {
		fprintf( stdout, "Open  file  error\n" );
		exit(-1);
	}
	
	yyin = fp;
	yylex();
	exit(0);
}*/

void setPseudoComment( const char *text )
{
	/* format : //&[A-Z][+-] */
	switch( text[3] ) {
	 case 'S':
		if( text[4] == '+' )
			Opt_S = 1;
		else if( text[4] == '-' )
			Opt_S = 0;
		break;
	 case 'T':
		if( text[4] == '+' )
			Opt_T = 1;
		else if( text[4] == '-' )
			Opt_T = 0;
	 	break;
	 case 'D':
	 	if( text[4] == '+' )
			Opt_D = 1;
		else if( text[4] == '-' )
			Opt_D = 0;
	 	break;
	 default:
	 	break;
	}

}


