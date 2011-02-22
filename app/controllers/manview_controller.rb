class ManviewController < ApplicationController
  unloadable

  require 'bdb'

  FILE = '/var/www/redmine/man.db'

  # XXX: autocompletion?
  def index
    @manpage = ""
  end

  # XXX: statt eigenen view in index rendern
  def search
    search = params[:name]
    category = params[:category]

    strict = params[:strict] == 'true' ? true : false

    @found = Array.new
    record = Struct.new('OpenBSDMan', :name, :title, :category, :text)

    if search !~ /^[a-zA-Z0-9\.]+$/
      @found.push record.new("nothing", "nothing", "any", "Invalid search string")
      return
    end

    db = BDB::Btree.open(FILE, nil, "r")

    if (strict)
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if manpage.category == category && manpage.name =~ /^#{search}$/
          @found.push manpage
        end
      }
    elsif (category != 'any')
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if manpage.category == category && manpage.name =~ /#{search}/
          @found.push manpage
        end
      }
    else
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if manpage.name =~ /#{search}/
          @found.push manpage
        end
      }
    end

    if @found.empty?
       @found.push record.new("nothing", "nothing", "any", "Nothing found for your search request #{search}")
    end

    @multiman = @found.size == 1 ? false : true

    db.close
  end
end
