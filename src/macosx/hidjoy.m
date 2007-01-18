/*         ______   ___    ___ 
 *        /\  _  \ /\_ \  /\_ \ 
 *        \ \ \L\ \\//\ \ \//\ \      __     __   _ __   ___ 
 *         \ \  __ \ \ \ \  \ \ \   /'__`\ /'_ `\/\`'__\/ __`\
 *          \ \ \/\ \ \_\ \_ \_\ \_/\  __//\ \L\ \ \ \//\ \L\ \
 *           \ \_\ \_\/\____\/\____\ \____\ \____ \ \_\\ \____/
 *            \/_/\/_/\/____/\/____/\/____/\/___L\ \/_/ \/___/
 *                                           /\____/
 *                                           \_/__/
 *
 *      HID Joystick driver routines for MacOS X.
 *
 *      By Angelo Mottola.
 *
 *      See readme.txt for copyright information.
 */

#include "allegro.h"
#include "allegro/internal/aintern.h"
#include "allegro/internal/aintern_joystick.h"
#include "allegro/platform/aintosx.h"

#ifndef ALLEGRO_MACOSX
#error something is wrong with the makefile
#endif                


static bool init_joystick(void);
static void exit_joystick(void);
static int poll(void);
static int count_joysticks(void);
static AL_JOYSTICK* get_joystick(int);
static void release_joystick(AL_JOYSTICK*);
static void get_state(AL_JOYSTICK*, AL_JOYSTATE*);

/* Driver table */
AL_JOYSTICK_DRIVER joystick_hid = {
   JOYSTICK_HID,        // int  id;
   empty_string,        // AL_CONST char *name;
   empty_string,        // AL_CONST char *desc;
   "HID Joystick",      // AL_CONST char *ascii_name;
   init_joystick,      	// AL_METHOD(bool, init, (void));
   exit_joystick,      	// AL_METHOD(void, exit, (void));
   count_joysticks,	// AL_METHOD(int, num_joysticks, (void));
   get_joystick,        // AL_METHOD(AL_JOYSTICK*, get_joystick, (int joyn));
   release_joystick, 	// AL_METHOD(void, release_joystick, (AL_JOYSTICK*));
   get_state, 		// AL_METHOD(void, get_state, (AL_JOYSTICK*, AL_JOYSTATE *ret_state));
};


static HID_DEVICE_COLLECTION hid_devices;

/* init_joystick:
 *  Initializes the HID joystick driver.
 */
static bool init_joystick(void)
{
   static char *name_stick = "stick";
   static char *name_hat = "hat";
   static char *name_slider = "slider";
   static char *name_x = "x";
   static char *name_y = "y";
   static char *name_b[] =
      { "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11", "B12", "B13", "B14", "B15", "B16" };
   HID_ELEMENT *element;
   int i, j, stick;
   /* TODO: */
   return 0;

   hid_devices.count=hid_devices.capacity=0;
   hid_devices.devices=NULL;
   osx_hid_scan(HID_JOYSTICK, &hid_devices);
   osx_hid_scan(HID_GAMEPAD, &hid_devices);
   num_joysticks = hid_devices.count > 0 ? hid_devices.devices[hid_devices.count - 1].cur_app : 0;
   for (i = 0; i < num_joysticks; i++) {
      memset(&joy[i], 0, sizeof(joy[i]));
   }
   for (i=0; i<hid_devices.count; ++i) {
      for (j = 0; j < hid_devices.devices[i].num_elements; j++) {
         element = &hid_devices.devices[i].element[j];
         switch (element->type) {
         case HID_ELEMENT_BUTTON:
            if (element->index >= MAX_JOYSTICK_BUTTONS || element->app>=MAX_JOYSTICKS) {
               element->cookie=0x0;
               break;
            }
            if (element->name)
               joy[element->app].button[element->index].name = element->name;
            else
               joy[element->app].button[element->index].name = name_b[element->index];
            joy[element->app].num_buttons++;
            break;

         case HID_ELEMENT_AXIS:
         case HID_ELEMENT_AXIS_PRIMARY_X:
         case HID_ELEMENT_AXIS_PRIMARY_Y:
         case HID_ELEMENT_STANDALONE_AXIS:
            if (element->app>=MAX_JOYSTICKS || element->col>=MAX_JOYSTICK_STICKS || element->index>=MAX_JOYSTICK_AXIS) {
               element->cookie=0x0;
               break;
            }
            joy[element->app].stick[element->col].name = name_stick;
            joy[element->app].stick[element->col].num_axis++;
            if (joy[element->app].num_sticks<(element->col+1))
               joy[element->app].num_sticks=element->col+1;
            joy[element->app].stick[element->col].flags = JOYFLAG_DIGITAL | JOYFLAG_ANALOGUE | JOYFLAG_SIGNED;
            if (element->name)
               joy[element->app].stick[element->col].axis[element->index].name = element->name;
            else
               joy[element->app].stick[element->col].axis[element->index].name = element->index==0 ? name_x : name_y;

            break;

         case HID_ELEMENT_HAT:
            if (element->app>=MAX_JOYSTICKS || element->col >= MAX_JOYSTICK_STICKS) {
               element->cookie=0x0;
               break;
            }
            if (joy[element->app].num_sticks<(element->col+1))
               joy[element->app].num_sticks=element->col+1;

            if (element->name)
               joy[element->app].stick[element->col].name = element->name;
            else
               joy[element->app].stick[element->col].name = name_hat;
            joy[element->app].stick[element->col].num_axis = 2;
            joy[element->app].stick[element->col].flags = JOYFLAG_DIGITAL | JOYFLAG_ANALOGUE | JOYFLAG_SIGNED;
            joy[element->app].stick[element->col].axis[0].name = name_x;
            joy[element->app].stick[element->col].axis[1].name = name_y;
            break;
         }
      }
   }
   return poll();
}



/* exit_joystick:
 *  Shuts down the HID joystick driver.
 */
static void exit_joystick(void)
{
   osx_hid_free(&hid_devices);
}



/* poll:
 *  Polls the active joystick devices and updates internal states.
 */
static int poll(void)
{
   HID_DEVICE *device;
   HID_ELEMENT *element;
   IOHIDEventStruct hid_event;
   int i, j, pos;

   if (num_joysticks <= 0)
      return -1;

   for (i = 0; i < hid_devices.count; i++) {
      device = &hid_devices.devices[i];
      if (device->interface) {
         for (j = 0; j < device->num_elements; j++) {
            element = &device->element[j];
            if ((element->cookie==0x0) || (*(device->interface))->getElementValue(device->interface, element->cookie, &hid_event))
               continue;
            switch (element->type) {

            case HID_ELEMENT_BUTTON:
               joy[element->app].button[element->index].b = hid_event.value;
               break;

            case HID_ELEMENT_AXIS:
            case HID_ELEMENT_AXIS_PRIMARY_X:
            case HID_ELEMENT_AXIS_PRIMARY_Y:
               pos = (((hid_event.value - element->min) * 256) / (element->max - element->min + 1)) - 128;
               joy[element->app].stick[element->col].axis[element->index].pos = pos;
               joy[element->app].stick[element->col].axis[element->index].d1 = FALSE;
               joy[element->app].stick[element->col].axis[element->index].d2 = FALSE;
               if (pos < 0)
                  joy[element->app].stick[element->col].axis[element->index].d1 = TRUE;
               else if (pos > 0)
                  joy[element->app].stick[element->col].axis[element->index].d2 = TRUE;
               break;

            case HID_ELEMENT_STANDALONE_AXIS:
               pos = (((hid_event.value - element->min) * 255) / (element->max - element->min + 1));
               joy[element->app].stick[element->col].axis[element->index].pos = pos;
               break;

            case HID_ELEMENT_HAT:
               switch (hid_event.value) {

               case 0:  /* up */
                  joy[element->app].stick[element->col].axis[0].pos = 0;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = -128;
                  joy[element->app].stick[element->col].axis[1].d1 = 1;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;

               case 1:  /* up and right */
                  joy[element->app].stick[element->col].axis[0].pos = 128;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 1;
                  joy[element->app].stick[element->col].axis[1].pos = -128;
                  joy[element->app].stick[element->col].axis[1].d1 = 1;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;

               case 2:  /* right */
                  joy[element->app].stick[element->col].axis[0].pos = 128;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 1;
                  joy[element->app].stick[element->col].axis[1].pos = 0;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;

               case 3:  /* down and right */
                  joy[element->app].stick[element->col].axis[0].pos = 128;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 1;
                  joy[element->app].stick[element->col].axis[1].pos = 128;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 1;
                  break;

               case 4:  /* down */
                  joy[element->app].stick[element->col].axis[0].pos = 0;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = 128;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 1;
                  break;

               case 5:  /* down and left */
                  joy[element->app].stick[element->col].axis[0].pos = -128;
                  joy[element->app].stick[element->col].axis[0].d1 = 1;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = 128;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 1;
                  break;

               case 6:  /* left */
                  joy[element->app].stick[element->col].axis[0].pos = -128;
                  joy[element->app].stick[element->col].axis[0].d1 = 1;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = 0;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;

               case 7:  /* up and left */
                  joy[element->app].stick[element->col].axis[0].pos = -128;
                  joy[element->app].stick[element->col].axis[0].d1 = 1;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = -128;
                  joy[element->app].stick[element->col].axis[1].d1 = 1;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;

               case 15:  /* centered */
                  joy[element->app].stick[element->col].axis[0].pos = 0;
                  joy[element->app].stick[element->col].axis[0].d1 = 0;
                  joy[element->app].stick[element->col].axis[0].d2 = 0;
                  joy[element->app].stick[element->col].axis[1].pos = 0;
                  joy[element->app].stick[element->col].axis[1].d1 = 0;
                  joy[element->app].stick[element->col].axis[1].d2 = 0;
                  break;
               }
               break;
            }
         }
      }
   }
   return 0;
}

/* num_joysticks:
 *  Return number of active joysticks
 */
int count_joysticks(void) 
{
   return num_joysticks;
}

/* get_joystick:
 * Get a pointer to a joystick structure
 */
AL_JOYSTICK* get_joystick(int index) 
{
   return NULL;
}

/* release_joystick:
 * Release a pointer that has been obtained
 */
void release_joystick(AL_JOYSTICK* joy)
{
}

/* get_state:
 * Get the current status of a joystick
 */
void get_state(AL_JOYSTICK* joy, AL_JOYSTATE* state)
{
}

/* Local variables:       */
/* c-basic-offset: 3      */
/* indent-tabs-mode: nil  */
/* End:                   */
