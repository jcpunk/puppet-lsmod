#
# Fact: lsusb
#
# Purpose: get the results of lsusb
#
# Resolution:
#   Uses lsusb
#
# Caveats:
#   Needs lsusb in path
#
# Notes:
#   The result is 
#
if Facter::Util::Resolution.which('lsmod')
  tmphash = {}
  finalhash = {}
  modinfo = ['intree', 'srcversion', 'vermagic', 'version']
  t = []
  Facter::Util::Resolution.exec("lsmod 2>/dev/null").each_line do |line|
    if not line =~ /.+/
      next
    end
    if line =~ /^Module.+/
      next
    end
    matches = line.match(/(\S+)/)
    if matches
      t.push(Thread.new {
        waitforit = []
        modulename = matches[1].strip
        modhash = {}

        modhash = {}

        if Facter::Util::Resolution.which('modinfo')
          # Can't do this in parallel, other things need it first
          for info in modinfo
            result = Facter::Util::Resolution.exec("modinfo --field='filename' #{modulename} 2>/dev/null")
            if not result.nil?
              if not result.empty?
                modhash['filename'] = result.strip
              end
            end
          end
        end

        if Facter::Util::Resolution.which('modinfo')
          waitforit.push(Thread.new {
            for info in modinfo
              result = Facter::Util::Resolution.exec("modinfo --field=#{info} #{modulename} 2>/dev/null")
              if not result.nil?
                if not result.empty?
                  modhash[info] = result.strip
                end
              end
            end
          })

          waitforit.push(Thread.new {
            if File.directory?("/sys/module/#{modulename}/parameters")
              modhash['parm'] = {}
              result = Facter::Util::Resolution.exec("grep '' /sys/module/#{modulename}/parameters/* 2>/dev/null")
              if not result.nil?
                if not result.empty?
                  result.each_line do |txt|
                    if not txt =~ /.+:.+/
                      next
                    end
                    path = txt.split(':')[0]
                    parm = path.split('/').last
                    value = txt.split(':')[1].strip
                    modhash['parm'][parm] = value
                  end
                end
              end
            end
          })

          waitforit.push(Thread.new {
            mytaint = Facter::Util::Resolution.exec("cat /sys/module/#{modulename}/taint 2>/dev/null")
            if not mytaint.nil?
              if not mytaint.empty?
                if mytaint != 'Y'
                  modhash['taint'] = mytaint.strip
                end
              end
            end
          })

          waitforit.push(Thread.new {
            modhash['depends'] = []
            result = Facter::Util::Resolution.exec("modinfo --field=depends #{modulename} 2>/dev/null")
            if not result.nil?
              if not result.empty?
                result.each_line do |txt|
                  modhash['depends']= txt.strip.split(',')
                end
              end
            end
            if modhash['depends'] == []
              modhash.delete('depends')
            else
              modhash['depends'].sort
            end
          })
        end

        realname = Facter::Util::Resolution.exec("readlink -f #{modhash['filename']} 2>/dev/null")
        if realname.nil? or realname.empty?
          realname = modhash['filename']
        end
        realname = realname.strip
        if Facter::Util::Resolution.which('rpm')
          waitforit.push(Thread.new {
              modhash['package'] = Facter::Util::Resolution.exec("rpm -qf #{realname} 2>/dev/null").strip
          })
        elsif Facter::Util::Resolution.which('dpkg')
          waitforit.push(Thread.new {
            mypkgname = Facter::Util::Resolution.exec("dpkg -s #{realname} 2>/dev/null").strip
            modhash['package'] = mypkgname.split(':')[0]
          })
        end

        for thread in waitforit
          thread.join
        end
        tmphash[modulename] = Hash[modhash.sort]
      })
    end
    for thread in t
      thread.join
    end
    finalhash = Hash[tmphash.sort]
  end

  Facter.add(:lsmod) do
    confine :kernel => "Linux"
    setcode do
      finalhash
    end
  end
end
