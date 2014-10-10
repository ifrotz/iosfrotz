//
// Glk Classes autosave/restore code based on CellarDoor (PalmOS) by Jeremy Bernstein
// Code below is from glk/glkop.c in CellarDoor 1.1.2 (GPLv2), with minor modifications.
//
///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

#define FrotzGlkClassChunkVersionNumV1 0x01000001
#define FrotzGlkClassChunkVersionNumV2 0x01000002
#define FrotzGlkClassChunkVersionNumV3 0x01000003
#define FrotzGlkClassChunkVersionNumV4 0x01000004
#define FrotzGlkClassChunkVersionNumCurrent FrotzGlkClassChunkVersionNumV4

static glui32 kFrotzGlkClassChunkVersionNumForSave = FrotzGlkClassChunkVersionNumCurrent;

struct glk_window_autosave {
    glui32 magicnum;
    glui32 rock;
    glui32 type;
    
    grect_t bbox;
    
    union {
        struct {
            int line_request;
            int line_request_uni;
            int char_request;
            int char_request_uni;
        } v1;
        struct {
            int reqFlags;
            int pad1, pad2, pad3;
        } v2;
    } requ;
    
    glui32 style;
    glui32 size;
    glui32 method;
    glui32 splitwin;
    
    char *inbuf; // textbuffer type only
    int inmax;
};

#define kInvalidSplitWin (0xFFFFFFFF)


struct glk_stream_autosave {
    glui32 magicnum;
    glui32 rock;
    
    int type; /* file, window, or memory stream */
    int unicode; /* one-byte or four-byte chars? Not meaningful for windows */
    
    glui32 readcount, writecount;
    int readable, writable;
    
    unsigned char *buf;
    unsigned char *bufptr;
    unsigned char *bufend;
    unsigned char *bufeof;
    glui32 *ubuf;
    glui32 *ubufptr;
    glui32 *ubufend;
    glui32 *ubufeof;
    glui32 buflen;
};

struct glk_fileref_autosave {
    glui32 magicnum;
    glui32 rock;
    
    int filetype;
    int textmode;
    
    char filename[48];
    
};

struct glk_winpair_autosave {
    int splitpos;
    int splitwidth; /* The width of the border. Zero or one. */
    
    glui32 dir; /* winmethod_Left, Right, Above, or Below */
    int vertical, backward; /* flags */
    glui32 division; /* winmethod_Fixed or winmethod_Proportional */
    
    glui32 size; /* size value */
    
    glui32 child1, child2; // child windows IDs
};

struct glk_wingraphics_autosave {
    int width, height;
    glui32 backcolor;
};

struct glk_object_save {
    glui32    type; // 0 = window, 1 = stream, 2 = file, 3 = sound, 0xFFFFFFFF = style
    glui32    id; // for style, this is the id of the owning window, or 0xFFFFFFF1 for buffer or 0xFFFFFFF2 for grid
    union {
        struct glk_window_autosave win;
        struct glk_stream_autosave str;
        struct glk_fileref_autosave fref;
        struct glk_winpair_autosave pair;
        struct glk_wingraphics_autosave gfx;
        GLK_STYLE_HINTS style[style_NUMSTYLES];
    } obj;
    int        iscurrent;
};

#define type_Style     0xFFFFFFFF
#define type_Pair      0xFFFFFFFE
#define type_Graphics  0xFFFFFFFD

enum kGlkReqBits { kGlkReqLine=1, kGlkReqLineUni=2, kGlkReqChar=4, kGlkReqCharUni=8, kGlkReqMouse=16, kGlkReqHyper=32, kGlkReqNoEchoLine=64 };

typedef struct glk_object_save glk_object_save_t;

static int wingfxcount = 0;

static void saveWin(window_t *win, struct glk_window_autosave *s) {
    s->magicnum = win->magicnum;
    s->rock = win->rock;
    s->type = win->type;
    
    s->bbox = win->bbox;
    
    if (kFrotzGlkClassChunkVersionNumForSave == FrotzGlkClassChunkVersionNumV1) {
        s->requ.v1.line_request = win->line_request;
        s->requ.v1.line_request_uni = win->line_request_uni;
        s->requ.v1.char_request = win->char_request;
        s->requ.v1.char_request_uni = win->char_request_uni;
    } else {
        s->requ.v2.reqFlags = 0;
        if (win->line_request) s->requ.v2.reqFlags |= kGlkReqLine;
        if (win->line_request_uni) s->requ.v2.reqFlags |= kGlkReqLineUni;
        if (win->char_request) s->requ.v2.reqFlags |= kGlkReqChar;
        if (win->char_request_uni) s->requ.v2.reqFlags |= kGlkReqCharUni;
        if (win->mouse_request) s->requ.v2.reqFlags |= kGlkReqMouse;
        if (win->hyper_request) s->requ.v2.reqFlags |= kGlkReqHyper;
        if (!win->echo_line_input) s->requ.v2.reqFlags |= kGlkReqNoEchoLine;
        s->requ.v2.pad1 = s->requ.v2.pad2 = s->requ.v2.pad3 = 0;
    }
    if (win->type == wintype_TextBuffer) {
        window_textbuffer_t *wtb = (window_textbuffer_t*)win->data;
        s->inbuf = wtb->inbuf;
        s->inmax = wtb->inmax;
    } else {
        s->inbuf = NULL;
        s->inmax = 0;
    }
    s->style = win->style;
    s->size = win->size;
    if (win->type == wintype_Graphics)
        iphone_save_glk_win_graphics_img(wingfxcount++, win->iphone_glkViewNum);
    //s->size = (win->type == wintype_TextGrid) ? ((window_textgrid_t*)win->data)->linessize : win->size;
    s->method = win->method;
    s->splitwin = win->splitwin;
}

static void saveStream(stream_t *str, struct glk_stream_autosave *s) {
    s->magicnum = str->magicnum;
    s->rock = str->rock;
    
    s->type = str->type;
    s->unicode = str->unicode;
    
    s->readcount = str->readcount;
    s->writecount = str->writecount;
    s->readable = str->readable;
    s->writable = str->writable;
    
    s->buf = str->buf;
    s->bufptr = str->bufptr;
    s->bufend = str->bufend;
    s->bufeof = str->bufeof;
    s->ubuf = str->ubuf;
    s->ubufptr = str->ubufptr;
    s->ubufend = str->ubufend;
    s->ubufeof = str->ubufeof;
    
    s->buflen = str->buflen;
}

extern char SAVE_PATH[];
static void saveFRef(fileref_t *fref, struct glk_fileref_autosave *s) {
    s->magicnum = fref->magicnum;
    s->rock = fref->rock;
    s->filetype = fref->filetype;
    s->textmode = fref->textmode;
    if (strstr(fref->filename, SAVE_PATH) == fref->filename || *fref->filename!='/') {
        int n = strlen(SAVE_PATH);
        char *p = fref->filename + n;
        if (*p=='/')
            ++p;
        n = strlen(p);
        if (n > 0 && n < sizeof(s->filename) && strcmp(p,kFrotzAutoSaveFile)!=0)
            strcpy(s->filename, p);
    }
}

static void saveWinPair(window_pair_t *wp, struct glk_winpair_autosave *s) {
    s->splitpos = wp->splitpos;
    s->splitwidth = wp->splitwidth;
    
    s->dir = wp->dir;
    s->vertical = wp->vertical;
    s->backward = wp->backward;
    s->division = wp->division;
    
    s->size = wp->size;
    
    s->child1 = 0;
    s->child2 = 0;
}

static void saveWinGfx(window_graphics_t *wp, struct glk_wingraphics_autosave *s) {
    s->width = wp->width;
    s->height = wp->height;
    s->backcolor = wp->backcolor;
}

static glui32 classes_find_id_for_object(int classid, void *obj)
{
	classtable_t *ctab;
	classref_t *cref;
	int i;
	if (classid < 0 || classid >= num_classes)
		return -1;
	ctab = classes[classid];
	for (i = 0; i < CLASSHASH_SIZE; i++) {
		cref = ctab->bucket[i];
		for (; cref; cref = cref->next) {
			if (cref->obj == obj)
				return cref->id;
		}
	}
	return -1;
}

/* Find a Glk object in the appropriate hash table. */
static classref_t *classes_pop_cref(int classid, glui32 objid)
{
	classtable_t *ctab;
	classref_t *cref;
	if (classid < 0 || classid >= num_classes)
		return NULL;
	ctab = classes[classid];
	cref = ctab->bucket[objid % CLASSHASH_SIZE];
	for (; cref; cref = cref->next) {
		if (cref->id == objid) {
			classref_t **crefp;
			int bucknum;
			
			bucknum = cref->bucknum;
			crefp = &(ctab->bucket[bucknum]);
			for (; *crefp; crefp = &((*crefp)->next)) {
				if ((*crefp) == cref) {
					*crefp = cref->next;
					return cref;
				}
			}
			return cref;
		}
	}
	return NULL;
}

static void classes_push_cref(int classid, classref_t *cref)
{
	int bucknum;
	classtable_t *ctab;
    
	if (classid < 0 || classid >= num_classes)
		return;
    
	if (!cref)
		return;
    
	ctab = classes[classid];
	
	bucknum = cref->id % CLASSHASH_SIZE;
	cref->bucknum = bucknum;
	cref->next = ctab->bucket[bucknum];
	ctab->bucket[bucknum] = cref;
    if (cref->id > ctab->lastid)
        ctab->lastid = cref->id+1;
    
    if (classid == gidisp_Class_Window) {
        cref = cref->next;
        while (cref) {
            if (ctab->bucket[bucknum]->id == cref->id)
                fprintf(stderr, "push_dref: Duplicate window_id during restore\n");
            cref = cref->next;
        }
    }
}

static void classes_denormalize_pointers(glui32 objclass, void *obj)
{
	if (objclass == gidisp_Class_Window) {
		struct glk_window_autosave *win = (struct glk_window_autosave *)obj;
		
		if (win->inbuf)	win->inbuf 	+= (glui32)GlulxRAM;
        
	} else if (objclass == gidisp_Class_Stream) {
		struct glk_stream_autosave *str = (struct glk_stream_autosave *)obj;
        
		if (str->buf)		str->buf     += (glui32)GlulxRAM;
		if (str->bufptr)	str->bufptr  += (glui32)GlulxRAM;
		if (str->bufend)	str->bufend  += (glui32)GlulxRAM;
		if (str->bufeof)	str->bufeof  += (glui32)GlulxRAM;
        
		if (str->ubuf)		str->ubuf    += (glui32)GlulxRAM;
		if (str->ubufptr)	str->ubufptr += (glui32)GlulxRAM;
		if (str->ubufend)	str->ubufend += (glui32)GlulxRAM;
		if (str->ubufeof)	str->ubufeof += (glui32)GlulxRAM;
	} else if (objclass == gidisp_Class_Fileref) {
        ;
	} else if (objclass == gidisp_Class_Schannel) {
		;
	}
}

static void classes_normalize_pointers(glk_object_save_t *obj)
{
    
	if (obj->type == gidisp_Class_Window) {
		struct glk_window_autosave *win = &obj->obj.win;
		
		if (win->inbuf)	win->inbuf	-= (glui32)GlulxRAM;
		if (win->splitwin) {
			win->splitwin = classes_find_id_for_object(gidisp_Class_Window, (void *)win->splitwin);
		} else {
			win->splitwin = kInvalidSplitWin; // definitely an invalid id
		}
	} else if (obj->type == gidisp_Class_Stream) {
		struct glk_stream_autosave *str = &obj->obj.str;
        
		if (str->buf) 		str->buf     -= (glui32)GlulxRAM;
		if (str->bufptr)	str->bufptr  -= (glui32)GlulxRAM;
		if (str->bufend)	str->bufend  -= (glui32)GlulxRAM;
		if (str->bufeof)	str->bufeof  -= (glui32)GlulxRAM;
        
		if (str->ubuf)		str->ubuf    -= (glui32)GlulxRAM;
		if (str->ubufptr)	str->ubufptr -= (glui32)GlulxRAM;
		if (str->ubufend)	str->ubufend -= (glui32)GlulxRAM;
		if (str->ubufeof)	str->ubufeof -= (glui32)GlulxRAM;
	} else if (obj->type == gidisp_Class_Fileref) {
		;
	} else if (obj->type == gidisp_Class_Schannel) {
		;
	}
}

static glui32 classes_iter(glk_object_save_t **objs)
{
	classtable_t *ctab;
	classref_t *cref;
	glui32 num_classes;
	glui32 i,j,ct = 0;
	glk_object_save_t *o = NULL, *cur;
	
	window_t  *win;
	stream_t *str_cur = glk_stream_get_current();
	
	if (!objs)
	    return 0;
	
	*objs = NULL;
    
	num_classes = gidispatch_count_classes();
	ct = 0;
	for (i = 0; i < num_classes; i++) { // iterate everything quickly
		if ((ctab = classes[i])) {
			for (j = 0; j < CLASSHASH_SIZE; j++) {
				cref = ctab->bucket[j];
				for ( ; cref; cref = cref->next) {
					if (i == 0) {
					    window_t *win = (window_t *)cref->obj;
					    win->store = 0;
					} else if (i == 1) {
					    stream_t *str = (stream_t *)cref->obj;
					    str->store = 0;
					}
					ct++;
				}
			}
		}
	}
	if (!ct) return 0;
	
	// add entries for windows with styles/pair info + the two general styles
	win = NULL;
	while ((win = gli_window_iterate_backward(win, NULL))) {
		if (win->type == wintype_TextBuffer || win->type == wintype_TextGrid
		    || win->type == wintype_Pair || win->type == wintype_Graphics)
			ct++;
	}
	// leave off the last 2 in the event of no styles in use!
	if (gli_window_has_stylehints())
		ct += 2;
	
	o = glulx_malloc(sizeof(glk_object_save_t) * ct);
	if (!o) return 0;
	
	ct = 0;
	win = NULL;
	while ((win = gli_window_iterate_backward(win, NULL))) {
		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));
        
		cur->type = gidisp_Class_Window;
		cur->id = classes_find_id_for_object(0, win);
        
		saveWin(win, &cur->obj.win);
		//!!!cur->obj.win = *win;
		win->store = TRUE;
		cur->iscurrent = FALSE; //(win == win_cur);
		classes_normalize_pointers(cur);
        
		ct++;
		// get stream for window
		if ((win->type == wintype_TextBuffer) || (win->type == wintype_TextGrid)) {
            
			// write STREAM chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
            
			cur->type = gidisp_Class_Stream;
			cur->id = classes_find_id_for_object(1, win->str);
			//!!!cur->obj.str = *win->str;
			
			saveStream(win->str, &cur->obj.str);
			win->str->store = TRUE;
			cur->iscurrent = (win->str == str_cur);
			classes_normalize_pointers(cur);
			ct++;
            
			// write STYLE chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
            
			cur->type = type_Style;
			cur->id = classes_find_id_for_object(0, win);
            
			GLK_STYLE_HINTS hints[style_NUMSTYLES];
            
			gli_window_get_stylehints(win, hints);
			memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);
            
			ct++;
		} else if (win->type == wintype_Pair) {
			window_pair_t *pairwin = (window_pair_t*)win->data;
            
			// write PAIR chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
			
			cur->type = type_Pair;
			cur->id = classes_find_id_for_object(0, win);
            
			//!!!cur->obj.pair = *((window_pair_t *)win->data);
			saveWinPair(pairwin, &cur->obj.pair);
            
			// set the children to their ids so we can find the pair on reload
			cur->obj.pair.child1 = classes_find_id_for_object(gidisp_Class_Window, pairwin->child1);
			cur->obj.pair.child2 = classes_find_id_for_object(gidisp_Class_Window, pairwin->child2);
			//!!!classes_normalize_pointers(cur);
            
			ct++;
		} else if (win->type == wintype_Graphics) {
			// write GRAPHICS chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
			
			cur->type = type_Graphics;
			cur->id = classes_find_id_for_object(0, win);
            
			saveWinGfx((window_graphics_t *)win->data, &cur->obj.gfx);
			ct++;
		}
	}
	// now, iterate other classes; window streams should have already been accounted for, but we check this
	for (i = 0; i < num_classes; i++) {
		if ((ctab = classes[i])) {
			for (j = 0; j < CLASSHASH_SIZE; j++) {
				cref = ctab->bucket[j];
				for ( ; cref; cref = cref->next) {
					if (i == 0) { // windows
						window_t *win = (window_t *)cref->obj;
						
						if (!win->store) {
							cur = o + ct;
							memset(cur, 0, sizeof(glk_object_save_t));
                            
							cur->type = i;
							cur->id = cref->id;
						}
					} else {
						if (i == 1) { // streams
							stream_t *str = (stream_t *)cref->obj;
                            
							if (!str->store) {
								cur = o + ct;
								memset(cur, 0, sizeof(glk_object_save_t));
								cur->type = i;
								cur->id = cref->id;
                                
								//!!!cur->obj.str = *str;
								saveStream(str, &cur->obj.str);
								cur->iscurrent = (str == str_cur);
								classes_normalize_pointers(cur);
								ct++;
							}
						} else if (i == 2) {
							fileref_t *fref = (fileref_t *)cref->obj;
                            
							cur = o + ct;
							memset(cur, 0, sizeof(glk_object_save_t));
							cur->type = i;
							cur->id = cref->id;
                            
							//!!!cur->obj.fref = *fref;
							saveFRef(fref, &cur->obj.fref);
							classes_normalize_pointers(cur);
							ct++;
						} else if (i == 3) { // won't happen here
							;
						}
					}
				}
			}
		}
	}
	// 2 general styles
    
	if (gli_window_has_stylehints()) {
		GLK_STYLE_HINTS hints[style_NUMSTYLES];
        
		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));
		cur->type = type_Style;
		cur->id = STYLEHINT_TEXT_BUFFER;
        
		gli_window_get_stylehints((winid_t)STYLEHINT_TEXT_BUFFER, hints);
        
		memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);
		ct++;
        
		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));
		cur->type = type_Style;
		cur->id = STYLEHINT_TEXT_GRID;
        
		gli_window_get_stylehints((winid_t)STYLEHINT_TEXT_GRID, hints);
        
		memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);
		ct++;
	}
    
	*objs = o;
	return ct;
}

typedef struct _winid {
	window_t	*win;
	glui32		id;
} t_winid;

static glsi32 classes_restore(glk_object_save_t *objects, glui32 objects_count, int versionNum)
{
	glk_object_save_t *cur;
	int found;
	classtable_t *ctab;
	classref_t *cref, *cref_id;
	int i, j;
	window_t *win = NULL, *splitwin = NULL;
	struct glk_window_autosave *foundwin = NULL;
	stream_t *str = NULL;
	struct glk_stream_autosave *foundstr = NULL;
	glui32 id;
	int winct = 0, winct2 = 0;
	t_winid winid[kMaxGlkViews];
	stream_t *cur_str = NULL;
	char errbuf[256];
    
	for (i = 0; i < kMaxGlkViews; i++) {
		winid[i].win = NULL;
		winid[i].id = 0;
	}
    int winLastId = classes[gidisp_Class_Window]->lastid;
    for (i = 0; i < objects_count; i++) {
		cur = objects + i;
        if (cur->type == gidisp_Class_Window && cur->id+1 > winLastId)
            winLastId = cur->id+1;
    }
    classes[gidisp_Class_Window]->lastid = winLastId; // make sure ids of new windows don't overlap orig ids
    
	for (i = 0; i < objects_count; i++) {
		found = FALSE;
		// windows come first, in the correct order, alternated with their streams/hints
		cur = objects + i;
		// don't bother iterating through current - there are none at autoload
		if (cur->type == gidisp_Class_Window) {
			winct++;
			foundwin = &cur->obj.win;
			classes_denormalize_pointers(gidisp_Class_Window, foundwin);
			winid[winct-1].id = cur->id; // fill this in for a pair, too
            
			if (foundwin->type != wintype_Pair) {
				splitwin = NULL;
				if (foundwin->splitwin != kInvalidSplitWin) { // this had no splitwin going in
					for (j = 0; j < kMaxGlkViews; j++) {
						if (winid[j].id == foundwin->splitwin) {
							splitwin = winid[j].win;
							break;
						}
					}
				}
				win = (window_t *)glk_window_open(splitwin, foundwin->method, foundwin->size, foundwin->type, foundwin->rock);
				if (!win) {
					sprintf(errbuf, "\nCould not create %s window with id %ld. Aborting restore.\n",
                            foundwin->type == wintype_TextBuffer ? "textbuffer" :
                            foundwin->type == wintype_TextGrid ? "textgrid" :
                            foundwin->type == wintype_Blank ? "blank" : "graphics", (long)cur->id);
					iphone_win_puts(0, errbuf);
					return FALSE;
				}
				winid[winct-1].win = win;
                
				// check id, set id if necessary
				id = classes_find_id_for_object(gidisp_Class_Window, win);
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should ensure that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
                if (versionNum == FrotzGlkClassChunkVersionNumV1) {
                    win->line_request = foundwin->requ.v1.line_request;
                    win->char_request = foundwin->requ.v1.char_request;
                    win->line_request_uni = foundwin->requ.v1.line_request_uni;
                    win->char_request_uni = foundwin->requ.v1.char_request_uni;
                } else {
                    int req = foundwin->requ.v2.reqFlags;
                    win->line_request = (req & kGlkReqLine) != 0;
                    win->line_request_uni = (req & kGlkReqLineUni) != 0;
                    win->char_request = (req & kGlkReqChar) != 0;
                    win->mouse_request = (req & kGlkReqMouse) != 0;
                    win->hyper_request = (req & kGlkReqHyper) != 0;
                    win->echo_line_input = (req & kGlkReqNoEchoLine) == 0;
                    if (win->type == wintype_TextBuffer) {
                        window_textbuffer_t *wtb = (window_textbuffer_t*)win->data;
                        wtb->inecho = win->echo_line_input;
                    }
                    if (win->mouse_request && (win->type == wintype_Graphics || win->type == wintype_TextGrid))
                        iphone_enable_tap(win->iphone_glkViewNum);
                    if (win->hyper_request && (win->type == wintype_TextGrid || win->type == wintype_TextBuffer))
                        iphone_enable_tap(win->iphone_glkViewNum);
                }
				if (foundwin->inbuf) {
					window_textbuffer_t *wtb = (window_textbuffer_t*)win->data;
					wtb->inbuf = foundwin->inbuf;
					wtb->inmax = foundwin->inmax;
				}
				found = TRUE;
			}
			if (found && (win->type == wintype_TextBuffer || win->type == wintype_TextGrid)) {
				// read STREAM chunk
				i++;
				cur = objects + i;
                
				if (cur->type != gidisp_Class_Stream) {
					sprintf(errbuf, "\nUnexpected window stream type %d. Aborting restore.\n", cur->type);
					iphone_win_puts(0, errbuf);
					return FALSE;
				} else {
					foundstr = &cur->obj.str;
					str = win->str;
                    
					id = classes_find_id_for_object(gidisp_Class_Stream, str);
					if (id != cur->id) {
						cref_id = classes_pop_cref(gidisp_Class_Stream, id);
						cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
						classes_push_cref(gidisp_Class_Stream, cref_id);
					}
					classes_denormalize_pointers(gidisp_Class_Stream, foundstr);
                    
					str->rock = foundstr->rock;
					str->readcount = foundstr->readcount;
					str->writecount = foundstr->writecount;
					str->readable = foundstr->readable;
					str->writable = foundstr->writable;
					if (!str->buf && foundstr->buf) {
						str->buf = foundstr->buf;
						str->bufptr = foundstr->bufptr;
						str->bufend = foundstr->bufend;
						str->bufeof = foundstr->bufeof;
						str->buflen = foundstr->buflen;
					}
					if (cur->iscurrent) {
						cur_str = str;
					}
				}
				// read STYLE chunk
				i++;
				cur = objects + i;
                
				if (cur->type != type_Style) {
					sprintf(errbuf, "\nUnexpected stream type %d. Aborting restore.\n", cur->type);
					iphone_win_puts(0, errbuf);
					return FALSE;
				} else {
					gli_window_set_stylehints(win, (GLK_STYLE_HINTS *)&cur->obj.style);
				}
				iphone_set_glk_default_colors(win->iphone_glkViewNum);
			} else if (found && win->type == wintype_Graphics) {
				if (i+1 < objects_count && objects[i+1].type == type_Graphics) {
					i++;
					cur = objects + i;
					window_graphics_t *wgp = (window_graphics_t*)win->data;
					wgp->width = cur->obj.gfx.width;
					wgp->height = cur->obj.gfx.height;
					wgp->backcolor = cur->obj.gfx.backcolor;
					iphone_set_background_color(win->iphone_glkViewNum, wgp->backcolor);
                    iphone_restore_glk_win_graphics_img(wingfxcount++, win->iphone_glkViewNum);
				}
			} else if (found && win->type == wintype_Pair) {
				// this will never happen
				i++;
			}
		} else if (cur->type == gidisp_Class_Stream) {
			break;
		} else if (cur->type == type_Pair) {
			struct glk_winpair_autosave *pairwin = &cur->obj.pair;
			// find the children; if they exist, make sure that this window is registered under the correct id
			glui32 id1 = (glui32)pairwin->child1;
			glui32 id2 = (glui32)pairwin->child2;
			window_t *win1 = NULL;
			window_t *win2 = NULL;
            
			for (j = 0; j < kMaxGlkViews; j++) {
				if (winid[j].id == id1) {
					win1 = winid[j].win;
				} else if (winid[j].id == id2) {
					win2 = winid[j].win;
				}
				if (win1 && win2) break;
			}
			if (win1 && win2) { // we found it
				// check id, set id if necessary
				id = classes_find_id_for_object(gidisp_Class_Window, win1->parent); // get the parent
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should ensure that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
				// enter window in the window id list, so other windows can find it, too, if it's being used as a splitwin
				for (j = 0; j < kMaxGlkViews; j++) {
					if (winid[j].id == cur->id) {
						winid[j].win = win1->parent;
						break;
					}
				}
			}
		} else if (cur->type == gidisp_Class_Fileref)
            ;
    }
	// verify window count
	if ((ctab = classes[gidisp_Class_Window])) {
		for (j = 0; j < CLASSHASH_SIZE; j++) {
			cref = ctab->bucket[j];
			for ( ; cref; cref = cref->next) {
				winct2++;
			}
		}
	}
	if (winct != winct2) {
		sprintf(errbuf, "\n[Autorestore warning: window count mismatch %d!=%d]\n", winct, winct2);
		iphone_win_puts(0, errbuf);
	}
    
	// freakin' great, so let's re-iterate, simultaneously doing an iteration and compare
    
	// start over, verify all window ids, including pairs
	win = NULL;
	for (i = 0; i < objects_count; i++) {
		// windows come first, in the correct order, alternated with their streams
		cur = objects + i;
		if (cur->type == gidisp_Class_Window) {
			foundwin = &cur->obj.win;
            
			win = gli_window_iterate_backward(win, NULL);
			if (win->type == foundwin->type) {
				win->rock = foundwin->rock;
				id = classes_find_id_for_object(gidisp_Class_Window, win);
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
                //break; // This incorrect break was in cellardoor impl --
			} else {
				iphone_win_puts(0, "\nCould not restore saved state. Sorry. Aborting restore.\n");
				return FALSE;
			}
			// restore RECT
			win->bbox = foundwin->bbox;
            
			if (win->type == wintype_TextBuffer || win->type == wintype_TextGrid) {
				// read STREAM chunk
				i++;
				cur = objects + i;
				if (cur->type != gidisp_Class_Stream) {
					iphone_win_puts(0, "\nMissing stream. Aborting restore.\n");
					return FALSE;
				} else {
					foundstr = &cur->obj.str;
					str = win->str;
                    
					str->rock = foundstr->rock;
					id = classes_find_id_for_object(gidisp_Class_Stream, str);
					if (id != cur->id) {
						cref_id = classes_pop_cref(gidisp_Class_Stream, id);
						cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
						classes_push_cref(gidisp_Class_Stream, cref_id);
					}
				}
				// read STYLE chunk
				i++;
				cur = objects + i;
				if (cur->type != type_Style) {
					// style chunk is not where it should be
					iphone_win_puts(0, "\nMissing style chunk. Aborting restore.\n");
					return FALSE;
				}
			} else if (win->type == wintype_Pair) {
				// read PAIR chunk
				i++;
				cur = objects + i;
				
				if (cur->type != type_Pair) {
					iphone_win_puts(0, "\nCorrupt win pair. Aborting restore.\n");
					return FALSE;
				} else {
					struct glk_winpair_autosave *foundpair = &cur->obj.pair;
					window_pair_t *pair = (window_pair_t *)win->data;
					
					pair->splitpos = foundpair->splitpos;
					pair->splitwidth = foundpair->splitwidth;
					pair->dir = foundpair->dir;
					pair->vertical = foundpair->vertical;
					pair->backward = foundpair->backward;
					pair->size = foundpair->size;
				}
			}
		} else if (cur->type == gidisp_Class_Stream) { // now do the streams
#if 0 // this doesn't work and seems to corrupt autorestore, e.g. Counterfeit Monkey
			stream_t *tempstr;
            
			found = FALSE;
			foundstr = &cur->obj.str;
			
			if ((ctab = classes[gidisp_Class_Stream])) {
				for (j = 0; j < CLASSHASH_SIZE; j++) {
					cref = ctab->bucket[j];
					for ( ; cref; cref = cref->next) {
						tempstr = (stream_t *)cref->obj;
						if (tempstr->type == foundstr->type && tempstr->rock == foundstr->rock) { // this id should be clearer
							id = classes_find_id_for_object(gidisp_Class_Stream, tempstr);
							if (id != cur->id) {
								cref_id = classes_pop_cref(gidisp_Class_Stream, id);
								cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
								classes_push_cref(gidisp_Class_Stream, cref_id);
							}
							classes_denormalize_pointers(gidisp_Class_Stream, foundstr);
                            
							tempstr->rock = foundstr->rock;
							if (tempstr->type != strtype_File && !tempstr->buf && foundstr->buf) {
								tempstr->readcount = foundstr->readcount;
								tempstr->writecount = foundstr->writecount;
								tempstr->readable = foundstr->readable;
								tempstr->writable = foundstr->writable;
								tempstr->buf = foundstr->buf;
								tempstr->bufptr = foundstr->bufptr;
								tempstr->bufend = foundstr->bufend;
								tempstr->bufeof = foundstr->bufeof;
								tempstr->buflen = foundstr->buflen;
								if (cur->iscurrent) {
									cur_str = tempstr;
								}
							} else if (tempstr->type == strtype_File) {
								//fd("not touching file info for the moment");
							}
							found = TRUE;
							break;
						}
					}
					if (found)
						break;
				}
			}
			if (!found) {
				// we're here because nothing matched; make a new stream
				sprintf(errbuf, "\n[Autorestore warning: a stream of type %s is missing: id %d]\n",
                        (cur->type == strtype_File) ? "strtype_File" :
                        (cur->type == strtype_Window) ? "strtype_Window" :
                        (cur->type == strtype_Memory) ? "strtype_Memory" : "UNKNOWN", (int)cur->id);
				iphone_win_puts(0, errbuf);
			}
#endif
		} else if (cur->type == gidisp_Class_Fileref) {
            //			iphone_win_puts(0, "\n[Autorestore warning: missing file stream]\n");
            if (*cur->obj.fref.filename && strcmp(cur->obj.fref.filename, kFrotzAutoSaveFile)!=0) {
                glui32 usage = (cur->obj.fref.textmode ? fileusage_TextMode : 0)
                | (cur->obj.fref.filetype & fileusage_TypeMask);
                
                fileref_t *fref = gli_new_fileref(cur->obj.fref.filename, usage, cur->obj.fref.rock);
                id = classes_find_id_for_object(gidisp_Class_Fileref, fref);
                if (id != cur->id) {
                    cref_id = classes_pop_cref(gidisp_Class_Fileref, id);
                    cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
                    classes_push_cref(gidisp_Class_Fileref, cref_id);
                }
            }
		} else if (cur->type == type_Style) {
			if (cur->id == STYLEHINT_TEXT_BUFFER) {
				gli_window_set_stylehints((winid_t)STYLEHINT_TEXT_BUFFER, (GLK_STYLE_HINTS *)&cur->obj.style);
			} else if (cur->id == STYLEHINT_TEXT_GRID) {
				gli_window_set_stylehints((winid_t)STYLEHINT_TEXT_GRID, (GLK_STYLE_HINTS *)&cur->obj.style);
			}
		}
	}
	// restore current output stream
	if (cur_str) {
		glk_stream_set_current(cur_str);
	}
	return TRUE;
}
