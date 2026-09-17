#ifndef RETROLIFE_UPDATER_H
#define RETROLIFE_UPDATER_H
/* Main-thread-only, versioned JSON ABI. Free every returned string. */
char *rl_updater_command(const char *command);
void rl_updater_free(char *value);
#endif
