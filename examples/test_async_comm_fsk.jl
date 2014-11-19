using AudioIO


const ONE_HZ = 1400.0
const ZERO_HZ = 1800.0

function freq_map(x::AudioIO.AudioSample)
	if x == 1
		return ONE_HZ
	end
	if x == -1
		return ZERO_HZ
	end
	if x == 0
		return 150 #just so we can hear the resting line for now
	end
end

freq_map_node = MemorylessNode(freq_map)



baud = Task(ascii_to_baud(Task(string_producer("Test 1234 ABC"))))

bits_node = AsyncSerialRendererNode(collect(baud))

fsk_node = ComposeNode(bits_node,freq_map_node)
modulated_node = SinOsc(fsk_node)


#modulated_node = AudioInput()  #comment this line to use the simulated message, otherwise listen to microphone.

demod_node = ComposeNode(modulated_node, FSK_IQ_DemodNode())

uart_rx = AsyncSerialDecoderNode()
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


play(0.0 * uart_node);
