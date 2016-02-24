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
            result = Facter::Util::Resolution.exec("modinfo --field='filename' #{modulename} 2>/dev/null").strip
            if not result.empty?
              modhash['filename'] = result
            end
          end
        end

        if Facter::Util::Resolution.which('modinfo')
          waitforit.push(Thread.new {
            for info in modinfo
              result = Facter::Util::Resolution.exec("modinfo --field=#{info} #{modulename} 2>/dev/null").strip
              if not result.empty?
                modhash[info] = result
              end
            end
          })

          waitforit.push(Thread.new {
            if File.directory?("/sys/module/#{modulename}/parameters")
              modhash['parm'] = {}
              Facter::Util::Resolution.exec("grep '' /sys/module/#{modulename}/parameters/* 2>/dev/null").each_line do |txt|
                if not txt =~ /.+:.+/
                  next
                end
                path = txt.split(':')[0]
                parm = path.split('/').last
                value = txt.split(':')[1].strip
                modhash['parm'][parm] = value
              end
            end
          })

          waitforit.push(Thread.new {
            mytaint = Facter::Util::Resolution.exec("cat /sys/module/#{modulename}/taint 2>/dev/null")
            if not mytaint.empty?
              if mytaint != 'Y'
                modhash['taint'] = mytaint.strip
              end
            end
          })

          waitforit.push(Thread.new {
            modhash['depends'] = []
            Facter::Util::Resolution.exec("modinfo --field=depends #{modulename} 2>/dev/null").each_line do |txt|
              modhash['depends']= txt.strip.split(',')
            end
            if modhash['depends'] == []
              modhash.delete('depends')
            else
              modhash['depends'].sort
            end
          })
        end

        if Facter::Util::Resolution.which('rpm')
          waitforit.push(Thread.new {
              realname = Facter::Util::Resolution.exec("readlink -f #{modhash['filename']} 2>/dev/null").strip
              # this is really slow
              if not realname.empty?
                modhash['package'] = Facter::Util::Resolution.exec("rpm -qf #{realname} 2>/dev/null").strip
              else
                modhash['package'] = Facter::Util::Resolution.exec("rpm -qf #{modhash['filename']} 2>/dev/null").strip
              end
          })
        elsif Facter::Util::Resolution.which('dpkg')
          waitforit.push(Thread.new {
              realname = Facter::Util::Resolution.exec("readlink -f #{modhash['filename']} 2>/dev/null").strip
              # this is really slow
              if not realname.empty?
                mypkgname = Facter::Util::Resolution.exec("dpkg -s #{realname} 2>/dev/null").strip
                modhash['package'] = mypkgname.split(':')[0]
              else
                mypkgname = Facter::Util::Resolution.exec("dpkg -s #{modhash['filename']} 2>/dev/null").strip
                modhash['package'] = mypkgname.split(':')[0]
              end
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
