class ManviewController < ApplicationController
  unloadable

  require 'bdb'

  FILE = '/var/www/redmine/man.db'

  # XXX: autocompletion?
  def index
    @manpage = ""
    @os_selection = [ 'PhantomBSD' ]
  end

  # XXX: statt eigenen view in index rendern
  # XXX: caching? shasum der DB speichern und gerenderte Seiten cachen.
  def search
    search = params[:manview][:man_name]
    category = params[:manview][:man_category]
    os = params[:manview][:man_os]
    strict = params[:manview][:strict] == 'true' ? true : false
    @raw = params[:manview][:raw] == 'true' ? true : false

    @found = Array.new
    record = Struct.new('OpenBSDMan', :name, :fullname, :title, :category, :text)

    if search !~ /^[a-zA-Z0-9\._-]+$/
      #@found.push record.new("nothing", "nothing", "nothing", "any", "Invalid search string")
      flash[:error] = "Invalid search string"
      redirect_to :action => 'index'
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
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          if manpage.category == category && (manpage.fullname =~ /.+, #{search}$/ || manpage.fullname =~ /.+, #{search},.+/)
            @found.push manpage
          end
        }
      end
    elsif (category != 'any')
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if manpage.category == category && manpage.fullname =~ /#{search}/
          @found.push manpage
        end
      }
    else
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if manpage.fullname =~ /#{search}/
          @found.push manpage
        end
      }
    end

    if @found.empty?
      #@found.push record.new("nothing", "nothing", "nothing", "any", "Nothing found for your search request #{search}")
      flash[:error] = "Nothing found for your search request #{search}"
      redirect_to :action => 'index'
      return
    end

    @multiman = @found.size == 1 ? false : true

    db.close
  end
end
