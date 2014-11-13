import Multirate: FIRFilter, filt!, firdes, outputlength, FIRResponse, LOWPASS, HIGHPASS

export  Filt,
        Resample,
        FIRResponse,
        HIGHPASS,
        LOWPASS

type FilterRenderer <: AudioRenderer
    in1::AudioNode
    filter::FIRFilter
    buf::AudioBuf

    function FilterRenderer( in1::AudioNode, filter::FIRFilter )
        new( in1, filter, AudioSample[] )
    end

end

function FilterRenderer( in1::AudioNode, cutoff::Real; transition::Real = 0.2*cutoff, samplerate = 44100, response::FIRResponse = LOWPASS )
    h      = firdes( cutoff, transition, samplerate = samplerate, response = response )
    filter = FIRFilter( h )
    FilterRenderer( in1, filter )
end


function render( node::FilterRenderer, device_input::AudioBuf, info::DeviceInfo )
    input = render( node.in1, device_input, info )::AudioBuf

    if length( node.buf ) != outputlength( node.filter, length( input ) )
        resize!( node.buf, length( input ) )
    end

    filt!( node.buf, node.filter, input )
    return node.buf
end


typealias Filt AudioNode{FilterRenderer}

function Filt( in1::AudioNode, cutoff::Real; response::FIRResponse = LOWPASS, transition::Real = 0.1*cutoff, samplerate = 44100 )
    Filt( FilterRenderer( in1, cutoff, transition = transition, samplerate = samplerate, response = response ) )
end


typealias Resample AudioNode{FilterRenderer}

function Resample( in1::AudioNode, ratio::Rational )

    ratio == 1//1 && error( "can't resample by a factor of 1" )

    interpolation = num( ratio )
    decimation    = den( ratio )

    cutoff              = 0.4/decimation
    transitionWidth     = 0.1/decimation
    stopbandAttenuation = 50

    h      = firdes( cutoff, transitionWidth, stopbandAttenuation )
    h      = h.*interpolation
    filter = FIRFilter( h, ratio )

    Resample( FilterRenderer( in1, filter ) )
end