
/*
 * CS-252
 * hell.y: parser for shell
 *
 * This parser compiles the following grammar:
 *
 *	cmd [arg]* [> filename]
 *
 * you must extend it to understand the complete shell grammar
 *
 */

%code requires 
{
#include <string>
#include <string.h>
#include <regex.h>
#include <unistd.h>

#if __cplusplus > 199711L
#define register      // Deprecated in C++11 so remove the keyword
#endif
}

%union
{
  char        *string_val;
  // Example of using a c++ type in yacc
  std::string *cpp_string;
}

%token <cpp_string> WORD
%token NOTOKEN GREAT NEWLINE GREATGREAT LESS PIPE TWOGREAT AMPERSAND GREATGREATAMPERSAND GREATAMPERSAND TWOGREATAMPERSANDONE
 
%{
//#define yylex yylex
#include <cstdio>
#include "shell.hh"
#include <sys/types.h>
 #include <pwd.h>
#include <vector>
#include <string>
#include <sys/types.h>
#include <dirent.h>
#include  <algorithm>

#define MAXFILENAME 1024

std::vector<std::string *> wildCards  = {};

void expandtilde(char *, char*);
void expandenv(char *,  char *);
void expandWildcard(char *, char *);
bool compfunc(std::string *, std::string *);

void yyerror(const char * s);
int yylex();
%}

%%

goal:
  command_list
  ;

command_list:
  command_line
  | command_list command_line
  ;

command_line: 
pipe_list io_modifier_list background_optional NEWLINE {
	Shell::_currentCommand.execute();	
} | NEWLINE {
	Shell::_currentCommand.execute();
}
| error NEWLINE{yyerrok;} 
       ;

io_modifier_list:
	io_modifier_list io_modifier {
		
	} | 
	
	;

background_optional:
	AMPERSAND {
		Shell::_currentCommand._background = 1;
	}| 
	
	;

pipe_list:
	cmd_and_args | pipe_list PIPE cmd_and_args
;

cmd_and_args:
  WORD {
	Command::_currentSimpleCommand = new SimpleCommand();
	//printf("%s ", $1);
	Command::_currentSimpleCommand->insertArgument($1);
  }arg_list {
	Shell::_currentCommand.insertSimpleCommand(Command::_currentSimpleCommand);
  }
  ;

arg_list:
  arg_list WORD {
	//printf("%s", $2);
	char midresult[MAXFILENAME];
	char * source = strdup($2->c_str());
	expandenv(source, midresult);
	free(source);
	char result[MAXFILENAME];
	expandtilde(midresult, result);
	delete $2;
	if ((strchr(result, '*') || strchr(result, '?'))) { 
		char prefix[MAXFILENAME];
		prefix[0]='\0';	
		expandWildcard(prefix, result);
		if (wildCards.size() == 0) {
			wildCards.push_back(new std::string(result));
		}
		//printf("size:%d\n", wildCards.size());
		std::sort(wildCards.begin(), wildCards.end(), compfunc);
		for (int i = 0; i < wildCards.size(); i++) {
			Command::_currentSimpleCommand->insertArgument(wildCards.at(i));
		}
		wildCards.clear();					
	} else {
		$2 = new std::string(result);
		Command::_currentSimpleCommand->insertArgument($2);
	}
  }
  | /* can be empty */
  ;

io_modifier:
  	GREATGREAT WORD {
		if (Shell::_currentCommand._outFile == NULL) {
			Shell::_currentCommand._outFile = $2;
			Shell::_currentCommand.outAppend = 1;
		} else {
			Shell::_currentCommand.redirectValid = 0;
		}
	}
	 |
	GREAT WORD{
		if (Shell::_currentCommand._outFile == NULL) {
			Shell::_currentCommand._outFile = $2;
			Shell::_currentCommand.outAppend = 0;
		} else {
			Shell::_currentCommand.redirectValid = 0;
		}
	}  |
	GREATGREATAMPERSAND WORD {
		 if (Shell::_currentCommand._errFile == NULL) {
         		Shell::_currentCommand._errFile = $2;
         		Shell::_currentCommand.errAppend = 1;
		 }  else {
       			Shell::_currentCommand.redirectValid = 0;
			}
		  if (Shell::_currentCommand._outFile == NULL) {
          		Shell::_currentCommand._outFile = new std::string($2->c_str());
          		Shell::_currentCommand.outAppend = 1;
		  } else {
       			Shell::_currentCommand.redirectValid = 0;
		}


	} |
	GREATAMPERSAND WORD {
	   if (Shell::_currentCommand._errFile == NULL) {
          	 Shell::_currentCommand._errFile = $2;
          	 Shell::_currentCommand.errAppend = 0;
	   } else {
       		Shell::_currentCommand.redirectValid = 0;
	   }
	  if (Shell::_currentCommand._outFile == NULL) {
       		Shell::_currentCommand._outFile = new std::string($2->c_str());
         	Shell::_currentCommand.outAppend = 0;
 	  }
 	  else {
       		Shell::_currentCommand.redirectValid = 0;

	  }

	} |
	LESS WORD {
		if (Shell::_currentCommand._inFile == NULL) {
			//printf("%s", $2);
			Shell::_currentCommand._inFile = $2;
		} else {
       			Shell::_currentCommand.redirectValid = 0;
		}
	} |
	TWOGREAT WORD {
		if (Shell::_currentCommand._errFile == NULL) {
			Shell::_currentCommand._errFile = $2;
			Shell::_currentCommand.errAppend = 0;
		} else {
       			Shell::_currentCommand.redirectValid = 0;
		}

	} |
	TWOGREATAMPERSANDONE {
		if (Shell::_currentCommand._errFile == NULL) {
			if (Shell::_currentCommand._outFile != NULL) {
			
				char * str  = strdup(Shell::_currentCommand._outFile->c_str());
				Shell::_currentCommand._errFile = new std::string(str);
				free(str);
			
			}
		} else {
			 Shell::_currentCommand.redirectValid = 0;
		}
	}

  ;

%%

bool compfunc(std::string * a, std::string * b) {
	//printf("%s:%s\n", a, a->c_str());
	//printf("%s %s\n", a->c_str(), b->c_str());
	//printf("about to return\n");
	if (strcmp(a->c_str(), b->c_str()) > 0) {
		return 0;
	} else {
		return 1;
	}
}

void expandenv(char * source, char * result) {
	//fprintf(stderr, "%s", source);
	for (int i = 0; i < MAXFILENAME; i++) {
		result[i] = '\0';
	}	
	regex_t pattern;
	char * patt = "${[^}\n][^}\n]*}";
	int rc;
	size_t nmatch = 1;
	regmatch_t pmatch[1];
	int index = 0;	
	int srclen = strlen(source);
	 char * ogsource = source;
	if (regcomp(&pattern, patt, 0)) {
		fprintf(stderr, "regcomp didn't work\n");
		exit(0);
	}
	if (regexec(&pattern, source, nmatch, pmatch, 0)) {
		strcpy(result, source);
		result[strlen(source)] = '\0';
		//fprintf(stderr, "failed");
		regfree(&pattern);
		return; 
	}
	while(1) {		
		if (regexec(&pattern, source, nmatch, pmatch, 0)) {
			break;
		}
		memcpy(result + index, source, pmatch[0].rm_so);
		index = index + pmatch[0].rm_so;
		char e[pmatch[0].rm_eo - pmatch[0].rm_so - 2];
		strncpy(e, source + pmatch[0].rm_so + 2, pmatch[0].rm_eo - pmatch[0].rm_so - 3);
		e[(pmatch[0].rm_eo) - (pmatch[0].rm_so) -3] = '\0';
		char * enva;
		if (strcmp(e, "$") == 0) {
			enva = (char*)malloc(250);
			sprintf(enva, "%d", getpid());				
		} else if (strcmp(e, "?") == 0) {
			enva = (char*)malloc(250);
			sprintf(enva, "%d", lastexitcode);				
		} else if (strcmp(e, "!") == 0) {
			enva = (char*)malloc(250);
			sprintf(enva, "%d", lastBackGround);
		} else if (strcmp(e, "_") == 0) {
			enva = strdup(lastcmdarg);
		}  else if (strcmp(e, "SHELL") == 0) {
			enva = strdup(shellPath);
		} else {
		//fprintf(stderr,"e: %s\n", e); 
			enva = strdup(getenv(e));
		}
		if (enva) {
		
		//fprintf(stderr, "enva:%s", enva);
			for (int j = 0; j < strlen(enva); j++) {
				result[index] = enva[j];
				index++;
			}
			free(enva);
		}		
		source = source + pmatch[0].rm_eo;		
		if (source >= ogsource + srclen) {
			regfree(&pattern);
			return;
		}
	}
	strncpy(result + index, source, strlen(source));	
	regfree(&pattern);
}

void expandtilde(char * source, char * result) {
	for (int i = 0; i < MAXFILENAME; i++) {
		result[i] = '\0';
	}	
	if (source[0] != '~') {
		strcpy(result, source);
		return;
	}
	if (source[1] == '\0' || source[1] == '/') {
		char * home = strdup(getenv("HOME"));
		strncpy(result, home, strlen(home));
		strcpy(result + strlen(home), source + 1);
		free(home);
		return; 		
	} else {
		int i = 1;
		for (i; i < strlen(source); i++) {
			if (source[i] == '/') {
				break;
			}
		}	
		char user[i];
		user[i-1] = '\0';
		strncpy(user, source + 1, i - 1);
		struct passwd * password = getpwnam(user);
		char * home = strdup(password->pw_dir);
		strncpy(result, home, strlen(home));
		strcpy(result + strlen(home), source + i);
		free(home);
		return;			
	}
}





void expandWildcard(char * prefix, char *suffix) {
	if (suffix[0] == '/' && prefix[0] == '\0') {
		suffix = suffix + 1;
		prefix[0] = '/';
		prefix[1] = '\0';
	}	
	//fprintf(stderr,"%d", suffix[0]);
	if (suffix[0] == '\0') {
	// suffix is empty. Put prefix in argument.
		//fprintf(stderr, "%s", prefix);
		std::string * ststr = new std::string(prefix);
		wildCards.push_back(ststr);
		return;
	}
	// Obtain the next component in the suffix
	// Also advance suffix.
	char * s = strchr(suffix, '/');
	//component is beginning of suffx that needs to be wildcard expanded
	char component[MAXFILENAME];
	if (s!=NULL){ // Copy up to the first “/”
		strncpy(component, suffix, s-suffix);
		component[s-suffix]='\0';
		suffix = s + 1;
		 //fprintf(stderr, "suffix:%s\ncomponent%s\n", suffix,component);
	} else { // Last part of path. Copy whole thing.
		strcpy(component, suffix);
		suffix = suffix + strlen(suffix);
		 //fprintf(stderr, "suffix:%s\ncomponent%s\n", suffix,component);
	}
// Now we need to expand the component
/// doesnt check to see if prefix is valid path before calling expandWildcard again
	char newPrefix[MAXFILENAME];
	if (strchr(component, '*')==NULL && strchr(component, '?')==NULL) {
		// component does not have wildcards
		//fprintf(stderr, "word:%s\ncomponent:%s\n", prefix, component);
		if (strcmp(prefix, "/")==0) {
			sprintf(newPrefix,"%s%s", prefix, component);
		} else { 
			sprintf(newPrefix,"%s/%s", prefix, component);
		}
		expandWildcard(newPrefix, suffix);
		return;
	}
	// Component has wildcards
	// Convert component to regular expression
	char * reg = (char*)malloc(2*strlen(component)+10);
	char * a = component;
	char * r = reg;
	*r = '^'; r++; // match beginning of line
	while (*a) {
		if (*a == '*') { *r='.'; r++; *r='*'; r++; }
		else if (*a == '?') { *r='.'; r++;}
		else if (*a == '.') { *r='\\'; r++; *r='.'; r++;}
		else { *r=*a; r++;}
			a++;
	}
	*r='$'; r++; *r=0;// match end of line and add null char
	
	regex_t pattern;
	size_t nmatch = 1;
	regmatch_t pmatch[1];
	if (regcomp(&pattern, reg, 0)) {
        	fprintf(stderr, "regcomp didn't work\n");
        	exit(0);
	}
	free(reg);
	char * dir = (char *) malloc(1000);
	// If prefix is empty then list current directory
	if (prefix[0] == '\0') 
		strcpy(dir, "."); 
	else 
		strcpy(dir, prefix);
	DIR * d=opendir(dir);
	struct dirent * ent;
	if (d==NULL){
		free(dir); 
		regfree(&pattern);
		return;
	}
	// Now we need to check what entries match
	while (( ent = readdir(d))!= NULL) {
		// Check if name matches
		if (!regexec(&pattern, ent->d_name, nmatch, pmatch, 0)) {
			// Entry matches. Add name of entry
			// that matches to the prefix and
			// call expandWildcard(..) recursively
			if (ent->d_name[0]=='.' && component[0]!='.') 
				continue;
			if (strcmp(prefix, "/")==0 || dir[0]=='.') {
        	                 sprintf(newPrefix,"%s%s", prefix, ent->d_name);
                	} else {
                        	 sprintf(newPrefix,"%s/%s", prefix, ent->d_name);
                 	}
 
			expandWildcard(newPrefix,suffix);
		}
	}
	free(dir);
	closedir(d);
	regfree(&pattern);	
}// expandWildcard


void
yyerror(const char * s)
{
  fprintf(stderr,"%s", s);
}

#if 0
main()
{
  yyparse();
}
#endif
