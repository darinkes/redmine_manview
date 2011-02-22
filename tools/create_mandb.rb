require 'rubygems'
require 'bdb'

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
  if File.exists?("/tmp/man/man#{category}/#{pure_name.downcase}.#{category}")
    File.open("/tmp/man/man#{category}/#{pure_name.downcase}.#{category}").each { |line|
      next if line =~ /<!--/
      data += line
    }
  end 
  if data.empty?
    puts "no manpage found for #{name} - #{title}"
    notfound += 1
    #exit 1
  else
    found += 1
    puts "found /tmp/man/man#{category}/#{pure_name.downcase}.#{category}"
  end

=begin
  datas = Hash.new
  datas = [
    'text' => data,
    'category' => category,
    'name' => name
  ]
  db[pure_name] = datas
=end

  rec = record.new(pure_name, name, title, category, data)
  db[id] = Marshal.dump(rec)

  id += 1

}
db.close

puts "Total: #{id}"
puts "Found: #{found}"
puts "Not Found: #{notfound}"
