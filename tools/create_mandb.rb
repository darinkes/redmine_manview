require 'bdb'
require 'tempfile'
require "open3"

env = BDB::Env.open "tmp", BDB::INIT_MPOOL | BDB::CREATE | BDB::INIT_LOCK

db = BDB::Btree.open "man.db", nil, BDB::CREATE, "env" => env

notfound = 0
id = 0

record = Struct.new('ManPage', :name, :fullname, :title, :category, :os, :text)

File.open("/usr/share/man/whatis.db").each { |line|
  array = line.split(/\s+-\s+/)
  name = array[0]
  array.delete_at(0)
  category = name.sub(/.*\(/, '').sub(/\).*/, '')
  pure_name = name.sub(/\s*\(.*/, '').sub(/,.*/, '')
  name = name.sub(/\s+\(.+\)/, '')

  category, arch = category.split('/')

  title = array.to_s

  data = ''
  output = ''

  man2web = "/usr/local/bin/man2web"
  man2web = "export MACHINE=#{arch} && "  + man2web if !arch.nil?

  Open3.popen3 "#{man2web} -s #{category} #{pure_name.downcase}" do |stdin, stdout, stderr|
    stdin.close
    output = stdout.read
  end

  #puts "Output-Size1: #{output.size}"

  if output =~ /<h2>No manual entry for #{Regexp.escape(pure_name.downcase)}<\/h2>/
    Open3.popen3 "#{man2web} -s #{category} #{pure_name}" do |stdin, stdout, stderr|
      stdin.close
      output = stdout.read
    end
  end
  #puts "Output-Size2: #{output.size}"

  if output =~ /<h2>No manual entry for #{Regexp.escape(pure_name)}<\/h2>/
    Open3.popen3 "#{man2web} #{pure_name}" do |stdin, stdout, stderr|
      stdin.close
      output = stdout.read
    end
  end
  #puts "Output-Size3: #{output.size}"

  if output =~ /<h2>No manual entry for #{Regexp.escape(pure_name)}<\/h2>/
    puts "man2web was unable to find #{category} #{pure_name}"
    notfound += 1
    next
  end
  #puts "Output-Size4: #{output.size}"

  if output.empty?
    puts "man2web returned empty string for: category => #{category}, arch => #{arch}, name => #{pure_name}"
    puts "command => #{man2web}"
    puts "output => #{output}"
    exit 1
  end

  output_array = output.split("\n")
  data = String.new
  output_array[21, output_array.size].each do | element |
    data += element + "\n" if element !~ /^<\/pre|^<\/body|^<\/html/
  end

  category = category + '/' + arch if !arch.nil?

  rec = record.new(pure_name, name, title, category, 'PhantomBSD', data)
  db["#{id}-PhantomBSD"] = Marshal.dump(rec)

  id += 1
}
db.close

puts "Found: #{id}"
puts "Not Found: #{notfound}"
