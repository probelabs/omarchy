/* vptr — send scroll gestures through wlr-virtual-pointer-unstable-v1.
 *
 * Usage:
 *   vptr move <x> <y>                       absolute move over the output
 *   vptr scroll <finger|wheel> <value> <discrete> [count] [gap-ms]
 *
 * One gesture: axis_source, axis_discrete, axis, frame.  "finger" is the
 * touchpad path (Qt sees pixelDelta), "wheel" the mouse-wheel path
 * (Qt sees angleDelta).  Exit 0 on success, 1 on usage / protocol failure.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <wayland-client.h>
#include "wlr-vptr-client-protocol.h"

static struct wl_display *display;
static struct wl_registry *registry;
static struct wl_seat *seat;
static struct wl_output *output;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *pointer;

static void registry_global(void *data, struct wl_registry *reg,
                            uint32_t name, const char *interface, uint32_t version)
{
    (void)data;
    fprintf(stderr, "vptr: global %s v%u\n", interface, version);
    if (strcmp(interface, "wl_seat") == 0) {
        seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 4 ? version : 4);
    } else if (strcmp(interface, "wl_output") == 0 && output == NULL) {
        output = wl_registry_bind(reg, name, &wl_output_interface, version < 3 ? version : 3);
    } else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(reg, name,
            &zwlr_virtual_pointer_manager_v1_interface, version < 2 ? version : 2);
    }
}

static void registry_global_remove(void *data, struct wl_registry *reg, uint32_t name)
{
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static uint32_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000u + ts.tv_nsec / 1000000u);
}

static int connect_pointer(void)
{
    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "vptr: cannot connect to a Wayland display\n"); return 1; }
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "vptr: zwlr_virtual_pointer_manager_v1 not advertised by this compositor\n");
        return 1;
    }
    fprintf(stderr, "vptr: manager v%u seat=%p output=%p\n",
        zwlr_virtual_pointer_manager_v1_get_version(manager), (void*)seat, (void*)output);
    if (zwlr_virtual_pointer_manager_v1_get_version(manager) >= 2 && output) {
        pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(manager, seat, output);
        fprintf(stderr, "vptr: created with_output pointer=%p\n", (void*)pointer);
    } else {
        pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
        fprintf(stderr, "vptr: created plain pointer=%p\n", (void*)pointer);
    }
    if (!pointer) { fprintf(stderr, "vptr: create_virtual_pointer failed\n"); return 1; }
    wl_display_roundtrip(display);
    return 0;
}

static void finish(void)
{
    if (pointer) zwlr_virtual_pointer_v1_destroy(pointer);
    if (manager) zwlr_virtual_pointer_manager_v1_destroy(manager);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: vptr move <x> <y> | vptr scroll <finger|wheel> <value> <discrete> [count] [gap-ms]\n");
        return 1;
    }
    if (connect_pointer() != 0) { finish(); return 1; }

    if (strcmp(argv[1], "move") == 0 && argc == 4) {
        double x = atof(argv[2]), y = atof(argv[3]);
        zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(),
            (uint32_t)x, (uint32_t)y, 65535, 65535);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        finish();
        return 0;
    }

    if (strcmp(argv[1], "scroll") == 0 && argc >= 5) {
        const char *src = argv[2];
        double value = atof(argv[3]);
        int discrete = atoi(argv[4]);
        int count = argc > 5 ? atoi(argv[5]) : 1;
        int gap = argc > 6 ? atoi(argv[6]) : 30;
        uint32_t source;
        if (strcmp(src, "finger") == 0) source = 1;        /* wl_pointer.axis_source.finger */
        else if (strcmp(src, "wheel") == 0) source = 0;    /* wl_pointer.axis_source.wheel */
        else if (strcmp(src, "continuous") == 0) source = 2;
        else { fprintf(stderr, "vptr: unknown source %s\n", src); finish(); return 1; }

        /* Seat warm-up: each fresh virtual device races the compositor's seat
         * negotiation and its first events can be dropped (the same race wtype
         * works around with a no-op key). Three near-zero gestures settle it
         * before anything measured is sent. */
        for (int w = 0; w < 3; w++) {
            uint32_t t = now_ms();
            zwlr_virtual_pointer_v1_axis_source(pointer, source);
            zwlr_virtual_pointer_v1_axis_discrete(pointer, t, 0, wl_fixed_from_double(1), 1);
            zwlr_virtual_pointer_v1_axis(pointer, t, 0, wl_fixed_from_double(1));
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            usleep(40 * 1000);
        }

        for (int i = 0; i < count; i++) {
            if (wl_display_get_error(display)) { fprintf(stderr, "vptr: display error before send\n"); finish(); return 1; }
            uint32_t t = now_ms();
            zwlr_virtual_pointer_v1_axis_source(pointer, source);
            zwlr_virtual_pointer_v1_axis_discrete(pointer, t, 0,
                wl_fixed_from_double(value), discrete);
            zwlr_virtual_pointer_v1_axis(pointer, t, 0, wl_fixed_from_double(value));
            zwlr_virtual_pointer_v1_frame(pointer);
            if (wl_display_roundtrip(display) < 0 || wl_display_get_error(display)) {
                fprintf(stderr, "vptr: display error after send\n"); finish(); return 1;
            }
            if (i + 1 < count) usleep((useconds_t)gap * 1000);
        }
        finish();
        return 0;
    }

    fprintf(stderr, "vptr: bad arguments\n");
    finish();
    return 1;
}
