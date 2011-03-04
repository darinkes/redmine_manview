class ManviewController < ApplicationController
  unloadable

  require 'bdb'
  require 'rubygems'
  require 'redis'

  FILE = '/var/www/redmine/man.db'
  CACHE = Redis.new
  DEF_ARCH = 'i386'

  # XXX: autocompletion?
  def index
    @manpage = ""
    @os_selection = [ 'any', 'PhantomBSD', 'OpenBSD49' ]
    @categories = [ 'any', 1, 2, 3, '3p', 4, 5, 6, 7, 8, 9 ]
    @archs = [ 'any', 'i386', 'AMD64']
    @cachesize = CACHE.dbsize
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

    @found = Array.new
    cached = false

    Struct.new('ManPage', :name, :fullname, :title, :category, :os, :text)

    if search !~ /^[a-zA-Z0-9\._\-:]+$/
      flash[:error] = "Invalid search string"
      redirect_to :action => 'index'
      return
    end

    query ="#{search}-#{category}-#{os}-#{arch}-#{strict}"

    db = BDB::Btree.open(FILE, nil, "r")

    @found = get_from_cache(query)

    if !@found.nil?
      cached = true
    elsif (strict)
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        next if manpage.category != category
        next if manpage.os != os && os != 'any'
        if manpage.name =~ /^#{search}$/i
          @found.push manpage
        end
      }
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != category
          next if manpage.os != os && os != 'any'
          if manpage.fullname =~ /.+, #{search}$/i || manpage.fullname =~ /.+, #{search},.+/i
            @found.push manpage
          end
        }
      end
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != "#{category}/#{DEF_ARCH}"
          next if manpage.os != os && os != 'any'
          if manpage.name =~ /^#{search}$/i || manpage.fullname =~ /.+, #{search}$/i || manpage.fullname =~ /.+, #{search},.+/i
            @found.push manpage
          end
        }
      end
    elsif (category != 'any')
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if arch != 'any' && manpage.category =~ /\//
          next if manpage.category !~ /\/#{arch}/i
        end
        next if manpage.category != category
        next if manpage.os != os && os != 'any'
        if manpage.fullname =~ /#{search}/i
          @found.push manpage
        end
      }
    else
      @found = Array.new
      db.each { | entry |
        manpage = Marshal.load(entry[1])
        if arch != 'any' && manpage.category =~ /\//
          next if manpage.category !~ /\/#{arch}/i
        end
        next if manpage.os != os && os != 'any'
        if manpage.fullname =~ /#{search}/i
          @found.push manpage
        end
      }
    end


    if @found.empty?
      db.close
      add2cache(query, [])
      flash[:error] = "Nothing found for your search request #{search} #{category} #{arch} #{os}"
      redirect_to :action => 'index', :querytime => Time.now - start
      return
    else
      if !cached && @found.size == 1
        @found.each do | element |
          element.text = add_links(element.text, element.os)
        end
      end
      add2cache(query, @found)
    end

    @multiman = @found.size == 1 ? false : true
    @cachesize = CACHE.dbsize
    @querytime = Time.now - start

    db.close
  end

private

  def add_links(text, os)
     # <span class="underline">gcc</span>(1),
      text.gsub!(/(<span class=\".+\")*([A-Za-z\-\.]+)(<\/span>)*\(([0-9]+)\)/,
        "<a href=\"search?manview[man_category]=\\4&manview[man_name]=\\2&manview[strict]=true&manview[man_os]=#{os}\">\\1\\2\\3(\\4)</a>")
      return text
  end

  # XXX: clear cache if the shasum of db has changed
  def get_from_cache(query)
    cache = CACHE.get query
    return nil if cache.nil?
    result = Marshal.load(cache)
    return result
  end

  def add2cache(query, result)
    CACHE.delete(query)
    CACHE.set query, Marshal.dump(result)
  end

  def clear_cache
  end

end
