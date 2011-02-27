require 'bdb'

Struct.new('OpenBSDMan', :name, :fullname, :title, :category, :os, :text)

db = BDB::Btree.open('man.db', nil, "r")

db.each do | bla |
  foo = Marshal.load(bla[1])
  #foo.each_pair {|name, value| puts("#{name} => #{value}") }
  puts "name: \"" + foo.name + "\""
  puts "fullname: \"" + foo.fullname + "\""
  puts "category: \"" + foo.category + "\""
  #exit 1
end

db.close
