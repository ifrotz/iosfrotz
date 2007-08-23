#if defined(__cplusplus)
  extern "C" id objc_msgSend_stret(id self, SEL op, ...);
  extern "C" id objc_msgSendSuper_stret(struct objc_super *super, SEL op, ...);
#else
  extern void objc_msgSend_stret(void * stretAddr, id self, SEL op, ...);
  extern void objc_msgSendSuper_stret(void * stretAddr, struct objc_super *super, SEL op, ...);
#endif


