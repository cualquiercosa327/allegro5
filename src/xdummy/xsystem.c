/* This is only a dummy driver, not implementing most required things,
 * it's just here to give me some understanding of the base framework of a
 * system driver.
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "allegro.h"
#include "internal/aintern.h"
#include "platform/aintunix.h"
#include "internal/system_new.h"
#include "internal/bitmap_new.h"

#include "xdummy.h"

static AL_SYSTEM_INTERFACE *vt;

static void *background_thread(void *arg)
{
   AL_SYSTEM_XDUMMY *s = arg;
   XEvent event;
   unsigned int i;

   while (1) {
      XNextEvent(s->xdisplay, &event);

      switch (event.type) {
         case KeyPress:
            _al_xwin_keyboard_handler(&event.xkey, false);
            break;
         case KeyRelease:
            _al_xwin_keyboard_handler(&event.xkey, false);
            break;
         case ConfigureNotify:
            // FIXME: With many windows, it's bad to loop through them all,
            // maybe can come up with a better system here.
            // TODO: am I supposed to access ._size?
            for (i = 0; i < s->system.displays._size; i++) {
               AL_DISPLAY_XDUMMY **d = _al_vector_ref(&s->system.displays, i);
               if ((*d)->window == event.xconfigure.window) {
                  _al_display_xdummy_configure(&(*d)->display,  &event);
                  break;
               }
            }
            break;
      }
   }
   return NULL;
}

/* Create a new system object for the dummy X11 driver. */
static AL_SYSTEM *initialize(int flags)
{
   AL_SYSTEM_XDUMMY *s = _AL_MALLOC(sizeof *s);
   memset(s, 0, sizeof *s);
   
   _al_vector_init(&s->system.displays, sizeof (AL_SYSTEM_XDUMMY *));

   XInitThreads();

   s->system.vt = vt;

   /* Get an X11 display handle. */
   s->xdisplay = XOpenDisplay(0);

   TRACE("xsystem: XDummy driver connected to X11.\n");

   pthread_create(&s->thread, NULL, background_thread, s);

   TRACE("events thread spawned.\n");

   return &s->system;
}

// FIXME: This is just for now, the real way is of course a list of
// available display drivers. Possibly such drivers can be attached at runtime
// to the system driver, so addons could provide additional drivers.
AL_DISPLAY_INTERFACE *get_display_driver(void)
{
    return _al_display_xdummy_driver();
}

// FIXME: Use the list.
AL_KEYBOARD_DRIVER *get_keyboard_driver(void)
{
   // FIXME: i would prefer a dynamic way to list drivers, not a static list
   return _al_xwin_keyboard_driver_list[0].driver;
}

/* Internal function to get a reference to this driver. */
AL_SYSTEM_INTERFACE *_al_system_xdummy_driver(void)
{
   if (vt) return vt;

   vt = _AL_MALLOC(sizeof *vt);
   memset(vt, 0, sizeof *vt);

   vt->initialize = initialize;
   vt->get_display_driver = get_display_driver;
   vt->get_keyboard_driver = get_keyboard_driver;

   return vt;
}
