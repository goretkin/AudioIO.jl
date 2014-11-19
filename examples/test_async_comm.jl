using AudioIO



baud = Task(ascii_to_baud(Task(string_producer("Test 123 ABC"))))

bits_node = AsyncSerialRendererNode(collect(baud))

uart_rx = AsyncSerialDecoderNode()
uart_node = ComposeNode(bits_node,uart_rx);
#uart_node = bits_node

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
end;


play(rec_node);




