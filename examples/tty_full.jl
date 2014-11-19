using AudioIO


const ONE_HZ = 1400.0
const ZERO_HZ = 1800.0
const BAUDRATE = 45.5

function freq_map(x::AudioIO.AudioSample)
	if x == 1
		return ONE_HZ
	end
	if x == -1
		return ZERO_HZ
	end
	if x == 0
		return 120 #just so we can hear the resting line for now
	end
end

freq_map_node = MemorylessNode(freq_map)


function stdio_producer()
	while true
		c = read(STDIN,Char)
		if c == '\e'
			println("Done")
			break
		else
			print(":"); print(c)
			produce(c)
		end
	end
end

baud = Task(ascii_to_baud(Task(  stdio_producer  )))	

code_buffer = Uint8[]

function load_buff()
	while baud.state != :done
		push!(code_buffer,consume(baud))
		#print(".")
	end
end

function send_string(s::ASCIIString)
	l = collect(Task(ascii_to_baud(Task(string_producer(s)))))
	for ll in l
		push!(code_buffer,ll)
	end
end

#load_buff_task = @async load_buff()
bits_node = AsyncSerialRendererNode(code_buffer,BAUDRATE)

fsk_node = ComposeNode(bits_node,freq_map_node)
modulated_node = SinOsc(fsk_node)

if false
	demod_node = ComposeNode(AudioInput(), FSK_IQ_DemodNode())

else
	Ione = ComposeNode( AudioInput() * SinOsc(ONE_HZ,0), Filt(200) )
	Qone = ComposeNode( AudioInput() * SinOsc(ONE_HZ,pi/2), Filt(200))
	Izero = ComposeNode( AudioInput() * SinOsc(ZERO_HZ,0), Filt(200))
	Qzero = ComposeNode( AudioInput() * SinOsc(ZERO_HZ,pi/2), Filt(200))

	Ione_sq = ComposeNode(Ione, MemorylessNode((x)->(x^2)))
	Qone_sq = ComposeNode(Qone, MemorylessNode((x)->(x^2)))

	Izero_sq = ComposeNode(Izero, MemorylessNode((x)->(x^2)))
	Qzero_sq = ComposeNode(Qzero, MemorylessNode((x)->(x^2)))

	one_bits = ComposeNode(Ione_sq+Qone_sq, MemorylessNode(sqrt))
	zero_bits = ComposeNode(Izero_sq+Qzero_sq, MemorylessNode(sqrt))

	demod_node = one_bits + (-1) * zero_bits
end


uart_rx = AsyncSerialDecoderNode(BAUDRATE)
uart_node = ComposeNode(demod_node,uart_rx);

b = AudioIO.AudioSample[]
resize!(b,44100 * 3);
b[:] = 0;

rec = ArrayRecorderNode(b)

rec_node = ComposeNode(uart_node,rec);

function empty_buff()
	while uart_rx.active
		if length( uart_rx.renderer.code_stream ) == 0
			wait(uart_rx.renderer.new_code)
		end 
		produce( shift!(uart_rx.renderer.code_stream) )
	end
end

ascii_task = Task(baud_to_ascii(Task(empty_buff)))

print_task = @async while ascii_task.state != :done
print(consume(ascii_task))
end


play(0.0 * uart_node); #uart node spits out the bit descisions. it's not audio and we don't want to play it
println("hooked up receiver")


play(modulated_node)
println("hooked up transmitter")


sleep(1.0)

send_string("beep boop beep beep beep. does it look like I am yelling?? the quick brown fox jumped over the lazy dog! here is a large number: 9078563412. GA\n")
