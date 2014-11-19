#### NullNode ####

type NullRenderer <: AudioRenderer end
typealias NullNode AudioNode{NullRenderer}
export NullNode

function render(node::NullRenderer, device_input::AudioBuf, info::DeviceInfo)
    # TODO: preallocate buffer
    return zeros(AudioSample,info.buf_size)
end

#### SinOsc ####

# Generates a sin tone at the given frequency
#the phase-version is a mess: freq is actually a tuple (freq,phase)
type SinOscRenderer{T<:Union(Float32, AudioNode,(Float32,Float32,))} <: AudioRenderer
    freq::T
    phase::Float32
    buf::AudioBuf

    function SinOscRenderer(freq)
        new(freq, 0.0, AudioSample[])
    end
end

typealias SinOsc AudioNode{SinOscRenderer}
SinOsc(freq::Real) = SinOsc(SinOscRenderer{Float32}(freq))
SinOsc(freq::Real,phase::Real) = SinOsc(SinOscRenderer{(Float32,Float32)}((freq,phase)))
SinOsc(freq::AudioNode) = SinOsc(SinOscRenderer{AudioNode}(freq))
SinOsc() = SinOsc(440)
export SinOsc

function render(node::SinOscRenderer{Float32}, device_input::AudioBuf,
        info::DeviceInfo)
    if length(node.buf) != info.buf_size
        resize!(node.buf, info.buf_size)
    end
    outbuf = node.buf
    phase = node.phase
    freq = node.freq
    # make sure these are Float32s so that we don't allocate doing conversions
    # in the tight loop
    pi2::Float32 = 2pi
    phase_inc::Float32 = 2pi * freq / info.sample_rate
    i::Int = 1
    while i <= info.buf_size
        outbuf[i] = sin(phase)
        phase = (phase + phase_inc) % pi2
        i += 1
    end
    node.phase = phase
    return outbuf
end

function render(node::SinOscRenderer{(Float32,Float32)}, device_input::AudioBuf,
        info::DeviceInfo)
    if length(node.buf) != info.buf_size
        resize!(node.buf, info.buf_size)
    end
    outbuf = node.buf

    (freq,phi) = node.freq
    phase = float32(( ( 2pi * freq * info.sample/info.sample_rate ) +phi)% 2pi )
    err = min(abs(phase-node.phase), 2pi - abs(phase-node.phase))
    if( err > 2pi/1e5) warn("Phase Noise: $(err)") end

    # make sure these are Float32s so that we don't allocate doing conversions
    # in the tight loop
    pi2::Float32 = 2pi
    phase_inc::Float32 = 2pi * freq / info.sample_rate
    i::Int = 1
    while i <= info.buf_size
        outbuf[i] = sin(phase)
        phase = (phase + phase_inc) % pi2
        i += 1
    end
    node.phase = phase
    return outbuf
end


function render(node::SinOscRenderer{AudioNode}, device_input::AudioBuf,
        info::DeviceInfo)
    freq = render(node.freq, device_input, info)::AudioBuf
    block_size = min(length(freq), info.buf_size)
    if(length(node.buf) != block_size)
        resize!(node.buf, block_size)
    end
    outbuf = node.buf

    phase::Float32 = node.phase
    pi2::Float32 = 2pi
    phase_step::Float32 = 2pi/(info.sample_rate)
    i::Int = 1
    while i <= block_size
        outbuf[i] = sin(phase)
        phase = (phase + phase_step*freq[i]) % pi2
        i += 1
    end
    node.phase = phase
    return outbuf
end

#### AudioMixer ####

# Mixes a set of inputs equally

type MixRenderer <: AudioRenderer
    inputs::Vector{AudioNode}
    buf::AudioBuf

    MixRenderer(inputs) = new(inputs, AudioSample[])
    MixRenderer() = MixRenderer(AudioNode[])
end

typealias AudioMixer AudioNode{MixRenderer}
export AudioMixer

function render(node::MixRenderer, device_input::AudioBuf, info::DeviceInfo)
    if length(node.buf) != info.buf_size
        resize!(node.buf, info.buf_size)
    end
    mix_buffer = node.buf
    n_inputs = length(node.inputs)
    i = 1
    max_samples = 0
    fill!(mix_buffer, 0)
    while i <= n_inputs
        rendered = render(node.inputs[i], device_input, info)::AudioBuf
        nsamples = length(rendered)
        max_samples = max(max_samples, nsamples)
        j::Int = 1
        while j <= nsamples
            mix_buffer[j] += rendered[j]
            j += 1
        end
        if nsamples < info.buf_size
            deleteat!(node.inputs, i)
            n_inputs -= 1
        else
            i += 1
        end
    end
    if max_samples < length(mix_buffer)
        return mix_buffer[1:max_samples]
    else
        # save the allocate and copy if we don't need to
        return mix_buffer
    end
end

Base.push!(mixer::AudioMixer, node::AudioNode) = push!(mixer.renderer.inputs, node)

#### Gain ####
type GainRenderer{T<:Union(Float32, AudioNode)} <: AudioRenderer
    in1::AudioNode
    in2::T
    buf::AudioBuf

    GainRenderer(in1, in2) = new(in1, in2, AudioSample[])
end

function render(node::GainRenderer{Float32},
                device_input::AudioBuf,
                info::DeviceInfo)
    input = render(node.in1, device_input, info)::AudioBuf
    if length(node.buf) != length(input)
        resize!(node.buf, length(input))
    end
    i = 1
    while i <= length(input)
        node.buf[i] = input[i] * node.in2
        i += 1
    end
    return node.buf
end

function render(node::GainRenderer{AudioNode},
                device_input::AudioBuf,
                info::DeviceInfo)
    in1_data = render(node.in1, device_input, info)::AudioBuf
    in2_data = render(node.in2, device_input, info)::AudioBuf
    block_size = min(length(in1_data), length(in2_data))
    if length(node.buf) != block_size
        resize!(node.buf, block_size)
    end
    i = 1
    while i <= block_size
        node.buf[i] = in1_data[i] * in2_data[i]
        i += 1
    end
    return node.buf
end

typealias Gain AudioNode{GainRenderer}
Gain(in1::AudioNode, in2::Real) = Gain(GainRenderer{Float32}(in1, in2))
Gain(in1::AudioNode, in2::AudioNode) = Gain(GainRenderer{AudioNode}(in1, in2))
export Gain

#### Offset ####
type OffsetRenderer <: AudioRenderer
    in_node::AudioNode
    offset::Float32
    buf::AudioBuf

    OffsetRenderer(in_node, offset) = new(in_node, offset, AudioSample[])
end

function render(node::OffsetRenderer, device_input::AudioBuf, info::DeviceInfo)
    input = render(node.in_node, device_input, info)::AudioBuf
    if length(node.buf) != length(input)
        resize!(node.buf, length(input))
    end
    i = 1
    while i <= length(input)
        node.buf[i] = input[i] + node.offset
        i += 1
    end
    return node.buf
end

typealias Offset AudioNode{OffsetRenderer}
export Offset


#### Array Player ####

# Plays a AudioBuf by rendering it out piece-by-piece

type ArrayRenderer <: AudioRenderer
    arr::AudioBuf
    arr_index::Int
    buf::AudioBuf

    ArrayRenderer(arr::AudioBuf) = new(arr, 1, AudioSample[])
end

typealias ArrayPlayer AudioNode{ArrayRenderer}
export ArrayPlayer

function render(node::ArrayRenderer, device_input::AudioBuf, info::DeviceInfo)
    range_end = min(node.arr_index + info.buf_size-1, length(node.arr))
    block_size = range_end - node.arr_index + 1
    if length(node.buf) != block_size
        resize!(node.buf, block_size)
    end
    copy!(node.buf, 1, node.arr, node.arr_index, block_size)
    node.arr_index = range_end + 1
    return node.buf
end

# Allow users to play a raw array by wrapping it in an ArrayPlayer
function play(arr::AudioBuf, args...)
    player = ArrayPlayer(arr)
    play(player, args...)
end

# If the array is the wrong floating type, convert it
function play{T <: FloatingPoint}(arr::Array{T}, args...)
    arr = convert(AudioBuf, arr)
    play(arr, args...)
end

# If the array is an integer type, scale to [-1, 1] floating point

# integer audio can be slightly (by 1) more negative than positive,
# so we just scale so that +/- typemax(T) becomes +/- 1
function play{T <: Signed}(arr::Array{T}, args...)
    arr = arr / typemax(T)
    play(arr, args...)
end

function play{T <: Unsigned}(arr::Array{T}, args...)
    zero = (typemax(T) + 1) / 2
    range = floor(typemax(T) / 2)
    arr = (arr .- zero) / range
    play(arr, args...)
end

#### Noise ####

type WhiteNoiseRenderer <: AudioRenderer end
typealias WhiteNoise AudioNode{WhiteNoiseRenderer}
export WhiteNoise

function render(node::WhiteNoiseRenderer, device_input::AudioBuf, info::DeviceInfo)
    return rand(AudioSample, info.buf_size) .* 2 .- 1
end


#### AudioInput ####

# Renders incoming audio input from the hardware

type InputRenderer <: AudioRenderer
    channel::Int
    InputRenderer(channel::Integer) = new(channel)
    InputRenderer() = new(1)
end

function render(node::InputRenderer, device_input::AudioBuf, info::DeviceInfo)
    @assert size(device_input, 1) == info.buf_size
    return device_input[:, node.channel]
end

typealias AudioInput AudioNode{InputRenderer}
export AudioInput



# Renders incoming audio input from the hardware
#for some reason, it requires something to be playing already, that isn't all 0.0s
type PullToPullRenderer <: AudioRenderer
    new_buf::Condition
    buf::AudioBuf
    dummy_buf::AudioBuf
    old::Bool
    PullToPullRenderer() = new(Condition(),AudioSample[],AudioSample[],true)
end

function render(node::PullToPullRenderer, device_input::AudioBuf, info::DeviceInfo)
    #println("PTPR id: $(object_id(node)), s: $(info.sample)")

    @assert size(device_input, 1) == info.buf_size #should handle smaller input buffers too.
    if length(node.dummy_buf) != info.buf_size 
        resize!(node.dummy_buf,info.buf_size)
        node.dummy_buf[:] = 0
    end

    @assert all(node.dummy_buf .== 0 ) #check, for now, whether someone tampered with our output buffer

    if length(node.buf) != length(device_input) 
        resize!(node.buf,length(device_input))
    end

    copy!(node.buf,1,device_input,1,length(device_input))
    node.old=false
    #println("PTPR id: $(object_id(node)) trigger notify")
    notify(node.new_buf)
    return node.dummy_buf
end

typealias PullToPull AudioNode{PullToPullRenderer}
export PullToPull



type PullToPullRendererOut <: AudioRenderer
    other::PullToPull
    n_sent::Int64
    PullToPullRendererOut(other::PullToPull) = new(other,0)
end


function render(node::PullToPullRendererOut, device_input::AudioBuf, info::DeviceInfo)
    n::PullToPullRenderer = node.other.renderer
    println("PTPRO id: $(hex(object_id(node))), s: $(info.sample)")
    if node.n_sent <= -1 #some bug. if we ever return dummy buf, then this render function never gets called again
        node.n_sent += 1
        return n.dummy_buf
    end
    if n.old
        wait(n.new_buf)
        @assert n.old == false
        n.old = true
    end
    
    println("\tPTPRO id: $(hex(object_id(node))), s: $(info.sample)")
    
    node.n_sent += 1
    
    return n.buf
end

typealias PullToPullOut AudioNode{PullToPullRendererOut}
export PullToPullOut




#### LinRamp ####

type LinRampRenderer <: AudioRenderer
    key_samples::Array{AudioSample}
    key_durations::Array{Float32}

    duration::Float32
    buf::AudioBuf

    LinRampRenderer(start, finish, dur) = LinRampRenderer([start,finish], [dur])

    LinRampRenderer(key_samples, key_durations) =
        LinRampRenderer(
            [convert(AudioSample,s) for s in key_samples],
            [convert(Float32,d) for d in key_durations]
        )

    function LinRampRenderer(key_samples::Array{AudioSample}, key_durations::Array{Float32})
        @assert length(key_samples) == length(key_durations) + 1
        new(key_samples, key_durations, sum(key_durations), AudioSample[])
    end
end

typealias LinRamp AudioNode{LinRampRenderer}
export LinRamp

function render(node::LinRampRenderer, device_input::AudioBuf, info::DeviceInfo)
    # Resize buffer if (1) it's too small or (2) we've hit the end of the ramp
    ramp_samples::Int = int(node.duration * info.sample_rate)
    block_samples = min(ramp_samples, info.buf_size)
    if length(node.buf) != block_samples
        resize!(node.buf, block_samples)
    end

    # Fill the buffer as long as there are more segments
    dt::Float32 = 1/info.sample_rate
    i::Int = 1
    while i <= length(node.buf) && length(node.key_samples) > 1

        # Fill as much of the buffer as we can with the current segment
        ds::Float32 = (node.key_samples[2] - node.key_samples[1]) / node.key_durations[1] / info.sample_rate
        while i <= length(node.buf)
            node.buf[i] = node.key_samples[1]
            node.key_samples[1] += ds
            node.key_durations[1] -= dt
            node.duration -= dt
            i += 1

            # Discard segment if we're finished
            if node.key_durations[1] <= 0
                if length(node.key_durations) > 1
                    node.key_durations[2] -= node.key_durations[1]
                end
                shift!(node.key_samples)
                shift!(node.key_durations)
                break
            end
        end
    end

    return node.buf
end



type MemorylessNodeRenderer <: AudioRenderer
    f::Function
    buf::AudioBuf

    function MemorylessNodeRenderer(f::Function)
        new(f,AudioSample[])
    end
end

function render(node::MemorylessNodeRenderer,input::AudioBuf,info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size

    if length(node.buf) != size(input, 1)
        resize!(node.buf, size(input, 1))
    end

    output = node.buf

    i::Int = 1
    while i <= length(node.buf)
        output[i] = node.f(input[i])
        i += 1
    end
    return output
end

typealias MemorylessNode AudioNode{MemorylessNodeRenderer}
export MemorylessNode


type ArrayRecorderRenderer <: AudioRenderer
    arr::AudioBuf
    arr_index::Int
    buf::AudioBuf

    ArrayRecorderRenderer(arr::AudioBuf) = new(arr, 1, AudioSample[])
end

typealias ArrayRecorderNode AudioNode{ArrayRecorderRenderer}
export ArrayRecorderNode

function render(node::ArrayRecorderRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size
    range_end = min(node.arr_index + size(input, 1)-1, length(node.arr))
    block_size = range_end - node.arr_index + 1
    if length(node.buf) != block_size
        resize!(node.buf, block_size)
        node.buf[:] = 0
    end

    
    copy!(node.arr,node.arr_index,input,1,block_size)
    node.arr_index = range_end + 1

    if node.arr_index == length(node.arr)
        return AudioSample[] #return an array of small size to signal that this node is done
    end
    return node.buf

end


type ComposeNodeRenderer <: AudioRenderer
    first::AudioNode
    second::AudioNode
    buf::AudioBuf
    #input to ComposeNode first goes through first, then second, then that is output.
    ComposeNodeRenderer(first::AudioNode,second::AudioNode) = new(first, second, AudioSample[])
end

typealias ComposeNode AudioNode{ComposeNodeRenderer}
export ComposeNode

function render(node::ComposeNodeRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size   #might get an incomplete buffer

    first = node.first
    second = node.second

    out1 = render(first,input,info)
    out2 = render(second,out1,info)

    @assert size(out2,1) <= info.buf_size

    block_size = size(out2,1)
    if length(node.buf) != block_size
        resize!(node.buf, block_size)
    end

    copy!(node.buf,1,out2,1,block_size)

    return node.buf

end



type DelayMixRenderer <: AudioRenderer
    delay::Int

    buf::AudioBuf
    buf_last_in::AudioBuf
    #output[n] = input[n] * input[n-delay]
    DelayMixRenderer(delay::Integer) = new(delay, AudioSample[], AudioSample[])
end

typealias DelayMixNode AudioNode{DelayMixRenderer}
export DelayMixNode

function render(node::DelayMixRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size   #might get an incomplete buffer
    @assert node.delay <= info.buf_size #otherwise need to store more buffers

    if length(node.buf_last_in) == 0
        resize!(node.buf_last_in,info.buf_size)
        node.buf_last_in[:] = 0
    end

    if length(node.buf) != size(input, 1)
        resize!(node.buf, size(input, 1))
    end


    for i=1:min(node.delay,length(input))
        v = input[i] * node.buf_last_in[end-node.delay + i ]
        node.buf[i] = v
    end

    if length(input)>node.delay
        for i=node.delay+1:length(input)
            node.buf[i] = input[i] * input[i-node.delay]
        end
    end

    if length(node.buf_last_in) == 0
        resize!(node.buf_last_in,info.buf_size)
    end

    resize!(node.buf_last_in,length(input))
    copy!(node.buf_last_in,1,input,1,length(input))

    return node.buf

end


import Multirate: FIRFilter, filt!, firdes, outputlength, FIRResponse, LOWPASS, HIGHPASS



type FSK_IQ_DemodRenderer <: AudioRenderer
    buf::AudioBuf
    buf1::AudioBuf
    buf2::AudioBuf
    buf3::AudioBuf
    buf4::AudioBuf

    buf1o::AudioBuf
    buf2o::AudioBuf
    buf3o::AudioBuf
    buf4o::AudioBuf

    filt1::FIRFilter
    filt2::FIRFilter
    filt3::FIRFilter
    filt4::FIRFilter

    function FSK_IQ_DemodRenderer()
        h = firdes( 200, .2 * 200, samplerate = 41000, response = LOWPASS )
        f1 = FIRFilter(h)
        f2 = FIRFilter(h)
        f3 = FIRFilter(h)
        f4 = FIRFilter(h)
        new(AudioSample[],AudioSample[],AudioSample[],AudioSample[],AudioSample[],
            AudioSample[],AudioSample[],AudioSample[],AudioSample[],f1,f2,f3,f4)
    end
end

typealias FSK_IQ_DemodNode AudioNode{FSK_IQ_DemodRenderer}
export FSK_IQ_DemodNode

function render(node::FSK_IQ_DemodRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size   #might get an incomplete buffer

    if length(node.buf) != length(input)
        resize!(node.buf,length(input))
        resize!(node.buf1,length(input))
        resize!(node.buf2,length(input))
        resize!(node.buf3,length(input))
        resize!(node.buf4,length(input))
    end

    if length(node.buf1o) != outputlength( node.filt1, length( input ) )
        resize!(node.buf1o,length(input))
        resize!(node.buf2o,length(input))
        resize!(node.buf3o,length(input))
        resize!(node.buf4o,length(input))
    end

    f_h = float32(2pi*1800 / info.sample_rate)
    f_l = float32(2pi*1400 / info.sample_rate)

    s = info.sample-1
    for i=1:length(input)
        node.buf1[i] = cos(f_h * (i+s) ) * input[i]
        node.buf2[i] = sin(f_h * (i+s) ) * input[i]
        node.buf3[i] = cos(f_l * (i+s) ) * input[i]
        node.buf4[i] = sin(f_l * (i+s) ) * input[i]
    end

    filt!( node.buf1o, node.filt1, node.buf1 )
    filt!( node.buf2o, node.filt2, node.buf2 )
    filt!( node.buf3o, node.filt3, node.buf3 )
    filt!( node.buf4o, node.filt4, node.buf4 )

    for i=1:length(input)
        node.buf1o[i] = sqrt(node.buf1o[i]^2 + node.buf2o[i]^2)
        node.buf3o[i] = sqrt(node.buf3o[i]^2 + node.buf4o[i]^2)

        node.buf[i] = node.buf3o[i] - node.buf1o[i]
    end



    return node.buf

end





type NormalizerRenderer <: AudioRenderer
    window::Int
    buf::AudioBuf
    buf_history::AudioBuf

    NormalizerRenderer(window::Int) = new(window, AudioSample[], AudioSample[])
end

typealias NormalizerNode AudioNode{NormalizerRenderer}
export NormalizerNode

function render(node::NormalizerRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size   #might get an incomplete buffer

    if length(node.buf_history) != node.window
        resize!(node.buf_history,node.window)
        node.buf_history[:] = 0
    end

    if length(node.buf) != size(input, 1)
        resize!(node.buf, size(input, 1))
    end
    #shift buffer over
    shift_over = length(input)
    for i=1:(length(node.buf_history)-shift_over)
        node.buf_history[i] = node.buf_history[i+shift_over]
    end
    copy!(node.buf_history,length(node.buf_history)-shift_over+1,input,1,shift_over)


    for i=1:length(input)
        m = median(node.buf_history[i:i+node.window-length(input)])
        node.buf[i] = input[i] - m
    end

    return node.buf

end


type MovingAverageRenderer <: AudioRenderer
    window::Int
    buf::AudioBuf
    ring_history::AudioBuf
    ring_history_idx::Int

    MovingAverageRenderer(window::Int) = new(window, AudioSample[], AudioSample[], 1,)
end

typealias MovingAverageNode AudioNode{MovingAverageRenderer}
export MovingAverageNode

function render(node::MovingAverageRenderer, input::AudioBuf, info::DeviceInfo)
    @assert size(input, 1) <= info.buf_size   #might get an incomplete buffer
    
    if length(node.ring_history) != node.window
        resize!(node.ring_history,node.window)
        node.ring_history[:] = 0
    end
    
    if length(node.buf) != size(input, 1)
        resize!(node.buf, size(input, 1))
    end

    for i=1:length(input)
        node.ring_history[node.ring_history_idx] = input[i]
        node.ring_history_idx = ((node.ring_history_idx+1) % node.window) + 1

        node.buf[i] = max(node.ring_history) + min(node.ring_history)

        
    end

    return node.buf

end























