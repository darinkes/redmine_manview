require 'redmine'

Dir::foreach(File.join(File.dirname(__FILE__), 'lib')) do |file|
  next unless /\.rb$/ =~ file
  require file
end

Redmine::Plugin.register :redmine_manpage do
  name 'Redmine Manpage plugin'
  author 'Stefan Rinkes'
  description 'This is a manpage-viewer plugin for Redmine'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'

  menu :application_menu, :manview, { :controller => 'manview', :action => 'index' }, :caption => 'ManView'

end
