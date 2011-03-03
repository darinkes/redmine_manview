require 'redmine'

module ManviewManMacro
  Redmine::WikiFormatting::Macros.register do
    desc "Creates link to manpage.\n\n" +
      " !{{manpage(name, category, os)}}\n"
    macro :manpage do |obj, args|
      return "Too few/many arguments for manpage: {{manpage(name, category, os)}}" if args.size != 3
      name = args[0].gsub(/\s+/, '')
      category = args[1].gsub(/\s+/, '')
      os = args[2].gsub(/\s+/, '')
      return link_to "#{h name}(#{h category})", {:controller => 'manview', :action => 'search',
                                                  :manview => {:man_name => name, :man_category => category, :strict => true, :man_os => os}
                                                 }
    end
  end
end
