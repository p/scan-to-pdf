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

  opts.on("-i", "--image", "Scan image, omit document processing") do
    options[:image] = true
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

  opts.on('-n', '--no-processing', 'Skip unpaper processing other than rotation') do
    options[:no_processing] = true
  end

  opts.on('--no-black-filter', 'Skip unpaper black filter') do
    options[:no_black_filter] = true
  end

  opts.on('--no-gray-filter', 'Skip unpaper gray filter') do
    options[:no_gray_filter] = true
  end

  opts.on('--no-noise-filter', 'Skip unpaper noise filter') do
    options[:no_noise_filter] = true
  end
end.parse!

dest = options.fetch(:output)
if options[:image]
  ext = 'jpg'
elsif File.extname(dest) == '.jpg'
  ext = 'jpg'
  options[:image] = true
else
  ext = 'pdf'
end
unless dest =~ /\.#{ext}\z/
  STDERR.puts "Adjusting #{dest} -> #{dest}.#{ext}"
  dest = "#{dest}.#{ext}"
end

target = options.fetch(:target)
if target.include?('@')
  user, host = target.split('@')
else
  user, host = nil, target
end

Net::SCP.start(host, user) do |scp|
  ssh = scp.session

  tmpdir = ssh.exec!('mkdir -p $HOME/.cache && mktemp -d $HOME/.cache/scan-remote-rb-XXXXXX').strip

  remote_dest = "#{tmpdir}/out.#{ext}"
  cmd  = "~/apps/scan-to-pdf/scan.rb -o '#{remote_dest}'"
  if options[:device]
    cmd += " -d '#{options[:device]}'"
  end
  if options[:resolution]
    cmd += " -r '#{options[:resolution]}'"
  end
  if options[:image]
    cmd += ' --image'
  end
  if options[:letter]
    cmd += ' --letter'
  end
  if options[:mode]
    cmd += " -m '#{options[:mode]}'"
  end
  if options[:rotate]
    cmd += ' -e'
  end
  if options[:no_processing]
    cmd += ' --no-processing'
  end
  if options[:no_black_filter]
    cmd += ' --no-black-filter'
  end
  if options[:no_gray_filter]
    cmd += ' --no-gray-filter'
  end
  if options[:no_noise_filter]
    cmd += ' --no-noise-filter'
  end
  p cmd
  ssh.exec(cmd).wait

  scp.download(remote_dest, dest).wait
  puts "Wrote #{dest}"
  unless options[:image]
    raw_dest = dest.sub(/\.pdf\z/, '-raw.pdf')
    scp.download("#{tmpdir}/out-raw.pdf", raw_dest).wait
    puts "Wrote #{raw_dest}"
  end

  ssh.exec("rm -rf #{tmpdir}").wait
end
