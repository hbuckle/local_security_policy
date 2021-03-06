require_relative '../../../puppet_x/user_rights_assignment/lookup'
require_relative '../secedit'

Puppet::Type.type(:user_rights_assignment).provide(:secedit, parent: Puppet::Provider::Secedit) do
  mk_resource_methods

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  def self.instances
    inf = read_policy_settings
    settings = process_lines inf
    currentsettings = settings.each.collect do |setting|
      system_to_friendly(setting)
    end
    allsettings = add_unset_policies(currentsettings)
    allsettings.each.collect do |setting|
      new(setting)
    end
  end

  def security_setting=(value)
    write_file
    file_name = DateTime.now.strftime('%Y%m%dT%H%M.log')
    secedit([
      '/configure', '/db', 'C:\\Windows\\Temp\\db.sdb',
      '/cfg', 'C:\\Windows\\Temp\\write.ini',
      '/log', "C:\\Windows\\security\\logs\\#{file_name}"
    ])
    FileUtils.rm_f 'C:\\Windows\\Temp\\write.ini'
    FileUtils.rm_f 'C:\\Windows\\Temp\\db.sdb'
    FileUtils.rm_f 'C:\\Windows\\Temp\\db.jfm'
  end

  def write_file
    text = <<-TEXT
[Version]
signature="$CHICAGO$"
Revision=1
[Unicode]
Unicode=yes
[Privilege Rights]
    TEXT
    setting_name = UserRightsAssignment::Lookup.system_name @resource[:policy]
    sids = users_to_sids @resource[:security_setting]
    setting_line = "#{setting_name} = #{sids}"
    text += setting_line
    out_file = File.new('C:\\Windows\\Temp\\write.ini', 'w')
    out_file.puts(text)
    out_file.close
  end

  def users_to_sids(users)
    correct_users = self.class.replace_incorrect_users users
    sids = correct_users.each.collect do |user|
      "*#{Puppet::Util::Windows::SID.name_to_sid user}"
    end
    sids.join(',')
  end

  # fix for Win10/Server2016
  def self.replace_incorrect_users(users)
    index = users.index('BUILTIN\\System Managed Group')
    users[index] = 'BUILTIN\\System Managed Accounts Group' if index
    users
  end

  def self.convert_line(line)
    name = line.split('=')[0].strip
    setting = line.split('=')[1].strip.delete('*').split(',')
    {
      name: name,
      security_setting: setting
    }
  end

  def self.process_lines(inf)
    settings = []
    current_section = ''
    inf.each_line do |line|
      if line.strip =~ /\[(.*?)\]/
        current_section = line.strip
        next
      end
      settings << convert_line(line) if current_section == '[Privilege Rights]'
    end
    settings
  end

  def self.system_to_friendly(setting)
    users = setting[:security_setting].each.collect do |sid|
      if Puppet::Util::Windows::SID.valid_sid? sid
        result = Puppet::Util::Windows::SID.sid_to_name sid
        result ? result : sid
      else
        sid
      end
    end
    {
      name: UserRightsAssignment::Lookup.friendly_name(setting[:name]),
      security_setting: users
    }
  end

  def self.add_unset_policies(settings)
    output = settings
    set_settings = settings.map { |x| x[:name] }
    UserRightsAssignment::Lookup.friendly_to_system_mapping.keys.each do |privilege|
      unless set_settings.include?(privilege)
        output << { name: privilege, security_setting: [] }
      end
    end
    output
  end
end
