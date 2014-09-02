type FilterRenderer <: AudioRenderer
    in1::AudioNode
    filter::FIRFilter    
    buf::AudioBuf

    function FilterRenderer( in1::AudioNode, cutoffFreq::Real )
        h      = firdes( 60, cutoffFreq, hanning; sampleRate = 44100 )
        filter = FIRFilter( h )
        new( in1, filter, AudioSample[] )
    end
end


function render( node::FilterRenderer, device_input::AudioBuf, info::DeviceInfo )
    input = render( node.in1, device_input, info )::AudioBuf
        
    if length( node.buf ) != outputlength( node.filter, length( input ) )
        resize!( node.buf, length( input ) )
    end

    node.buf = filt( node.filter, input )
    return node.buf
end

typealias Filt AudioNode{FilterRenderer}
Filt(in1::AudioNode, in2::Real) = Filt(FilterRenderer(in1, in2))
export Filt
