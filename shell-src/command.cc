
#include "command.hh"
#include "shell.hh"
#include <unistd.h>
#include <fcntl.h>
#include <cstring>
#include <sys/wait.h> 

int stopFork = 0;
bool commandRunning = 0;
int last_child_running = -1;
bool ctrlcBackground = 0;
int lastBackGround = -1;
char * shellPath = NULL;
char * lastcmdarg = NULL;
int lastexitcode = -10000;

Command::Command() {
    // Initialize a new vector of Simple Commands
    _simpleCommands = std::vector<SimpleCommand *>();

    _outFile = NULL;
    _inFile = NULL;
    _errFile = NULL;
    _background = false;
}

void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
    // add the simple command to the vector
    _simpleCommands.push_back(simpleCommand);
}

void Command::clear() {
    // deallocate all the simple commands in the command vector
    for (auto simpleCommand : _simpleCommands) {
        delete simpleCommand;
    }

    // remove all references to the simple commands we've deallocated
    // (basically just sets the size to 0)
    _simpleCommands.clear();

   if ( _outFile ) {
        delete _outFile;
    }
    _outFile = NULL;

    if ( _inFile ) {
        delete _inFile;
    }
    _inFile = NULL;

    if ( _errFile ) {
        delete _errFile;
    }
    _errFile = NULL;

    _background = false;
}

void Command::print() {
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    int i = 0;
    // iterate over the simple commands and print them nicely
    for ( auto & simpleCommand : _simpleCommands ) {
        printf("  %-3d ", i++ );
        simpleCommand->print();
    }

    printf( "\n\n" );
    printf( "  Output       Input        Error        Background\n" );
    printf( "  ------------ ------------ ------------ ------------\n" );
    printf( "  %-12s %-12s %-12s %-12s\n",
            _outFile?_outFile->c_str():"default",
            _inFile?_inFile->c_str():"default",
            _errFile?_errFile->c_str():"default",
            _background?"YES":"NO");
    printf( "\n\n" );
}

void Command::execute() {
    
    //commandRunning = 1;
/*
    if (Shell::_currentCommand._background == 0) {
    	//ctrlcBackground = 0;
    } else {
//	ctlcBackground = 1;
    }
  */
	//fprintf(stderr, "is this bvar %s\n", Shell::_currentCommand._simpleCommands[1]->_arguments[1]->c_str());
	if (Shell::_currentCommand.redirectValid == 0) {
		printf("Ambiguous output redirect.\n");
		clear();
		//printf("after clear\n");
		Shell::_currentCommand.redirectValid = 1;
		if (isatty(0)) {
		Shell::prompt();
		}
		return;
	}
       if ( _simpleCommands.size() == 0 ) {
       if (isatty(0)) {
       Shell::prompt();
       }
       return;
   }
    int index_last = Shell::_currentCommand._simpleCommands[Shell::_currentCommand._simpleCommands.size() - 1]->_arguments.size()-1;
	if (lastcmdarg) {
		free(lastcmdarg);
	}
	lastcmdarg=strdup(Shell::_currentCommand._simpleCommands[Shell::_currentCommand._simpleCommands.size()-1]
->_arguments[index_last]->c_str());
   //print();
    if (Shell::_currentCommand._background == 0) {
	commandRunning = 1;
    } 
    if (strcmp(Shell::_currentCommand._simpleCommands[0]->_arguments[0]->c_str(), "setenv") == 0) {
	//assume for now both A and B exist	
	setenv(Shell::_currentCommand._simpleCommands[0]->_arguments[1]->c_str(), Shell::_currentCommand._simpleCommands[0]->_arguments[2]->c_str(), 1);
	if (isatty(0)) {
		Shell::prompt();
	}
	commandRunning = 0;
	clear();
	return;
    }
    if (strcmp(Shell::_currentCommand._simpleCommands[0]->_arguments[0]->c_str(), "unsetenv") == 0) {
	unsetenv(Shell::_currentCommand._simpleCommands[0]->_arguments[1]->c_str());
	if (isatty(0)) {
	Shell::prompt();
	}
	commandRunning = 0;
	clear();
	return;
    } 
    if (strcmp(Shell::_currentCommand._simpleCommands[0]->_arguments[0]->c_str(), "cd") == 0) {
	if (Shell::_currentCommand._simpleCommands[0]->_arguments.size() > 1) {
		int result = chdir(Shell::_currentCommand._simpleCommands[0]->_arguments[1]->c_str());		
		if (result == -1) {
			fprintf(stderr, "cd: can't cd to %s\n", Shell::_currentCommand._simpleCommands[0]->_arguments[1]->c_str()); 
			clear();
			Shell::prompt();
			commandRunning = 0;
			return;
		}
	} else {
		char * home = getenv("HOME");
		chdir(home);			
	}
	if (isatty(0)) {	
	Shell::prompt();
	}
	commandRunning = 0;
	clear();
	return;
    } 
    // Don't do anything if there are no simple commands
    int tmp1 = dup(0);
    int tmp2 = dup(1);
    int tmp3 = dup(2);
    if (strcmp(Shell::_currentCommand._simpleCommands[0]->_arguments[0]->c_str(), "exit") == 0) {
	free(lastcmdarg);
	close(tmp1);
	close(tmp2);
	close(tmp3);
	exit(0);
    }
    // Print contents of Command data structure
    //print();

    // Add execution here
    // For every simple command fork a new process
    // Setup i/o redirection
    // and call exec
    int inFile;
    if (Shell::_currentCommand._inFile != NULL) {
	inFile = open(Shell::_currentCommand._inFile->c_str(), O_RDONLY);
    } else {
	inFile = dup(0);
    }
    int errFile = -1;
    int outFile = -1;
    if (Shell::_currentCommand._errFile != NULL) {
	if (errAppend) {
		errFile = open(Shell::_currentCommand._errFile->c_str(), O_CREAT|O_WRONLY|O_APPEND, 0664);
	} else {
		errFile = open(Shell::_currentCommand._errFile->c_str(), O_TRUNC|O_WRONLY|O_CREAT, 0664);
	}
    } else {
	errFile = tmp3;
    }
    dup2(errFile,2);
    //fprintf(stderr, "hi");
    int ret;
    for (unsigned long int i = 0; i < Shell::_currentCommand._simpleCommands.size(); i++) {
	if (i == Shell::_currentCommand._simpleCommands.size() - 1) {
		//fprintf(stderr, "hello");
		dup2(inFile, 0);
		close(inFile);
		if (Shell::_currentCommand._outFile != NULL) {
			if (outAppend) {
				outFile = open(Shell::_currentCommand._outFile->c_str(), O_WRONLY | O_APPEND | O_CREAT, 0664);
			} else {
				outFile = open(Shell::_currentCommand._outFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0664);
			}
		} else {
			outFile = tmp2;
		}
	} else {
		dup2(inFile, 0);
		close(inFile);
		int fdp[2];
		pipe(fdp);
		outFile = dup(fdp[1]);
		inFile = dup(fdp[0]);
		close(fdp[1]);
		close(fdp[0]);
	}
	dup2(outFile, 1);
	close(outFile);
	
	if (stopFork) {
		break;
	}	
	ret = fork();
	if (ret == 0) {
	if (strcmp(Shell::_currentCommand._simpleCommands[i]->_arguments[0]->c_str(), "printenv") == 0		) {
     	int i = 0;
      	while (environ[i] != NULL) {
              printf("%s\n", environ[i]);
              i++;
      	}
      	printf("\n");
	//close(fdp[1]);
	//close(fdp[0]);
	exit(0);
   	} else {
	
		unsigned long int j;
		char * argvs[Shell::_currentCommand._simpleCommands[i]->_arguments.size() + 1];
		for (j = 0; j < Shell::_currentCommand._simpleCommands[i]->_arguments.size(); j++) {
			char * str = (char*)malloc(Shell::_currentCommand._simpleCommands[i]->_arguments[j]->length() + 1);
			memcpy(str, Shell::_currentCommand._simpleCommands[i]->_arguments[j]->c_str(), Shell::_currentCommand._simpleCommands[i]->_arguments[j]->length() + 1);
			argvs[j] = str;
		}
		argvs[j] = NULL;
		//printf("%s", Shell::_currentCommand._simpleCommands[i]->_arguments[0]->c_str());
		execvp(Shell::_currentCommand._simpleCommands[i]->_arguments[0]->c_str(), argvs);	
	    perror("execvp");
		exit(1);					
	}
	}
	last_child_running = ret;
	
    } 
    // Clear to prepare for next command
    if (!Shell::_currentCommand._background) {	
	int wstatus; 
	waitpid(ret, &wstatus, 0);
	if (WIFEXITED(wstatus)) 
		lastexitcode = WEXITSTATUS(wstatus);
    } else {
	lastBackGround = ret;
    }
    clear();
    dup2(tmp1, 0);
    dup2(tmp2, 1);
    dup2(tmp3, 2);
    close(tmp1);
    close(tmp2);
    close(tmp3);
    if (-1 == errFile) {
	close(errFile);
    }
    if (outFile == -1) {
	close(outFile);
    }
    // Print new prompt
    if (isatty(0)) {
    	Shell::prompt();
    }
    ctrlcBackground = 0;
    commandRunning = 0;
    last_child_running = -1;
    stopFork = 0;

}

SimpleCommand * Command::_currentSimpleCommand;

