#ifndef command_hh
#define command_hh

#include "simpleCommand.hh"

// Command Data Structure

extern bool commandRunning;
extern int last_child_running;
extern int stopFork;
extern bool ctrlcBackground;
extern int lastBackGround;
//extern bool redirectValid;
extern char * shellPath;
extern char * lastcmdarg;
extern int lastexitcode;

struct Command {
  std::vector<SimpleCommand *> _simpleCommands;
  std::string * _outFile;
  std::string * _inFile;
  std::string * _errFile;
  bool outAppend;
  bool errAppend;
  bool _background = 0;
  bool redirectValid = 1;
  Command();
  void insertSimpleCommand( SimpleCommand * simpleCommand );

  void clear();
  void print();
  void execute();

  static SimpleCommand *_currentSimpleCommand;

};

#endif
