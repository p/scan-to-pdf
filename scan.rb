#!/usr/bin/env ruby

require 'byebug'
require 'tmpdir'
require 'optparse'
require 'childprocess'

def run(cmd)
  puts "Running: #{cmd.join(' ')}"
  process = ChildProcess.build(*cmd)
  process.io.inherit!
  process.start
  process.wait
end

def get_output(cmd)
  process = ChildProcess.build(*cmd)
  rd, wr = IO.pipe
  begin
    process.io.stdout = wr
    process.start
    wr.close

    output = ''
    thread = Thread.new do
      begin
        loop do
          output << rd.readpartial(16384)
        end
      rescue EOFError
        # Child has closed the write end of the pipe
      end
    end

    process.wait
    thread.join
  ensure
    wr.close rescue nil
    rd.close
  end

  output
end

def human_size(size)
  suffixes = %w(bytes KB MB GB)
  suffix_index = 0
  while size > 1024
    suffix_index += 1
    size = size.to_f / 1024
  end
  '%.2f %s' % [size, suffixes[suffix_index]]
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: scan [-d device] [-r dpi]"

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

  opts.on("-e", '--rotate', "Rotate the image clockwise 90 degrees") do
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

case extname = File.extname(options[:output])
when '.jpg'
  puts "Assuming image processing: #{options[:output]}"
  options[:image] = true
  options[:output_image] = true
end

FileUtils.mkdir_p(File.expand_path('~/.cache/scan-rb'))
Dir.mktmpdir('scan-rb-', File.expand_path('~/.cache/scan-rb')) do |tmpdir|
  args = ['scanadf', '-o', File.join(tmpdir, 'image-%04d.pnm')]
  if options[:device]
    args += ['-d', options[:device]]
  end
  if options[:resolution]
    args += ['--resolution', options[:resolution].to_s]
  end
  if options[:letter]
    args += %w(-x 215 -y 279.4)
  end
  if options[:mode]
    args += ['--mode', options[:mode]]
  end
  run(args)

  children = Dir.children(tmpdir)
  if children.length != 1 && options[:image]
    raise "Requested to scan an image but received multiple pages!"
  end
  children.each do |filename|
    path = File.join(tmpdir, filename)
    output = get_output(['identify', path])
    puts
    STDOUT << output.sub(%r,\A/([^\s/]+/)*,, '')

    if options[:resolution] && options[:resolution] > 0 && options[:letter]
      expected_w = (options[:resolution] * 8.5).to_i
      expected_h = options[:resolution] * 11

      actual_w, actual_h = output.split(' ', 4)[3].sub(/\+.*/, '').split('x').map(&:to_i)
      unless (0.9...1.1).include?(actual_w.to_f / expected_w) &&
        (0.9...1.1).include?(actual_h.to_f / expected_h)
      then
        raise "Expected image approximately #{expected_w}x#{expected_h}, got #{actual_w}x#{actual_h}"
      end
    end

    puts
    unpapered_path = path.sub(/\.pnm\z/, '-u.pnm')
    cmd = ['unpaper', '-l', 'none', '--dpi', options[:resolution].to_s]
    if options[:rotate]
      cmd += %w(--pre-rotate 90)
    end
    if options[:no_processing]
      cmd += %w(-n)
    end
    if options[:no_black_filter]
      cmd += %w(--no-blackfilter)
    end
    if options[:no_gray_filter]
      cmd += %w(--no-grayfilter)
    end
    if options[:no_noise_filter]
      cmd += %w(--no-noisefilter)
    end
    cmd += [path, unpapered_path]
    run(cmd)

    raw_path = path
    if options[:rotate]
      cmd = ['pnmrotate', '90', path]
      output = get_output(cmd)
      raw_path = path.sub(/\.pnm\z/, '-r.pnm')
      File.open(raw_path, 'w') do |f|
        f << output
      end
    end

    if options[:image]
      puts "Raw file size: #{human_size(File.stat(raw_path).size)}"
      cmd = ['convert', '-quality', '92', raw_path, output_path = options.fetch(:output)]
      run(cmd)
      puts "Compressed file size: #{human_size(File.stat(output_path).size)}"
    else
      puts
      cmd = ['tesseract', '--dpi', options[:resolution].to_s, raw_path, path.sub(/\.pnm\z/, ''), 'pdf']
      run(cmd)

      puts
      cmd = ['tesseract', '--dpi', options[:resolution].to_s, unpapered_path, unpapered_path.sub(/\.pnm\z/, ''), 'pdf']
      run(cmd)
    end
  end

  if options[:image]
    #FileUtils.mv(File.join(tmpdir, children.first), options[:output])
  else
    raw_cmd = %w(pdfunite)
    cmd = %w(pdfunite)
    1.upto(children.length) do |page_num|
      raw_cmd << File.join(tmpdir, "image-#{'%04d' % page_num}.pdf")
      cmd << File.join(tmpdir, "image-#{'%04d' % page_num}-u.pdf")
    end
    raw_path = options[:output].sub(/\.pdf\z/, '-raw.pdf')
    if raw_path == options[:output]
      raise "Output path must end in .pdf"
    end
    raw_cmd << raw_path
    cmd << options.fetch(:output)
    puts
    run(raw_cmd)
    run(cmd)
  end
end
