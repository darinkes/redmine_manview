require 'rubygems'
require 'bdb'

require "open3"

db = BDB::Btree.create('man.db', nil, "w", 0644)

notfound = 0
found = 0
id = 0

record = Struct.new('OpenBSDMan', :name, :fullname, :title, :category, :text)

File.open("/usr/share/man/whatis.db").each { |line|
  array = line.split(/\s+-\s+/)
  name = array[0]
  array.delete_at(0)
  category = name.sub(/.*\(/, '').sub(/\).*/, '')
  pure_name = name.sub(/\s*\(.*/, '').sub(/,.*/, '')
  name = name.sub(/\s+\(.+\)/, '')

  title = array.to_s

  data = ''
  output = ''

  Open3.popen3 "/usr/bin/man -w #{category} #{pure_name}" do |stdin, stdout, stderr|
    stdin.close
    output = stdout.read
  end
  output_a = output.split(/\n/)
  puts "for #{pure_name}(#{category}) man said: #{output_a.join(' ')}"

  if !output_a.to_s.empty?
    output_a.each do |manfile|
      if File.exists?(manfile)
        File.open(manfile).each { |line|
          data += line
        }
      else
        puts "#{manfile} does not exists"
      end
      if data.empty?
        puts "Found #{manfile}, but it is empty"
        notfound += 1
      else
        found += 1
      end
    end
  end


  rec = record.new(pure_name, name, title, category, data)
  db[id] = Marshal.dump(rec)

  id += 1

}
db.close

puts "Total: #{id}"
puts "Found: #{found}"
puts "Not Found: #{notfound}"
