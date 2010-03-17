# based on Mikael Kalms / DICE Documentation of the Remote Administration Interface for BF:BC2, Retail R3
# see http://blogs.battlefield.ea.com/battlefield_bad_company/archive/2010/02/05/remote-administration-interface-for-bfbc2-pc.aspx

require 'digest/md5'
require 'socket'
include Socket::Constants

module Battlefield
	module BC2
		class Server
			attr_accessor :hostname, :command_port, :admin_password, :socket, :sequence, :receive_events

			def initialize(options = {})
				@hostname = options[:hostname]
				@command_port = options[:command_port]
				@admin_password = options[:admin_password]
			end
			
			def connect
				@sequence = 0

				puts "Connecting to #{hostname}:#{command_port}"
				@socket = TCPSocket.new(hostname, command_port)

				puts "\tLogging in..."
				password_salt_request = Request.new(self, ["login.hashed"])

				socket.send(password_salt_request.packet.encoded, 0)
				response = Packet.new(socket.recv(4096))


				salt = response.strings[1].scan(/../).collect{|a|a.hex.chr}.join
				puts "decoded salt: #{salt.inspect}"
				hash = Digest::MD5.digest(salt + admin_password)
				hash_hex = hash.chars.collect{|a|sprintf("%02x", a.unpack('C*')[0])}.join.upcase

				puts 'Computed password hash: ' + hash_hex

				login_request = Request.new(self, ["login.hashed", hash_hex])
				socket.send(login_request.packet.encoded, 0)

				response = Packet.new(socket.recv(4096))


				@connected = true
			end

			def connected?
				@connected ? @connected : false
			end

			def sequence
				@sequence = (@sequence + 1) & 0x3fffffff
			end
			
			def receive_events=(enabled)
				@receive_events = enabled

				connect if !connected?
				return false if !connected?

				request = Request.new(self, ["eventsEnabled", "true"])
				socket.send(request.packet.encoded, 0)

				response = Packet.new(socket.recv(4096))
			end
			
			def poll
				data = socket.recv(4096)
				if data
					packet = Packet.new(data)
					if packet.response?
						socket.send(Response.new(packet.sequence, ['OK']).packet.encoded, 0)
					else
						if packet.event?
							return Event.new(packet.strings[0], packet.strings[1..-1])
						end
					end
					return packet
				end
				return false
			end
		end

		class Event
			attr_accessor :event, :arguments
			def initialize(event, *args)
				@event = event.chomp
				@arguments = args[0]
			end
		end
		
		class Player <
			Struct.new(:name)
		end

		class Request <
			Struct.new(:server, :strings)
			
			def packet
				Packet.new(false, false, server.sequence, strings)
			end
		end

		class Response <
			Struct.new(:sequence, :strings)

			def packet
				Packet.new(false, true, sequence, strings)
			end
		end

		class Header
			attr_accessor :is_from_server, :is_response, :sequence

			def initialize(*args)
				if args.size <= 1
 					data = args.first
					header = data[0..4].unpack('<I')[0]
					@is_from_server = header & 0x80000000
					@is_response = header & 0x40000000
					@sequence = header & 0x3fffffff
				else
					@sequence = args.pop
					@is_response = args.pop
					@is_from_server = args.pop
				end
			end

			def encoded
				header = sequence & 0x3fffffff
				if is_from_server
					header += 0x80000000
				elsif is_response
					header += 0x40000000
				end
				[header].pack('<I')
			end

			def decoded
				[@is_from_server, @is_response, @sequence]
			end
		end

		class Packet
			attr_accessor :is_from_server, :is_response, :sequence, :strings

			def initialize(*args)
				if args.size <= 1
					data = args.first
					header = Header.new(data)
					@is_from_server = header.is_from_server
					@is_response = header.is_response
					@sequence = header.sequence

					string_size = decode_int32(data[4..8]) - 12
					@strings = decode_strings(string_size, data[12..-1])
				else
					@strings = args.pop
					@sequence = args.pop
					@is_response = args.pop
					@is_from_server = args.pop
				end
				
				puts "New Packet: #{self.inspect}"
			end

			# flag in the packet? guess not.
			def event?
				(strings.first.match(/player\./) || strings.first.match(/punkBuster/)) ? true : false
			end

			def response?
				(is_response.to_i > 0)
			end

			def encode_int32(size)
				return [size].pack('<I')
			end

			def decode_int32(data)
				return data[0..4].unpack('<I')[0]
			end

			def encode_strings(strings)
				size = 0
				encodedWords = ''
				for word in strings do
					strWord = word.to_str
					encodedWords += encode_int32(strWord.size)
					encodedWords += strWord
					encodedWords += "\x0"
					size += strWord.size + 5
				end

				return [size, encodedWords]
			end

			def decode_strings(size, data)
				numWords = decode_int32(data[0..-1])
				words = []
				offset = 0
				while offset < size do
					wordLen = decode_int32(data[offset..(offset+4)])
					word = data[(offset + 4)..(offset + 4 + wordLen)]
					words << word.strip
					offset += wordLen + 5
				end

				return words
			end

			def encoded
				header = Header.new(is_from_server, is_response, sequence)
				encoded_num_strings = encode_int32(strings.size)
				string_size, encoded_strings = encode_strings(strings)
				encoded_size = encode_int32(string_size + 12)
				return header.encoded + encoded_size + encoded_num_strings + encoded_strings
			end

			def decoded
				[is_from_server, is_response, sequence, strings]
			end
		end
	end
end
