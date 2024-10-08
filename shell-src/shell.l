
/*
 *
 * CS-252 
 * shell.l: lexical analyzer for shell
 * You have to extend it.
 *
 */

%{

#include <cstring>
#include "y.tab.hh"
#include <sys/wait.h>
#include <sys/types.h>
#include <fcntl.h>              /* Definition of O_* constants */
#include <unistd.h>
#include <regex.h>

static  void yyunput (int c,char *buf_ptr  );
FILE * global_fp = NULL;
bool global_yyinrestart = false;
FILE * source_fp = NULL;

void myunputc(int c) {
  unput(c);
}

int yypop_flag=0;

%}

%option noyywrap
%x s_mode

%%

"\n" {
  return NEWLINE;
}

[ \t] {
  /* Discard spaces and tabs */
}

">" {
  return GREAT;
}
">>" {
  return GREATGREAT;
}
"<" {
	return LESS;
}
"|" {
	return PIPE;
    }
"2>" {
	return TWOGREAT;
}
"&" {
	return AMPERSAND;
}
">>&" {
	return GREATGREATAMPERSAND;
}
">&" {
	return GREATAMPERSAND;
}
"2>&1" {
	return TWOGREATAMPERSANDONE;
}

^[ \t]*source[ \t]* {
	BEGIN(s_mode);
}

<s_mode>[^ \n\t]+ {
	yytext[yyleng] = '\0';
	source_fp = fopen(yytext, "r+");
	//fputc('\n', fp);
	if (!source_fp) {
		printf("source could not open file\n");
	} else {
		yypush_buffer_state(yy_create_buffer(source_fp, YY_BUF_SIZE));
		BEGIN(INITIAL);
		yypop_flag = 1;
	}        			
}

<<EOF>> {
	if (yypop_flag == 1) {
		fclose(source_fp);
		yypop_buffer_state();
		yypop_flag = 0;
	} else if (global_yyinrestart) {
		global_yyinrestart = false;
		//YY_BUFFER_STATE mybuffer = yy_create_buffer(stdin, YY_BUF_SIZE);
		fclose(global_fp);
		yyrestart(stdin);
	}else {
		return 0;
	}
}

\'[^\n]+\'|\$\([^\n]+\) {
	char subshell[yyleng+15];
	int count;
	if (yytext[0] == '\'') {
		int i;
		for (i = 1; i < yyleng - 1; i++) {
			subshell[i - 1] = yytext[i];
		}
		subshell[i - 1] = '\0';
		count = yyleng - 2;
	} else {
		int i;
		for (i = 2; i < yyleng - 1; i++) {
			subshell[i - 2] = yytext[i];
		}	
		subshell[i - 2] = '\0';
		count = yyleng-3;
	}
	int j = strlen(subshell);
	subshell[j] = '\n';
	subshell[j+1] = 'e';
	subshell[j+2] = 'x';
	subshell[j+3] = 'i';
	subshell[j+4] = 't';
	subshell[j+5] = '\n';
	subshell[j+6] = '\0';
	count = count + 6;
	//printf("subshell command:%s\n", subshell);
	int p_in[2];
	pipe2(p_in, O_NONBLOCK);
	int p_out[2];
	pipe(p_out);
	//printf("%s", subshell);
	int ret = fork();
	if (ret == -1) {
		perror("fork failed");
		exit(1);
	}
	if (ret ==  0) {
		dup2(p_in[0], 0);
		dup2(p_out[1], 1);
		close(p_in[1]);
		close(p_out[0]);
		close(p_out[1]);
		close(p_in[0]);
		char * args[2];
		args[0] = (char*)malloc(500);		
		strcpy(args[0], "/proc/self/exe");
		//fprintf(stderr, "args[0]:%s\n", args[0]);
		//strcpy(args[0], "/usr/local/bin/bash");
		args[1] = NULL;
		execvp(args[0], args);
		perror("execvp didn't work");
		exit(1);				
	} else {
		close(p_in[0]);
		close(p_out[1]);
		for (int i = 0; i < count; i++) {
			write(p_in[1], &subshell[i], 1);
			//printf("writen c:%c\n", subshell[i]);
		}
		close(p_in[1]);
		//write(p_in[1], subshell, strlen(subshell));	
		char c;
		int  bufsize=100;
		char *result = (char *) malloc(bufsize);
		int ind = 0;
		waitpid(ret, NULL, 0);
		//fprintf(stderr, "waitpid:child process done\n");
		while(read(p_out[0], &c, 1)) {
			if (c == '\n') {
				c = '\t';
			}
			result[ind] = c;
			ind++;
			if ((ind + 2) ==bufsize) {
				bufsize = bufsize*2;
				char * ptr = (char *) realloc(result,bufsize);
				if (!ptr) {
					fprintf(stderr, "realloc() failed.\n");
					exit(1);
				} 
				result = ptr;
			}
			//fprintf(stderr, "child output char: %c\n", c);
		}
		result[ind] = ' ';
		close(p_out[0]);
		for (int h = ind - 1; h >= 0; h--) {
			unput(result[h]);
		}
		free(result);			
	}	
}

[^ \t\n<>|&"\\][^ \t\n<>|&"\\]*  {
  //fprintf(stderr, "regular word:%s\n", yytext);
  /* Assume that file names have only alpha chars */
  yylval.cpp_string = new std::string(yytext);
  //printf ("%s ", yytext);
  return WORD;
}




["][^\n\"]*["] {
        yylval.cpp_string = new std::string(yytext);
        yylval.cpp_string->erase(0, 1);
	yylval.cpp_string->erase(yylval.cpp_string->length() - 1, 1);
///handle case where last char is \

	for (int i = 0; i < yylval.cpp_string->length() - 1; i++) {
		if (yylval.cpp_string->at(i) == '\\') {
			yylval.cpp_string->erase(i, 1);	
		}
	}
        return WORD;
}

[^ \n\t]*\\[^ \n\t]* {
	//fprintf(stderr, "\\ matched:%s\n",yytext);
	yylval.cpp_string = new std::string(yytext);
	//handle case where lat char is "\"
	char str[yyleng + 1];
	int strindex = 0;	
        for (int i = 0; i < yylval.cpp_string->length(); i++) {
                if (yylval.cpp_string->at(i) == '\\') {
			if (yylval.cpp_string->at(i + 1) != '\\') {
				continue;
			} else {
                        	while((i + 1) < yyleng && yylval.cpp_string->at(i+1) == '\\') {
					i++;
				}
				str[strindex] = yylval.cpp_string->at(i);
				strindex++;
			}			
                } else {
			str[strindex] = yylval.cpp_string->at(i);
			//printf("%c\n", str[strindex]);

			strindex++;
		}
        }
	str[strindex] = '\0';
	delete yylval.cpp_string;
	yylval.cpp_string = new std::string(str);	
	//fprintf(stderr, "WORD:%s\n", yylval.cpp_string->c_str()); 
	return WORD;				

}

