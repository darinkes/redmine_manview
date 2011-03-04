require 'bdb'
require "open3"

db = BDB::Btree.create('man.db', nil, "w", 0644)

notfound = 0
found = 0
id = 0

record = Struct.new('ManPage', :name, :fullname, :title, :category, :os, :text)

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

  Open3.popen3 "man2web -s #{category} #{pure_name.downcase}" do |stdin, stdout, stderr|
    stdin.close
    output = stdout.read
  end

  output_array = output.split("\n")
  data = String.new
  output_array[21, output_array.size].each do | element |
    data += element + "\n" if element !~ /^<\/pre|^<\/body|^<\/html/
  end

  if output.empty?
    puts "man2web returned empty string for #{category} #{pure_name}"
    next
  end

  rec = record.new(pure_name, name, title, category, 'OpenBSD49', data)
  db["#{id}-OpenBSD49"] = Marshal.dump(rec)

  id += 1
}
db.close

puts "Total: #{id}"
puts "Found: #{found}"
puts "Not Found: #{notfound}"
