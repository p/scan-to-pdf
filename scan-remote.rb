#!/usr/bin/env ruby

require 'byebug'
require 'optparse'
require 'net/ssh'
require 'net/scp'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: scan-remote [-t target] [-d device] [-r dpi]"

  opts.on("-t", "--target TARGET", "The host on which to scan") do |v|
    options[:target] = v
  end

  opts.on("-d", "--device DEVICE", "Specify the device to use") do |v|
    options[:device] = v
  end

  opts.on("-r", "--resolution RES", "Specify the resolution to use") do |v|
    options[:resolution] = v.to_i
  end

  opts.on("-m", "--mode MODE", "Specify the mode to use") do |v|
    options[:mode] = v
  end

  opts.on("--letter", "Explicitly specify Letter dimensions") do
    options[:letter] = true
  end

  opts.on("-o", "--output PATH", "Specify the final PDF path") do |v|
    options[:output] = v
  end

  opts.on("-e", '--rotate', "Rotate the image counterclockwise 90 degrees") do
    options[:rotate] = true
  end
end.parse!

dest = options.fetch(:output)
unless dest =~ /\.pdf\z/
  STDERR.puts "Adjusting #{dest} -> #{dest}.pdf"
  dest = "#{dest}.pdf"
end

user, host = options.fetch(:target).split('@')

Net::SCP.start(host, user) do |scp|
  ssh = scp.session

  tmpdir = ssh.exec!('mktemp -d /tmp/scan-remote-rb-XXXXXX').strip

  remote_dest = "#{tmpdir}/out.pdf"
  cmd  = "~/apps/scan-to-pdf/scan.rb -d '#{options[:device]}' -r '#{options[:resolution]}' --letter -o '#{remote_dest}'"
  if options[:mode]
    cmd += " -m '#{options[:mode]}'"
  end
  if options[:rotate]
    cmd += ' -e'
  end
  ssh.exec(cmd).wait

  scp.download(remote_dest, dest)
  scp.download("#{tmpdir}/out-raw.pdf", dest.sub(/\.pdf\z/, '-raw.pdf'))

  ssh.exec('rm -rf #{tmpdir}').wait
end
