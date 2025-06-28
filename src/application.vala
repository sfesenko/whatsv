/* MIT License
 *
 * Copyright (c) 2025 Sergii Fesenko
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * SPDX-License-Identifier: MIT
 */

[GtkTemplate (ui = "/com/github/sfesenko/whatsv/window.ui")]
public class Whatsv.Window : Gtk.ApplicationWindow {

    public Window (Gtk.Application app) {
        Object (application: app);
        var view = new WebKit.WebView();
        view.load_uri("https://web.whatsapp.com");
        set_child (view);
    }
}

public class Whatsv.Application : Gtk.Application {
    public Application () {
        Object (
            application_id: "com.github.sfesenko.whatsv",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/com/github/sfesenko/whatsv"
        );
    }

    construct {
        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "quit", this.quit }
        };
        this.add_action_entries (action_entries, this);
        this.set_accels_for_action ("app.quit", {"<primary>q"});
    }

    public override void activate () {
        base.activate ();
        var win = this.active_window ?? new Whatsv.Window (this);
        win.present ();
    }

    private void on_about_action () {
        string[] authors = { "Sergii Fesenko" };
        Gtk.show_about_dialog (
            this.active_window,
           "program-name", "WhatsV",
           "logo-icon-name", "com.github.sfesenko.whatsv",
           "authors", authors,
           "translator-credits", _("translator-credits"),
           "version", "0.1.0",
           "copyright", "© 2025 Sergii Fesenko"
       );
    }
}
