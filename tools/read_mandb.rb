require 'bdb'

Struct.new('OpenBSDMan', :name, :fullname, :title, :category, :text)

db = BDB::Btree.open('man.db', nil, "r")

db.each do | bla |
  foo = Marshal.load(bla[1])
  #foo.each_pair {|name, value| puts("#{name} => #{value}") }
  puts "\"" + foo.name + "\""
  puts "\"" + foo.fullname + "\""
  #exit 1
end

db.close
