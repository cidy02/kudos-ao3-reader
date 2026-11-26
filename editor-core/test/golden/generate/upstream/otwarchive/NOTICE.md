# Vendored otwarchive files

The Ruby files in this directory are unmodified copies from the Organization for
Transformative Works' Archive of Our Own source code, <https://github.com/otwcode/otwarchive>,
at commit `452391b648f2fb06b55c36133812449747634504` (2026-11-01). otwarchive is licensed under the
GNU General Public License, version 2 (see `LICENSE` here). They are used only to generate the golden
test files in `editor-core/test/golden/`; they are not part of any shipped bundle.

Files: config/config.yml (read for the FIELDS_* lists), lib/html_cleaner.rb, lib/paragraph_maker.rb, lib/otw_sanitize/{embed,media,user_class}_sanitizer.rb,
config/initializers/gem-plugin_config/sanitizer_config.rb.
GPL-2.0-or-later per otwarchive's README (as relayed by the coordinator); LICENSE here is the GPL-2.0 text from the repo.
