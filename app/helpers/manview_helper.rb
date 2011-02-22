module ManviewHelper

  def man_parser(text, name)

    atext = text.split("\n")
    ntext = Array.new

    atext.each do | line |
      # stuff we don't want
      line.sub!(/^\s*/, '')
      line.sub!(/^\.\\\".*/, '')
      line.sub!(/^\.Dt.*/, '')
      line.sub!(/^\.Dd.*/, '')
      line.sub!(/^\.Os/, '')
      line.sub!(/^\.Nd/, ' - ')
      line.sub!(/^\.Pp/, '<br><br>')
      line.sub!(/\\&$/, '')

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
      # order matters here!
      line.sub!(/^\.Nm\s+(.+)\s*(,)*/, " <b>\\1</b>\\2 ")
      line.sub!(/^\.Xr\s*([a-zA-Z\.]+)\s*([0-9]+)\s*(,)*/, "<a href=\"search?manview[man_category]=\\2&manview[man_name]=\\1&manview[strict]=true\">\\1(\\2)</a>\\3")
      line.sub!(/^\.Sh\s+(.+)/, "<br><br><b>\\1</b><br>")
      line.sub!(/^\.Nm\s+(.+)/, "<b>\\1</b>")
      line.sub!(/^\.Nm\s*$/, "<b>#{name}</b>")
      line.sub!(/^\.Cm\s+(.+)/, "<b>\\1</b>")
      line.sub!(/^\.Fd\s+(.+)/, "<b>\\1</b><br>")
      line.sub!(/^\.Pq\s+Ar\s+([a-zA-Z0-9]+)/, " (<u>\\1</u>) ")
      line.sub!(/^\.Pa\s+(.+)/, "<u>\\1</u>")
      line.sub!(/^\.Op\s+Fl\s+(.+)Ar\s+(.+)/, " [<b>-\\1</b><u>\\2</u>]")
      line.sub!(/^\.Op\s+Fl\s+(.+)/, " [<b>-\\1</b>]")
      line.sub!(/^\.Op\s+Ar\s+(.+)/, " [<u>\\1</u>]")
      line.sub!(/^\.Ar\s+([a-zA-Z0-9]+)/, " <u>\\1</u> ")
      line.sub!(/^\.Oo/, '[')
      line.sub!(/^\.Oc/, ']')
      line.sub!(/^\.Dq\s*([a-zA-Z0-9]+)\s*([a-zA-Z0-9]*)/, "\"\\1 \\2\"")
      line.sub!(/^\.It\s+Fl\s+(.+)/, "<b>-\\1</b>")
      line.sub!(/^\.It\s+Ar\s+(.+)/, "<u>\\1</u>")

      line.sub!(/\s+(\")+/, "\\1")

      line = ' ' + line
      line.sub!(/\s+/, ' ')
      line.sub!(/\s+\./, '.')

      ntext.push(line) if !line.empty?
    end

    return ntext.to_s
  end
end
