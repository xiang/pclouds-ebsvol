require 'rubygems'
require 'fog'
require 'facter'

$debug=true

Puppet::Type.type(:ebsvol).provide(:aws) do
    desc "AWS provider to ebsvol types"

    # Only allow the provider if fog is installed.
    commands :fog => '/usr/bin/fog'
    # Only run the provider on ec2 instances themselves.
    #confine :ec2_profile => 'default-paravirtual'
    #confine :operatingsystem => [:fedora, :centos]

    def create
    	region = resource[:availability_zone].to_s.gsub(/.$/,'') 
	compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
	print "ebsvol[aws]->create: Region is #{region}\n" if $debug
	print "ebsvol[aws]->create: Availability_zone is #{resource[:availability_zone]}\n" if $debug
	# create the requested volume
	response = compute.create_volume(resource[:availability_zone],resource[:size])	
	if (response.status == 200)
		volumeid = response.body['volumeId']
		print "ebsvol[aws]->create: I created volume #{volumeid}.\n" if $debug
		# now tag the volume with volumename so we can identify it by name
		# and not the volumeid
		response = compute.create_tags(volumeid,{ :Name => resource[:volume_name] })
		if (response.status == 200)
			print "ebsvol[aws]->create: I tagged #{volumeid} with Name = #{resource[:volume_name]}\n" if $debug
		end
		# Check if I need to attach it to an ec2 instance.
		attachto = resource[:attached_to].to_s
		print "attachto is #{attachto}\n" if $debug
		if ( attachto != '' )
			if ( attachto == 'me')
				instance = instanceinfo(compute,myname(compute))
			else
				instance = instanceinfo(compute,attachto)
			end
			if ( resource[:device] != nil )
				# try to attach the volume to requested instance
				print "attach the volume\n" if $debug
				volume = volinfo(compute,resource[:volume_name])
				attachvol(compute,volume,instance,resource[:device])
			else
				raise "ebsvol[aws]->create: Sorry, I can't attach a volume with out a device to attach to!"
			end
		end
	else
		raise "ebsvol[aws]->create: I couldn't create the ebs volume, sorry!"
	end
    end

    def destroy
	# remove an existing ebsvolume - exists? must be true
	# if it is attached to an instance then it must be detached first
    	region = resource[:availability_zone].to_s.gsub(/.$/,'') 
	compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")

	volume = volinfo(compute,resource[:volume_name])
	# check if volume is attached to something- detach before delete.
	if (volume != nil) 
		if ( volume['status'] == 'in-use' && volume['attachmentSet'] != nil )
			if ( volume['attachmentSet'][0]['status'] == 'attached' && 
			volume['attachmentSet'][0]['device'] != nil && volume['attachmentSet'][0]['instanceId'] != nil)
				# detach the volume
				detachvol(compute,volume)
			end
		end
		print "ebsvol[aws]->destroy: deleting #{volume['volumeId']}\n" if $debug
		response = compute.delete_volume(volume['volumeId'])
		if ( response.status == 200) 
			print "ebsvol[aws]->destroy: I successfully deleted #{volume['volumeId']}\n" if $debug
		else
			raise "ebsvol[aws]->destroy: Sorry, I could not delete the volume!"
		end
	else
		raise "ebsvol[aws]->destroy: Sorry! I couldn't find the volume #{resource[:volume_name]} to delete"
	end
    end

    def exists?
    	region = resource[:availability_zone].to_s.gsub(/.$/,'') 
	compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
	volume = volinfo(compute,resource[:volume_name])
	if (volume != nil && volume['status'] != 'deleting')
		true
	else
		false
	end
    end

    # Functions to handle the attach_to property.  A volume can change who it is attached to.
    # or an existing volume can then be attached to an ec2 instance.
   
    def attached_to
    	region = resource[:availability_zone].to_s.gsub(/.$/,'') 
	compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
	volume = volinfo(compute,resource[:volume_name])
	print "attached_to: looking at volume #{resource[:volume_name]}\n" if $debug
	if ( volume['status'] == 'in-use' ) 
		# Look for the name of the instance which this volume is attached to.
		if ( volume['attachmentSet'][0]['instanceId'] != nil )
			print "#{resource[:volume_name]} is attached to #{volume['attachmentSet'][0]['instanceId']}\n" if $debug
			# If the resource is specified as attached_to => "me" then we'd better check that it is attached
			# to this machine.
			if ( resource[:attached_to] == "me")
				print "Am I me?\n" if $debug
				print "I am #{myname(compute)}\n" if $debug
				if ( myname(compute) == lookupname(compute,volume['attachmentSet'][0]['instanceId']))
					return "me"
				else
					return lookupname(compute,volume['attachmentSet'][0]['instanceId'])
				end
			else
				return lookupname(compute,volume['attachmentSet'][0]['instanceId'])
			end
		end
	end
	return ''
    end

    def attached_to=(instance_name)
    	region = resource[:availability_zone].to_s.gsub(/.$/,'') 
	compute = Fog::Compute.new(:provider => 'aws', :region => "#{region}")
	volume = volinfo(compute,resource[:volume_name])

	# Test that the instance exists, special case for 'me' again...
	if (instance_name == "me" )
		instance = instanceinfo(compute,myname(compute))
	else
		instance = instanceinfo(compute,instance_name)
	end
	
	raise "ebsvol[aws]->attached_to=: Sorry! I can't find an instance named #{instance_name}\n" if (instance == nil)
	print "attached_to=: I need to attach to #{instance_name}\n" if $debug
	# first check if we already attached to another instance and detach....
	if (volume != nil) 
		if ( volume['status'] == 'in-use' && volume['attachmentSet'] != nil )
			if ( volume['attachmentSet'][0]['status'] == 'attached' && 
			volume['attachmentSet'][0]['device'] != nil && volume['attachmentSet'][0]['instanceId'] != nil)
				# detach the volume
				print "ebsvol[aws]->attached_to=:  First detaching #{resource[:volume_name]} from #{volume['attachmentSet'][0]['instanceId']}\n" if $debug
				detachvol(compute,volume)
				# lookup the state of the volume again now that it is detached.
				volume = volinfo(compute,resource[:volume_name])
			end
		end
		# the volume is not in use
		print "ebsvol[aws]->attached_to=: Attaching #{resource[:volume_name]} to #{instance_name}\n" if $debug
		attachvol(compute,volume,instance,resource[:device])
	else
		raise "ebsvol[aws]->attached_to=: Sorry! I couldn't find the volume #{resource[:volume_name]} to delete"
	end
    end

    # Helper Methods.  These are not called by puppet, only the methods above.

    # retrieve a volumes information given its Name tag
    # list the volumes in the region and look for one with a Name tag which matches our name.
    # returns the volumeSet associative array... or nil
    def volinfo(compute,name)
	volumes = compute.describe_volumes
	if (volumes.status == 200)
		# check each of the volumes in our availability zone which match our name.
		volumes.body['volumeSet'].each {|x|
			# Match the name unless the volume is actually being deleted...
			if (x['tagSet']['Name'] == resource[:volume_name] )
				#print "ebsvol[aws]->volinfo: Volume #{x['volumeId']} has Name = #{resource[:volume_name]}\n" if $debug
				return x
			end
		}
	else
		raise "ebsvol[aws]->volinfo: I couldn't list the ebsvolumes"
	end
	nil
    end

    # for looking up information about an ec2 instance given the Name tag
    def instanceinfo(compute,name)
	resp = compute.describe_instances	
	if (resp.status == 200)
		# check through the instances looking for one with a matching Name tag
		resp.body['reservationSet'].each { |x|
			x['instancesSet'].each { |y| 
				if ( y['tagSet']['Name'] == name)
					return y
				end
			}
		}
	else
		raise "ebsvol[aws]->instanceinfo: I couldn't list the instances"
	end
	nil
    end	

    # helper function to attach a volume to an ec2 instance
    def attachvol(compute,volume,instance,device)
        print "Running attachvol\n" if $debug
	raise ArgumentError "ebsvol[aws]->attachvol: Sorry, you must specify a valid device matching /dev/sd[a-m]." if (device !~ /^\/dev\/sd[a-m]/)
    	if (volume['status'] != "in-use" )
		# check instance is in the same availability zone
		if ( volume['availabilityZone'] != instance['placement']['availabilityZone'])
			raise "ebsvol[aws]->attachvol: Sorry, volumes must be in the same availability zone as the instance to be attached to.\nThe volume #{volume['tagSet']['Name']} is in availability zone #{volume['availabilityZone']} and the instance is in #{instance['placement']['availabilityZone']}"  
		else
			# check that the device is available
			inuse = false
			instance['blockDeviceMapping'].each { |x| inuse=true if x['deviceName'] == device }
			if ( inuse )
				raise "ebsvol[aws]->attachvol: Sorry, the device #{device} is already in use on #{instance['tagSet']['Name']}"  
			else
				resp = compute.attach_volume(instance['instanceId'],volume['volumeId'],device)
				if (resp.status == 200)
					# now wait for it to attach!
					check = volinfo(compute,volume['tagSet']['Name'])
					while ( check['status'] !~ /(attached|in-use)/ ) do
						print "ebsvol[aws]->attachvol: status is #{check['status']}\n" if $debug
						sleep 5
						check = volinfo(compute,volume['tagSet']['Name'])
					end
					sleep 5  # allow aws to propigate the fact
					print "ebsvol[aws]->attachvol: volume is now attached\n" if $debug
				end
			end
		end
	else
		raise "ebsvol[aws]->attachvol: Sorry, I could not attach #{volume['volumeId']} because it is in use!"
	end
    end

    # detach a volume from the instance it is attached to.
    def detachvol(compute,volume)
	print "ebsvol[aws]->destroy: detaching #{volume['volumeId']} from #{volume['attachmentSet'][0]['instanceId']}\n" if $debug
	response = compute.detach_volume(volume['volumeId'], 
		{ 'Device' => volume['attachmentSet'][0]['device'], 
		'Force' => true, 
		'InstanceId' => volume['attachmentSet'][0]['instanceId'] })
	if (response.status == 200)
		# now wait for it to detach!
		check = volinfo(compute,volume['tagSet']['Name'])
		while ( check['status'] != 'available' ) do
			print "ebsvol[aws]->detachvol: status is #{check['status']}\n" if $debug
			sleep 5
			check = volinfo(compute,volume['tagSet']['Name'])
		end
		sleep 5  # allow aws to propigate the fact
		print "ebsvol[aws]->detachvol: volume is now detached\n" if $debug
	else
		raise "ebsvol[aws]->detachvol: Sorry, I could not detach #{volume['volumeId']} from #{volume['attachmentSet'][0]['instanceId']}"
	end
    end

    # Lookup an instances Name given it's instanceId
    def lookupname(compute,id)
	if ( id =~ /i-/ )
		resp = compute.describe_instances	
		if (resp.status == 200)
			# check through the instances looking for one with a matching instanceId
			resp.body['reservationSet'].each { |x|
				x['instancesSet'].each { |y| 
					if ( y['instanceId'] == id )
						if ( y['tagSet']['Name'] != nil )
							print "#{id} is #{y['tagSet']['Name']}\n" if $debug
							return y['tagSet']['Name']
						else
							raise "ebsvol[aws]->myname: #{id} does not have a Name tag!  Sorry, I NEED aws objects to have Name tags in order to work!"
						end
					end
				}
			}
		else
			raise "ebsvol[aws]->lookupname: I couldn't list the instances!"
		end
	else
		raise "ebsvol[aws]->lookupname: Sorry, #{id} does not look like an aws instance id!"
	end
	nil
    end
	

    # what's my name?  Lookup the Name tag of the instance runing this provider and return it.
    def myname(compute)
	# lookup the name of the running instance
	instanceid = Facter.value('ec2_instance_id')
	if ( instanceid =~ /i-/ )
		return lookupname(compute,instanceid)
	else
		raise "ebsvol[aws]->myname: Sorry, I can't find my instanceId - please check Facter fact ec2_instance_id is available"
	end
	nil
    end

end
