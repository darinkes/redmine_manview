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
    @os_selection = [ 'any', 'PhantomBSD', 'OpenBSD current' ]
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
    @raw = params[:manview][:raw] == 'true' ? true : false

    @found = Array.new
    cached = false

    Struct.new('ManPage', :name, :fullname, :title, :category, :os, :text, :rawtext)

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
        if manpage.name =~ /^#{search}$/
          @found.push manpage
        end
      }
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != category
          next if manpage.os != os && os != 'any'
          if manpage.fullname =~ /.+, #{search}$/ || manpage.fullname =~ /.+, #{search},.+/
            @found.push manpage
          end
        }
      end
      if @found.empty?
        db.each { | entry |
          manpage = Marshal.load(entry[1])
          next if manpage.category != "#{category}/#{DEF_ARCH}"
          next if manpage.os != os && os != 'any'
          if manpage.name =~ /^#{search}$/ || manpage.fullname =~ /.+, #{search}$/ || manpage.fullname =~ /.+, #{search},.+/
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
        next if manpage.os != os && os != 'any'
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
        next if manpage.os != os && os != 'any'
        if manpage.fullname =~ /#{search}/
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
          element.text = new_man_parser(element.rawtext, element.name, element.os)
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

  def man_link(name, category, os)
    return  "<a href=\"search?manview[man_category]=#{category}&manview[man_name]=#{name}&manview[man_os]=#{os}&manview[strict]=true\">#{name}(#{category})</a> "
  end

  def new_man_parser(text, name, os)

    atext = text.split("\n")
    ntext = Array.new

    close_tr = false
    pre_opened = false
    gnu = false

    atext = atext.join(' --n-- ').gsub(/\\[&]/, '').gsub(/\\([\-\s\|]){1}/, "\\1").gsub(/\\fB([A-Za-z0-9\-=\,\+\*\s\.\#\@]+)\\fR/, "<b>\\1</b>").split(' --n-- ')
    atext = atext.join(' --n-- ').gsub(/\\[&]/, '').gsub(/\\([\-\s\|]){1}/, "\\1").gsub(/\\fB([A-Za-z0-9\-=\,\+\*\s\.\#\@]+)\\fP/, "<b>\\1</b>").split(' --n-- ')
    atext = atext.join(' --n-- ').gsub(/\\[&]/, '').gsub(/\\([\-\s\|]){1}/, "\\1").gsub(/\\fI([A-Za-z0-9\-=\,\+\*\s\.\#\@]+)\\fR/, "<u>\\1</u>").split(' --n-- ')
    atext = atext.join(' --n-- ').gsub(/\\[&]/, '').gsub(/\\([\-\s\|]){1}/, "\\1").gsub(/\\fI([A-Za-z0-9\-=\,\+\*\s\.\#\@]+)\\fP/, "<u>\\1</u>").split(' --n-- ')

    atext.each_index do | index |
      line = atext[index].to_s

      if pre_opened && line !~ /^\.Ed/
        ntext << line.gsub(/\\e/, '\\') + "\n"
        next
      end

      gnu = true if line =~ /^\.\\\"\s+Standard\s+preamble:/


      if gnu && line !~ /^\.SH/
        next
      else
        gnu = false
      end

      line.sub!(/^\.BR\s*/, '')
      line.gsub!(/\\\*\(C\+/, 'C++')
      line.gsub!(/\\\*\([L|R]/, '')

      line.gsub!(/\s*(\\fB|\\fI)*([A-Za-z\-\.]+)(\\fR|\\fP)*\s*\|*\(([0-9]+)\)(,|\.)*/,
        " <a href=\"search?manview[man_category]=\\4&manview[man_name]=\\2&manview[strict]=true&manview[man_os]=#{os}\">\\1\\2\\3(\\4)</a>\\5 ")
      line.sub!(/^\.IX\s+Item\s+(.+)/, "<br><br><u>\\1</u><br><br>")

      next if line =~ /^\.\\\"|^\.Dt|^\.Os|^\.Dd|^\.Bk|^\.Ek|^\.TH|^\.Sm|^\.IX|^\.IP/

      items = line.split(' ')
      line = ''

      close_u   = false
      close_b   = false
      no_space  = false
      columns = true

      items.each_index do | index |
        item = items[index]

        if close_u
          item += '</u>'
          close_u = false
        end

        if close_b
          item += '</b>'
          close_b = false
        end

        # these elements must have a leading dot
        if item =~ /^\.It$/
          item = ''
          item = '</th></tr>' if close_tr
          item += '<tr><th style="font-weight: normal" valign="top">'
          items << '</th><th style="font-weight: normal" valign="top">'
          close_tr = true
        end

        # remove leading dot
        item.sub!(/^\./, '')

        if item =~ /^Sh$|^SH$/
          line = "<br><br><h2>#{items[1, items.size].join(' ').to_s}</h2>"
          break
        elsif item =~ /^Nm$/
          if items.size == 1
            line = "<b>#{name}</b>"
          else
            line = "<b>#{items.join(' ').sub(/\.*Nm\s+/, '')}</b>"
          end
          break
        elsif item =~ /^Nd$/
          line = " - #{items[1, items.size].join(' ').to_s}"
          break
        elsif item =~ /^Xr$/
          line = man_link(items[index + 1], items[index + 2], os)
          line += ',' if items[index + 3].eql?(',')
          break
        elsif item =~ /^Ns$/
          nospace = true
          item = ''
        elsif item =~ /^Xo$/
          item = ''
        elsif item =~ /^Xc$/
          item = ''
        elsif item =~ /^Op$/
          item = '['
          items << 'Oc'
        elsif item =~ /^Pa$/
          item = '<u>'
          items << '</u>'
        elsif item =~ /^Va$/
          item = '<u>'
          items << '</u>'
        elsif item =~ /^Pq$/
          item = '(<u>'
          items << '</u>)'
        elsif item =~ /^Em$/
          item = '<u>'
          items << '</u>'
        elsif item =~ /^Ft$/
          item = '<br><u>'
          items << '</u>'
        elsif item =~ /^Aq$/
          item = '&lt;'
          items << '&gt;'
        elsif item =~ /^Oo$/
          item = '['
        elsif item =~ /^Oc$/
          item = ']'
        elsif item =~ /^Fl$/
          #item = '- <b>'
          #close_b = true
          item = '- '
        elsif item =~ /^B$/
          item = '<b>'
          items << '</b>'
        elsif item =~ /^Fn$/
          item = '<b>'
          items << '</b>'
        elsif item =~ /^Cm$/
          item = '<b>'
          close_b = true
        elsif item =~ /^Ar$/
          item = '<u>'
          close_u = true
        elsif item =~ /^Dq$/
          item = '"'
          items << '"'
        elsif item =~ /^Sq$/
          item = '\''
          items << '\''
        elsif item =~ /^Pp$|^PP$/
          item = '<br><br>'
        elsif item =~ /^Bl$/
          item = '<table border="0" style="text-align:left;" cellpadding="2">'
        elsif item =~ /^El$/
          item = '</table>'
          close_tr = false
        elsif item =~ /^Ds$/
          item = ''
        elsif item =~ /^Sy$/
          item = ''
        elsif item =~ /^Dv$/
          item = ''
        elsif item =~ /^Ta$/
          item = ''
        elsif item =~ /^Li$/
          item = ''
        elsif item =~ /^Bd$/
          item = '<pre>'
          pre_opened = true
        elsif item =~ /^Ed$/
          item = '</pre>'
          pre_opened = false
        elsif item =~ /^Dl$/
          item = '<pre>'
          items << '</pre>'
        elsif item =~ /^Fd$/
          line = '<b><pre>' + CGI::escapeHTML(items.join(' ').sub(/^Fd\s/, '')) + '</pre></b>'
          break
        elsif item =~ /^Bx/
          item = 'BSD'
        elsif item =~ /^Fx/
          item = 'FreeBSD'
        elsif item =~ /^Nx/
          item = 'NetBSD'
        elsif item =~ /^Ox/
          item = 'OpenBSD'
        elsif item =~ /^Bsx/
          item = 'BSDI BSD/OS'
        elsif item =~ /^\-literal/
          item = ''
          break
        elsif item =~ /^\-dash/
          item = ''
          break
        elsif item =~ /^\-offset/
          item = ''
          break
        elsif item =~ /^\-tag/
          item = ''
        elsif item =~ /^\-width/
          item = ''
          break
        elsif item =~ /^\-column/
          nline = line.sub(/.+\s+\-column/, '').sub(/\-.+/, '')
          if nline =~ /\"/
            columns = nline.split(/\"/).delete_if{|a| a.empty? || a.eql?(' ')}.size
          else
            columns = nline.split(/\s+/).delete_if{|a| a.empty? || a.eql?(' ')}.size
          end
          break
        end

        if nospace
          line += item
        else
          line += ' ' + item
        end
      end
      line.gsub!(/\\e/, '\\')
      ntext << line + "\n" if !line.empty?
    end
    return ntext
  end

  def man_parser(text, name, os)

    atext = text.split("\n")
    ntext = Array.new
    close_tr = false
    add_tab_br = false
    reference_start = false
    reference_done = false
    columns = nil

    ref_title = ''
    ref_date = ''
    ref_name = ''

    atext.each_index do | index |
      line = atext[index].to_s

      # default for each line
      bracket_open = false

      # stuff we don't want
      line.sub!(/^\s*/, '')
      line.sub!(/^\.\\\".*/, '')
      line.sub!(/^\.Dt.*/, '')
      line.sub!(/^\.Dd.*/, '')
      line.sub!(/^\.Sm.*/, '')
      line.sub!(/^\.TH.*/, '')
      line.sub!(/^\.Os/, '')
      line.sub!(/^\.Dv\s*/, '')
      line.sub!(/^\.Li\s*/, '')
      line.sub!(/^\.\s*$/, '')
      line.sub!(/\\&/, '')
      line.gsub!(/\\e/, '\\')

      # not sure here
      line.sub!(/^\.Bk.*/, '')
      line.sub!(/^\.Ek.*/, '')
      line.sub!(/^\.Ev\s*/, '')

      # reformat
      bracket_open = true if !line.sub!(/^\.Pf\s+\(\s*(.+)\s*/, ".\\1").nil?

      # escape line to be able to show e.g. include-paths
      line = CGI::escapeHTML(line)

      # aliases
      line.sub!(/^\.Bx/, '<em>BSD</em>')
      line.sub!(/^\.Fx/, '<em>FreeBSD</em>')
      line.sub!(/^\.Nx/, '<em>NetBSD</em>')
      line.sub!(/^\.Ox/, '<em>OpenBSD</em>')
      line.sub!(/^\.Bsx/, '<em>BSDI BSD/OS</em>')
      line.sub!(/^\.At v([0-9\.]+).*/, "<em>Version \\1 AT&T UNIX.</em>")

      # serious stuff
      line.sub!(/^\.Nd/, ' - ')
      line.sub!(/^\.Ql\s+(.+)/, " '\\1' ")
      line.sub!(/^\.So\s+(.+)\s+Sc/, " '\\1' ")
      line.sub!(/^\.Pp/, '<br><br>')
      line.sub!(/^\.Xr\s+(.+)\s+([0-9]+)\s*(,)*/, " <a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true&manview[man_os]=#{os}\">\\1(\\2)</a>\\3 ")
      line.sub!(/^\.Sh\s+(.+)/, "<br><br><b>\\1</b><br>")
      line.sub!(/^\.SH\s+(.+)/, "<br><br><b>\\1</b><br>")
      # order matters here!
      line.sub!(/^\.Nm\s+:\s*$/, "<b>#{name}</b>:")
      line.sub!(/^\.Nm\s+(.+)\s+(,)+/, " <b>\\1</b>\\2 ")
      line.sub!(/^\.Nm\s+\./, " <b>#{name}</b>. ")
      line.sub!(/^\.Nm\s+(.+)/, "<br><b>\\1</b>")
      line.sub!(/^\.Nm\s*$/, "<b>#{name}</b>")

      line.sub!(/^\.Cm\s+(.+)/, "<b>\\1</b>")
      line.sub!(/^\.Cd\s+(.+)/, "<b>\\1</b>")
      line.sub!(/^\.Fd\s+(.+)/, "<b>\\1</b><br>")
      line.sub!(/^\.Ft\s+(.+)/, "<u>\\1</u><br>")
      line.sub!(/^\.Em\s+(.+)/, " <u>\\1</u> ")
      line.sub!(/^\.Pq\s+Ar\s+(.+)/, " (<u>\\1</u>) ")
      line.sub!(/^\.Pq\s+(.+)/, " (\\1) ")
      line.sub!(/^\.Pq\s+Dq\s+(.+)/, " (\"\\1\") ")
      line.sub!(/^\.Pq\s+Sq\s+(.+)/, " ('\\1') ")
      line.sub!(/^\.Pa\s+(.+)/, "<u>\\1</u>")
      line.sub!(/^\.Fa\s+(.+)/, "<u>\\1</u>")
      line.sub!(/^\.Va\s+(.+)/, "<u>\\1</u>")
      # order matters here!
      line.sub!(/^\.Op\s+Oo\s+Fl\s+Oc\s+Ns\s+Cm\s+(.+)\s+Ar\s+(.+)/, " [[-]<b>\\1</b> <u>\\2</u>]")
      line.sub!(/^\.Op\s+Oo\s+Fl\s+Oc\s+Cm\s+(.+)\s+Op\s+Ar\s+(.+)/, " [[-]<b>\\1</b> [<u>\\2</u>]]")
      line.sub!(/^\.Op\s+Oo\s+Fl\s+Oc\s+Cm\s+(.+)\s+Ar\s+(.+)/, " [[-]<b>\\1</b> <u>\\2</u>]")
      line.sub!(/^\.Op\s+Oo\s+Fl\s+Oc\s+Cm\s+(.+)/, " [[-]<b>\\1</b> <u>\\2</u>]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Oo\s+Ar\s+(.+)\s+\:\s+Oc\s+Ns\s+Ar\s+(.+)\s+\:\s+Ns\s+Ar\s+(.+)\s+\:\s+Ns\s+Ar\s+(.+)/, "[-\\1 [\\2:]\\3:\\4:\\5]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Oo\s+Ar\s+(.+)\s+\:\s+Oc\s+Ns\s+Ar\s+(.+)/, "[-\\1 [\\2:]\\3]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Oo\s+Ar\s+(.+)\s+Oc\s+Ns\s+Ar\s+(.+)/, "[-\\1 [\\2]\\3]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Ar\s+(.+)Ns\s+Op\s+\:\s+Ns\s+Ar\s+(.+)/, "[<b>-\\1</b><u>\\2</u>[:<u>\\3</u>]]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Ar\s+(.+)\s+\:\s+Ns\s+Ar\s+(.+)/, " [<b>-\\1</b><u>\\2:\\3</u>]")
      line.sub!(/^\.Op\s+Fl\s+(.+)Ar\s+(.+)/, " [<b>-\\1</b><u>\\2</u>]")
      line.sub!(/^\.Op\s+Cm\s+(.+)Ar\s+(.+)/, " [<b>\\1</b><u>\\2</u>]")
      line.sub!(/^\.Op\s+Fl\s+(.+)/, " [<b>-\\1</b>]")
      line.sub!(/^\.Op\s+Cm\s+(.+)/, " [<b>\\1</b>]")
      line.sub!(/^\.Op\s+Ar\s+(.+)/, " [<u>\\1</u>]")

      line.sub!(/^\.Fl\s+(.+)\s+Ar\s+(.+)\s+\|\s+Fl\s+(.+)\s+Ar\s+(.+)/, "<b>-\\1</b> \\2 | <b>-\\3</b> \\4")
      line.sub!(/^\.Fl\s+(.+)\s+Ar\s+(.+)/, "<b>-\\1</b> \\2")
      line.sub!(/^\.Fl\s+(.+)/, " <b>-\\1</b> ")

      line.sub!(/^\.Ar\s+(.+)Oc/, " <u>\\1</u>] ")
      line.sub!(/^\.Ar\s+(.+)/, " <u>\\1</u> ")
      line.sub!(/^\.Dl\s+(.+)/, "<p><PRE>\\1</PRE></p>")
      line.sub!(/^\.Oo\s+Oo\s+Fl\s+Oc\s+Cm\s+(.+)\s+Ar\s+(.+)/, "[[-] <b>\\1</b> <u>\\2</u>")
      line.sub!(/^\.Oo\s+Fl\s+Oc\s+Cm\s+(.+)\s+Ar\s+(.+)/, "[-] <b>\\1</b> <u>\\2</u>")
      line.sub!(/^\.Oo\s+Fl\s+Oc\s+Ns\s+Cm\s+(.+)/, "[-] <b>\\1</b>")
      line.sub!(/^\.Oo\s+Fl\s+(.+)\\(.+)/, "[<b>-\\1</b>")
      line.sub!(/^\.Oo\s+Ar\s+(.+)\s+Ns\s+(.+)\s+Oc\s+Ns\s+Ar(.+)/, "[\\1\\2]\\3")
      line.sub!(/^\.Oo\s+Ar\s+(.+)\s+Ns\s+Oc/, "[\\1]")
      line.sub!(/^\.Oo\s+Ar\s+(.+)\s+Oc/, "[\\1]")
      line.sub!(/^\.Oo/, '[')
      line.sub!(/^\.Oc/, ']')
      line.sub!(/^\.Dq\s*([a-zA-Z0-9]+)\s*([a-zA-Z0-9]*)/, "\"\\1 \\2\"")
      line.sub!(/^\.Sq\s+(.+)\s+(.+)/, "'\\1'\\2")
      line.sub!(/^\.Sq\s+(.+)/, "'\\1'")
      line.sub!(/^\.Bd\s+(.+)/, "<p><PRE>")
      line.sub!(/^\.Ed\s*/, "</PRE></p>")

      # Reference
      reference_done = true if !line.sub!(/^\.Re\s*/, '').nil?
      if reference_start && !reference_done
        ref_title = line if !line.sub!(/^\.%T\s+(.+)/, "\\1").nil?
        ref_date = line if !line.sub!(/^\.%D\s+(.+)/, "\\1").nil?
        ref_name = line if !line.sub!(/^\.%R\s+(.+)/, "\\1").nil?
        line = ''
      end
      reference_start = true if !line.sub!(/^\.Rs\s*/, '<br><br>').nil?

      if reference_done
        line = "<u>#{ref_title}</u>, #{ref_name}, #{ref_date}"
        reference_start = false
        reference_done = false
      end

      if !line.sub!(/^\.In\s+(.+)/, "<b>#include &lt;\\1&gt;</b><br>").nil? &&
         atext[index + 1].to_s !~ /^\.In\s+(.+)/
        line += "<br>"
      end

      if line =~ /^\.Fn\s+.+\s+.+/
        line.sub!(/^\.Fn\s+/, '')
        items = line.gsub(/\s+/,' ').split(/&quot;/)
        items = line.gsub(/\s+/,' ').split(/ /) if items.size == 1
        items.each_index do |index|
          item = items[index]
          next if item =~ /^\s*$/
          if index == 0
            line = "<b>#{item}</b>("
          elsif item == items.last
            line += "<u>#{item}</u>);<br><br>"
          else
            line += "<u>#{item}</u>, "
          end
        end
      elsif line =~ /^\.Fn\s+.+/
        line.sub!(/^\.Fn\s+(.+)/, "<b>\\1()</b>")
      end

      if atext[index + 1].to_s =~ /^\.(El|It)/ && close_tr && columns.nil?
        line += "</th></tr>"
        close_tr = false
      end

      # Begin List
      # column list
      if line =~ /\.Bl\s+-column/ && columns.nil?
         columns = atext[index].sub(/\.It/, '').sub(/\s+/, ' ').split(/\s+/).size
         line = "<table border=\"0\" style=\"text-align:left;\" cellpadding=\"10\">"
      end

      if !columns.nil? && line =~ /^\.It.+/
         items = line.sub(/\.It/, '').gsub(/\s+[A-Z]{1}[a-z]{1}\s+/, '').sub(/\s+/, ' ').split(/\s+/)
         line = "<tr>"
         items.each do | item |
           line += "<th>#{item}</th>"
         end
         line += "</tr>"
      end

      line.sub!(/^\.Bl(.+)/, "<table border=\"0\" style=\"text-align:left;\" cellpadding=\"10\">")

      # List Item
      # .It Cm carpdemote Op Ar number
      close_tr = true if
          !line.sub!(/^\.It\s+Fl\s+(.+)\s+Op\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>-\\1</b> [<u>\\2</u>]</th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Fl\s+(.+)\s+Ar\s+(.+)/, "<tr><th valign=\"top\" ><b>-\\1</b> <u>\\2</u></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Fl\s+(.+)/, "<tr><th valign=\"top\"><b>-\\1</b></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)\s+Ar\s+(.+)\s+Ns\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b> <u>\\2\\3</u></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)\s+Op\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b> [<u>\\2</u>]</th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b> <u>\\2</u></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><u>\\1</u></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Pa\s+(.+)/, "<tr><th valign=\"top\">\\1</th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Va\s+(.+)/, "<tr><th valign=\"top\">\\1</th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Aq\s+Pa\s+(.+)/, "<tr><th valign=\"top\"><u>&lt;\\1&gt;</u></th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s+Bq\s+Er\s+(.+)/, "<tr><th valign=\"top\">[\\1]</th><th style=\"font-weight: normal\">").nil? ||
          !line.sub!(/^\.It\s*/, "<tr><th valign=\"top\"></th><th style=\"font-weight: normal\">").nil?

      # End List
      # reset to defaults
      if !line.sub!(/^\.El\s*/, "</table>").nil?
        columns = nil
      end

      # Debian-Manpage-Tags see dpkg(1)

      # link to man-page
=begin
      if line =~ /.+\(\d+\)/
         line.sub!(/(.+)\s*([0-9]+)\s*(,)*/, " <a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true&manview[man_os]=#{os}\">\\1\\2</a>\\3 ")
      end
=end

      line.sub!(/^\.SS\s+(.+)/, "<br><br><b>\\1</b><br>")
      add_tab_br = true  if !line.sub!(/^\.nf/, '').nil?
      add_tab_br = false if !line.sub!(/^\.fi/, '').nil?
      line.gsub!(/\\fI(.+)\\fP/, "<u>\\1</u>")
      line.gsub!(/\\fB(.+)\\fP/, "<b>\\1</b>")

      line = "<pre>\t" + line + "</pre>" if add_tab_br

      # remove escape-char
      # XXX: uncomment if all debian-tags are parsed
      # line.gsub!(/\\/, '')

      # some cleanup with spaces
      line.sub!(/\s+(\")+/, "\\1")

      line = ' ' + line
      line.sub!(/\s+/, ' ')
      line.sub!(/\s+\./, '.')

      line = '( ' + line if bracket_open

      ntext.push(line + "\n") if !line.empty?
    end

    return ntext.to_s
  end

end
