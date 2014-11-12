

#codes of TIA/EIA-825. skip non-printable chars, and some others, depicted as "_"
const letter = "_E\nA SIU\rDRJNFCKTZLWHYPQOBG_MXV_"
const figure = "_3\n- _87\r_4`,!:(5_)2=6019?+_./;_"

baudot_both = [:bksp=>0b00000,
                '\n'=>0b00010,
                :figs=>0b11011,
                :ltrs=>0b11111,]

baudot_letter = [
            ' '=>0b00100,
            'Q'=>0b10111,
            'W'=>0b10011,
            :bksp=>0b00000]

baudot_figure = [:bksp=>0b00000,
                '\$'=>0b01001,
                '\"'=>0b10001,]

for (k,v) = baudot_both
    baudot_letter[k]=v
    baudot_figure[k]=v
end

for (i,c) = enumerate(letter)
    if c != '_'
        baudot_letter[c] = uint8(i-1)
    end
end

for (i,c) = enumerate(figure)
    if c != '_'
        baudot_figure[c] = uint8(i-1)
    end
end

#create inverse dictionaries
baudot_figure_inv = Dict()
baudot_letter_inv = Dict()

for (k,v) = baudot_figure
    baudot_figure_inv[v] = k
end

for (k,v) in baudot_letter
    baudot_letter_inv[v] = k 
end


#can call consume(p) ;  p=Task(string_producer("test") )
function string_producer(s::ASCIIString)
    function sp()
        for c = s
            produce(c)
        end
    end
    return sp
end

function ascii_to_baud(input_task::Task)
    function p()
        state = :neither
        last_sync = 0 #how many symbols have we emitted since sending FIGS or LTRS

        while input_task.state != :done 
            c = consume(input_task)
            if c == nothing
                continue
            end

            c = uppercase(c)
            if haskey(baudot_letter,c)
                if state != :ltrs
                    produce(baudot_both[:ltrs])
                    state = :ltrs
                    last_sync = 0
                end
                produce(baudot_letter[c])
                last_sync += 1

            elseif haskey(baudot_figure,c)
                if state != :figs
                    produce(baudot_both[:figs])
                    state = :figs
                    last_sync = 0
                end
                produce(baudot_figure[c])
                last_sync += 1
            else
                warn("Encountered unknown input character: $(c)")
            end

            if last_sync > 70
                state = :neither
            end
        end
    end
    return p 
end

function baud_to_ascii(input_task::Task)
    function p()
        state = :ltrs #assume we start with letters

        while input_task.state != :done
            c = consume(input_task)

            if c == nothing
                continue
            end

            d = ifelse(state==:ltrs,baudot_letter_inv,baudot_figure_inv)

            if haskey(d,c)
                if d[c] == :figs
                    state = :figs
                elseif d[c] == :ltrs
                    state = :ltrs 
                else
                    produce(d[c])
                end
            else
                produce('#')
            end
        end
    end
    return p 
end


function consume_all(task::Task)
while task.state != :done
   print(consume(task)); print(", ")
end
end

baud = Task(ascii_to_baud(Task(string_producer("Test123abc"))))
ascii = Task(baud_to_ascii(baud))
consume_all(ascii)

export consume_all
export ascii_to_baud
export baud_to_ascii
export string_producer



#bit banger
type AsyncSerialRenderer <: AudioRenderer
    code_stream::Task
    baudrate::Real
    n_bits::Int
    n_start_bits::Real
    n_stop_bits::Real

    sample_index::Int
    state::Symbol
    buf::AudioBuf
    current_code::Uint8 
    AsyncSerialRenderer(code::Task) = new(code,50,5,1,1.5,0,:nothing,AudioSample[],0)
end

typealias AsyncSerialRendererNode AudioNode{AsyncSerialRenderer}
export AsyncSerialRendererNode

function render(node::AsyncSerialRenderer, device_input::AudioBuf, info::DeviceInfo)
    if length(node.buf) != info.buf_size
        resize!(node.buf, info.buf_size)
        node.buf[:] = NaN
    end

    samples_per_symbol = int(info.sample_rate / node.baudrate)
    symbols_per_code = node.n_bits 
    
    samples_per_code = int(symbols_per_code * samples_per_symbol)
    samples_per_start = int(node.n_start_bits * samples_per_symbol)
    samples_per_stop = int(node.n_stop_bits * samples_per_symbol)

    i::Int = 1

    while i <= length(node.buf)
        #println("$(node.state), i:$(i)")
        if node.state == :nothing
            node.state = :take_code
            #println("now state is: $(node.state)")
        
        elseif node.state == :take_code
            if node.code_stream.state == :done
                return AudioSample[] #return empty buffer to signal I'm done
            elseif node.code_stream.state == :waiting
                node.state = :waiting_for_codes
                node.buf[i] = -1 #resting value
                i += 1
            else
                c = consume(node.code_stream) #won't block because it's not waiting... right?
                if c != nothing
                    node.current_code = c
                    node.state = :transmitting_code
                    #println("now state is: $(node.state)")
                    node.sample_index = 0 #how many samples of this code have we transmitted
                end
            end

        elseif node.state == :transmitting_code
            if node.sample_index < samples_per_start
                node.buf[i] = 0 #transmitting start bit
            elseif node.sample_index < samples_per_start + samples_per_code
                intocode = node.sample_index - samples_per_start
                bit = div(intocode,samples_per_symbol) + 1
                node.buf[i] = digits(node.current_code,2,int(node.n_bits))[bit]
            elseif node.sample_index < samples_per_start + samples_per_code + samples_per_stop
                node.buf[i] = 1 #transmitting stop bit
            end
            node.sample_index += 1
            i += 1

            if node.sample_index >= samples_per_start + samples_per_code + samples_per_stop
                node.state = :take_code
            end
        end
    end
    return node.buf
end







type BaudotRenderer <: AudioRenderer
    text::ASCIIString
    text_index::Int
    sample_index::Int
    baudrate::Real

    buf::AudioBuf

    BaudotRenderer(text::ASCIIString,baudrate::Real=50) = new(uppercase(text),1,1,baudrate,AudioSample[])
end

typealias BaudotRendererNode AudioNode{BaudotRenderer}
export BaudotRendererNode

function render(node::BaudotRenderer, device_input::AudioBuf, info::DeviceInfo)
    if length(node.buf) != info.buf_size
        resize!(node.buf, info.buf_size)
        node.buf[:] = NaN
    end

    char =  node.text[node.text_index]

    samples_per_symbol = int(info.sample_rate / node.baudrate)

    symbols_per_char = 5

    samples_per_char = symbols_per_char * samples_per_symbol

    i::Int = 1

    while i <= info.buf_size
        this_char_idx,sample_into_char = divrem( node.sample_index-1 , samples_per_char )
        this_char_idx += 1;

        if this_char_idx < length(node.text)
            this_symbol_idx = div(sample_into_char,samples_per_symbol) 
            this_symbol_idx +=1

            char =  node.text[this_char_idx]
            code = baudot5[char]

            node.buf[i] = digits(code,2,symbols_per_char)[this_symbol_idx]

            #print("this_char_idx: $(this_char_idx)\n")
            #print("this_symbol_idx: $(this_symbol_idx)\n")
            #print("node.sample_idx: $(node.sample_index)\n")

            node.sample_index +=1
        else 
            #complete buffer
            node.buf[i] = -1
        end
        i += 1
    end


    return node.buf
end