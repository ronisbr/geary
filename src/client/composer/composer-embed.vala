/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A ComposerEmbed is a widget that is used to compose emails that are inlined into a
 * conversation view, e.g. for reply or forward mails.
 */
public class ComposerEmbed : Gtk.EventBox, ComposerContainer {

    private const int MIN_EDITOR_HEIGHT = 200;

    private ConversationViewer conversation_viewer;

    // The id of the composer HTML element
    private string embed_id;
    private bool setting_inner_scroll;
    private bool scrolled_to_bottom = false;
    //private double inner_scroll_adj_value;
    private int inner_view_height;
    private int min_height = MIN_EDITOR_HEIGHT;

    protected ComposerWidget composer { get; set; }

    protected Gee.MultiMap<string, string>? old_accelerators { get; set; }

    public Gtk.ApplicationWindow top_window {
        get { return (Gtk.ApplicationWindow) get_toplevel(); }
    }

    public ComposerEmbed(ComposerWidget composer, ConversationViewer conversation_viewer,
        Geary.Email referred) {
        this.composer = composer;
        this.conversation_viewer = conversation_viewer;
        this.halign = Gtk.Align.FILL;
        this.valign = Gtk.Align.FILL;

        WebKit.DOM.HTMLElement? email_element = null;
        // email_element = conversation_viewer.web_view.get_dom_document().get_element_by_id(
        //     conversation_viewer.get_div_id(referred.id)) as WebKit.DOM.HTMLElement;
        // embed_id = referred.id.to_string() + "_reply";
        // if (email_element == null) {
        //     warning("Embedded composer could not find email to follow.");
        //     email_element = conversation_viewer.web_view.get_dom_document().get_element_by_id(
        //         "placeholder") as WebKit.DOM.HTMLElement;
        // }

        try {
            email_element.insert_adjacent_html("afterend",
                @"<div id='$embed_id' class='composer_embed'></div>");
        } catch (Error error) {
            debug("Error creating embed element: %s", error.message);
            return;
        }

        add(composer);
        realize.connect(on_realize);
        this.composer.editor.focus_in_event.connect(on_focus_in);
        this.composer.editor.focus_out_event.connect(on_focus_out);
        this.composer.editor.document_load_finished.connect(on_loaded);
        this.conversation_viewer.compose_overlay.add_overlay(this);
        show();
        present();
    }

    private void on_realize() {
        update_style();

        Gtk.ScrolledWindow win = (Gtk.ScrolledWindow) this.composer.editor.parent;
        win.get_vscrollbar().hide();

        this.composer.editor.vadjustment.value_changed.connect(on_inner_scroll);
        this.composer.editor.vadjustment.changed.connect(on_adjust_changed);
        this.composer.editor.user_changed_contents.connect(on_inner_size_changed);

        reroute_scroll_handling(this);
    }

    private void on_loaded() {
        try {
           composer.editor.get_dom_document().body.get_class_list().add("embedded");
        } catch (Error error) {
            debug("Error setting class of editor: %s", error.message);
        }
        Idle.add(() => {
            recalc_height();
            conversation_viewer.compose_overlay.queue_resize();
            return false;
        });
    }

    private void reroute_scroll_handling(Gtk.Widget widget) {
        widget.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK);
        widget.scroll_event.connect(on_inner_scroll_event);
        Gtk.Container? container = widget as Gtk.Container;
        if (container != null) {
            foreach (Gtk.Widget child in container.get_children())
                reroute_scroll_handling(child);
        }
    }

    private void disable_scroll_reroute(Gtk.Widget widget) {
        widget.scroll_event.disconnect(on_inner_scroll_event);
        Gtk.Container? container = widget as Gtk.Container;
        if (container != null) {
            foreach (Gtk.Widget child in container.get_children())
                disable_scroll_reroute(child);
        }
    }

    private void update_style() {
        Gdk.RGBA window_background = top_window.get_style_context()
            .get_background_color(Gtk.StateFlags.NORMAL);
        Gdk.RGBA background = get_style_context().get_background_color(Gtk.StateFlags.NORMAL);

        if (background == window_background)
            return;

        get_style_context().changed.disconnect(update_style);
        override_background_color(Gtk.StateFlags.NORMAL, window_background);
        get_style_context().changed.connect(update_style);
    }

    public void remove_composer() {
        if (this.composer.editor.has_focus)
            on_focus_out();

        this.composer.editor.focus_in_event.disconnect(on_focus_in);
        this.composer.editor.focus_out_event.disconnect(on_focus_out);

        this.composer.editor.vadjustment.value_changed.disconnect(on_inner_scroll);
        this.composer.editor.user_changed_contents.disconnect(on_inner_size_changed);
        disable_scroll_reroute(this);
        Gtk.ScrolledWindow win = (Gtk.ScrolledWindow) composer.editor.parent;
        win.get_vscrollbar().show();

        try {
            this.composer.editor.get_dom_document().body.get_class_list().remove("embedded");
        } catch (Error error) {
            debug("Error setting class of editor: %s", error.message);
        }

        remove(composer);
        close_container();
    }

    public bool set_position(ref Gdk.Rectangle allocation, double hscroll, double vscroll,
        int view_height) {
        // WebKit.DOM.Element embed = this.conversation_viewer.web_view.get_dom_document()
        //     .get_element_by_id(this.embed_id);
        // if (embed == null)
        //     return false;

        // int div_height = (int) embed.client_height;
        // int y_top = (int) (embed.offset_top + embed.client_top) - (int) vscroll;
        // int available_height = int.min(y_top + div_height, view_height) - int.max(y_top, 0);

        // if (available_height < 0 || available_height == div_height) {
        //     // It fits in the available space, or it doesn't fit at all
        //     allocation.y = y_top;
        //     // When offscreen, make it very small to ensure scrolling during any edit
        //     allocation.height = (available_height < 0) ? 1 : div_height;
        // } else if (available_height > min_height) {
        //     // There's enough room, so make sure we get the whole widget in
        //     allocation.y = int.max(y_top, 0);
        //     allocation.height = available_height;
        // } else {
        //     // Minimum height widget, placed so as much as possible is visible
        //     allocation.y = int.max(y_top, int.min(y_top + div_height - min_height, 0));
        //     allocation.height = min_height;
        // }
        // allocation.x = (int) (embed.offset_left + embed.client_left) - (int) hscroll;
        // allocation.width = (int) embed.client_width;

        // // Work out adjustment of composer web view
        // this.setting_inner_scroll = true;
        // this.composer.editor.vadjustment.set_value(allocation.y - y_top);
        // this.setting_inner_scroll = false;
        // // This sets the scroll before the widget gets resized.  Although the adjustment
        // // may be scrolled to the bottom right now, the current value may not do that
        // // once the widget is shrunk; for example, while scrolling down the page past
        // // the bottom of the editor.  So if we're at the bottom, record that fact.  When
        // // the limits of the adjustment are changed (watched by on_adjust_changed), we
        // // can keep it at the bottom.
        // this.scrolled_to_bottom = (y_top <= 0 && available_height < view_height);

        return true;
    }

    private void on_inner_scroll(Gtk.Adjustment adj) {
        // double delta = adj.value - this.inner_scroll_adj_value;
        // this.inner_scroll_adj_value = adj.value;
        // if (delta != 0 && !setting_inner_scroll) {
        //     Gtk.Adjustment outer_adj = this.conversation_viewer.web_view.vadjustment;
        //     outer_adj.set_value(outer_adj.value + delta);
        // }
    }

    private void on_adjust_changed(Gtk.Adjustment adj) {
        if (this.scrolled_to_bottom) {
            this.setting_inner_scroll = true;
            adj.set_value(adj.upper);
            this.setting_inner_scroll = false;
        }
    }

    private void on_inner_size_changed() {
        this.scrolled_to_bottom = false;  // The inserted character may cause a desired scroll
        Idle.add(recalc_height);  // So that this runs after the character has been inserted
    }

    private bool recalc_height() {
        int view_height,
            base_height = get_allocated_height() - this.composer.editor.get_allocated_height();
        try {
            view_height = (int) this.composer.editor.get_dom_document()
                .query_selector("#message-body").offset_height;
        } catch (Error error) {
            debug("Error getting height of editor: %s", error.message);
            return false;
        }

        if (view_height != inner_view_height || min_height != base_height + MIN_EDITOR_HEIGHT) {
            this.inner_view_height = view_height;
            this.min_height = base_height + MIN_EDITOR_HEIGHT;
            // Calculate height widget should be to avoid scrolling in editor
            // int widget_height = int.max(view_height + base_height - 2, min_height); //? about 2
            // WebKit.DOM.Element embed = this.conversation_viewer.web_view
            //     .get_dom_document().get_element_by_id(this.embed_id);
            // if (embed != null) {
            //     try {
            //         embed.style.set_property("height", @"$widget_height", "");
            //     } catch (Error error) {
            //         debug("Error setting height of composer widget");
            //     }
            // }
        }
        return false;
    }

    private bool on_inner_scroll_event(Gdk.EventScroll event) {
        //this.conversation_viewer.web_view.scroll_event(event);
        return true;
    }

    public void present() {
        this.top_window.present();
        // this.conversation_viewer.web_view.get_dom_document().get_element_by_id(this.embed_id)
        //     .scroll_into_view_if_needed(false);
    }

    public void vanish() {
        hide();
        this.composer.state = ComposerWidget.ComposerState.DETACHED;
        this.composer.editor.focus_in_event.disconnect(on_focus_in);
        this.composer.editor.focus_out_event.disconnect(on_focus_out);

        // WebKit.DOM.Element embed = this.conversation_viewer.web_view.get_dom_document().
        //     get_element_by_id(this.embed_id);
        // try{
        //     embed.parent_element.remove_child(embed);
        // } catch (Error error) {
        //     warning("Could not remove embed from WebView: %s", error.message);
        // }
    }

    public void close_container() {
        if (visible)
            vanish();
        this.conversation_viewer.compose_overlay.remove(this);
    }
}

