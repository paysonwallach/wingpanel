/*-
 * Copyright (c) 2015 Wingpanel Developers (http://launchpad.net/wingpanel)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class Wingpanel.PanelWindow : Gtk.Window {
	private Widgets.Panel panel;

	private Services.PopoverManager popover_manager;

	private int monitor_number;

	private int monitor_width;
	private int monitor_height;

	private int monitor_x;
	private int monitor_y;

	private int panel_height;

	private bool expanded;

	private int panel_displacement;

	public PanelWindow (Gtk.Application app, int monitor_number = -1) {
		this.monitor_number = monitor_number == -1 ? this.screen.get_primary_monitor () : monitor_number;

		Services.BackgroundManager.get_default ().init (this.monitor_number);

		this.set_application (app);

		this.decorated = false;
		this.resizable = false;
		this.skip_taskbar_hint = true;
		this.app_paintable = true;
		this.type_hint = Gdk.WindowTypeHint.DOCK;
		this.vexpand = false;

		var style_context = get_style_context ();
		style_context.add_class (Widgets.StyleClass.PANEL);
		style_context.add_class (Gtk.STYLE_CLASS_MENUBAR);

		this.screen.size_changed.connect (update_panel_dimensions);
		this.screen.monitors_changed.connect (update_panel_dimensions);
		this.screen_changed.connect (update_visual);

		update_visual ();

		popover_manager = new Services.PopoverManager (this);

		panel = new Widgets.Panel (popover_manager);
		panel.realize.connect (on_realize);

		this.add (panel);

		set_expanded (false);
	}

	private bool animation_step () {
		if (panel_displacement <= panel_height * (-1))
			return false;

		panel_displacement--;

		update_panel_dimensions ();

		return true;
	}

	private void on_realize () {
		update_panel_dimensions ();

		Services.BackgroundManager.get_default ().update_panel_alpha ();

		Timeout.add (300 / panel_height, animation_step);
	}

	private void update_panel_dimensions () {
		panel.get_preferred_height (out panel_height, null);

		Gdk.Rectangle monitor_dimensions;
		this.screen.get_monitor_geometry (monitor_number, out monitor_dimensions);

		monitor_width = monitor_dimensions.width;
		monitor_height = monitor_dimensions.height;

		this.set_size_request (monitor_width, -1);

		monitor_x = monitor_dimensions.x;
		monitor_y = monitor_dimensions.y;

		this.move (monitor_x, monitor_y - (panel_height + panel_displacement));

		Services.BackgroundManager.get_default ().update_panel_height (panel_height);

		update_struts ();
	}

	private void update_visual () {
		var visual = this.screen.get_rgba_visual ();

		if (visual == null)
			warning ("Compositing not available, things will Look Bad (TM)");
		else
			this.set_visual (visual);
	}

	private void update_struts () {
		if (!this.get_realized () || panel == null)
			return;

		var monitor = monitor_number == -1 ? this.screen.get_primary_monitor () : monitor_number;

		var position_top = monitor_y - panel_displacement;

		Gdk.Atom atom;
		Gdk.Rectangle primary_monitor_rect;

		long struts[12];

		this.screen.get_monitor_geometry (monitor, out primary_monitor_rect);

		struts = {0, 0, position_top, 0, // strut-left, strut-right, strut-top, strut-bottom
				0, 0, // strut-left-start-y, strut-left-end-y
				0, 0, // strut-right-start-y, strut-right-end-y
				monitor_x, monitor_x + monitor_width -1, // strut-top-start-x, strut-top-end-x
				0, 0}; // strut-bottom-start-x, strut-bottom-end-x

		atom = Gdk.Atom.intern ("_NET_WM_STRUT_PARTIAL", false);

		Gdk.property_change (this.get_window (), atom, Gdk.Atom.intern ("CARDINAL", false),
				32, Gdk.PropMode.REPLACE, (uint8[])struts, 12);
	}
	
	uint shrink_timeout = 0;

	public void set_expanded (bool expanded) {
		if (this.expanded == expanded)
			return;
		if (expanded) {
			Services.BackgroundManager.get_default ().remember_window ();

			this.expanded = expanded;
			
			if (shrink_timeout > 0) {
				Source.remove (shrink_timeout);
				shrink_timeout = 0;
			}
			this.set_size_request (monitor_width, expanded ? monitor_height : -1);
		} else {
			Services.BackgroundManager.get_default ().restore_window ();

			this.expanded = expanded;

			if (shrink_timeout > 0)
				Source.remove (shrink_timeout);

			shrink_timeout = Timeout.add (300, () => {
				shrink_timeout = 0;
				this.set_size_request (monitor_width, expanded ? monitor_height : -1);
				return false;
			});
		}
	}
}
