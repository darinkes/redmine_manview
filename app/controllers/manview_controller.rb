class ManviewController < ApplicationController
  unloadable

  require 'bdb'

  FILE = '/var/www/redmine/man.db'
  CACHE = Hash.new

  # XXX: autocompletion?
  def index
    @manpage = ""
    @os_selection = [ 'any', 'PhantomBSD', 'OpenBSD current' ]
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
      if !cached
        @found.each do | element |
          element.text = man_parser(element.rawtext, element.name)
        end
        add2cache(query, @found)
      end
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

  def man_parser(text, name)

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
      line.sub!(/^\.Xr\s+(.+)\s+([0-9]+)\s*(,)*/, " <a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true\">\\1(\\2)</a>\\3 ")
      line.sub!(/^\.Sh\s+(.+)/, "<br><br><b>\\1</b><br>")
      line.sub!(/^\.SH\s+(.+)/, "<br><br><b>\\1</b><br>")
      # order matters here!
      line.sub!(/^\.Nm\s+:\s*$/, "<b>#{name}</b>:")
      line.sub!(/^\.Nm\s+(.+)\s*(,)*/, " <b>\\1</b>\\2 ")
      line.sub!(/^\.Nm\s+(.+)/, "<b>\\1</b>")
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
         columns = atext[index + 1].sub(/\.It.+/, '').sub(/\s+/, ' ').split(/\s+/).size
         line = "<table border=\"0\" style=\"text-align:left;\" cellpadding=\"10\">"
      end

      if !columns.nil? && line =~ /^\.It.+/
         items = line.sub(/\.It\s+(Sy\s*)*/, '').sub(/\s+/, ' ').split(/\s+/)
         line = "<tr>"
         items.each do | item |
           line += "<th>#{item}</th>"
         end
         line += "</tr>"
      end

      line.sub!(/^\.Bl(.+)/, "<table border=\"0\" style=\"text-align:left;\" cellpadding=\"10\">")

      # List Item
      close_tr = true if !line.sub!(/^\.It\s+Fl\s+(.+)\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>-\\1</b> <u>\\2</u></th><th>").nil? ||
          !line.sub!(/^\.It\s+Fl\s+(.+)/, "<tr><th valign=\"top\"><b>-\\1</b></th><th>").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)\s+Ar\s+(.+)\s+Ns\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b> <u>\\2\\3</u></th><th>").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b> <u>\\2</u></th><th>").nil? ||
          !line.sub!(/^\.It\s+Cm\s+(.+)/, "<tr><th valign=\"top\"><b>\\1</b></th><th>").nil? ||
          !line.sub!(/^\.It\s+Ar\s+(.+)/, "<tr><th valign=\"top\"><u>\\1</u></th><th>").nil? ||
          !line.sub!(/^\.It\s+Pa\s+(.+)/, "<tr><th valign=\"top\">\\1</th><th>").nil? ||
          !line.sub!(/^\.It\s+Va\s+(.+)/, "<tr><th valign=\"top\">\\1</th><th>").nil? ||
          !line.sub!(/^\.It\s+Aq\s+Pa\s+(.+)/, "<tr><th valign=\"top\"><u>&lt;\\1&gt;</u></th><th>").nil? ||
          !line.sub!(/^\.It\s+Bq\s+Er\s+(.+)/, "<tr><th valign=\"top\">[\\1]</th><th>").nil? ||
          !line.sub!(/^\.It\s*/, "<tr><th valign=\"top\"></th><th>").nil?

      # End List
      # reset to defaults
      if !line.sub!(/^\.El\s*/, "</table>").nil?
        columns = nil
      end

      # Debian-Manpage-Tags see dpkg(1)

      # link to man-page
=begin
      if line =~ /.+\(\d+\)/
         line.sub!(/(.+)\s*([0-9]+)\s*(,)*/, " <a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true\">\\1\\2</a>\\3 ")
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
