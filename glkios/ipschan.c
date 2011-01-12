/* gtschan.c: Sound channel objects
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#include "gtoption.h"
#include <stdio.h>
#include <wchar.h>
#include "glk.h"
#include "glkios.h"

/* The whole sound-channel situation is very simple for us;
   we don't support it. */

#ifdef GLK_MODULE_SOUND

schanid_t glk_schannel_create(glui32 rock)
{
  return NULL;
}

void glk_schannel_destroy(schanid_t chan)
{
}

schanid_t glk_schannel_iterate(schanid_t chan, glui32 *rockptr)
{
  if (rockptr)
    *rockptr = 0;
  return NULL;
}

glui32 glk_schannel_get_rock(schanid_t chan)
{
  gli_strict_warning(L"schannel_get_rock: invalid id.");
  return 0;
}

glui32 glk_schannel_play(schanid_t chan, glui32 snd)
{
  gli_strict_warning(L"schannel_play: invalid id.");
  return 0;
}

glui32 glk_schannel_play_ext(schanid_t chan, glui32 snd, glui32 repeats,
    glui32 notify)
{
  gli_strict_warning(L"schannel_play_ext: invalid id.");
  return 0;
}

void glk_schannel_stop(schanid_t chan)
{
  gli_strict_warning(L"schannel_stop: invalid id.");
}

void glk_schannel_set_volume(schanid_t chan, glui32 vol)
{
  gli_strict_warning(L"schannel_set_volume: invalid id.");
}

void glk_sound_load_hint(glui32 snd, glui32 flag)
{
  gli_strict_warning(L"schannel_sound_load_hint: invalid id.");
}

#endif /* GLK_MODULE_SOUND */
