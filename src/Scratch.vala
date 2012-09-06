// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE

  Copyright (C) 2011-2012 Giulio Collura <random.cpp@gmail.com>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as
  published    by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses>

  END LICENSE
***/

using Gtk;
using Gdk;

using Granite;
using Granite.Services;
using Scratch.Services;

namespace Scratch {


    public class ScratchApp : Granite.Application {

        public MainWindow window = null;
        static string app_cmd_name;
        static string app_set_arg;
        static bool new_instance;
        public GLib.List<Document> documents = new GLib.List<Document>();
        public string current_directory = ".";

        construct {

            build_data_dir = Constants.DATADIR;
            build_pkg_data_dir = Constants.PKGDATADIR;
            build_release_name = Constants.RELEASE_NAME;
            build_version = Constants.VERSION;
            build_version_info = Constants.VERSION_INFO;

            program_name = app_cmd_name;
            exec_name = app_cmd_name.down();
            app_years = "2011-2012";
            app_icon = "accessories-text-editor";
            app_launcher = "scratch-text-editor.desktop";
            application_id = "org.elementary." + app_cmd_name.down();
            main_url = "https://launchpad.net/scratch";
            bug_url = "https://bugs.launchpad.net/scratch";
            help_url = "https://answers.launchpad.net/scratch";
            translate_url = "https://translations.launchpad.net/scratch";
            about_authors = {"Mario Guerriero <mefrio.g@gmail.com>",
                         "Giulio Collura <random.cpp@gmail.com>",
                         "Lucas Baudin <xapantu@gmail.com>",
                         null
                         };
            //about_documenters = {"",""};
            about_artists = {"Harvey Cabaguio <harveycabaguio@gmail.com>",
                         null
                         };
            about_translators = "Launchpad Translators";
            about_license_type = License.GPL_3_0;
        }

        public ScratchApp () {

            Logger.initialize ("Scratch");
            Logger.DisplayLevel = LogLevel.DEBUG;

            ApplicationFlags flags = ApplicationFlags.HANDLES_OPEN;
            if(new_instance)
                flags |= ApplicationFlags.NON_UNIQUE;
            set_flags (flags);
            
            //register_session = true;
            
            saved_state = new SavedState ();
            settings = new Settings ();
            services = new ServicesSettings ();

            plugins = new Scratch.Plugins.Manager(settings.schema, "plugins-enabled", Constants.PLUGINDIR,  exec_name, app_set_arg);
            plugins.hook_example("Example text");
            plugins.scratch_app = this;
            plugins.hook_app(this);
            plugins.hook_set_arg(app_cmd_name, app_set_arg);
    
        }

        protected override void open (File[] files, string hint) {

            if (get_windows () == null) {
                window = new MainWindow (this);
                plugins.hook_new_window (window);
                window.TITLE = app_cmd_name ?? "Scratch";
                window.title = window.TITLE;
                window.show ();
            }

            for (int i = 0; i < files.length; i++) {
                if (files[i].get_basename () == "--new-tab")
                    window.action_new_tab ();
                else {
                    open_file(files[i].get_uri()).opening = false;
                }
            }

            window.present ();

        }

        public Document open_file(string? filename)
        {

            /* First, let's check it is not already opened */
            foreach(var doc in documents)
            {
                if(doc.filename == filename) {
                    /* Already opened, then, we will just focus it */
                    doc.focus_sourceview();
                    return doc;
                }
            }

            /* Is not open
             * filename is still encoded as uri, so a file is created
             * to extract a decoded version/display_name
             */

            var f = File.new_for_uri(filename);
            string decoded_filename = f.query_info(FileAttribute.STANDARD_DISPLAY_NAME, FileQueryInfoFlags.NONE).get_display_name();
            f.unref();

            current_directory = Path.get_dirname (filename);
            /* use the decoded version for presentation */
            var document = new Document(decoded_filename, window);
            document.create_sourceview ();
            documents.append (document);
            document.closed.connect( (doc) => { documents.remove(doc); });
            document.tab.make_backup ();
            window.current_notebook.set_tab ();
            window.set_window_title (decoded_filename);
            return document;

        }

        public void open_document(Document document) {
            document.create_sourceview ();
            documents.append (document);
            document.closed.connect( (doc) => { documents.remove(doc); });
            window.current_notebook.set_tab ();
            /* Apparently, it needs an iteration of the main loop to add the tab properly before we can focus it */
            Idle.add( () => { document.focus_sourceview(); return false; });
            
            window.set_window_title ("Scratch");
        }

        protected override void activate () {

            if (get_windows () == null) {
                window = new MainWindow (this);
                window.TITLE = app_cmd_name ?? "Scratch";
                window.title = window.TITLE;
                window.show ();
                plugins.hook_new_window (window);
                if (settings.show_at_start == "last-tabs")
                    restore_opened_files ();
            } else {
                window.present ();
            }

        }
        
        void on_quit () {
            foreach(var doc in documents)
                if(!doc.saved)
                    inhibit (window, ApplicationInhibitFlags.LOGOUT, _("There are unsaved changes in Scratch!"));
        }
        
        void restore_opened_files () {
            
            string[] op = settings.schema.get_strv ("opened-files");
            
            foreach (string file in op) {
               if (file != "") {
                    var doc = new Document (file, window);
                    if (doc.exists) 
                        open_document (doc);
                }
            }

        }
        
        static const OptionEntry[] entries = {
            { "set", 's', 0, OptionArg.STRING, ref app_cmd_name, N_("Set of plugins"), "" },
            { "set-arg", 'a', 0, OptionArg.STRING, ref app_set_arg, N_("Argument for the set of plugins"), "" },
            { "new-instance", 'n', 0, OptionArg.NONE, ref new_instance, N_("Create a new instance"), "" },
            { null }
        };

        public static int main (string[] args) {
            app_cmd_name = "Scratch";
            var context = new OptionContext("File");
            context.add_main_entries(entries, "scratch");
            context.add_group(Gtk.get_option_group(true));
            try {
                context.parse(ref args);
            }
            catch(Error e) {
                print(e.message + "\n");
            }

            var app = new ScratchApp ();
            
            plugins.plugin_iface.args = args;
            
            return app.run (args);

        }
        
    }
}