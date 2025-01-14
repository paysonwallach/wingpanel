/*
 * Copyright 2011-2020 elementary, Inc. (https://elementary.io)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

public class Wingpanel.Widgets.Panel : Gtk.EventBox {
    public Services.PopoverManager popover_manager { get; construct; }

    private Gtk.Box box;
    private Appmenu.MenuWidget? left_menubar;
    private IndicatorMenuBar right_menubar;

    private unowned Gtk.StyleContext style_context;
    private Gtk.CssProvider? style_provider = null;

    private static Gtk.CssProvider resource_provider;

    public Panel (Services.PopoverManager popover_manager) {
        Object (popover_manager : popover_manager);
    }

    static construct {
        resource_provider = new Gtk.CssProvider ();
        resource_provider.load_from_resource ("io/elementary/wingpanel/panel.css");
    }

    construct {
        height_request = 30;
        hexpand = true;
        vexpand = true;
        valign = Gtk.Align.START;

        right_menubar = new IndicatorMenuBar ();
        right_menubar.halign = Gtk.Align.END;
        right_menubar.get_style_context ().add_provider (resource_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

        box.pack_end (right_menubar);

        add (box);

        unowned IndicatorManager indicator_manager = IndicatorManager.get_default ();
        indicator_manager.indicator_added.connect (add_indicator);
        indicator_manager.indicator_removed.connect (remove_indicator);

        indicator_manager.get_indicators ().@foreach ((indicator) => {
            add_indicator (indicator);

            return true;
        });

        style_context = get_style_context ();
        style_context.add_class (StyleClass.PANEL);
        style_context.add_provider (resource_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        Services.BackgroundManager.get_default ().background_state_changed.connect (update_background);

        var granite_settings = Granite.Settings.get_default ();
        var gtk_settings = Gtk.Settings.get_default ();

        gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;

        granite_settings.notify["prefers-color-scheme"].connect (() => {
            gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        });
    }

    public override bool button_press_event (Gdk.EventButton event) {
        if (event.button != Gdk.BUTTON_PRIMARY) {
            return Gdk.EVENT_PROPAGATE;
        }

        var window = get_window ();
        if (window == null) {
            return Gdk.EVENT_PROPAGATE;
        }

        // Grabbing with touchscreen on X does not work unfortunately
        if (event.device.get_source () == Gdk.InputSource.TOUCHSCREEN) {
            return Gdk.EVENT_PROPAGATE;
        }

        uint32 time = event.time;

        window.get_display ().get_default_seat ().ungrab ();

        Gdk.ModifierType state;
        event.get_state (out state);

        popover_manager.close ();

        var scale_factor = this.get_scale_factor ();
        var x = (int)event.x_root * scale_factor;
        var y = (int)event.y_root * scale_factor;

        var background_manager = Services.BackgroundManager.get_default ();
        return background_manager.begin_grab_focused_window (x, y, (int)event.button, time, state);
    }

    public void cycle (bool forward) {
        var current = popover_manager.current_indicator;
        if (current == null) {
            return;
        }

        IndicatorEntry? sibling;
        if (forward) {
            sibling = get_next_sibling (current);
        } else {
            sibling = get_previous_sibling (current);
        }

        if (sibling != null) {
            popover_manager.current_indicator = sibling;
        }
    }

    public void initialize (IndicatorManager.ServerType server_type) {
        if (server_type == IndicatorManager.ServerType.GREETER)
            return;

        left_menubar = new Appmenu.MenuWidget ();
        left_menubar.bold_application_name = true;
        left_menubar.margin_start = 6;
        left_menubar.get_style_context ().add_provider (resource_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        box.pack_start (left_menubar);
    }

    private IndicatorEntry? get_next_sibling (IndicatorEntry current) {
        IndicatorEntry? sibling = null;

        var children = right_menubar.get_children ();
        int index = children.index (current);
        if (index < children.length () - 1) { // Has more than one indicator in the right menubar
            sibling = children.nth_data (index + 1) as IndicatorEntry;
        }

        return sibling;
    }

    private IndicatorEntry? get_previous_sibling (IndicatorEntry current) {
        IndicatorEntry? sibling = null;

        var children = right_menubar.get_children ();
        int index = children.index (current);
        if (index != 0) { // Is not the first indicator in the right menubar
            sibling = children.nth_data (index - 1) as IndicatorEntry;
        }

        return sibling;
    }

    private void add_indicator (Indicator indicator) {
        var indicator_entry = new IndicatorEntry (indicator, popover_manager);

        indicator_entry.set_transition_type (Gtk.RevealerTransitionType.SLIDE_LEFT);
        right_menubar.insert_sorted (indicator_entry);
        indicator_entry.show_all ();
    }

    private void remove_indicator (Indicator indicator) {
        remove_indicator_from_container (right_menubar, indicator);
    }

    private void remove_indicator_from_container (Gtk.Container container, Indicator indicator) {
        foreach (unowned Gtk.Widget child in container.get_children ()) {
            unowned IndicatorEntry? entry = (child as IndicatorEntry);

            if (entry != null && entry.base_indicator == indicator) {
                container.remove (child);

                return;
            }
        }
    }

    private void update_background (Services.BackgroundState state, uint animation_duration) {
        if (style_provider == null) {
            style_provider = new Gtk.CssProvider ();
            style_context.add_provider (style_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        string css = """
            .panel {
                transition: all %ums ease-in-out;
            }
        """.printf (animation_duration);

        try {
            style_provider.load_from_data (css, css.length);
        } catch (Error e) {
            warning ("Parsing own style configuration failed: %s", e.message);
        }

        switch (state) {
            case Services.BackgroundState.DARK :
                style_context.add_class ("color-light");
                style_context.remove_class ("color-dark");
                style_context.remove_class ("maximized");
                style_context.remove_class ("translucent");
                break;
            case Services.BackgroundState.LIGHT:
                style_context.add_class ("color-dark");
                style_context.remove_class ("color-light");
                style_context.remove_class ("maximized");
                style_context.remove_class ("translucent");
                break;
            case Services.BackgroundState.MAXIMIZED:
                style_context.add_class ("maximized");
                style_context.remove_class ("color-light");
                style_context.remove_class ("color-dark");
                style_context.remove_class ("translucent");
                break;
            case Services.BackgroundState.TRANSLUCENT_DARK:
                style_context.add_class ("translucent");
                style_context.add_class ("color-light");
                style_context.remove_class ("color-dark");
                style_context.remove_class ("maximized");
                break;
            case Services.BackgroundState.TRANSLUCENT_LIGHT:
                style_context.add_class ("translucent");
                style_context.add_class ("color-dark");
                style_context.remove_class ("color-light");
                style_context.remove_class ("maximized");
                break;
        }
    }
}
