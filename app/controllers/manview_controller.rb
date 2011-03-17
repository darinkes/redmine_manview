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
    @os_selection = [ 'PhantomBSD', 'OpenBSD49', 'any' ]
    @categories = [ 'any', 1, 2, 3, '3p', 4, 5, 6, 7, 8, 9 ]
    @archs = [ 'any', 'i386', 'AMD64']
    @cachesize = CACHE.dbsize
    @querytime = params[:querytime] || nil
    @search = ''

    if params[:manview]

      @search = params[:manview][:man_name] || ''
      category = params[:manview][:man_category] || 0
      os = params[:manview][:man_os] || 'PhantomBSD'
      arch = params[:manview][:man_arch] || 'any'
      strict = params[:manview][:strict] == 'true' ? true : false

      if @search != ''
        search_man(@search, category, os, arch, strict)
      end
    end

  end

private

  def search_man(search, category, os, arch, strict)
    start = Time.now

    @found = Array.new
    cached = false

    Struct.new('ManPage', :name, :fullname, :title, :category, :os, :text)

    if search !~ /^[a-zA-Z0-9\._\-:\+]+$/
      flash[:error] = "Invalid search string"
      redirect_to :action => 'index'
      return
    end

    query ="#{search}-#{category}-#{os}-#{arch}-#{strict}"

    db = BDB::Btree.open(FILE, nil, "r")

    @found = get_from_cache(query)

    search = Regexp.escape(search)

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
          break
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
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != category
          next if manpage.os != os && os != 'any'
          if manpage.title =~ /\s*#{search}\s*/i
            @found.push manpage
          end
        }
      end
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != "#{category}/#{DEF_ARCH}"
          next if manpage.os != os && os != 'any'
          if manpage.title =~ /\s*#{search}\s*/i
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
        if manpage.fullname =~ /#{search}/i || manpage.title =~ /\s*#{search}\s*/i
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
        if manpage.fullname =~ /#{search}/i || manpage.title =~ /\s*#{search}\s*/i
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

  def add_links(text, os)
     # <span class="underline">gcc</span>(1),
      text.gsub!(/(<span class=\".+\")*([a-zA-Z0-9\._\-:\+]+)(<\/span>)*\(([0-9]+)\)/,
        "<a href=\"?manview[man_category]=\\4&manview[man_name]=\\2&manview[strict]=true&manview[man_os]=#{os}\">\\1\\2(\\4)\\3</a>")
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
    CACHE.set query, Marshal.dump(result)
  end

  def clear_cache
  end

end
