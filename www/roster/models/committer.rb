require 'whimsy/asf/memapps'

class Committer

  def self.serialize(id, env)
    response = {}

    person = ASF::Person.find(id)
    person.reload!
    return unless person.attrs['cn']

    response[:id] = id

    response[:member] = person.asf_member?
    # reformat the timestamp
    m = person.createTimestamp.match(/^(\d\d\d\d)(\d\d)(\d\d)/)
    if m
      response[:createTimestamp] = m[1] + '-' + m[2] + '-' + m[3]
    else # should not happen, but ...
      response[:createTimestamp] = person.createTimestamp
    end

    name = {}

    if person.icla
      name[:public_name] = person.public_name

      if id == env.user or ASF::Person.find(env.user).asf_member?
        name[:legal_name] = person.icla.legal_name
      end
    end

    unless person.attrs['cn'].empty?
      name[:ldap] = person.attrs['cn'].first.force_encoding('utf-8')
    end

    unless (person.attrs['givenName'] || []).empty?
      name[:given_name] = person.attrs['givenName'].first.force_encoding('utf-8')
    end

    unless person.attrs['sn'].empty?
      name[:family_name] = person.attrs['sn'].first.force_encoding('utf-8')
    end

    response[:name] = name

    response[:mail] = person.all_mail

    unless person.pgp_key_fingerprints.empty?
      response[:pgp] = person.pgp_key_fingerprints 
    end

    unless person.ssh_public_keys.empty?
      response[:ssh] = person.ssh_public_keys
    end

    if person.attrs['asf-sascore']
      response[:sascore] = person.attrs['asf-sascore'].first
    end

    if person.attrs['githubUsername']
      response[:githubUsername] = person.githubUsername
    end

    response[:urls] = person.urls unless person.urls.empty?

    response[:committees] = person.committees.map(&:name)

    response[:groups] = person.services
    response[:committer] = []
    response[:podlings] = []
    committees = ASF::Committee.pmcs.map(&:name)
    podlings = ASF::Podling.current.map(&:id)
    person.groups.map(&:name).each do |group|
      unless committees.include? group
        response[:groups] << group
      end
    end

    # Get project(member) details
    person.projects.map(&:name).each do |project|
      if committees.include? project
          # Don't show committer karma if person has committee karma
          unless response[:committees].include? project
            # LDAP project group
            response[:committer] << project 
          end
      elsif podlings.include? project
        response[:podlings] << project 
      else
        # TODO should this populate anything?
      end
    end

    ASF::Authorization.new('asf').each do |group, members|
      response[:groups] << group if members.include? id
    end

    ASF::Authorization.new('pit').each do |group, members|
      response[:groups] << group if members.include? id
    end

    response[:committees].sort!
    response[:groups].sort!
    response[:committer].sort!
    response[:podlings].sort!

    member = {} # collect member info

    inMembersTxt = ASF::Member.find(id) # i.e. present in members.txt

    if inMembersTxt
      # This is public
      member[:status] = ASF::Member.status[id] || 'Active'
    end

    response[:forms] = {}

    if ASF::Person.find(env.user).asf_member? # i.e. member karma

      if person.icla and person.icla.claRef # Not all people have iclas
        claRef = person.icla.claRef.untaint
        file = ASF::ICLAFiles.match_claRef(claRef)
        response[:forms][:icla] = file if file
      end


      if inMembersTxt
        member[:info] = person.members_txt

        if person.icla # not all members have iclas
          file = ASF::MemApps.find1st(person)
          response[:forms][:member] = file if file 
        end
      else
        if person.member_nomination
          member[:nomination] = person.member_nomination
        end
      end

    else # not an ASF member; no karma for ICLA docs so don't add link
      response[:forms][:icla] = '' if person.icla and person.icla.claRef
    end

    response[:member] = member unless member.empty?

    if ASF::Person.find(env.user).asf_member? or env.user == id
      response[:moderates] = {}

      require 'whimsy/asf/mlist'
      ASF::MLIST.moderates(person.all_mail, response)
    end

    auth = Auth.info(env)
    if env.user == id or auth[:root] or auth[:secretary]
      require 'whimsy/asf/mlist'
      ASF::MLIST.subscriptions(person.all_mail, response) # updates response[:subscriptions]
      # (Does not update the response if the digest info is not available)
      ASF::MLIST.digests(person.all_mail, response)
      # Check for missing private@ subscriptions
      response[:privateNosub] = []
    end

    # chair info is public, so let everyone see it
    response[:chairOf] = []
    response[:committees].each do |cttee|
      pmc = ASF::Committee.find(cttee)
      chairs = pmc.chairs.map {|x| x[:id]}
      response[:chairOf] << cttee if chairs.include?(id)
      # mailing list info is not public ...
      if response[:subscriptions] # did we get access to the mail?
        pmail = "private@#{pmc.mail_list}.apache.org" rescue ''
        subbed = false
        response[:subscriptions].each do |sub|
          if sub[0] == pmail
            subbed = true
          end
        end
        response[:privateNosub] << cttee unless subbed
      end
    end

    response
  end
end
