#include <cstdio>

#include <signal.h>

#include "shell.hh"

#include <sys/wait.h>

#include <unistd.h>

int yyparse(void);
extern FILE * yyin;
extern FILE * global_fp;
extern bool global_yyinrestart;

void Shell::prompt() {
  if(isatty(0)){
 	 printf("myshell>");
  	fflush(stdout);
  }
}

void handle_ctrlC(int sig) {
	
	if (commandRunning) {
		kill(last_child_running, SIGTERM);
		stopFork = 1;			
	} else {	
		printf("\n");
		Shell::prompt();	
	}
	
}

void removeZombie(int sig) {
	while (waitpid(-1, NULL, WNOHANG) > 0) {
        }			
}

int main(int argc, char ** argv) {
   
  struct sigaction sa;
  sa.sa_handler = handle_ctrlC;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;
  if (sigaction(SIGINT, &sa, NULL)) {
	perror("sigaction");
	exit(2);
  }
  
    
  struct sigaction zombie;
  zombie.sa_handler = removeZombie;
  zombie.sa_flags = SA_RESTART;
  sigemptyset(&zombie.sa_mask);
  if (sigaction(SIGCHLD, &zombie, NULL)) {
	perror("sigchild");
	exit(2);
  }
 
  shellPath = (char*)malloc(200);
  realpath(argv[0], shellPath);
  if (isatty(0)) {
  	Shell::prompt();
  } 
  yyparse();
}

Command Shell::_currentCommand;
