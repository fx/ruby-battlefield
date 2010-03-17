require 'lib/battlefield'
include Battlefield
	
host = 'bc2.aesyr.com'
port = 48302
pw = 'wtfhax'

bc = BC2::Server.new(:hostname => host, 
					 :command_port => port, 
					 :admin_password => pw)
bc.receive_events = true

while true do
	packet = bc.poll
	if packet.is_a?(BC2::Event)
		case packet.event
			when 'player.onJoin':
				puts "*** #{packet.arguments[0]} has joined the server."
			when 'player.onLeave':
				puts "*** #{packet.arguments[0]} has left the server."
			when 'player.onChat':
				puts "<#{packet.arguments[0]}> #{packet.arguments[1]}"
			when 'player.onKill':
				puts "* #{packet.arguments[0]} has slit #{packet.arguments[1]}'s throat and spit on his bleeding corpse."
		end
	end
end
