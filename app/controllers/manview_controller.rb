class ManviewController < ApplicationController
  unloadable

  require 'bdb'

  FILE = '/var/www/redmine/man.db'
  CACHE = Hash.new

  # XXX: autocompletion?
  def index
    @manpage = ""
    @os_selection = [ 'PhantomBSD' ]
    @categories = [ 'any', 1, 2, 3, '3p', 4, 5, 6, 7, 8, 9 ]
    @archs = [ 'any', 'i386', 'AMD64']
    @cachesize = CACHE.size
    @querytime = params[:querytime] || nil
  end

  # XXX: statt eigenen view in index rendern
  def search
    start = Time.now

    search = params[:manview][:man_name]
    category = params[:manview][:man_category]
    os = params[:manview][:man_os]
    arch = params[:manview][:man_arch] || 'any'
    strict = params[:manview][:strict] == 'true' ? true : false
    @raw = params[:manview][:raw] == 'true' ? true : false

    @found = Array.new
    Struct.new('OpenBSDMan', :name, :fullname, :title, :category, :text)

    if search !~ /^[a-zA-Z0-9\._\-:]+$/
      flash[:error] = "Invalid search string"
      redirect_to :action => 'index'
      return
    end

    query ="#{search}-#{category}-#{os}-#{arch}-#{strict}"

    db = BDB::Btree.open(FILE, nil, "r")

    @found = get_from_cache(query)

    if !@found.nil?
      # nothing
    elsif (strict)
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        next if manpage.category != category
        if manpage.name =~ /^#{search}$/
          @found.push manpage
        end
      }
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != category
          if manpage.fullname =~ /.+, #{search}$/ || manpage.fullname =~ /.+, #{search},.+/
            @found.push manpage
          end
        }
      end
    elsif (category != 'any')
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if arch != 'any' && manpage.category =~ /\//
          next if manpage.category !~ /\/#{arch}/
        end
        next if manpage.category != category
        if manpage.fullname =~ /#{search}/
          @found.push manpage
        end
      }
    else
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if arch != 'any' && manpage.category =~ /\//
          next if manpage.category !~ /\/#{arch}/
        end
        if manpage.fullname =~ /#{search}/
          @found.push manpage
        end
      }
    end


    if @found.empty?
      db.close
      add2cache(query, [])
      flash[:error] = "Nothing found for your search request #{search} #{category} #{arch}"
      redirect_to :action => 'index', :querytime => Time.now - start
      return
    else
      add2cache(query, @found)
    end

    @multiman = @found.size == 1 ? false : true
    @cachesize = CACHE.size
    @querytime = Time.now - start

    db.close
  end

private

  # XXX: clear cache if the shasum of db has changed
  def get_from_cache(query)
    return CACHE.fetch(query, nil)
  end

  def add2cache(query, result)
    CACHE.merge!({ query => result })
  end

  def clear_cache
    CACHE.clear
  end

end
