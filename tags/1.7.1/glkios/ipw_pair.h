/* ipw_pair.h: The pair window header
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#ifndef IPW_PAIR_H
#define IPW_PAIR_H

typedef struct window_pair_struct {
    window_t *owner;

    window_t *child1, *child2; 
    int splitpos; /* The split center. To be picky, this is the position
        of the top of the border, or the top of the bottom window if the
        border is zero-width. (If vertical is true, rotate this comment
        90 degrees.) */
    int splitwidth; /* The width of the border. Zero or one. */
    
    /* split info... */
    glui32 dir; /* winmethod_Left, Right, Above, or Below */
    int vertical, backward, hasborder; /* flags */
    glui32 division; /* winmethod_Fixed or winmethod_Proportional */
    window_t *key; /* NULL or a leaf-descendant (not a Pair) */
    int keydamage; /* used as scratch space in window closing */
    glui32 size; /* size value */
    
} window_pair_t;

extern window_pair_t *win_pair_create(window_t *win, glui32 method, 
    window_t *key, glui32 size);
extern void win_pair_destroy(window_pair_t *dwin);
extern void win_pair_rearrange(window_t *win, grect_t *box);
extern void win_pair_redraw(window_t *win);

#endif