module ManviewHelper

  def parse_manhtml(text, name, category)
    atext = text.split("\n")
    ntext = Array.new
    upname = name.upcase

    atext.each do |line|
      next if line =~ /^<html>|<\/html>|<head>|<\/head>|<body>|<\/body>|<\!--|-->|<meta/ ||
              line =~ /OpenBSD 4.5 [January|Febuary|March|April|May|June|July|September|October|November|December]+/ ||
              line =~ /OpenBSD .+ Manual/ ||
              line =~ /<p><font size=3>#{upname} \( #{category} \)/

      line.sub!(/align=center/, '')
      line.sub!(/``/, '"')
      line.gsub!(/<font size=3><tt>([a-zA-Z\.\-_0-9]+)<\/tt><font size=3>\(([0-9]+)\)(,*)/, " <a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true\">\\1(\\2)</a>\\3 ")
      line.sub!(/width="100%"  rules="none"  frame="none"/, '')
      ntext << line + "\n"
    end

    return ntext
  end

  def man_parser(text, name)

    atext = text.split("\n")
    ntext = Array.new
    close_tr = false
    add_tab_br = false
    columns = nil

    atext.each_index do | index |
      line = atext[index].to_s

      # default for each line
      bracket_open = false

      # stuff we don't want
      line.sub!(/^\s*/, '')
      line.sub!(/^\.\\\".*/, '')
      line.sub!(/^\.Dt.*/, '')
      line.sub!(/^\.Dd.*/, '')
      line.sub!(/^\.Os/, '')
      line.sub!(/^\.Dv\s*/, '')
      line.sub!(/^\.Li\s*/, '')
      line.sub!(/^\.TH.*/, '')
      line.sub!(/^\.\s*$/, '')
      line.sub!(/\\&/, '')

      # not sure here
      line.sub!(/^\.Bk.*/, '')
      line.sub!(/^\.Ek.*/, '')

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
      line.sub!(/^\.Oo/, '[')
      line.sub!(/^\.Oc/, ']')
      line.sub!(/^\.Dq\s*([a-zA-Z0-9]+)\s*([a-zA-Z0-9]*)/, "\"\\1 \\2\"")
      line.sub!(/^\.Sq\s+(.+)\s+(.+)/, "'\\1'\\2")
      line.sub!(/^\.Sq\s+(.+)/, "'\\1'")
      line.sub!(/^\.Bd\s+(.+)/, "<p><PRE>")
      line.sub!(/^\.Ed\s*/, "</PRE></p>")

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
