#include <stdio.h>
#include "iphone_frotz.h"

const char *AUTOSAVE_FILE = "FrotzSIP.sav";

int do_autosave = 0, autosave_done =1;

void iphone_putchar(char c) {
   if (cwin != 7)
      putchar(c);
}

void iphone_puts(char *s) {
   fputs(s, stdout);
}

void iphone_disable_input() {
}

void iphone_enable_input() {
}

int iphone_getchar() {
  return getchar();
}

int iphone_textview_height, iphone_textview_width;
void iphone_enable_single_key_input() {
}

int iphone_read_file_name(char *file_name, const char *default_name, int flag) {
}

void iphone_more_prompt() {
}

extern int autorestore;

int iphone_main(int argc, char *argv) {
   init_buffer ();

    init_err ();

    init_memory ();

    init_interpreter ();

    init_sound ();

    os_init_screen ();

    init_undo ();

    z_restart ();

    if (autorestore) {
	do_autosave = 1;
	z_restore();
	do_autosave = 0;
    }
    interpret ();

    reset_memory ();

    os_reset_screen ();

    return 0;
}

void acs_map() {
}
