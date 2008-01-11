#ifndef RBS_ENVIRON_H
#define RBS_ENVIRON_H

struct rubinius_environment {
  pthread_mutex_t mutex;
  struct hashtable *machines;
  char *platform_config;
  char *bootstrap_path;
  char *platform_path;
  char *core_path;
  char *loader_path;
  int machine_id;
};

typedef struct rubinius_environment *environment;

struct rubinius_global {
  environment e;
  machine m;
};

environment environment_new();
void environment_at_startup();
void environment_setup_thread(environment e, machine m);
environment environment_current();
machine environment_current_machine();
void environment_add_machine(environment e, machine m);
int environment_del_machine(environment e, machine m);
int environment_load_machine(environment e, machine m);
void environment_start_thread(environment e, machine m);
void environment_exit_machine();
int environment_join_machine(environment e, int id);

#endif
